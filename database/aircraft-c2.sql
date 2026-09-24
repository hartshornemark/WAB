begin;

alter policy "perm_operating_select" on "Basic_Carrier_Record"."Carrier_Loadsheet_Options"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
alter policy "perm_operating_insert" on "Basic_Carrier_Record"."Carrier_Loadsheet_Options"
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_operating_update" on "Basic_Carrier_Record"."Carrier_Loadsheet_Options"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_operating_delete" on "Basic_Carrier_Record"."Carrier_Loadsheet_Options"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

alter policy "perm_operating_select" on "Basic_Carrier_Record"."Carrier_Document_Requirements"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
alter policy "perm_operating_insert" on "Basic_Carrier_Record"."Carrier_Document_Requirements"
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_operating_update" on "Basic_Carrier_Record"."Carrier_Document_Requirements"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_operating_delete" on "Basic_Carrier_Record"."Carrier_Document_Requirements"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

-- The table was introduced empty. Replace its surrogate-key structure with
-- the carrier-aircraft-trim identity used by Sheet C2.
alter table "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output"
  drop constraint "Carrier_Passenger_Trim_Output_pkey",
  drop column "TRIM_Option_UUID",
  add column "Aircraft_Series_Subtype" varchar(4),
  alter column "Carrier_IATA" type varchar(2),
  alter column "Aircraft_Type_IATA" type varchar(3),
  alter column "TRIM_Option" type varchar(32),
  alter column "TRIM_Option_Priority" drop not null;

alter table "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output"
  alter column "Aircraft_Series_Subtype" set not null,
  add constraint "Carrier_Passenger_Trim_Output_pkey"
    primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","TRIM_Option"),
  add constraint "Carrier_Passenger_Trim_Output_Aircraft_fkey"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data" ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update restrict on delete cascade,
  add constraint "Carrier_Passenger_Trim_Output_Option_fkey"
    foreign key ("TRIM_Option")
    references "Basic_Carrier_Record"."MASTER_Passenger_Trim_Output" ("TRIM_Option")
    on update restrict on delete restrict,
  add constraint "Carrier_Passenger_Trim_Output_Priority_check"
    check (("Is_Option_Selected" and "TRIM_Option_Priority" between 1 and 3)
       or (not "Is_Option_Selected" and "TRIM_Option_Priority" is null));

create unique index "Carrier_Passenger_Trim_Output_Selected_Priority_key"
  on "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","TRIM_Option_Priority")
  where "Is_Option_Selected";

alter table "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output" enable row level security;
revoke all on table "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output" from public,anon,authenticated;
grant select,insert,update,delete on table "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output" to authenticated;
create policy "aircraft_c2_trim_select" on "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output"
  for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "aircraft_c2_trim_insert" on "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output"
  for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_c2_trim_update" on "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output"
  for update to authenticated
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_c2_trim_delete" on "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output"
  for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

create table "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Passenger_Trim_Remarks" text null,
  "Captains_Information" text null,
  "Pre_LMC_Load_Message" text null,
  "Updated_At" timestamptz not null default now(),
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data" ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update restrict on delete cascade,
  check ("Passenger_Trim_Remarks" is null or ("Passenger_Trim_Remarks"=btrim("Passenger_Trim_Remarks") and char_length("Passenger_Trim_Remarks") between 1 and 1000)),
  check ("Captains_Information" is null or ("Captains_Information"=btrim("Captains_Information") and char_length("Captains_Information") between 1 and 2000)),
  check ("Pre_LMC_Load_Message" is null or ("Pre_LMC_Load_Message"=btrim("Pre_LMC_Load_Message") and char_length("Pre_LMC_Load_Message") between 1 and 2000))
);

alter table "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings" enable row level security;
revoke all on table "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings" from public,anon,authenticated;
grant select,insert,update,delete on table "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings" to authenticated;
create policy "aircraft_c2_settings_select" on "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings"
  for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "aircraft_c2_settings_insert" on "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings"
  for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_c2_settings_update" on "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings"
  for update to authenticated
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_c2_settings_delete" on "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings"
  for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

