with
flight as (select "Operational_Flight_ID","Carrier_IATA","Service_Date","Flight_Number","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Configuration","Version","Updated_At" from "Basic_Carrier_Record"."Operational_Flights" where "Operational_Flight_ID"='0d6daa41-c08e-4776-9753-f4319155ceff' and "Carrier_IATA"='ZZ'),
specs as (select s.*,m."ULD_Volume" as "Master_Volume_M3" from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s join flight f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID")),
pallet as (select * from specs where btrim("ULD_Type")='LD7' order by "ULD_Default" desc,btrim("ULD_ID") limit 1),
container as (select * from specs where "ULD_Baggage_Default"),
candidates as (select p.*,greatest(0,least(p."ULD_Position_Max_Weight"::numeric,case when btrim(p."ULD_Code")=btrim(pallet."ULD_ID") then pallet."ULD_Max_Weight" else container."ULD_Max_Weight" end)-case when btrim(p."ULD_Code")=btrim(pallet."ULD_ID") then pallet."ULD_Tare_Weight" else container."ULD_Tare_Weight" end) as net,
(select jsonb_agg(p."Hold_Name_ID"||':'||o."Atomic_Bay_ID" order by o."Atomic_Bay_ID") from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" o where o."ULD_Position_UUID"=p."ULD_Position_UUID") as bays
from "Basic_Carrier_Record"."Carrier_ULD_Positions" p join flight f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") cross join pallet cross join container where p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Code") in(btrim(pallet."ULD_ID"),btrim(container."ULD_ID"))),
baggage as (select b."Version",b."ULD_Count",b."ULD_Net_Weight",b."Bulk_Net_Weight",b."Planned_Contents",b."Accepted_At" from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" b join flight f using("Operational_Flight_ID")),
booking as (select b."Booked_By_Class",b."Version",b."Updated_At" from "Basic_Carrier_Record"."Operational_Passenger_Bookings" b join flight f using("Operational_Flight_ID"))
select jsonb_build_object(
'capturedAt',clock_timestamp(),'databaseSnapshot',pg_current_snapshot()::text,'projectId','ffmadtrcirrzywdqahbu',
'flight',(select to_jsonb(flight) from flight),'booking',(select to_jsonb(booking) from booking),'baggage',(select to_jsonb(baggage) from baggage),
'selectedPallet',(select to_jsonb(pallet) from pallet),'selectedContainer',(select to_jsonb(container) from container),'defaultContainerCount',(select count(*) from container),
'units',(select to_jsonb(u) from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" u join flight f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'holds',(select jsonb_agg(to_jsonb(h) order by h."Hold_Name_ID") from "Basic_Carrier_Record"."Aircraft_Holds" h join flight f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'holdConfiguration',(select to_jsonb(h) from "Basic_Carrier_Record"."Aircraft_Hold_Configuration" h join flight f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")),
'candidateSourceRows',(select jsonb_agg(to_jsonb(candidates) order by "ULD_Position_UUID") from candidates),
'databaseArguments',jsonb_build_object(
'p_pallets',(select jsonb_agg(jsonb_build_object('id',"ULD_Position_UUID",'uldCode',btrim("ULD_Code"),'netWeightCapacity',net,'bays',bays) order by "ULD_Position_UUID") from candidates where btrim("ULD_Code")=(select btrim("ULD_ID") from pallet)),
'p_containers',(select jsonb_agg(jsonb_build_object('id',"ULD_Position_UUID",'uldCode',btrim("ULD_Code"),'netWeightCapacity',net,'bays',bays) order by "ULD_Position_UUID") from candidates where btrim("ULD_Code")=(select btrim("ULD_ID") from container)),
'p_baggage_count',(select "ULD_Count" from baggage)),
'functionDefinitions',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),'definition',pg_get_functiondef(p.oid)) order by n.nspname,p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='private' and p.proname in('a350_pallet_first_capacity','compatible_baggage_positions')) or (n.nspname='Basic_Carrier_Record' and p.proname='get_operational_freight_planning'))
) as snapshot;
