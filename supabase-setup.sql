-- Run in Supabase SQL Editor. Replace CHANGE_THIS_TO_A_PRIVATE_INVITE_CODE before running.
create extension if not exists pgcrypto;
create table if not exists public.trips (
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 invite_hash text not null
);
create table if not exists public.trip_members (
 trip_id uuid not null references public.trips(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 primary key (trip_id,user_id)
);
create table if not exists public.families (
 id uuid primary key default gen_random_uuid(),
 trip_id uuid not null references public.trips(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 60),
 unique(trip_id,name),
 unique(id,trip_id)
);
create table if not exists public.expenses (
 id uuid primary key default gen_random_uuid(),
 trip_id uuid not null references public.trips(id) on delete cascade,
 description text not null check(length(trim(description)) between 1 and 120),
 amount_cents integer not null check(amount_cents>0),
 payer_id uuid not null,
 shares jsonb not null check(jsonb_typeof(shares)='object'),
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 foreign key(payer_id,trip_id) references public.families(id,trip_id)
);
create or replace function public.is_trip_member(t uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.trip_members where trip_id=t and user_id=(select auth.uid()));
$$;
revoke all on function public.is_trip_member(uuid) from public;
grant execute on function public.is_trip_member(uuid) to authenticated;
create or replace function public.join_san_rafael(code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare t public.trips%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into t from public.trips where name='San Rafael 2026';
 if t.id is null or t.invite_hash <> extensions.crypt(code,t.invite_hash) then
   raise exception 'Invalid trip access code';
 end if;
 insert into public.trip_members(trip_id,user_id) values(t.id,auth.uid()) on conflict do nothing;
 return t.id;
end; $$;
revoke all on function public.join_san_rafael(text) from public;
grant execute on function public.join_san_rafael(text) to authenticated;
insert into public.trips(name,invite_hash)
values ('San Rafael 2026', extensions.crypt('CHANGE_THIS_TO_A_PRIVATE_INVITE_CODE',extensions.gen_salt('bf')))
on conflict(name) do nothing;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.families enable row level security;
alter table public.expenses enable row level security;
create policy "Members view trip" on public.trips for select to authenticated using(public.is_trip_member(id));
create policy "Members view membership" on public.trip_members for select to authenticated using(public.is_trip_member(trip_id));
create policy "Members view families" on public.families for select to authenticated using(public.is_trip_member(trip_id));
create policy "Members add families" on public.families for insert to authenticated with check(public.is_trip_member(trip_id));
create policy "Members view expenses" on public.expenses for select to authenticated using(public.is_trip_member(trip_id));
create policy "Members add expenses" on public.expenses for insert to authenticated with check(public.is_trip_member(trip_id) and created_by=auth.uid());
create policy "Members delete expenses" on public.expenses for delete to authenticated using(public.is_trip_member(trip_id));
-- Additional server-side integrity: verify share amounts, membership, and total before writing.
create or replace function public.validate_expense() returns trigger language plpgsql security definer set search_path = '' as $$
declare k text; v text; total bigint := 0;
begin
 if not public.is_trip_member(new.trip_id) then raise exception 'Not a trip member'; end if;
 if jsonb_object_length(new.shares)=0 then raise exception 'At least one family required'; end if;
 for k,v in select key,value from jsonb_each_text(new.shares) loop
   if v !~ '^[0-9]+$' or length(v)>12 then raise exception 'Invalid share'; end if;
   if not exists(select 1 from public.families where id=k::uuid and trip_id=new.trip_id) then raise exception 'Invalid family'; end if;
   total := total+v::bigint;
 end loop;
 if total<>new.amount_cents then raise exception 'Shares do not match amount'; end if;
 return new;
end; $$;
create trigger expense_integrity before insert or update on public.expenses for each row execute function public.validate_expense();
