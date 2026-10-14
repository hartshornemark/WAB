alter table "Basic_Carrier_Record"."Aircraft_Holds"
 add column if not exists "Hold_DOOR_Anchor_Type" varchar(20),
 add column if not exists "Hold_DOOR_Anchor_Ref" varchar(20);
alter table "Basic_Carrier_Record"."Aircraft_Holds" drop constraint if exists "Aircraft_Holds_Door_Anchor_check";
alter table "Basic_Carrier_Record"."Aircraft_Holds" add constraint "Aircraft_Holds_Door_Anchor_check" check (
 ("Hold_DOOR_Anchor_Type" is null and "Hold_DOOR_Anchor_Ref" is null) or
 ("Hold_DOOR_Anchor_Type" in ('COMPARTMENT','AREA','ULD_POSITION') and nullif(btrim("Hold_DOOR_Anchor_Ref"),'') is not null)
);

create or replace function "Basic_Carrier_Record".get_aircraft_d4(p_iata text,p_type_code text,p_subtype text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');doors_active boolean:=false;locks_active boolean:=false;missing_active boolean:=false;door_rows jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select s."Doors_Active",s."Locks_Active",s."Missing_Restraints_Active" into doors_active,locks_active,missing_active from "Basic_Carrier_Record"."Carrier_Aircraft_D4_Settings" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st;
 doors_active:=coalesce(doors_active,false);locks_active:=coalesce(locks_active,false);missing_active:=coalesce(missing_active,false);
 select coalesce(jsonb_agg(jsonb_build_object('holdId',btrim(h."Hold_Name_ID"),'holdType',btrim(h."Hold_Type"),'deckName',coalesce(d."Deck_Display_Name",h."Hold_Deck_Location"),'forwardArm',h."Hold_DOOR_Start",'aftArm',h."Hold_DOOR_End",'height',h."Hold_DOOR_Height",'orientation',nullif(btrim(h."Hold_DOOR_Orientation"),''),'anchorType',h."Hold_DOOR_Anchor_Type",'anchorRef',h."Hold_DOOR_Anchor_Ref") order by private.aircraft_hold_sort_arm(h."Carrier_IATA"::text,h."Aircraft_Type_IATA"::text,h."Aircraft_Series_Subtype"::text,h."Hold_Name_ID"::text) asc nulls last,btrim(h."Hold_Name_ID")),'[]'::jsonb) into door_rows from "Basic_Carrier_Record"."Aircraft_Holds" h left join "Basic_Carrier_Record"."MASTER_Deck_Types" d on d."Deck_Code"=h."Hold_Deck_Location" where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and coalesce(h."Hold_Has_Door",true);
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(jsonb_build_object('doorsActive',doors_active,'locksActive',locks_active,'missingRestraintsActive',missing_active,'doors',door_rows)::text),'typeCode',tc,'subtype',st,'doorsActive',doors_active,'locksActive',locks_active,'missingRestraintsActive',missing_active,'doors',door_rows);
end$$;

create or replace function "Basic_Carrier_Record".save_aircraft_d4(p_iata text,p_type_code text,p_subtype text,p_revision text,p_doors jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;item jsonb;hold_id text;forward_arm double precision;aft_arm double precision;door_height double precision;door_orientation text;anchor_type text;anchor_ref text;valid_anchor boolean;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='PT409';end if;
 if jsonb_typeof(p_doors)<>'array' or jsonb_array_length(p_doors)<>(select count(*) from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and coalesce("Hold_Has_Door",true)) then raise exception 'Every hold requires one door' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_doors) loop
  hold_id:=upper(btrim(item->>'holdId'));forward_arm:=nullif(item->>'forwardArm','')::double precision;aft_arm:=nullif(item->>'aftArm','')::double precision;door_height:=nullif(item->>'height','')::double precision;door_orientation:=nullif(upper(btrim(item->>'orientation')),'');anchor_type:=nullif(upper(btrim(item->>'anchorType')),'');anchor_ref:=nullif(upper(btrim(item->>'anchorRef')),'');
  if (forward_arm is null)<>(aft_arm is null) or (anchor_type is null)<>(anchor_ref is null) then raise exception 'Incomplete door definition' using errcode='23514';end if;
  if anchor_type is not null then
   valid_anchor:=case anchor_type
    when 'COMPARTMENT' then exists(select 1 from "Basic_Carrier_Record"."Aircraft_Compartments" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and btrim(c."Hold_Name_ID")=hold_id and upper(btrim(c."Compartment_ID"))=anchor_ref)
    when 'AREA' then exists(select 1 from "Basic_Carrier_Record"."Aircraft_Compartment_Areas" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st and btrim(a."Hold_Name_ID")=hold_id and upper(btrim(a."Area_ID"))=anchor_ref)
    when 'ULD_POSITION' then exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and btrim(p."Hold_Name_ID")=hold_id and p."ULD_Row_Type"='POSITION' and upper(btrim(p."ULD_Position_ID"))=anchor_ref)
    else false end;
   if not valid_anchor then raise exception 'Door anchor does not belong to hold' using errcode='23503';end if;
  end if;
  update "Basic_Carrier_Record"."Aircraft_Holds" set "Hold_DOOR_Start"=forward_arm,"Hold_DOOR_End"=aft_arm,"Hold_DOOR_Height"=door_height,"Hold_DOOR_Orientation"=door_orientation,"Hold_DOOR_Anchor_Type"=anchor_type,"Hold_DOOR_Anchor_Ref"=anchor_ref where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id and coalesce("Hold_Has_Door",true);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);
end$$;
