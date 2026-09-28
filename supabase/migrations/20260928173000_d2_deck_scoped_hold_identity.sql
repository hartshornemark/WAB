begin;

-- A visible hold name can repeat on different decks. Keep one stable, deck-scoped
-- key in all dependent tables while retaining the short AHM hold name for display.
alter table "Basic_Carrier_Record"."Aircraft_Holds"
  add column if not exists "Hold_Display_Name" varchar(3);

update "Basic_Carrier_Record"."Aircraft_Holds"
set "Hold_Display_Name"=upper(btrim("Hold_Name_ID"))
where "Hold_Display_Name" is null;

create temporary table _hold_key_map on commit drop as
select "Carrier_IATA", "Aircraft_Type_IATA", "Aircraft_Series_Subtype",
       btrim("Hold_Name_ID") old_key,
       upper(btrim("Hold_Deck_Location")) || ':' || upper(btrim("Hold_Display_Name")) new_key
from "Basic_Carrier_Record"."Aircraft_Holds";

create temporary table _hold_foreign_keys on commit drop as
select ns.nspname schema_name, rel.relname table_name, con.conname constraint_name,
       pg_get_constraintdef(con.oid) definition
from pg_constraint con
join pg_class rel on rel.oid=con.conrelid
join pg_namespace ns on ns.oid=rel.relnamespace
where con.contype='f' and ns.nspname='Basic_Carrier_Record'
  and (
    exists(select 1 from unnest(con.conkey) key(attnum) join pg_attribute a on a.attrelid=con.conrelid and a.attnum=key.attnum where a.attname in ('Hold_Name_ID','Flight_Deck_Baggage_Location','Cabin_Crew_Baggage_Location'))
    or exists(select 1 from unnest(con.confkey) key(attnum) join pg_attribute a on a.attrelid=con.confrelid and a.attnum=key.attnum where a.attname='Hold_Name_ID')
  );

do $$ declare r record; begin
  for r in select * from _hold_foreign_keys loop
    execute format('alter table %I.%I drop constraint %I',r.schema_name,r.table_name,r.constraint_name);
  end loop;
end $$;

alter table "Basic_Carrier_Record"."Aircraft_Holds" drop constraint if exists "Aircraft_Holds_Name_check";
alter table "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" drop constraint if exists "Carrier_ULD_Position_Configurations_Hold_check";
alter table "Basic_Carrier_Record"."Carrier_ULD_Positions" drop constraint if exists "Carrier_ULD_Positions_Hold_check";

do $$ declare r record; begin
  for r in select table_name from information_schema.columns
           where table_schema='Basic_Carrier_Record' and column_name='Hold_Name_ID'
  loop
    execute format('alter table "Basic_Carrier_Record".%I alter column "Hold_Name_ID" type varchar(16) using btrim("Hold_Name_ID")',r.table_name);
  end loop;
end $$;

alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes"
  alter column "Flight_Deck_Baggage_Location" type varchar(16) using btrim("Flight_Deck_Baggage_Location"),
  alter column "Cabin_Crew_Baggage_Location" type varchar(16) using btrim("Cabin_Crew_Baggage_Location");

do $$ declare r record; begin
  for r in select table_name from information_schema.columns
           where table_schema='Basic_Carrier_Record' and column_name='Hold_Name_ID' and table_name<>'Aircraft_Holds'
  loop
    execute format($q$
      update "Basic_Carrier_Record".%I t set "Hold_Name_ID"=m.new_key
      from _hold_key_map m
      where t."Carrier_IATA"=m."Carrier_IATA"
        and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
        and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
        and btrim(t."Hold_Name_ID")=m.old_key$q$,r.table_name);
  end loop;
end $$;

update "Basic_Carrier_Record"."Aircraft_Crew_Codes" t
set "Flight_Deck_Baggage_Location"=m.new_key
from _hold_key_map m
where t."Carrier_IATA"=m."Carrier_IATA" and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Flight_Deck_Baggage_Location")=m.old_key;

update "Basic_Carrier_Record"."Aircraft_Crew_Codes" t
set "Cabin_Crew_Baggage_Location"=m.new_key
from _hold_key_map m
where t."Carrier_IATA"=m."Carrier_IATA" and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Cabin_Crew_Baggage_Location")=m.old_key;