create table "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Output_Short_Code" char(9) not null,
  "Remarks" text null,
  "Use_Reference_Chord" boolean not null default false,
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Output_Short_Code"),
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data" ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update restrict on delete cascade,
  foreign key ("Output_Short_Code")
    references "Basic_Carrier_Record"."MASTER_Loadsheet_Output_Naming_Conventions" ("Output_Short_Code")
    on update restrict on delete restrict,
  check ("Remarks" is null or ("Remarks"=btrim("Remarks") and char_length("Remarks") between 1 and 500)),
  check (not "Use_Reference_Chord" or btrim("Output_Short_Code") in ('MACDLW','MACZFW','MACTOW','MACLAW'))
);

alter table "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks" enable row level security;
revoke all on table "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks" from public,anon,authenticated;
grant select,insert,update,delete on table "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks" to authenticated;
create policy "aircraft_c2_output_remarks_select" on "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks"
  for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "aircraft_c2_output_remarks_insert" on "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks"
  for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_c2_output_remarks_update" on "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks"
  for update to authenticated
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_c2_output_remarks_delete" on "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks"
  for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

notify pgrst,'reload schema';
commit;

begin;

create function "Basic_Carrier_Record".get_aircraft_c2(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  can_view boolean := (select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean := private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  tc text := upper(btrim(p_type_code));
  st text := upper(btrim(p_subtype));
  output_rows jsonb;
  document_rows jsonb;
  trim_rows jsonb;
  output_remark_rows jsonb;
  settings_row jsonb;
  revision_text text;
  has_saved_trim boolean;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then
    raise exception 'Aircraft not found' using errcode='23503';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code',btrim(m."Output_Short_Code"::text),'name',btrim(m."Long_Name"::text),'group',m."Output_Group",'displayOrder',m."Display_Order",
    'validEdpPrelim',coalesce(m."VALID_AHM517_EDP_Prelim",false),'validAcarsPrelim',coalesce(m."VALID_AHM518_ACARS_Prelim",false),
    'validEdpFinal',coalesce(m."VALID_AHM517_EDP_Final",false),'validAcarsFinal',coalesce(m."VALID_AHM518_ACARS_Final",false),
    'selectedEdpPrelim',exists(select 1 from "Basic_Carrier_Record"."Carrier_Loadsheet_Options" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and c."Output_Short_Code"=m."Output_Short_Code" and c."Document_Short_Code"='LS EDP PRELIM' and c."Required"),
    'selectedAcarsPrelim',exists(select 1 from "Basic_Carrier_Record"."Carrier_Loadsheet_Options" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and c."Output_Short_Code"=m."Output_Short_Code" and c."Document_Short_Code"='LS ACARS PRELIM' and c."Required"),
    'selectedEdpFinal',exists(select 1 from "Basic_Carrier_Record"."Carrier_Loadsheet_Options" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and c."Output_Short_Code"=m."Output_Short_Code" and c."Document_Short_Code"='LS EDP FINAL' and c."Required"),
    'selectedAcarsFinal',exists(select 1 from "Basic_Carrier_Record"."Carrier_Loadsheet_Options" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and c."Output_Short_Code"=m."Output_Short_Code" and c."Document_Short_Code"='LS ACARS FINAL' and c."Required")
  ) order by m."Display_Order",btrim(m."Output_Short_Code"::text)),'[]'::jsonb) into output_rows
  from "Basic_Carrier_Record"."MASTER_Loadsheet_Output_Naming_Conventions" m;

  select coalesce(jsonb_agg(jsonb_build_object('code',m."Document_Short_Code",'name',btrim(m."Document_Long_Name"),'ahmReference',coalesce(btrim(m."Document_AHM_Reference"),''),'suggested',m."Document_Required",'required',coalesce(c."Document-Required",m."Document_Required")) order by m."Document_Short_Code"),'[]'::jsonb) into document_rows
  from "Basic_Carrier_Record"."MASTER__Document_Requirements" m
  left join "Basic_Carrier_Record"."Carrier_Document_Requirements" c on c."Carrier_IATA"=p_iata and c."Document_Short_Code"=m."Document_Short_Code"
  where m."Document_Short_Code" like 'LS %';

  select exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) into has_saved_trim;
  select coalesce(jsonb_agg(jsonb_build_object('option',m."TRIM_Option",'suggested',m."Required",'selected',case when has_saved_trim then coalesce(c."Is_Option_Selected",false) else m."Required" end,'priority',case when has_saved_trim then c."TRIM_Option_Priority" else case when m."Required" then 1 else null end end) order by m."TRIM_Option"),'[]'::jsonb) into trim_rows
  from "Basic_Carrier_Record"."MASTER_Passenger_Trim_Output" m
  left join "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output" c on c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and c."TRIM_Option"=m."TRIM_Option";

  select coalesce(jsonb_agg(jsonb_build_object('code',btrim("Output_Short_Code"::text),'remarks',coalesce("Remarks",''),'useReferenceChord',"Use_Reference_Chord") order by btrim("Output_Short_Code"::text)),'[]'::jsonb) into output_remark_rows
  from "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;

  select coalesce(to_jsonb(s),'{}'::jsonb) into settings_row from "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st;
  settings_row := coalesce(settings_row,'{}'::jsonb);
  revision_text := md5(output_rows::text||document_rows::text||trim_rows::text||output_remark_rows::text||settings_row::text);

  return jsonb_build_object('canView',can_view,'canEdit',can_edit,'exists',has_saved_trim or settings_row<>'{}'::jsonb or output_remark_rows<>'[]'::jsonb or exists(select 1 from "Basic_Carrier_Record"."Carrier_Loadsheet_Options" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),
    'revision',revision_text,'typeCode',tc,'subtype',st,'outputs',output_rows,'documents',document_rows,'trimOptions',trim_rows,'trimSaved',has_saved_trim,'outputRemarks',output_remark_rows,
    'passengerTrimRemarks',coalesce(settings_row->>'Passenger_Trim_Remarks',''),'captainsInformation',coalesce(settings_row->>'Captains_Information',''),'preLmcLoadMessage',coalesce(settings_row->>'Pre_LMC_Load_Message',''));
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_c2(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c2(text,text,text) to authenticated;

create function "Basic_Carrier_Record".save_aircraft_c2(p_iata text,p_type_code text,p_subtype text,p_revision text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text := upper(btrim(p_type_code)); st text := upper(btrim(p_subtype)); current_data jsonb;
  trim_count integer; priority_count integer; item jsonb; doc text; code text;
begin
  if (select auth.uid()) is null or not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503'; end if;
  current_data := "Basic_Carrier_Record".get_aircraft_c2(p_iata,tc,st);
  if p_revision is distinct from current_data->>'revision' then raise exception 'C2 data changed' using errcode='40001'; end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'outputs')<>'array' or jsonb_typeof(p_values->'documents')<>'array' or jsonb_typeof(p_values->'trimOptions')<>'array' or jsonb_typeof(p_values->'outputRemarks')<>'array' then raise exception 'Invalid C2 data' using errcode='22023'; end if;

  if char_length(btrim(coalesce(p_values->>'passengerTrimRemarks','')))>1000 or char_length(btrim(coalesce(p_values->>'captainsInformation','')))>2000 or char_length(btrim(coalesce(p_values->>'preLmcLoadMessage','')))>2000 then raise exception 'C2 text is too long' using errcode='22023'; end if;

  select count(*) filter(where (x->>'selected')::boolean),count(distinct (x->>'priority')::integer) filter(where (x->>'selected')::boolean) into trim_count,priority_count from jsonb_array_elements(p_values->'trimOptions') x;
  if trim_count<1 or trim_count<>priority_count or exists(select 1 from jsonb_array_elements(p_values->'trimOptions') x where (x->>'selected')::boolean and (x->>'priority')::integer not between 1 and 3) then raise exception 'Select at least one Passenger Trim option with unique priorities' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(p_values->'trimOptions') x left join "Basic_Carrier_Record"."MASTER_Passenger_Trim_Output" m on m."TRIM_Option"=x->>'option' where m."TRIM_Option" is null) then raise exception 'Unknown Passenger Trim option' using errcode='23503'; end if;

  delete from "Basic_Carrier_Record"."Carrier_Loadsheet_Options" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select * from jsonb_array_elements(p_values->'outputs') loop
    code:=item->>'code';
    foreach doc in array array['LS EDP PRELIM','LS ACARS PRELIM','LS EDP FINAL','LS ACARS FINAL'] loop
      if coalesce((item->>case doc when 'LS EDP PRELIM' then 'selectedEdpPrelim' when 'LS ACARS PRELIM' then 'selectedAcarsPrelim' when 'LS EDP FINAL' then 'selectedEdpFinal' else 'selectedAcarsFinal' end)::boolean,false)
        and exists (
          select 1
          from jsonb_array_elements(p_values->'documents') selected_document
          where selected_document->>'code'=doc
            and coalesce((selected_document->>'required')::boolean,false)
        ) then
        if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Loadsheet_Output_Naming_Conventions" m where btrim(m."Output_Short_Code"::text)=code and case doc when 'LS EDP PRELIM' then coalesce(m."VALID_AHM517_EDP_Prelim",false) when 'LS ACARS PRELIM' then coalesce(m."VALID_AHM518_ACARS_Prelim",false) when 'LS EDP FINAL' then coalesce(m."VALID_AHM517_EDP_Final",false) else coalesce(m."VALID_AHM518_ACARS_Final",false) end) then raise exception 'Invalid loadsheet output selection' using errcode='22023'; end if;
        insert into "Basic_Carrier_Record"."Carrier_Loadsheet_Options"("Carrier_IATA","Document_Short_Code","Output_Short_Code","Required","Aircraft_Type_IATA","Aircraft_Series_Subtype") select p_iata,doc,m."Output_Short_Code",true,tc,st from "Basic_Carrier_Record"."MASTER_Loadsheet_Output_Naming_Conventions" m where btrim(m."Output_Short_Code"::text)=code;
      end if;
    end loop;
  end loop;

  delete from "Basic_Carrier_Record"."Carrier_Document_Requirements" where "Carrier_IATA"=p_iata and "Document_Short_Code" like 'LS %';
  insert into "Basic_Carrier_Record"."Carrier_Document_Requirements"("Carrier_IATA","Document_Short_Code","Document_Long_Name","Document-Required")
  select p_iata,x->>'code',null,(x->>'required')::boolean from jsonb_array_elements(p_values->'documents') x
  join "Basic_Carrier_Record"."MASTER__Document_Requirements" m on m."Document_Short_Code"=x->>'code' where m."Document_Short_Code" like 'LS %';

  delete from "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  insert into "Basic_Carrier_Record"."Carrier_Passenger_Trim_Output"("TRIM_Option","Carrier_IATA","Aircraft_Type_IATA","TRIM_Option_Priority","Is_Option_Selected","Aircraft_Series_Subtype")
  select x->>'option',p_iata,tc,case when (x->>'selected')::boolean then (x->>'priority')::smallint else null end,(x->>'selected')::boolean,st from jsonb_array_elements(p_values->'trimOptions') x;

  delete from "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  insert into "Basic_Carrier_Record"."Carrier_Loadsheet_Output_Remarks"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Output_Short_Code","Remarks","Use_Reference_Chord")
  select p_iata,tc,st,m."Output_Short_Code",nullif(btrim(coalesce(x->>'remarks','')),''),coalesce((x->>'useReferenceChord')::boolean,false)
  from jsonb_array_elements(p_values->'outputRemarks') x join "Basic_Carrier_Record"."MASTER_Loadsheet_Output_Naming_Conventions" m on btrim(m."Output_Short_Code"::text)=x->>'code'
  where btrim(coalesce(x->>'remarks',''))<>'' or coalesce((x->>'useReferenceChord')::boolean,false);

  insert into "Basic_Carrier_Record"."Carrier_Aircraft_C2_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Passenger_Trim_Remarks","Captains_Information","Pre_LMC_Load_Message","Updated_At")
  values(p_iata,tc,st,nullif(btrim(coalesce(p_values->>'passengerTrimRemarks','')),''),nullif(btrim(coalesce(p_values->>'captainsInformation','')),''),nullif(btrim(coalesce(p_values->>'preLmcLoadMessage','')),''),now())
  on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Passenger_Trim_Remarks"=excluded."Passenger_Trim_Remarks","Captains_Information"=excluded."Captains_Information","Pre_LMC_Load_Message"=excluded."Pre_LMC_Load_Message","Updated_At"=now();
  return "Basic_Carrier_Record".get_aircraft_c2(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_c2(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c2(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
