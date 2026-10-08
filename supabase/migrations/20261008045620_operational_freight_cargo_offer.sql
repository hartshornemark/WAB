begin;

create or replace function "Basic_Carrier_Record".get_operational_freight_planning(
  p_iata text,
  p_operational_flight_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype;
  can_operate boolean;
  base_weight integer;
  crew_adjustment integer:=0;
  pantry_adjustment integer:=0;
  planning_weight integer;
  maximum_zfw integer;
  cargo_density numeric;
  uld_capacity bigint:=0;
  bulk_capacity bigint:=0;
  structural_capacity bigint;
  space_capacity bigint;
  offer_weight bigint;
  limiting_factor text;
  registrations jsonb;
  crew_codes jsonb;
  pantry_codes jsonb;
  position_groups jsonb;
  bulk_holds jsonb;
  missing jsonb:='[]'::jsonb;
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')
    or private.has_global_permission('LOAD_CONTROL_VIEW')
  ) then raise exception 'Load Control access denied' using errcode='42501';end if;
  can_operate:=private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE');

  select * into f from "Basic_Carrier_Record"."Operational_Flights"
  where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
  if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;

  select * into aircraft from "Basic_Carrier_Record"."Basic_Aircraft_Data"
  where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
    and "Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype";
  if not found then raise exception 'Aircraft configuration not found' using errcode='23503';end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'registration',btrim(x."Aircraft_Registration"),
    'weight',case when aircraft."Start_Weight_Principle"='DRY_OPERATING_WEIGHT' then x."Dry_Operating_Weight" else x."Basic_Weight" end
  ) order by btrim(x."Aircraft_Registration")),'[]'::jsonb)
  into registrations
  from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" x
  where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
    and x."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and x."E1_2_Registration_Reference";

  select coalesce(jsonb_agg(jsonb_build_object('code',q.code,'isBase',q.is_base) order by q.code),'[]'::jsonb)
  into crew_codes from(
    select btrim(c."Crew_Code_ID") code,bool_or(c."Is_DOW_Base") is_base
    from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype"
    group by btrim(c."Crew_Code_ID")
  ) q;
  select coalesce(jsonb_agg(jsonb_build_object('code',q.code,'isBase',q.is_base) order by q.code),'[]'::jsonb)
  into pantry_codes from(
    select btrim(c."Pantry_Code_ID") code,bool_or(c."Is_DOW_Base") is_base
    from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype"
    group by btrim(c."Pantry_Code_ID")
  ) q;

  if aircraft."Aircraft_Operating_Role"<>'FREIGHTER' then
    return jsonb_build_object('applicable',false,'operatingRole',aircraft."Aircraft_Operating_Role",'canEdit',can_operate);
  end if;

  if f."Aircraft_Registration" is null then
    base_weight:=aircraft."Standard_Fleet_Weight";
  else
    select case when aircraft."Start_Weight_Principle"='DRY_OPERATING_WEIGHT' then x."Dry_Operating_Weight" else x."Basic_Weight" end
    into base_weight
    from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" x
    where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and x."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and x."E1_2_Registration_Reference"
      and btrim(x."Aircraft_Registration")=btrim(f."Aircraft_Registration");
  end if;

  if aircraft."Start_Weight_Principle"='DRY_OPERATING_WEIGHT' then
    select coalesce(max(c."DOW_Weight_Adjustment"),0) into crew_adjustment
    from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(c."Crew_Code_ID")=btrim(f."Crew_Code_ID");
    select coalesce(max(c."DOW_Weight_Adjustment"),0) into pantry_adjustment
    from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(c."Pantry_Code_ID")=btrim(f."Pantry_Code_ID");
    planning_weight:=base_weight+crew_adjustment+pantry_adjustment;
  else
    planning_weight:=null;
    missing:=missing||jsonb_build_array('DOW_REQUIRED');
  end if;

  select coalesce(
    (select w."Zero_Fuel_Weight" from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" w
      where w."Carrier_IATA"=p_iata and w."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
        and w."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and w."Table_Name"='ALL'
        and w."Carrier_Variant_Code"=f."Aircraft_Series_Subtype"
        and (w."Aircraft_Registration" is null or btrim(w."Aircraft_Registration")=btrim(f."Aircraft_Registration"))
      order by (w."Aircraft_Registration" is not null) desc limit 1),
    aircraft."MZFW"
  ) into maximum_zfw;
  select u."Density_General_Cargo"::numeric into cargo_density
  from "Basic_Carrier_Record"."Carrier_Units_of_Measure" u where u."Carrier_IATA"=p_iata;

  with selected_config as(
    select distinct on(c."Hold_Name_ID") c."Hold_Name_ID",c."ULD_Configuration_Code"
    from "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype"
    order by c."Hold_Name_ID",c."ULD_Configuration_Code"
  ), groups as(
    select h."Hold_Deck_Location" deck,p."ULD_Type" uld_type,p."ULD_Code" uld_code,
      count(*)::integer position_count,sum(p."ULD_Position_Max_Weight")::bigint maximum_weight
    from selected_config c
    join "Basic_Carrier_Record"."Carrier_ULD_Positions" p
      on p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and p."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and p."Hold_Name_ID"=c."Hold_Name_ID"
      and p."ULD_Configuration_Code"=c."ULD_Configuration_Code" and p."ULD_Row_Type"='POSITION'
    join "Basic_Carrier_Record"."Aircraft_Holds" h
      on h."Carrier_IATA"=p."Carrier_IATA" and h."Aircraft_Type_IATA"=p."Aircraft_Type_IATA"
      and h."Aircraft_Series_Subtype"=p."Aircraft_Series_Subtype" and h."Hold_Name_ID"=p."Hold_Name_ID"
    group by h."Hold_Deck_Location",p."ULD_Type",p."ULD_Code"
  ) select coalesce(jsonb_agg(jsonb_build_object('deck',deck,'uldType',uld_type,'uldCode',uld_code,
      'positionCount',position_count,'maximumWeight',maximum_weight) order by case deck when 'MDECK' then 1 else 2 end,uld_type),'[]'::jsonb),
      coalesce(sum(maximum_weight),0)
    into position_groups,uld_capacity from groups;

  with rows as(
    select btrim(h."Hold_Name_ID") hold_id,btrim(coalesce(h."Hold_Display_Name",h."Hold_Name_ID")) hold_name,
      h."Hold_MAX_Weight"::bigint maximum_weight,h."Hold_MAX_Volume"::numeric volume,
      case when h."Hold_MAX_Weight" is null or h."Hold_MAX_Volume" is null or cargo_density is null then null
        else least(h."Hold_MAX_Weight"::numeric,round(h."Hold_MAX_Volume"::numeric*cargo_density))::bigint end planning_weight
    from "Basic_Carrier_Record"."Aircraft_Holds" h
    where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and h."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(h."Hold_Type")='BLK'
  ) select coalesce(jsonb_agg(jsonb_build_object('holdId',hold_id,'name',hold_name,'maximumWeight',maximum_weight,
      'volume',volume,'planningWeight',planning_weight) order by hold_id),'[]'::jsonb),coalesce(sum(planning_weight),0)
    into bulk_holds,bulk_capacity from rows;

  if base_weight is null then missing:=missing||jsonb_build_array('AIRCRAFT_WEIGHT');end if;
  if f."Crew_Code_ID" is null then missing:=missing||jsonb_build_array('CREW_CODE');end if;
  if f."Pantry_Code_ID" is null then missing:=missing||jsonb_build_array('PANTRY_CODE');end if;
  if maximum_zfw is null then missing:=missing||jsonb_build_array('MZFW');end if;
  if cargo_density is null then missing:=missing||jsonb_build_array('B1_CARGO_DENSITY');end if;
  if jsonb_array_length(position_groups)=0 then missing:=missing||jsonb_build_array('ULD_POSITIONS');end if;

  structural_capacity:=greatest(0,maximum_zfw-planning_weight);
  space_capacity:=uld_capacity+bulk_capacity;
  offer_weight:=least(structural_capacity,space_capacity);
  limiting_factor:=case when structural_capacity<=space_capacity then 'MZFW' else 'HOLD_CAPACITY' end;

  return jsonb_build_object(
    'applicable',true,'operatingRole',aircraft."Aircraft_Operating_Role",'canEdit',can_operate,'version',f."Version",
    'weightBasis',case when f."Aircraft_Registration" is null then 'FLEET_WEIGHT' else 'REGISTRATION' end,
    'registration',f."Aircraft_Registration",'crewCode',f."Crew_Code_ID",'pantryCode',f."Pantry_Code_ID",
    'startWeightPrinciple',aircraft."Start_Weight_Principle",'fleetWeight',aircraft."Standard_Fleet_Weight",
    'planningAircraftWeight',planning_weight,'crewWeightAdjustment',crew_adjustment,'pantryWeightAdjustment',pantry_adjustment,
    'mzfw',maximum_zfw,'structuralCapacity',structural_capacity,'cargoPlanningDensity',cargo_density,
    'uldPositionGroups',position_groups,'uldWeightCapacity',uld_capacity,'bulkHolds',bulk_holds,
    'bulkWeightCapacity',bulk_capacity,'spaceWeightCapacity',space_capacity,'cargoOfferWeight',offer_weight,
    'limitingFactor',limiting_factor,'ready',jsonb_array_length(missing)=0,'missing',missing,
    'registrationOptions',registrations,'crewOptions',crew_codes,'pantryOptions',pantry_codes
  );
