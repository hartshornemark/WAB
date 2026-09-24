begin;
create or replace function "Basic_Carrier_Record".get_aircraft_e3(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean;can_edit boolean;settings jsonb;water jsonb;service jsonb;locations jsonb;
begin
  can_view:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW');
  can_edit:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503'; end if;
  select to_jsonb(s) into settings from "Basic_Carrier_Record"."Carrier_Aircraft_E3_Settings" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(c."Potable_Water_Code"),'tankId',btrim(c."PW_Tank_Short_Form"),'tankName',btrim(l."PW_Tank_Name"),'weight',c."Potable_Water_Weight",'index',c."Potable_Water_Weight"*l."PW_Tnk_Index_Per_Weight_Unit",'remarks',c."Remarks") order by btrim(c."Potable_Water_Code"),btrim(c."PW_Tank_Short_Form")),'[]') into water
    from "Basic_Carrier_Record"."Aircraft_Potable_Water_Codes" c join "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" l on l."Carrier_IATA"=c."Carrier_IATA" and l."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and l."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and l."PW_Tank_Short_Form"=c."PW_Tank_Short_Form"
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(s."Service_Weight_Adjustment_Code"),'description',s."Service_Weight_Adjustment_Description",'weight',s."Service_Weight_Adjustment_Weight",'balanceArm',s."Service_Weight_Adjustment_Balance_Arm",'index',s."Service_Weight_Adjustment_Index",'remarks',s."Remarks") order by btrim(s."Service_Weight_Adjustment_Code")),'[]') into service
    from "Basic_Carrier_Record"."Aircraft_Service_Weight_Adjustment_Codes" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('id',btrim(l."PW_Tank_Short_Form"),'name',btrim(l."PW_Tank_Name"),'indexPerWeightUnit',l."PW_Tnk_Index_Per_Weight_Unit") order by btrim(l."PW_Tank_Short_Form")),'[]') into locations
    from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" l where l."Carrier_IATA"=p_iata and l."Aircraft_Type_IATA"=tc and l."Aircraft_Series_Subtype"=st;
  return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(coalesce(settings::text,'null')||water::text||service::text||locations::text),'typeCode',tc,'subtype',st,
    'applicabilityReviewed',settings is not null,'waterAvailable',jsonb_array_length(locations)>0,'waterActive',coalesce((settings->>'Potable_Water_Active')::boolean,false) and jsonb_array_length(locations)>0,'serviceActive',coalesce((settings->>'Service_Adjustments_Active')::boolean,false),
    'waterRows',water,'serviceRows',service,'waterLocations',locations);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e3_applicability(p_iata text,p_type_code text,p_subtype text,p_revision text,p_water_active boolean,p_service_active boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_e3(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if p_water_active and not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" l where l."Carrier_IATA"=p_iata and l."Aircraft_Type_IATA"=tc and l."Aircraft_Series_Subtype"=st) then raise exception 'Configure a D6 Potable Water Location first' using errcode='23514'; end if;
  insert into "Basic_Carrier_Record"."Carrier_Aircraft_E3_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Potable_Water_Active","Service_Adjustments_Active","Updated_At") values(p_iata,tc,st,p_water_active,p_service_active,now())
  on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Potable_Water_Active"=excluded."Potable_Water_Active","Service_Adjustments_Active"=excluded."Service_Adjustments_Active","Updated_At"=now();
  return "Basic_Carrier_Record".get_aircraft_e3(p_iata,tc,st);
end $$;
commit;
