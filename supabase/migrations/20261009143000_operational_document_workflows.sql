begin;

create table "Basic_Carrier_Record"."Operational_Document_Workflows"(
  "Operational_Flight_ID" uuid primary key references "Basic_Carrier_Record"."Operational_Flights"("Operational_Flight_ID") on update cascade on delete cascade,
  "Carrier_IATA" varchar(2) not null,
  "Final_Load_Plan_Edition" integer,
  "Load_Plan_Finalised_By" uuid,
  "Load_Plan_Finalised_At" timestamptz,
  "NOTOC_Version" integer not null default 0 check("NOTOC_Version">=0),
  "NOTOC_Status" text not null default 'EMPTY' check("NOTOC_Status" in('EMPTY','DRAFT','FINAL','NOT_REQUIRED')),
  "NOTOC_Details" jsonb not null default '[]'::jsonb check(jsonb_typeof("NOTOC_Details")='array'),
  "NOTOC_Snapshot" jsonb,
  "NOTOC_Released_By" uuid,
  "NOTOC_Released_At" timestamptz,
  "Loadsheet_Number" integer not null default 0 check("Loadsheet_Number">=0),
  "Loadsheet_Status" text not null default 'EMPTY' check("Loadsheet_Status" in('EMPTY','FINAL')),
  "Loadsheet_Snapshot" jsonb,
  "Loadsheet_Produced_By" uuid,
  "Loadsheet_Produced_At" timestamptz,
  "Updated_By" uuid not null default auth.uid(),
  "Updated_At" timestamptz not null default now()
);
create index "operational_document_workflows_carrier_idx" on "Basic_Carrier_Record"."Operational_Document_Workflows"("Carrier_IATA","Operational_Flight_ID");
alter table "Basic_Carrier_Record"."Operational_Document_Workflows" enable row level security;
grant select on "Basic_Carrier_Record"."Operational_Document_Workflows" to authenticated;
create policy "operational_document_workflows_select" on "Basic_Carrier_Record"."Operational_Document_Workflows" for select to authenticated using(
  (select private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW'))or(select private.has_global_permission('LOAD_CONTROL_VIEW'))
);

create or replace function "Basic_Carrier_Record".get_operational_documents(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare d "Basic_Carrier_Record"."Operational_Document_Workflows"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')or private.has_global_permission('LOAD_CONTROL_VIEW'))then raise exception 'Permission denied' using errcode='42501';end if;
 select*into d from "Basic_Carrier_Record"."Operational_Document_Workflows" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 return jsonb_build_object(
  'loadPlanStatus',case when d."Final_Load_Plan_Edition" is null then'DRAFT'else'FINAL'end,
  'finalLoadPlanEdition',d."Final_Load_Plan_Edition",'loadPlanFinalisedAt',d."Load_Plan_Finalised_At",
  'notocVersion',coalesce(d."NOTOC_Version",0),'notocStatus',coalesce(d."NOTOC_Status",'EMPTY'),'notocDetails',coalesce(d."NOTOC_Details",'[]'::jsonb),'notocReleasedAt',d."NOTOC_Released_At",
  'loadsheetNumber',coalesce(d."Loadsheet_Number",0),'loadsheetStatus',coalesce(d."Loadsheet_Status",'EMPTY'),'loadsheetSnapshot',d."Loadsheet_Snapshot",'loadsheetProducedAt',d."Loadsheet_Produced_At"
 );
end$$;

create or replace function "Basic_Carrier_Record".finalise_operational_load_plan(p_iata text,p_operational_flight_id uuid,p_edition integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_edition integer;f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then raise exception 'Permission denied' using errcode='42501';end if;
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if not found then raise exception 'Operational flight not found' using errcode='22023';end if;
 select coalesce(max("Edition_Number"),0)into current_edition from "Basic_Carrier_Record"."Operational_Load_Plan_Editions" where "Operational_Flight_ID"=p_operational_flight_id;
 if current_edition<1 or current_edition<>p_edition then raise exception 'Finalise the current saved load-plan edition.' using errcode='40001';end if;
 insert into "Basic_Carrier_Record"."Operational_Document_Workflows"("Operational_Flight_ID","Carrier_IATA","Final_Load_Plan_Edition","Load_Plan_Finalised_By","Load_Plan_Finalised_At","Updated_By")
 values(p_operational_flight_id,p_iata,p_edition,auth.uid(),now(),auth.uid())
 on conflict("Operational_Flight_ID")do update set "Final_Load_Plan_Edition"=excluded."Final_Load_Plan_Edition","Load_Plan_Finalised_By"=auth.uid(),"Load_Plan_Finalised_At"=now(),"NOTOC_Status"=case when "Basic_Carrier_Record"."Operational_Document_Workflows"."NOTOC_Status"='FINAL'then'DRAFT'else "Basic_Carrier_Record"."Operational_Document_Workflows"."NOTOC_Status" end,"NOTOC_Snapshot"=null,"NOTOC_Released_By"=null,"NOTOC_Released_At"=null,"Loadsheet_Status"='EMPTY',"Loadsheet_Snapshot"=null,"Loadsheet_Produced_By"=null,"Loadsheet_Produced_At"=null,"Updated_By"=auth.uid(),"Updated_At"=now();
 insert into "Basic_Carrier_Record"."Operational_Flight_Events"("Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data","Actor_User_ID")values(p_operational_flight_id,p_iata,'UPDATED',f."Status",f."Status",jsonb_build_object('action','LOAD_PLAN_FINALISED','loadPlanEdition',p_edition),auth.uid());
 return "Basic_Carrier_Record".get_operational_documents(p_iata,p_operational_flight_id);
end$$;

create or replace function "Basic_Carrier_Record".save_operational_notoc(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_finalise boolean,p_details jsonb,p_snapshot jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_version integer;final_edition integer;current_edition integer;next_status text;f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then raise exception 'Permission denied' using errcode='42501';end if;
 if p_details is null or jsonb_typeof(p_details)<>'array'then raise exception 'NOTOC details are incomplete' using errcode='22023';end if;
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if not found then raise exception 'Operational flight not found' using errcode='22023';end if;
 select coalesce("NOTOC_Version",0),"Final_Load_Plan_Edition" into current_version,final_edition from "Basic_Carrier_Record"."Operational_Document_Workflows" where "Operational_Flight_ID"=p_operational_flight_id;
 select coalesce(max("Edition_Number"),0)into current_edition from "Basic_Carrier_Record"."Operational_Load_Plan_Editions" where "Operational_Flight_ID"=p_operational_flight_id;
 current_version:=coalesce(current_version,0);
 if current_version<>p_expected_version then raise exception 'The NOTOC has changed in another session. Reload before saving.' using errcode='40001';end if;
 if p_finalise and(final_edition is null or final_edition<>current_edition)then raise exception 'Finalise the current load plan before finalising the NOTOC.' using errcode='22023';end if;
 next_status:=case when jsonb_array_length(p_details)=0 then'NOT_REQUIRED'when p_finalise then'FINAL'else'DRAFT'end;
 insert into "Basic_Carrier_Record"."Operational_Document_Workflows"("Operational_Flight_ID","Carrier_IATA","NOTOC_Version","NOTOC_Status","NOTOC_Details","NOTOC_Snapshot","NOTOC_Released_By","NOTOC_Released_At","Updated_By")
 values(p_operational_flight_id,p_iata,1,next_status,p_details,case when p_finalise then p_snapshot else null end,case when p_finalise then auth.uid()else null end,case when p_finalise then now()else null end,auth.uid())
 on conflict("Operational_Flight_ID")do update set "NOTOC_Version"="Basic_Carrier_Record"."Operational_Document_Workflows"."NOTOC_Version"+1,"NOTOC_Status"=excluded."NOTOC_Status","NOTOC_Details"=excluded."NOTOC_Details","NOTOC_Snapshot"=excluded."NOTOC_Snapshot","NOTOC_Released_By"=excluded."NOTOC_Released_By","NOTOC_Released_At"=excluded."NOTOC_Released_At","Updated_By"=auth.uid(),"Updated_At"=now();
 insert into "Basic_Carrier_Record"."Operational_Flight_Events"("Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data","Actor_User_ID")values(p_operational_flight_id,p_iata,'UPDATED',f."Status",f."Status",jsonb_build_object('action',case when p_finalise then'NOTOC_FINALISED'else'NOTOC_DRAFT_SAVED'end,'notocStatus',next_status),auth.uid());
 return "Basic_Carrier_Record".get_operational_documents(p_iata,p_operational_flight_id);
end$$;

create or replace function "Basic_Carrier_Record".produce_operational_loadsheet(p_iata text,p_operational_flight_id uuid,p_expected_number integer,p_snapshot jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_number integer;final_edition integer;fuel_status text;notoc_status text;f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then raise exception 'Permission denied' using errcode='42501';end if;
 if p_snapshot is null or jsonb_typeof(p_snapshot)<>'object'then raise exception 'Loadsheet data are incomplete' using errcode='22023';end if;
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if not found then raise exception 'Operational flight not found' using errcode='22023';end if;
 select coalesce("Loadsheet_Number",0),"Final_Load_Plan_Edition","NOTOC_Status" into current_number,final_edition,notoc_status from "Basic_Carrier_Record"."Operational_Document_Workflows" where "Operational_Flight_ID"=p_operational_flight_id;
 select "Status"into fuel_status from "Basic_Carrier_Record"."Operational_Fuel_Plans" where "Operational_Flight_ID"=p_operational_flight_id;
 current_number:=coalesce(current_number,0);
 if current_number<>p_expected_number then raise exception 'The loadsheet has changed in another session. Reload before producing another version.' using errcode='40001';end if;
 if final_edition is null or final_edition<>coalesce((p_snapshot->>'loadPlanEdition')::integer,0)then raise exception 'Finalise the current load plan before producing the loadsheet.' using errcode='22023';end if;
 if notoc_status not in('FINAL','NOT_REQUIRED')then raise exception 'Complete the NOTOC workflow before producing the loadsheet.' using errcode='22023';end if;
 if fuel_status is distinct from'FINAL'then raise exception 'Finalise the fuel data before producing the loadsheet.' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Operational_Document_Workflows"("Operational_Flight_ID","Carrier_IATA","Loadsheet_Number","Loadsheet_Status","Loadsheet_Snapshot","Loadsheet_Produced_By","Loadsheet_Produced_At","Updated_By")
 values(p_operational_flight_id,p_iata,1,'FINAL',p_snapshot,auth.uid(),now(),auth.uid())
 on conflict("Operational_Flight_ID")do update set "Loadsheet_Number"="Basic_Carrier_Record"."Operational_Document_Workflows"."Loadsheet_Number"+1,"Loadsheet_Status"='FINAL',"Loadsheet_Snapshot"=excluded."Loadsheet_Snapshot","Loadsheet_Produced_By"=auth.uid(),"Loadsheet_Produced_At"=now(),"Updated_By"=auth.uid(),"Updated_At"=now();
 insert into "Basic_Carrier_Record"."Operational_Flight_Events"("Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data","Actor_User_ID")values(p_operational_flight_id,p_iata,'UPDATED',f."Status",f."Status",jsonb_build_object('action','LOADSHEET_PRODUCED','loadsheetNumber',current_number+1,'loadPlanEdition',final_edition),auth.uid());
 return "Basic_Carrier_Record".get_operational_documents(p_iata,p_operational_flight_id);
end$$;

revoke all on function "Basic_Carrier_Record".get_operational_documents(text,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".finalise_operational_load_plan(text,uuid,integer) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_notoc(text,uuid,integer,boolean,jsonb,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".produce_operational_loadsheet(text,uuid,integer,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_documents(text,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".finalise_operational_load_plan(text,uuid,integer) to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_notoc(text,uuid,integer,boolean,jsonb,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".produce_operational_loadsheet(text,uuid,integer,jsonb) to authenticated;
comment on table "Basic_Carrier_Record"."Operational_Document_Workflows" is 'Current final load-plan edition, editable and final NOTOC data, and immutable operational loadsheet output snapshot for a flight.';
notify pgrst,'reload schema';
commit;
