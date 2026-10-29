-- Run once in Supabase SQL Editor to set up the five trip families.
-- This inserts missing family codes without deleting existing expenses.
insert into public.families(trip_id,name)
select t.id, v.code
from public.trips t
cross join (values ('FM'),('NT'),('GA'),('KA'),('SS')) as v(code)
where t.name='San Rafael 2026'
on conflict (trip_id,name) do nothing;

-- Verify five family codes:
select f.name from public.families f join public.trips t on t.id=f.trip_id
where t.name='San Rafael 2026' order by f.name;