update "Basic_Carrier_Record"."Aircraft_Holds" h
set "Hold_Name_ID"=m.new_key
from _hold_key_map m
where h."Carrier_IATA"=m."Carrier_IATA" and h."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and h."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(h."Hold_Name_ID")=m.old_key;

alter table "Basic_Carrier_Record"."Aircraft_Holds"
  alter column "Hold_Display_Name" set not null,
  add constraint "Aircraft_Holds_Name_check" check (
    ((btrim("Hold_Type")='BLK' and btrim("Hold_Display_Name") ~ '^[A-Z0-9]$')
      or (btrim("Hold_Type")='ULD' and btrim("Hold_Display_Name") ~ '^[A-Z]{3}$'))
    and btrim("Hold_Name_ID")=upper(btrim("Hold_Deck_Location"))||':'||upper(btrim("Hold_Display_Name"))
  );

alter table "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
  add constraint "Carrier_ULD_Position_Configurations_Hold_check"
  check (btrim("Hold_Name_ID") ~ '^[A-Z0-9]{2,5}:[A-Z]{3}$');

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  add constraint "Carrier_ULD_Positions_Hold_check"
  check (btrim("Hold_Name_ID") ~ '^[A-Z0-9]{2,5}:[A-Z]{3}$');

do $$ declare r record; begin
  for r in select * from _hold_foreign_keys order by table_name,constraint_name loop
    execute format('alter table %I.%I add constraint %I %s',r.schema_name,r.table_name,r.constraint_name,r.definition);
  end loop;
end $$;

