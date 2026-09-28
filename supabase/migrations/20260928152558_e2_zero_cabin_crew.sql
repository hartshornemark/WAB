-- No cabin crew is a real absence, not an invented D5 location.
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" add column "Crew_Row_ID" uuid not null default gen_random_uuid();
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" drop constraint "Aircraft_Crew_Codes_DUPE_pkey";
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" add primary key ("Crew_Row_ID");
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" alter column "Cabin_Crew_Location_Short_Form_ID" drop not null;
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" add constraint aircraft_crew_location_combination unique nulls not distinct ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Flight_Deck_Location_Short_Form_ID","Cabin_Crew_Location_Short_Form_ID");
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" add constraint aircraft_crew_absent_cabin_check check ("Cabin_Crew_Location_Short_Form_ID" is not null or ("Cabin_Crew_Seats_Occupied" is not null and "Cabin_Crew_Seats_Occupied"=0 and "Cabin_Crew_Baggage_Location" is null));
do $$
declare original text; revised text;
begin
 select pg_get_functiondef('"Basic_Carrier_Record".save_aircraft_e2_crew(text,text,text,text,jsonb)'::regprocedure) into original;
 revised:=replace(original,'row_data->>''cabinCrewLocationId''','case when (row_data->>''cabinCrewSeats'')::integer=0 then null else nullif(row_data->>''cabinCrewLocationId'','''') end');
 if revised=original then raise exception 'E2 save expression changed'; end if;
 revised:=replace(revised,'nullif(row_data->>''cabinCrewBaggageLocation'','''')','case when (row_data->>''cabinCrewSeats'')::integer=0 then null else nullif(row_data->>''cabinCrewBaggageLocation'','''') end');
 execute revised;
 select pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_e2(text,text,text)'::regprocedure) into original;
 revised:=replace(original,'btrim(c."Cabin_Crew_Location_Short_Form_ID"::text)','coalesce(btrim(c."Cabin_Crew_Location_Short_Form_ID"::text),'''')');
 if revised=original then raise exception 'E2 read expression changed'; end if;
 execute revised;
end $$;
