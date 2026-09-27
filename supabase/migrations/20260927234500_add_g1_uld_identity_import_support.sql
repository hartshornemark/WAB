create or replace function "Basic_Carrier_Record".get_aircraft_g1(p_iata text, p_type_code text, p_subtype text)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  ci text:=upper(btrim(p_iata));
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean;
  can_edit boolean;
  applicable boolean;
  bays jsonb;
  uld_types jsonb;
  uld_identities jsonb;
  compatibilities jsonb;
  suggestions jsonb;
begin
  can_view:=private.has_carrier_permission(ci,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW');
  can_edit:=private.has_carrier_permission(ci,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=ci and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503'; end if;

  select c."ULD_Holds_Applicable" into applicable
  from "Basic_Carrier_Record"."Aircraft_Hold_Configuration" c
  where c."Carrier_IATA"=ci and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st;

  select coalesce(jsonb_agg(jsonb_build_object('holdId',x.hold_id,'bayId',x.bay_id) order by x.hold_id,x.bay_id),'[]'::jsonb) into bays
  from (
    select distinct btrim(p."Hold_Name_ID") hold_id,btrim(p."ULD_Position_ID") bay_id
    from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
    where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION'
  ) x;

  select coalesce(jsonb_agg(x.uld_type order by x.uld_type),'[]'::jsonb) into uld_types
  from (
    select distinct btrim(s."ULD_Type") uld_type
    from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
    where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('code',x.uld_id,'type',x.uld_type) order by x.uld_type,x.uld_id),'[]'::jsonb) into uld_identities
  from (
    select distinct btrim(s."ULD_ID") uld_id,btrim(s."ULD_Type") uld_type
    from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
    where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('bayId',btrim(c."Bay_ID"),'uldType',btrim(c."ULD_Type"),'compatible',c."ULD_Compatibility") order by btrim(c."Bay_ID"),btrim(c."ULD_Type")),'[]'::jsonb) into compatibilities
  from "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" c
  where c."Carrier_IATA"=ci and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_SubType"=st
    and exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Position_ID")=btrim(c."Bay_ID"))
    and exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st and btrim(s."ULD_Type")=btrim(c."ULD_Type"));

  select coalesce(jsonb_agg(jsonb_build_object('bayId',x.bay_id,'uldType',x.uld_type,'compatible',x.compatible) order by x.bay_id,x.uld_type),'[]'::jsonb) into suggestions
  from (
    select b.bay_id,u.uld_type,bool_or(b.bay_base_code=u.uld_base_code) filter(where b.bay_base_code is not null and u.uld_base_code is not null) compatible
    from (
      select distinct btrim(p."ULD_Position_ID") bay_id,nullif(btrim(p."ULD_Base_Code"),'') bay_base_code
      from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
      where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION'
    ) b
    cross join (
      select distinct btrim(s."ULD_Type") uld_type,nullif(btrim(m."ULD_Base_Code"),'') uld_base_code
      from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
      left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=s."Master_ULD_ID"
      where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st
    ) u
    group by b.bay_id,u.uld_type
  ) x;

  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,
    'revision',md5(jsonb_build_object('applicable',applicable,'bays',bays,'uldTypes',uld_types,'uldIdentities',uld_identities,'rows',compatibilities,'suggestions',suggestions)::text),
    'typeCode',tc,'subtype',st,'applicable',applicable,'bays',bays,'uldTypes',uld_types,'uldIdentities',uld_identities,'rows',compatibilities,'suggestions',suggestions
  );
end
$function$;

notify pgrst, 'reload schema';
