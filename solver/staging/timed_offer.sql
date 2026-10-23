-- Private benchmark wrapper on the current Supabase database. Install after the
-- two unchanged reference SQL files inside the reviewed single transaction.
-- Reads only the supplied fixed JSON input; no operational tables or plan writes.
create or replace function capacity_reference.timed_offer(p jsonb)
returns jsonb language plpgsql as $$
declare started timestamptz; result jsonb; elapsed numeric;
begin
 started:=clock_timestamp();result:=capacity_reference.max_net_cargo_v2(p);
 elapsed:=extract(epoch from clock_timestamp()-started)*1000;
 return jsonb_build_object('result',result,'calculationMilliseconds',elapsed);
end $$;
