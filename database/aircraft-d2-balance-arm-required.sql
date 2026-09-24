begin;
alter table "Basic_Carrier_Record"."Aircraft_Holds"
  drop constraint "Aircraft_Holds_Balance_Arm_check",
  alter column "Hold_BA_Centroid" set not null,
  add constraint "Aircraft_Holds_Balance_Arm_check"
    check (("Hold_BA_Start" is null and "Hold_BA_End" is null) or
      ("Hold_BA_Start" is not null and "Hold_BA_End" is not null
       and "Hold_BA_Start" <= "Hold_BA_Centroid"
       and "Hold_BA_Centroid" <= "Hold_BA_End"));
alter table "Basic_Carrier_Record"."Aircraft_Hold_Configuration"
  add column "Bulk_Balance_Limits_Required" boolean not null default true,
  add column "ULD_Balance_Limits_Required" boolean not null default true;
create or replace function "Basic_Carrier_Record".get_aircraft_d2(
  p_iata text,p_type_code text,p_subtype text
) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and (
    private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW')
    or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')
  );
  can_edit boolean:=(
    private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT')
    or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
  );
  cfg "Basic_Carrier_Record"."Aircraft_Hold_Configuration"%rowtype;
  all_rows jsonb;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists (
    select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc
      and "Aircraft_Series_Subtype"=st
  ) then raise exception 'Aircraft not found' using errcode='23503'; end if;

  select * into cfg
  from "Basic_Carrier_Record"."Aircraft_Hold_Configuration"
  where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc
    and "Aircraft_Series_Subtype"=st;

  select coalesce(jsonb_agg(jsonb_build_object(
      'name',btrim(h."Hold_Name_ID"),
      'holdType',btrim(h."Hold_Type"),
      'deckCode',h."Hold_Deck_Location",
      'maxWeight',h."Hold_MAX_Weight",
      'maxVolume',h."Hold_MAX_Volume",
      'lateralCentroid',h."Hold_LA_Centroid",
      'lateralFrom',h."Hold_LA_Start",
      'lateralTo',h."Hold_LA_End",
      'balanceCentroid',h."Hold_BA_Centroid",
      'balanceFrom',h."Hold_BA_Start",
      'balanceTo',h."Hold_BA_End",
      'indexPerWeightUnit',h."Hold_Index_Per_Weight_Unit"
    ) order by btrim(h."Hold_Type"),btrim(h."Hold_Name_ID")),'[]'::jsonb)
  into all_rows
  from "Basic_Carrier_Record"."Aircraft_Holds" h
  where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc
    and h."Aircraft_Series_Subtype"=st;

  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,
    'revision',md5(jsonb_build_object(
      'bulkApplicable',cfg."Bulk_Holds_Applicable",
      'uldApplicable',cfg."ULD_Holds_Applicable",
      'bulkBalanceLimitsRequired',coalesce(cfg."Bulk_Balance_Limits_Required",true),
      'uldBalanceLimitsRequired',coalesce(cfg."ULD_Balance_Limits_Required",true),
      'rows',all_rows
    )::text),
    'typeCode',tc,'subtype',st,
    'bulkApplicable',cfg."Bulk_Holds_Applicable",
    'uldApplicable',cfg."ULD_Holds_Applicable",
    'bulkBalanceLimitsRequired',coalesce(cfg."Bulk_Balance_Limits_Required",true),
    'uldBalanceLimitsRequired',coalesce(cfg."ULD_Balance_Limits_Required",true),
    'rows',all_rows,
    'deckTypes',coalesce((
      select jsonb_agg(jsonb_build_object(
        'code',d."Deck_Code",'name',d."Deck_Display_Name"
      ) order by d."Deck_Display_Name")
      from "Basic_Carrier_Record"."MASTER_Deck_Types" d
      where d."Deck_Category"='Deadload'
    ),'[]'::jsonb)
  );
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_d2(text,text,text)
  from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d2(text,text,text)
  to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_d2(
  p_iata text,p_type_code text,p_subtype text,p_revision text,
  p_section text,p_values jsonb
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  section_code text:=upper(btrim(p_section));
  hold_type_code text;
  applicable boolean;
  balance_limits_required boolean;
  rows_data jsonb;
  current_data jsonb;
  item jsonb;
  hold_name text;
  deck_code text;
  max_weight integer;
  max_volume double precision;
  lateral_centroid double precision;
  lateral_from double precision;
  lateral_to double precision;
  balance_centroid double precision;
  balance_from double precision;
  balance_to double precision;
  index_value double precision;
begin
  if not (
    private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT')
    or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
  ) then raise exception 'Not authorised' using errcode='42501'; end if;
  if section_code not in ('BULK','ULD') then
    raise exception 'Invalid D2 section' using errcode='22023';
  end if;
  if p_values is null or jsonb_typeof(p_values)<>'object'
    or not (p_values ? 'applicable')
    or not (p_values ? 'balanceLimitsRequired')
    or jsonb_typeof(p_values->'applicable')<>'boolean'
    or jsonb_typeof(p_values->'balanceLimitsRequired')<>'boolean'
    or jsonb_typeof(p_values->'rows')<>'array' then
    raise exception 'Invalid D2 values' using errcode='22023';
  end if;

  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data"
  where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc
    and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503'; end if;

  current_data:="Basic_Carrier_Record".get_aircraft_d2(p_iata,tc,st);
  if p_revision is distinct from current_data->>'revision' then
    raise exception 'Aircraft D2 changed' using errcode='40001';
  end if;

  applicable:=(p_values->>'applicable')::boolean;
  balance_limits_required:=(p_values->>'balanceLimitsRequired')::boolean;
  rows_data:=p_values->'rows';
  hold_type_code:=case section_code when 'BULK' then 'BLK' else 'ULD' end;

  if not applicable and jsonb_array_length(rows_data)<>0 then
    raise exception 'A skipped section cannot contain rows' using errcode='22023';
  end if;
  if applicable and jsonb_array_length(rows_data)=0 then
    raise exception 'An applicable section requires at least one row' using errcode='22023';
  end if;
  if exists (
    select 1 from (
      select upper(btrim(value->>'name')) as name,count(*) as n
      from jsonb_array_elements(rows_data)
      group by upper(btrim(value->>'name'))
    ) duplicates where duplicates.name='' or duplicates.n>1
  ) then raise exception 'Hold names must be present and unique' using errcode='22023'; end if;

  for item in select value from jsonb_array_elements(rows_data)
  loop
    hold_name:=upper(btrim(item->>'name'));
    deck_code:=upper(btrim(item->>'deckCode'));
    if hold_name !~ '^[A-Z0-9]$' then
      raise exception 'Invalid hold name' using errcode='22023';
    end if;
    if not exists (
      select 1 from "Basic_Carrier_Record"."MASTER_Deck_Types"
      where "Deck_Code"=deck_code and "Deck_Category"='Deadload'
    ) then raise exception 'Invalid deadload deck' using errcode='23503'; end if;

    max_weight:=(item->>'maxWeight')::integer;
    max_volume:=(item->>'maxVolume')::double precision;
    index_value:=(item->>'indexPerWeightUnit')::double precision;

    if max_weight<=0 or max_volume<=0 or abs(index_value)>1000000000 then
      raise exception 'Invalid hold values' using errcode='22023';
    end if;

    if coalesce(item->>'balanceCentroid','')='' then
      raise exception 'Balance Arm Centroid is required' using errcode='22023';
    end if;
    balance_centroid:=(item->>'balanceCentroid')::double precision;
    if coalesce(item->>'balanceFrom','')='' and coalesce(item->>'balanceTo','')='' then
      if balance_limits_required then
        raise exception 'Balance Arm From and To are required' using errcode='22023';
      end if;
      balance_from:=null;balance_to:=null;
    elsif coalesce(item->>'balanceFrom','')='' or coalesce(item->>'balanceTo','')='' then
      raise exception 'Complete both Balance Arm From and To values' using errcode='22023';
    else
      balance_from:=(item->>'balanceFrom')::double precision;
      balance_to:=(item->>'balanceTo')::double precision;
      if not (balance_from<=balance_centroid and balance_centroid<=balance_to) then
        raise exception 'Invalid Balance Arm values' using errcode='22023';
      end if;
    end if;
  end loop;

  insert into "Basic_Carrier_Record"."Aircraft_Hold_Configuration"
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",
     "Bulk_Holds_Applicable","ULD_Holds_Applicable",
     "Bulk_Balance_Limits_Required","ULD_Balance_Limits_Required","Updated_At")
  values (
    p_iata,tc,st,
    case when section_code='BULK' then applicable else null end,
    case when section_code='ULD' then applicable else null end,
    case when section_code='BULK' then balance_limits_required else true end,
    case when section_code='ULD' then balance_limits_required else true end,
    now()
  )
  on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
  do update set
    "Bulk_Holds_Applicable"=case when section_code='BULK'
      then applicable else "Aircraft_Hold_Configuration"."Bulk_Holds_Applicable" end,
    "ULD_Holds_Applicable"=case when section_code='ULD'
      then applicable else "Aircraft_Hold_Configuration"."ULD_Holds_Applicable" end,
    "Bulk_Balance_Limits_Required"=case when section_code='BULK'
      then balance_limits_required else "Aircraft_Hold_Configuration"."Bulk_Balance_Limits_Required" end,
    "ULD_Balance_Limits_Required"=case when section_code='ULD'
      then balance_limits_required else "Aircraft_Hold_Configuration"."ULD_Balance_Limits_Required" end,
    "Updated_At"=now();

  delete from "Basic_Carrier_Record"."Aircraft_Holds" h
  where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc
    and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Type")=hold_type_code
    and not exists (
      select 1 from jsonb_array_elements(rows_data) r
      where upper(btrim(r->>'name'))=btrim(h."Hold_Name_ID")
    );

  for item in select value from jsonb_array_elements(rows_data)
  loop
    hold_name:=upper(btrim(item->>'name'));
    deck_code:=upper(btrim(item->>'deckCode'));
    max_weight:=(item->>'maxWeight')::integer;
    max_volume:=(item->>'maxVolume')::double precision;
    index_value:=(item->>'indexPerWeightUnit')::double precision;
    balance_centroid:=(item->>'balanceCentroid')::double precision;
    balance_from:=case when coalesce(item->>'balanceFrom','')='' then null else (item->>'balanceFrom')::double precision end;
    balance_to:=case when coalesce(item->>'balanceTo','')='' then null else (item->>'balanceTo')::double precision end;

    insert into "Basic_Carrier_Record"."Aircraft_Holds"(
      "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",
      "Hold_Name_ID","Hold_MAX_Weight","Hold_MAX_Volume",
      "Hold_BA_Centroid","Hold_BA_Start","Hold_BA_End",
      "Hold_Index_Per_Weight_Unit","Hold_Type","Hold_Deck_Location"
    ) values (
      p_iata,tc,st,hold_name,max_weight,max_volume,
      balance_centroid,balance_from,balance_to,index_value,
      hold_type_code,deck_code
    )
    on conflict ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    do update set
      "Hold_MAX_Weight"=excluded."Hold_MAX_Weight",
      "Hold_MAX_Volume"=excluded."Hold_MAX_Volume",
      "Hold_BA_Centroid"=excluded."Hold_BA_Centroid",
      "Hold_BA_Start"=excluded."Hold_BA_Start",
      "Hold_BA_End"=excluded."Hold_BA_End",
      "Hold_Index_Per_Weight_Unit"=excluded."Hold_Index_Per_Weight_Unit",
      "Hold_Type"=excluded."Hold_Type",
      "Hold_Deck_Location"=excluded."Hold_Deck_Location";
  end loop;

  return "Basic_Carrier_Record".get_aircraft_d2(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_d2(
  text,text,text,text,text,jsonb
) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d2(
  text,text,text,text,text,jsonb
) to authenticated;

notify pgrst,'reload schema';
commit;
