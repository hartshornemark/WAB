begin;

alter table "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"
  drop constraint if exists "Scheduled_Flight_Load_Control_Parameters_Parameter_Source_check";
alter table "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"
  add constraint "Scheduled_Flight_Load_Control_Parameters_Parameter_Source_check"
  check("Parameter_Source" in('ONLY_CHOICE_DEFAULT','SEGMENT_DEFAULT','FLIGHT_OVERRIDE'));

create or replace function "Basic_Carrier_Record".get_flight_schedule_parameter_options(p_iata text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare passenger_available boolean;baggage_available boolean;baggage_actual boolean;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW')) then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 passenger_available:=exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS" where "Carrier_IATA"=p_iata) or exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" where "Carrier_IATA"=p_iata and "Flight_Type_Variation" is null);
 baggage_actual:=exists(select 1 from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" where "Carrier_IATA"=p_iata and "Page_Code"='B4' and "Section_Code"='BAGGAGE_OPERATION_MODE' and "Review_State"='APPLIES');
 baggage_available:=baggage_actual or exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" where "Carrier_IATA"=p_iata) or exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" where "Carrier_IATA"=p_iata and "Flight_Type_Variation" is null);
 return jsonb_build_object(
  'passenger',jsonb_build_object('available',passenger_available,'defaultBasis','STANDARD','variations',coalesce((select jsonb_agg(jsonb_build_object('code',v."Flight_Type_Variation",'description',v."Flight_Type_Variation_Description") order by v."Flight_Type_Variation") from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w where w."Carrier_IATA"=p_iata and w."Flight_Type_Variation"=v."Flight_Type_Variation")),'[]'::jsonb)),
  'baggage',jsonb_build_object('available',baggage_available,'defaultBasis',case when baggage_actual then 'ACTUAL' else 'STANDARD' end,'variations',coalesce((select jsonb_agg(jsonb_build_object('code',v."Flight_Type_Variation",'description',v."Flight_Type_Variation_Description") order by v."Flight_Type_Variation") from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and (exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" w where w."Carrier_IATA"=p_iata and w."Flight_Type_Variation"=v."Flight_Type_Variation") or exists(select 1 from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" r where r."Carrier_IATA"=p_iata and r."Page_Code"='B4' and r."Section_Code"='BAGGAGE_VARIATION_'||v."Flight_Type_Variation" and r."Review_State" in('REVIEWED','APPLIES')))),'[]'::jsonb))
 );
end $$;

create or replace function private.apply_schedule_only_choice_defaults(p_iata text,p_import_id uuid,p_user uuid)
returns void language plpgsql security definer set search_path='' as $$
declare passenger_available boolean;passenger_varies boolean;baggage_available boolean;baggage_varies boolean;baggage_basis text;
begin
 passenger_available:=exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS" where "Carrier_IATA"=p_iata) or exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" where "Carrier_IATA"=p_iata and "Flight_Type_Variation" is null);
 passenger_varies:=exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" where "Carrier_IATA"=p_iata and "Flight_Type_Variation" is not null);
 baggage_basis:=case when exists(select 1 from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" where "Carrier_IATA"=p_iata and "Page_Code"='B4' and "Section_Code"='BAGGAGE_OPERATION_MODE' and "Review_State"='APPLIES') then 'ACTUAL' else 'STANDARD' end;
 baggage_available:=baggage_basis='ACTUAL' or exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" where "Carrier_IATA"=p_iata) or exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" where "Carrier_IATA"=p_iata and "Flight_Type_Variation" is null);
 baggage_varies:=exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" where "Carrier_IATA"=p_iata and "Flight_Type_Variation" is not null) or exists(select 1 from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" where "Carrier_IATA"=p_iata and "Page_Code"='B4' and "Section_Code" like 'BAGGAGE_VARIATION_%' and "Review_State" in('REVIEWED','APPLIES'));
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
 with resolved as(
  select l."Schedule_Leg_ID",l."Aircraft_Type_IATA",min(a."Aircraft_Series_Subtype") subtype,min(a."Aircraft_Operating_Role") role
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Basic_Aircraft_Data" a on a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=l."Aircraft_Type_IATA" and (l."Aircraft_Series_Subtype" is null or a."Aircraft_Series_Subtype"=l."Aircraft_Series_Subtype")
  where l."Import_ID"=p_import_id and l."Aircraft_Type_IATA" is not null group by l."Schedule_Leg_ID",l."Aircraft_Type_IATA" having count(distinct a."Aircraft_Series_Subtype")=1
 ), choices as(
  select r.*,c.code crew,p.code pantry from resolved r
  join lateral(select min(btrim(x."Crew_Code_ID")) code from "Basic_Carrier_Record"."Aircraft_Crew_Codes" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and x."Aircraft_Series_Subtype"=r.subtype having count(distinct btrim(x."Crew_Code_ID"))=1)c on true
  join lateral(select min(btrim(x."Pantry_Code_ID")) code from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and x."Aircraft_Series_Subtype"=r.subtype having count(distinct btrim(x."Pantry_Code_ID"))=1)p on true
 )
 select "Schedule_Leg_ID",p_iata,subtype,crew,pantry,'STANDARD',null,baggage_basis,null,null,'ONLY_CHOICE_DEFAULT',p_user,now() from choices where role='FREIGHTER' or (passenger_available and not passenger_varies and baggage_available and not baggage_varies)
 on conflict("Schedule_Leg_ID") do nothing;
