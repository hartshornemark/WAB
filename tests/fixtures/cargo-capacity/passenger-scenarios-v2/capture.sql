with f as(select * from "Basic_Carrier_Record"."Operational_Flights" where "Operational_Flight_ID"='0d6daa41-c08e-4776-9753-f4319155ceff' and "Carrier_IATA"='ZZ')
select jsonb_build_object(
'capturedAt',clock_timestamp(),'databaseSnapshot',pg_current_snapshot()::text,'projectId','ffmadtrcirrzywdqahbu',
'flight',(select to_jsonb(f)-'Started_By'-'Updated_By' from f),
'aircraft',(select to_jsonb(a) from "Basic_Carrier_Record"."Basic_Aircraft_Data" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'fleet',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'crew',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from "Basic_Carrier_Record"."Aircraft_Crew_Codes" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") where btrim(a."Crew_Code_ID")=btrim(f."Crew_Code_ID")),
'pantry',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") where btrim(a."Pantry_Code_ID")=btrim(f."Pantry_Code_ID")),
'compartments',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from "Basic_Carrier_Record"."Aircraft_Compartments" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'areas',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from "Basic_Carrier_Record"."Aircraft_Compartment_Areas" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'limitingWeights',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'holds',(select jsonb_agg(to_jsonb(a) order by a."Hold_Name_ID") from "Basic_Carrier_Record"."Aircraft_Holds" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'positions',(select jsonb_agg(to_jsonb(a) order by a."ULD_Position_UUID") from "Basic_Carrier_Record"."Carrier_ULD_Positions" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") where a."ULD_Row_Type"='POSITION' and btrim(a."ULD_Code") in ('PAG','AKE')),
'specifications',(select jsonb_agg(to_jsonb(a)) from "Basic_Carrier_Record"."Carrier_ULD_Specifications" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") where btrim(a."ULD_ID") in ('PAG','AKE')),
'functionDefinitions',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'definition',pg_get_functiondef(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='Basic_Carrier_Record' and p.proname in('get_operational_passenger_booking','get_operational_freight_planning_without_a350_baggage','get_operational_freight_planning_without_a350_pallet_first')),
'fuelConfigurations',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" a join f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'units',(select to_jsonb(a) from "Basic_Carrier_Record"."Carrier_Units_of_Measure" a join f using("Carrier_IATA")),
'passengerBaseline',(select to_jsonb(a) from "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS" a join f using("Carrier_IATA")),
'passengerByClass',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" a join f using("Carrier_IATA"))
) snapshot;
