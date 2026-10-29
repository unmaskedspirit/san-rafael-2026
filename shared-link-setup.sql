-- Run ONCE in Supabase SQL Editor. Replace the secret below with a long random phrase.
-- Share the secret only in your private link; never commit it to GitHub.
create extension if not exists pgcrypto with schema extensions;
create table if not exists public.shared_trip_access (
 trip_id uuid primary key references public.trips(id) on delete cascade,
 secret_hash text not null
);
insert into public.shared_trip_access(trip_id,secret_hash)
select id, extensions.crypt('REPLACE_WITH_A_LONG_RANDOM_SECRET',extensions.gen_salt('bf'))
from public.trips where name='San Rafael 2026'
on conflict(trip_id) do update set secret_hash=excluded.secret_hash;

create or replace function public.shared_trip_id(p_secret text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 select a.trip_id into v_id from public.shared_trip_access a
 join public.trips t on t.id=a.trip_id
 where t.name='San Rafael 2026' and a.secret_hash=extensions.crypt(p_secret,a.secret_hash);
 if v_id is null then raise exception 'Invalid private trip link'; end if;
 return v_id;
end $$;
create or replace function public.shared_trip_data(p_secret text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid := public.shared_trip_id(p_secret);
begin
 return jsonb_build_object(
 'families',coalesce((select jsonb_agg(to_jsonb(f) order by f.name) from public.families f where f.trip_id=v_id),'[]'::jsonb),
 'expenses',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from public.expenses e where e.trip_id=v_id),'[]'::jsonb));
end $$;
create or replace function public.shared_add_family(p_secret text,p_name text)
returns void language plpgsql security definer set search_path='' as $$
begin
 insert into public.families(trip_id,name) values(public.shared_trip_id(p_secret),trim(p_name));
end $$;
create or replace function public.shared_add_expense(p_secret text,p_description text,p_amount_cents integer,p_payer_id uuid,p_shares jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_id uuid := public.shared_trip_id(p_secret); k text; v text; total bigint:=0;
begin
 if p_amount_cents is null or p_amount_cents<=0 or p_shares is null or jsonb_typeof(p_shares)<>'object' or p_shares='{}'::jsonb then raise exception 'Invalid expense'; end if;
 if not exists(select 1 from public.families where id=p_payer_id and trip_id=v_id) then raise exception 'Invalid payer'; end if;
 for k,v in select key,value from jsonb_each_text(p_shares) loop
   if v !~ '^[0-9]+$' or length(v)>12 then raise exception 'Invalid share'; end if;
   if not exists(select 1 from public.families where id=k::uuid and trip_id=v_id) then raise exception 'Invalid family'; end if;
   total:=total+v::bigint;
 end loop;
 if total<>p_amount_cents then raise exception 'Shares do not match amount'; end if;
 -- Existing trigger checks auth membership, so bypass that trigger only for this scoped insert.
 -- Instead, update trigger function to accept trusted security-definer calls via a transaction-local flag.
 perform set_config('app.shared_trip_write','true',true);
 insert into public.expenses(trip_id,description,amount_cents,payer_id,shares,created_by)
 values(v_id,trim(p_description),p_amount_cents,p_payer_id,p_shares,null);
end $$;
alter table public.expenses alter column created_by drop not null;
create or replace function public.validate_expense() returns trigger language plpgsql security definer set search_path='' as $$
declare k text; v text; total bigint := 0;
begin
 if current_setting('app.shared_trip_write',true) is distinct from 'true' and not public.is_trip_member(new.trip_id) then raise exception 'Not a trip member'; end if;
 if new.shares='{}'::jsonb then raise exception 'At least one family required'; end if;
 for k,v in select key,value from jsonb_each_text(new.shares) loop
   if v !~ '^[0-9]+$' or length(v)>12 then raise exception 'Invalid share'; end if;
   if not exists(select 1 from public.families where id=k::uuid and trip_id=new.trip_id) then raise exception 'Invalid family'; end if;
   total := total+v::bigint;
 end loop;
 if total<>new.amount_cents then raise exception 'Shares do not match amount'; end if;
 return new;
end $$;
create or replace function public.shared_delete_expense(p_secret text,p_expense_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from public.expenses where id=p_expense_id and trip_id=public.shared_trip_id(p_secret);
end $$;
revoke all on function public.shared_trip_id(text) from public;
revoke all on function public.shared_trip_data(text) from public;
revoke all on function public.shared_add_family(text,text) from public;
revoke all on function public.shared_add_expense(text,text,integer,uuid,jsonb) from public;
revoke all on function public.shared_delete_expense(text,uuid) from public;
grant execute on function public.shared_trip_id(text),public.shared_trip_data(text),public.shared_add_family(text,text),public.shared_add_expense(text,text,integer,uuid,jsonb),public.shared_delete_expense(text,uuid) to anon;
-- No direct table access for anonymous visitors.
revoke all on public.trips,public.trip_members,public.families,public.expenses,public.shared_trip_access from anon;