end $$;

create or replace function "Basic_Carrier_Record".refresh_flight_schedule_only_choice_defaults(p_iata text)
returns void language plpgsql security definer set search_path='' as $$
declare published_id uuid;actor uuid;
begin
 p_iata:=upper(btrim(p_iata));actor:=(select auth.uid());
 if actor is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW')) then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 select "Import_ID" into published_id from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 if published_id is null then return;end if;
 delete from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p using "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where p."Schedule_Leg_ID"=l."Schedule_Leg_ID" and l."Import_ID"=published_id and p."Parameter_Source"='ONLY_CHOICE_DEFAULT';
 perform private.apply_schedule_only_choice_defaults(p_iata,published_id,actor);
end $$;

create or replace function private.copy_schedule_parameters_to_new_publication()
returns trigger language plpgsql security definer set search_path='' as $$
declare previous_id uuid;
begin
 if new."Status"<>'PUBLISHED' or old."Status"='PUBLISHED' then return new;end if;
 select "Import_ID" into previous_id from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=new."Carrier_IATA" and "Status"='SUPERSEDED' and "Import_ID"<>new."Import_ID" order by "Superseded_At" desc nulls last limit 1;
 if previous_id is not null then
  insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
  select target."Schedule_Leg_ID",new."Carrier_IATA",p."Aircraft_Series_Subtype",p."Crew_Code_ID",p."Pantry_Code_ID",p."Passenger_Weight_Basis",p."Passenger_Flight_Variation",p."Baggage_Weight_Basis",p."Baggage_Flight_Variation",p."Remarks",p."Parameter_Source",new."Published_By",now() from "Basic_Carrier_Record"."Scheduled_Flight_Legs" source join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p on p."Schedule_Leg_ID"=source."Schedule_Leg_ID" join "Basic_Carrier_Record"."Scheduled_Flight_Legs" target on target."Import_ID"=new."Import_ID" and target."Airline_Designator"=source."Airline_Designator" and target."Flight_Number"=source."Flight_Number" and target."Operational_Suffix"=source."Operational_Suffix" and target."Itinerary_Variation_Identifier"=source."Itinerary_Variation_Identifier" and target."Leg_Sequence_Number"=source."Leg_Sequence_Number" and target."Departure_Airport_IATA"=source."Departure_Airport_IATA" and target."Arrival_Airport_IATA"=source."Arrival_Airport_IATA" and target."Aircraft_Type_IATA" is not distinct from source."Aircraft_Type_IATA" where source."Import_ID"=previous_id and p."Parameter_Source"='FLIGHT_OVERRIDE' on conflict("Schedule_Leg_ID") do nothing;
 end if;
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
 select l."Schedule_Leg_ID",new."Carrier_IATA",d."Aircraft_Series_Subtype",d."Crew_Code_ID",d."Pantry_Code_ID",d."Passenger_Weight_Basis",d."Passenger_Flight_Variation",d."Baggage_Weight_Basis",d."Baggage_Flight_Variation",d."Remarks",'SEGMENT_DEFAULT',new."Published_By",now() from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" d on d."Carrier_IATA"=new."Carrier_IATA" and d."Departure_Airport_IATA"=l."Departure_Airport_IATA" and d."Arrival_Airport_IATA"=l."Arrival_Airport_IATA" and d."Aircraft_Type_IATA"=l."Aircraft_Type_IATA" where l."Import_ID"=new."Import_ID" on conflict("Schedule_Leg_ID") do nothing;
 perform private.apply_schedule_only_choice_defaults(new."Carrier_IATA",new."Import_ID",new."Published_By");
 return new;
end $$;

do $$ declare item record;begin for item in select "Carrier_IATA","Import_ID",coalesce("Published_By","Uploaded_By") actor from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Status"='PUBLISHED' loop perform private.apply_schedule_only_choice_defaults(item."Carrier_IATA",item."Import_ID",item.actor);end loop;end $$;

revoke all on function private.apply_schedule_only_choice_defaults(text,uuid,uuid) from public,anon,authenticated;
revoke all on function "Basic_Carrier_Record".get_flight_schedule_parameter_options(text) from public,anon;
revoke all on function "Basic_Carrier_Record".refresh_flight_schedule_only_choice_defaults(text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_flight_schedule_parameter_options(text) to authenticated;
grant execute on function "Basic_Carrier_Record".refresh_flight_schedule_only_choice_defaults(text) to authenticated;
notify pgrst,'reload schema';
commit;