create or replace function "Basic_Carrier_Record".get_aircraft_d2(p_iata text,p_type_code text,p_subtype text) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');cfg "Basic_Carrier_Record"."Aircraft_Hold_Configuration"%rowtype;all_rows jsonb;
begin
if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
select * into cfg from "Basic_Carrier_Record"."Aircraft_Hold_Configuration" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
select coalesce(jsonb_agg(jsonb_build_object('id',btrim(h."Hold_Name_ID"),'name',btrim(h."Hold_Display_Name"),'holdType',btrim(h."Hold_Type"),'deckCode',h."Hold_Deck_Location",'maxWeight',h."Hold_MAX_Weight",'maxVolume',h."Hold_MAX_Volume",'lateralCentroid',h."Hold_LA_Centroid",'lateralFrom',h."Hold_LA_Start",'lateralTo',h."Hold_LA_End",'balanceCentroid',h."Hold_BA_Centroid",'balanceFrom',h."Hold_BA_Start",'balanceTo',h."Hold_BA_End",'indexPerWeightUnit',h."Hold_Index_Per_Weight_Unit",'compartments',coalesce((select jsonb_agg(jsonb_build_object('id',btrim(c."Compartment_ID"),'areas',coalesce((select jsonb_agg(jsonb_build_object('id',btrim(a."Area_ID"),'maxWeight',a."Area_Max_Weight",'maxVolume',a."Area_Max_Volume",'indexPerWeightUnit',a."Area_Index_Per_Weight_Unit") order by btrim(a."Area_ID")) from "Basic_Carrier_Record"."Aircraft_Compartment_Areas" a where a."Carrier_IATA"=c."Carrier_IATA" and a."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and a."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and a."Hold_Name_ID"=c."Hold_Name_ID" and a."Compartment_ID"=c."Compartment_ID"),'[]'::jsonb)) order by btrim(c."Compartment_ID")) from "Basic_Carrier_Record"."Aircraft_Compartments" c where c."Carrier_IATA"=h."Carrier_IATA" and c."Aircraft_Type_IATA"=h."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=h."Aircraft_Series_Subtype" and c."Hold_Name_ID"=h."Hold_Name_ID"),'[]'::jsonb)) order by btrim(h."Hold_Type"),h."Hold_Deck_Location",h."Hold_Display_Name"),'[]'::jsonb) into all_rows from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;
return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(jsonb_build_object('bulkApplicable',cfg."Bulk_Holds_Applicable",'uldApplicable',cfg."ULD_Holds_Applicable",'rows',all_rows)::text),'typeCode',tc,'subtype',st,'bulkApplicable',cfg."Bulk_Holds_Applicable",'uldApplicable',cfg."ULD_Holds_Applicable",'bulkBalanceLimitsRequired',false,'uldBalanceLimitsRequired',false,'rows',all_rows,'deckTypes',coalesce((select jsonb_agg(jsonb_build_object('code',d."Deck_Code",'name',d."Deck_Display_Name") order by d."Deck_Display_Name") from "Basic_Carrier_Record"."MASTER_Deck_Types" d where d."Deck_Category"='Deadload'),'[]'::jsonb));
end$$;

create or replace function "Basic_Carrier_Record".save_aircraft_d2(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_values jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));section_code text:=upper(btrim(p_section));hold_type_code text;applicable boolean;rows_data jsonb;current_data jsonb;item jsonb;comp jsonb;area jsonb;hold_name text;hold_id text;deck_code text;compartment_id text;area_id text;max_weight integer;max_volume double precision;area_max_weight bigint;area_max_volume double precision;area_index_value double precision;balance_centroid double precision;balance_from double precision;balance_to double precision;index_value double precision;
begin
if not(private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
if section_code not in('BULK','ULD') or p_values is null or jsonb_typeof(p_values->'rows')<>'array' or jsonb_typeof(p_values->'applicable')<>'boolean' then raise exception 'Invalid D2 values' using errcode='22023';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
current_data:="Basic_Carrier_Record".get_aircraft_d2(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft D2 changed' using errcode='40001';end if;
applicable:=(p_values->>'applicable')::boolean;rows_data:=p_values->'rows';hold_type_code:=case section_code when 'BULK' then 'BLK' else 'ULD' end;
if (not applicable and jsonb_array_length(rows_data)<>0) or (applicable and jsonb_array_length(rows_data)=0) then raise exception 'Check applicable D2 rows' using errcode='22023';end if;
insert into "Basic_Carrier_Record"."Aircraft_Hold_Configuration"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Bulk_Holds_Applicable","ULD_Holds_Applicable","Bulk_Balance_Limits_Required","ULD_Balance_Limits_Required","Updated_At") values(p_iata,tc,st,case when section_code='BULK' then applicable end,case when section_code='ULD' then applicable end,false,false,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Bulk_Holds_Applicable"=case when section_code='BULK' then applicable else "Aircraft_Hold_Configuration"."Bulk_Holds_Applicable" end,"ULD_Holds_Applicable"=case when section_code='ULD' then applicable else "Aircraft_Hold_Configuration"."ULD_Holds_Applicable" end,"Updated_At"=now();
for hold_id in select btrim(h."Hold_Name_ID") from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Type")=hold_type_code and not exists(select 1 from jsonb_array_elements(rows_data) r where upper(btrim(r->>'deckCode'))||':'||upper(btrim(r->>'name'))=btrim(h."Hold_Name_ID")) loop
 delete from "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id;
 delete from "Basic_Carrier_Record"."Aircraft_Compartment_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id;
 delete from "Basic_Carrier_Record"."Aircraft_Compartments" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id;
 delete from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id;
end loop;
for item in select value from jsonb_array_elements(rows_data) loop
 hold_name:=upper(btrim(item->>'name'));deck_code:=upper(btrim(item->>'deckCode'));hold_id:=deck_code||':'||hold_name;max_weight:=(item->>'maxWeight')::integer;max_volume:=nullif(item->>'maxVolume','')::double precision;index_value:=(item->>'indexPerWeightUnit')::double precision;balance_centroid:=nullif(item->>'balanceCentroid','')::double precision;balance_from:=nullif(item->>'balanceFrom','')::double precision;balance_to:=nullif(item->>'balanceTo','')::double precision;
 if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Deck_Types" where "Deck_Code"=deck_code and "Deck_Category"='Deadload') or ((section_code='BULK' and hold_name !~ '^[A-Z0-9]$') or (section_code='ULD' and hold_name !~ '^[A-Z]{3}$') or max_weight<=0 or (section_code='BULK' and (max_volume is null or max_volume<=0)) or (section_code='ULD' and max_volume is not null and max_volume<=0) or index_value is null or (balance_from is null)<>(balance_to is null) or (balance_from is not null and (balance_from>balance_to or (balance_centroid is not null and balance_centroid not between balance_from and balance_to)))) then raise exception 'Invalid hold values' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Aircraft_Holds"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","Hold_Display_Name","Hold_MAX_Weight","Hold_MAX_Volume","Hold_BA_Centroid","Hold_BA_Start","Hold_BA_End","Hold_Index_Per_Weight_Unit","Hold_Type","Hold_Deck_Location") values(p_iata,tc,st,hold_id,hold_name,max_weight,max_volume,balance_centroid,balance_from,balance_to,index_value,hold_type_code,deck_code) on conflict("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype") do update set "Hold_Display_Name"=excluded."Hold_Display_Name","Hold_MAX_Weight"=excluded."Hold_MAX_Weight","Hold_MAX_Volume"=excluded."Hold_MAX_Volume","Hold_BA_Centroid"=excluded."Hold_BA_Centroid","Hold_BA_Start"=excluded."Hold_BA_Start","Hold_BA_End"=excluded."Hold_BA_End","Hold_Index_Per_Weight_Unit"=excluded."Hold_Index_Per_Weight_Unit","Hold_Type"=excluded."Hold_Type","Hold_Deck_Location"=excluded."Hold_Deck_Location";
 if jsonb_typeof(item->'compartments')<>'array' then raise exception 'Invalid compartments' using errcode='22023';end if;
 for comp in select value from jsonb_array_elements(item->'compartments') loop
  compartment_id:=upper(btrim(comp->>'id'));if compartment_id !~ '^[A-Z0-9]{1,3}$' or jsonb_typeof(comp->'areas')<>'array' then raise exception 'Invalid compartment' using errcode='22023';end if;
  insert into "Basic_Carrier_Record"."Aircraft_Compartments"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","Compartment_ID","Compartment_Max_Weight","Compartment_Max_Volume","Compartment_BA_Centroid","Compartment_BA_Start","Compartment_BA_End","Compartment_Index_Per_Weight_Unit") values(p_iata,tc,st,hold_id,compartment_id,max_weight,max_volume,balance_centroid,balance_from,balance_to,index_value) on conflict("Carrier_IATA","Aircraft_Type_IATA","Compartment_ID","Hold_Name_ID","Aircraft_Series_Subtype") do update set "Compartment_Max_Weight"=excluded."Compartment_Max_Weight","Compartment_Max_Volume"=excluded."Compartment_Max_Volume","Compartment_BA_Centroid"=excluded."Compartment_BA_Centroid","Compartment_BA_Start"=excluded."Compartment_BA_Start","Compartment_BA_End"=excluded."Compartment_BA_End","Compartment_Index_Per_Weight_Unit"=excluded."Compartment_Index_Per_Weight_Unit";
  delete from "Basic_Carrier_Record"."Aircraft_Compartment_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "Compartment_ID"=compartment_id;
  if section_code='ULD' and jsonb_array_length(comp->'areas')>0 then raise exception 'ULD compartments cannot contain Areas' using errcode='22023';end if;
  for area in select value from jsonb_array_elements(comp->'areas') loop
   area_id:=upper(btrim(area->>'id'));area_max_weight:=nullif(area->>'maxWeight','')::bigint;area_max_volume:=nullif(area->>'maxVolume','')::double precision;area_index_value:=nullif(area->>'indexPerWeightUnit','')::double precision;
   if area_id !~ '^[A-Z0-9]{1,3}$' or area_max_weight is null or area_max_weight<=0 or area_max_volume is null or area_max_volume<=0 or area_index_value is null or area_index_value not between -1000000000 and 1000000000 then raise exception 'Invalid area values' using errcode='22023';end if;
   insert into "Basic_Carrier_Record"."Aircraft_Compartment_Areas"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","Compartment_ID","Area_ID","Area_Max_Weight","Area_Max_Volume","Area_Index_Per_Weight_Unit") values(p_iata,tc,st,hold_id,compartment_id,area_id,area_max_weight,area_max_volume,area_index_value);
  end loop;
 end loop;
 delete from "Basic_Carrier_Record"."Aircraft_Compartments" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and c."Hold_Name_ID"=hold_id and not exists(select 1 from jsonb_array_elements(item->'compartments') x where upper(btrim(x->>'id'))=btrim(c."Compartment_ID"));
end loop;
return "Basic_Carrier_Record".get_aircraft_d2(p_iata,tc,st);end$$;

notify pgrst,'reload schema';
commit;
