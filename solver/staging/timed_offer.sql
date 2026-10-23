-- Install ONLY in a separate empty staging-reference database, after the two
-- versioned reference SQL files. Not a Supabase/shared application migration.
create or replace function capacity_reference.timed_offer(p jsonb)
returns jsonb language plpgsql as $$
declare started timestamptz; result jsonb; elapsed numeric;
begin
 started:=clock_timestamp();result:=capacity_reference.max_net_cargo_v2(p);
 elapsed:=extract(epoch from clock_timestamp()-started)*1000;
 return jsonb_build_object('result',result,'calculationMilliseconds',elapsed);
end $$;
