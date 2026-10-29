-- Run once in Supabase SQL Editor to enable editable expense dates.
alter table public.expenses add column if not exists expense_date date;
update public.expenses set expense_date=(created_at at time zone 'America/Los_Angeles')::date where expense_date is null;
alter table public.expenses alter column expense_date set default current_date;
alter table public.expenses alter column expense_date set not null;

-- Replace the old RPC signatures so PostgREST has no ambiguous overloads.
drop function if exists public.shared_add_expense(text,text,integer,uuid,jsonb);
drop function if exists public.shared_update_expense(text,uuid,text,integer,uuid,jsonb);

create function public.shared_add_expense(p_secret text,p_description text,p_amount_cents integer,p_payer_id uuid,p_shares jsonb,p_expense_date date)
returns void language plpgsql security definer set search_path='' as $$
declare v_id uuid:=public.shared_trip_id(p_secret); k text; v text; total bigint:=0;
begin
 if p_amount_cents is null or p_amount_cents<=0 or p_expense_date is null or nullif(trim(p_description),'') is null
 or p_shares is null or jsonb_typeof(p_shares)<>'object' or p_shares='{}'::jsonb then raise exception 'Invalid expense'; end if;
 if not exists(select 1 from public.families where id=p_payer_id and trip_id=v_id) then raise exception 'Invalid payer'; end if;
 for k,v in select key,value from jsonb_each_text(p_shares) loop
  if v !~ '^[0-9]+$' or length(v)>12 then raise exception 'Invalid share'; end if;
  if not exists(select 1 from public.families where id=k::uuid and trip_id=v_id) then raise exception 'Invalid family'; end if;
  total:=total+v::bigint;
 end loop;
 if total<>p_amount_cents then raise exception 'Shares do not match amount'; end if;
 perform set_config('app.shared_trip_write','true',true);
 insert into public.expenses(trip_id,description,amount_cents,payer_id,shares,created_by,expense_date)
 values(v_id,trim(p_description),p_amount_cents,p_payer_id,p_shares,null,p_expense_date);
end $$;

create function public.shared_update_expense(p_secret text,p_expense_id uuid,p_description text,p_amount_cents integer,p_payer_id uuid,p_shares jsonb,p_expense_date date)
returns void language plpgsql security definer set search_path='' as $$
declare v_id uuid:=public.shared_trip_id(p_secret); k text; v text; total bigint:=0;
begin
 if p_expense_id is null or p_amount_cents is null or p_amount_cents<=0 or p_expense_date is null
 or nullif(trim(p_description),'') is null or p_shares is null or jsonb_typeof(p_shares)<>'object'
 or p_shares='{}'::jsonb then raise exception 'Invalid expense'; end if;
 if not exists(select 1 from public.families where id=p_payer_id and trip_id=v_id) then raise exception 'Invalid payer'; end if;
 for k,v in select key,value from jsonb_each_text(p_shares) loop
  if v !~ '^[0-9]+$' or length(v)>12 then raise exception 'Invalid share'; end if;
  if not exists(select 1 from public.families where id=k::uuid and trip_id=v_id) then raise exception 'Invalid family'; end if;
  total:=total+v::bigint;
 end loop;
 if total<>p_amount_cents then raise exception 'Shares do not match amount'; end if;
 perform set_config('app.shared_trip_write','true',true);
 update public.expenses set description=trim(p_description),amount_cents=p_amount_cents,payer_id=p_payer_id,shares=p_shares,expense_date=p_expense_date
 where id=p_expense_id and trip_id=v_id;
 if not found then raise exception 'Expense not found'; end if;
end $$;

revoke all on function public.shared_add_expense(text,text,integer,uuid,jsonb,date) from public;
revoke all on function public.shared_update_expense(text,uuid,text,integer,uuid,jsonb,date) from public;
grant execute on function public.shared_add_expense(text,text,integer,uuid,jsonb,date),
public.shared_update_expense(text,uuid,text,integer,uuid,jsonb,date) to anon;
