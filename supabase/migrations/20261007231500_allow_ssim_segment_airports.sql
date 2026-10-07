begin;

alter table "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults"
  drop constraint if exists "Schedule_Segment_Load_Control_Defa_Departure_Airport_IATA_fkey",
  drop constraint if exists "Schedule_Segment_Load_Control_Default_Arrival_Airport_IATA_fkey";

create or replace function "Basic_Carrier_Record".save_flight_schedule_segment_default(p_iata text,p_departure_airport text,p_arrival_airport text,p_aircraft_type text,p_values jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare subtype text;crew text;pantry text;passenger_basis text;passenger_variation text;baggage_basis text;baggage_variation text;remarks text;published_id uuid;
begin
 p_iata:=upper(btrim(p_iata));p_departure_airport:=upper(btrim(p_departure_airport));p_arrival_airport:=upper(btrim(p_arrival_airport));p_aircraft_type:=upper(btrim(p_aircraft_type));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Flight schedule configuration access denied' using errcode='42501';end if;
 if p_departure_airport!~'^[A-Z]{3}$' or p_arrival_airport!~'^[A-Z]{3}$' or p_departure_airport=p_arrival_airport or p_aircraft_type!~'^[A-Z0-9]{2,4}$' then raise exception 'Select a valid directional segment and aircraft type' using errcode='22023';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Segment defaults are required' using errcode='22023';end if;
 subtype:=upper(btrim(p_values->>'aircraftSubtype'));crew:=upper(btrim(p_values->>'crewCode'));pantry:=upper(btrim(p_values->>'pantryCode'));
 passenger_basis:=upper(btrim(p_values->>'passengerWeightBasis'));passenger_variation:=nullif(upper(btrim(p_values->>'passengerVariation')),'');
 baggage_basis:=upper(btrim(p_values->>'baggageWeightBasis'));baggage_variation:=nullif(upper(btrim(p_values->>'baggageVariation')),'');remarks:=nullif(btrim(p_values->>'remarks'),'');
 select "Import_ID" into published_id from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 if published_id is null or not exists(select 1 from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=published_id and btrim(l."Departure_Airport_IATA")=p_departure_airport and btrim(l."Arrival_Airport_IATA")=p_arrival_airport and l."Aircraft_Type_IATA"=p_aircraft_type) then raise exception 'Select a segment from the published schedule' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=p_aircraft_type and a."Aircraft_Series_Subtype"=subtype) then raise exception 'Select a configured aircraft subtype matching the segment aircraft type' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=p_aircraft_type and c."Aircraft_Series_Subtype"=subtype and btrim(c."Crew_Code_ID")=crew) then raise exception 'Select a valid crew code' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=p_aircraft_type and p."Aircraft_Series_Subtype"=subtype and btrim(p."Pantry_Code_ID")=pantry) then raise exception 'Select a valid pantry code' using errcode='23503';end if;
 if passenger_basis not in('STANDARD','VARIATION','ACTUAL') or baggage_basis not in('STANDARD','VARIATION','ACTUAL') then raise exception 'Select passenger and baggage weight methods' using errcode='22023';end if;
 if (passenger_basis='VARIATION')<>(passenger_variation is not null) or (baggage_basis='VARIATION')<>(baggage_variation is not null) then raise exception 'Select the required flight variation' using errcode='22023';end if;
 if passenger_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=passenger_variation) then raise exception 'Passenger variation not found' using errcode='23503';end if;
 if baggage_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=baggage_variation) then raise exception 'Baggage variation not found' using errcode='23503';end if;
 if char_length(coalesce(remarks,''))>1000 then raise exception 'Remarks are too long' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" as existing("Carrier_IATA","Departure_Airport_IATA","Arrival_Airport_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Updated_By","Updated_At")
 values(p_iata,p_departure_airport,p_arrival_airport,p_aircraft_type,subtype,crew,pantry,passenger_basis,passenger_variation,baggage_basis,baggage_variation,remarks,auth.uid(),now())
 on conflict("Carrier_IATA","Departure_Airport_IATA","Arrival_Airport_IATA","Aircraft_Type_IATA") do update set "Aircraft_Series_Subtype"=excluded."Aircraft_Series_Subtype","Crew_Code_ID"=excluded."Crew_Code_ID","Pantry_Code_ID"=excluded."Pantry_Code_ID","Passenger_Weight_Basis"=excluded."Passenger_Weight_Basis","Passenger_Flight_Variation"=excluded."Passenger_Flight_Variation","Baggage_Weight_Basis"=excluded."Baggage_Weight_Basis","Baggage_Flight_Variation"=excluded."Baggage_Flight_Variation","Remarks"=excluded."Remarks","Updated_By"=auth.uid(),"Updated_At"=now();
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" as existing("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
 select l."Schedule_Leg_ID",p_iata,subtype,crew,pantry,passenger_basis,passenger_variation,baggage_basis,baggage_variation,remarks,'SEGMENT_DEFAULT',auth.uid(),now() from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=published_id and btrim(l."Departure_Airport_IATA")=p_departure_airport and btrim(l."Arrival_Airport_IATA")=p_arrival_airport and l."Aircraft_Type_IATA"=p_aircraft_type
 on conflict("Schedule_Leg_ID") do update set "Aircraft_Series_Subtype"=excluded."Aircraft_Series_Subtype","Crew_Code_ID"=excluded."Crew_Code_ID","Pantry_Code_ID"=excluded."Pantry_Code_ID","Passenger_Weight_Basis"=excluded."Passenger_Weight_Basis","Passenger_Flight_Variation"=excluded."Passenger_Flight_Variation","Baggage_Weight_Basis"=excluded."Baggage_Weight_Basis","Baggage_Flight_Variation"=excluded."Baggage_Flight_Variation","Remarks"=excluded."Remarks","Updated_By"=auth.uid(),"Updated_At"=now() where existing."Parameter_Source" in('SEGMENT_DEFAULT','ONLY_CHOICE_DEFAULT');
end $$;

revoke all on function "Basic_Carrier_Record".save_flight_schedule_segment_default(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_flight_schedule_segment_default(text,text,text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
