begin;

create or replace function private.enforce_aircraft_start_weight_principle_from_carrier()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  select case
    when b."Carrier_Basic_Weight" then 'BASIC_WEIGHT'
    when b."Carrier_Dry_Operating_Weight" then 'DRY_OPERATING_WEIGHT'
    else null
  end
  into new."Start_Weight_Principle"
  from "Basic_Carrier_Record"."Basic_Carrier_Data" b
  where b."Carrier_IATA"=new."Carrier_IATA";
  return new;
end
$$;

revoke all on function private.enforce_aircraft_start_weight_principle_from_carrier() from public,anon,authenticated;

drop trigger if exists enforce_aircraft_start_weight_principle_from_carrier
on "Basic_Carrier_Record"."Basic_Aircraft_Data";
create trigger enforce_aircraft_start_weight_principle_from_carrier
before insert or update of "Carrier_IATA","Start_Weight_Principle"
on "Basic_Carrier_Record"."Basic_Aircraft_Data"
for each row execute function private.enforce_aircraft_start_weight_principle_from_carrier();

commit;
