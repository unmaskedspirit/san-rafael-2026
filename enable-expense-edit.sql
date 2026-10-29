-- Run once in Supabase SQL Editor to enable secure editing from the private-link app.
create or replace function public.shared_update_expense(
 p_secret text,
 p_expense_id uuid,
 p_description text,
 p_amount_cents integer,
 p_payer_id uuid,
 p_shares jsonb
)
returns void language plpgsql security definer set search_path='' as $$
declare
 v_id uuid := public.shared_trip_id(p_secret);
 k text;
 v text;
 total bigint := 0;
begin
 if p_expense_id is null or p_amount_cents is null or p_amount_cents<=0
    or nullif(trim(p_description),'') is null
    or p_shares is null or jsonb_typeof(p_shares)<>'object'
    or p_shares='{}'::jsonb then
   raise exception 'Invalid expense';
 end if;
 if not exists(select 1 from public.families where id=p_payer_id and trip_id=v_id) then
   raise exception 'Invalid payer';
 end if;
 for k,v in select key,value from jsonb_each_text(p_shares) loop
   if v !~ '^[0-9]+$' or length(v)>12 then raise exception 'Invalid share'; end if;
   if not exists(select 1 from public.families where id=k::uuid and trip_id=v_id) then
     raise exception 'Invalid family';
   end if;
   total := total+v::bigint;
 end loop;
 if total<>p_amount_cents then raise exception 'Shares do not match amount'; end if;
 perform set_config('app.shared_trip_write','true',true);
 update public.expenses
 set description=trim(p_description),amount_cents=p_amount_cents,payer_id=p_payer_id,shares=p_shares
 where id=p_expense_id and trip_id=v_id;
 if not found then raise exception 'Expense not found'; end if;
end $$;
revoke all on function public.shared_update_expense(text,uuid,text,integer,uuid,jsonb) from public;
grant execute on function public.shared_update_expense(text,uuid,text,integer,uuid,jsonb) to anon;
