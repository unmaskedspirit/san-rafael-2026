-- Run once in Supabase SQL Editor to enable recorded family-to-family payments.
-- Settlements are payments ALREADY MADE, not new IOUs.
create table if not exists public.settlements (
 id uuid primary key default gen_random_uuid(),
 trip_id uuid not null references public.trips(id) on delete cascade,
 from_family_id uuid not null references public.families(id),
 to_family_id uuid not null references public.families(id),
 amount_cents integer not null check(amount_cents>0),
 created_at timestamptz not null default now(),
 constraint different_settlement_families check(from_family_id<>to_family_id)
);
create index if not exists settlements_trip_idx on public.settlements(trip_id,created_at desc);
alter table public.settlements enable row level security;
revoke all on public.settlements from anon,authenticated;

create or replace function public.shared_trip_data(p_secret text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=public.shared_trip_id(p_secret);
begin
 return jsonb_build_object(
  'families',coalesce((select jsonb_agg(to_jsonb(f) order by f.name) from public.families f where f.trip_id=v_id),'[]'::jsonb),
  'expenses',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from public.expenses e where e.trip_id=v_id),'[]'::jsonb),
  'settlements',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from public.settlements s where s.trip_id=v_id),'[]'::jsonb)
 );
end $$;

create or replace function public.shared_add_settlement(
 p_secret text,p_amount_cents integer,p_from_family_id uuid,p_to_family_id uuid
)
returns void language plpgsql security definer set search_path='' as $$
declare v_id uuid:=public.shared_trip_id(p_secret);
begin
 if p_amount_cents is null or p_amount_cents<=0 or p_from_family_id is null
 or p_to_family_id is null or p_from_family_id=p_to_family_id then raise exception 'Invalid payment'; end if;
 if not exists(select 1 from public.families where id=p_from_family_id and trip_id=v_id)
 or not exists(select 1 from public.families where id=p_to_family_id and trip_id=v_id) then raise exception 'Invalid family'; end if;
 insert into public.settlements(trip_id,from_family_id,to_family_id,amount_cents)
 values(v_id,p_from_family_id,p_to_family_id,p_amount_cents);
end $$;

create or replace function public.shared_delete_settlement(p_secret text,p_settlement_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from public.settlements where id=p_settlement_id and trip_id=public.shared_trip_id(p_secret);
end $$;

revoke all on function public.shared_trip_data(text) from public;
revoke all on function public.shared_add_settlement(text,integer,uuid,uuid) from public;
revoke all on function public.shared_delete_settlement(text,uuid) from public;
grant execute on function public.shared_trip_data(text),
 public.shared_add_settlement(text,integer,uuid,uuid),
 public.shared_delete_settlement(text,uuid) to anon;