end;
$$;

revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;

create or replace function "Basic_Carrier_Record".save_operational_freight_planning(
  p_iata text,
  p_operational_flight_id uuid,
  p_version integer,
  p_values jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  weight_basis text:=upper(btrim(p_values->>'weightBasis'));
  registration text:=nullif(upper(btrim(p_values->>'registration')),'');
  crew_code text:=nullif(upper(btrim(p_values->>'crewCode')),'');
  pantry_code text:=nullif(upper(btrim(p_values->>'pantryCode')),'');
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')
    or private.has_global_permission('LOAD_CONTROL_OPERATE')
  ) then raise exception 'Load Control operation denied' using errcode='42501';end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' or weight_basis not in('FLEET_WEIGHT','REGISTRATION')
    or crew_code!~'^[A-Z0-9]$' or pantry_code!~'^[A-Z0-9]$'
    or (weight_basis='REGISTRATION' and registration is null)
    or (weight_basis='FLEET_WEIGHT' and registration is not null)
  then raise exception 'Check the freight planning selections' using errcode='22023';end if;

  select * into f from "Basic_Carrier_Record"."Operational_Flights"
  where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
  if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
  if f."Version"<>p_version then raise exception 'The flight changed. Reload before saving.' using errcode='40001';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
    where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and a."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and a."Aircraft_Operating_Role"='FREIGHTER')
  then raise exception 'Cargo Offer is available for freighter aircraft' using errcode='23514';end if;
  if weight_basis='REGISTRATION' and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" x
    where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and x."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and x."E1_2_Registration_Reference"
      and btrim(x."Aircraft_Registration")=registration)
  then raise exception 'Select a valid aircraft registration' using errcode='23503';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(c."Crew_Code_ID")=crew_code)
  then raise exception 'Select a valid crew code' using errcode='23503';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(c."Pantry_Code_ID")=pantry_code)
  then raise exception 'Select a valid pantry code' using errcode='23503';end if;

  update "Basic_Carrier_Record"."Operational_Flights" set
    "Aircraft_Registration"=registration,"Crew_Code_ID"=crew_code,"Pantry_Code_ID"=pantry_code,
    "Status"=case when "Status"='INITIATED' then 'LOAD_PLANNING' else "Status" end
  where "Operational_Flight_ID"=p_operational_flight_id and "Carrier_IATA"=p_iata;
  return "Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);
end;
$$;

revoke all on function "Basic_Carrier_Record".save_operational_freight_planning(text,uuid,integer,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_freight_planning(text,uuid,integer,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
