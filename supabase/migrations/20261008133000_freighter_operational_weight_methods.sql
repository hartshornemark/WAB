begin;

create or replace function private.normalise_operational_freighter_weight_methods()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if exists(
    select 1
    from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
    where a."Carrier_IATA"=new."Carrier_IATA"
      and a."Aircraft_Type_IATA"=new."Aircraft_Type_IATA"
      and a."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype"
      and a."Aircraft_Operating_Role"='FREIGHTER'
  ) then
    new."Passenger_Weight_Basis":=null;
    new."Passenger_Flight_Variation":=null;
    new."Baggage_Weight_Basis":=null;
    new."Baggage_Flight_Variation":=null;
  end if;
  return new;
end;
$$;

revoke all on function private.normalise_operational_freighter_weight_methods() from public,anon,authenticated;

create trigger "normalise_operational_freighter_weight_methods"
before insert or update on "Basic_Carrier_Record"."Operational_Flights"
for each row execute function private.normalise_operational_freighter_weight_methods();

alter table "Basic_Carrier_Record"."Operational_Flights" disable trigger "touch_operational_flight";

update "Basic_Carrier_Record"."Operational_Flights" f
set "Passenger_Weight_Basis"=null,
    "Passenger_Flight_Variation"=null,
    "Baggage_Weight_Basis"=null,
    "Baggage_Flight_Variation"=null
from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
where a."Carrier_IATA"=f."Carrier_IATA"
  and a."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
  and a."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype"
  and a."Aircraft_Operating_Role"='FREIGHTER'
  and (f."Passenger_Weight_Basis" is not null or f."Baggage_Weight_Basis" is not null);

alter table "Basic_Carrier_Record"."Operational_Flights" enable trigger "touch_operational_flight";

commit;
