begin;

alter table "Basic_Carrier_Record"."Aircraft_Bays"
  drop constraint "Aircraft_Bays_Compartment_FK",
  drop constraint "Aircraft_Bays_Hold_FK";

alter table "Basic_Carrier_Record"."Aircraft_Compartment_Areas"
  drop constraint "Aircraft_Compartment_Areas_Carrier_IATA_Aircraft_Type_IATA_fkey";

alter table "Basic_Carrier_Record"."Aircraft_Compartments"
  drop constraint "Aircraft_Compartments_Hold_FK";

alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes"
  drop constraint "Aircraft_Crew_Codes_Cabin_Crew_Baggage_Hold_fkey",
  drop constraint "Aircraft_Crew_Codes_Flight_Deck_Baggage_Hold_fkey";

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  drop constraint "Carrier_ULD_Positions_Compartment_FK",
  drop constraint "Carrier_ULD_Positions_Configuration_fkey",
  drop constraint "Carrier_ULD_Positions_Hold_fkey";

alter table "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
  drop constraint "Carrier_ULD_Position_Configurations_Hold_fkey";

alter table "Basic_Carrier_Record"."Aircraft_Holds"
  drop constraint "Aircraft_Holds_Name_check",
  drop constraint "Aircraft_Holds_MAX_Volume_check",
  alter column "Hold_Name_ID" type varchar(3) using btrim("Hold_Name_ID"),
  alter column "Hold_MAX_Volume" drop not null;

alter table "Basic_Carrier_Record"."Aircraft_Compartments"
  alter column "Hold_Name_ID" type varchar(3) using btrim("Hold_Name_ID"),
  alter column "Compartment_Max_Volume" drop not null;

alter table "Basic_Carrier_Record"."Aircraft_Compartment_Areas"
  alter column "Hold_Name_ID" type varchar(3) using btrim("Hold_Name_ID");

alter table "Basic_Carrier_Record"."Aircraft_Bays"
  alter column "Hold_Name_ID" type varchar(3) using btrim("Hold_Name_ID");

alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes"
  alter column "Cabin_Crew_Baggage_Location" type varchar(3) using btrim("Cabin_Crew_Baggage_Location"),
  alter column "Flight_Deck_Baggage_Location" type varchar(3) using btrim("Flight_Deck_Baggage_Location");

alter table "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
  drop constraint "Carrier_ULD_Position_Configurations_Hold_check",
  alter column "Hold_Name_ID" type varchar(3) using btrim("Hold_Name_ID");

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  drop constraint "Carrier_ULD_Positions_Hold_check",
  alter column "Hold_Name_ID" type varchar(3) using btrim("Hold_Name_ID");

create temporary table d2_uld_hold_name_map on commit drop as
with ranked as (
  select
    "Carrier_IATA",
    "Aircraft_Type_IATA",
    "Aircraft_Series_Subtype",
    btrim("Hold_Name_ID") as old_name,
    row_number() over (
      partition by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"
      order by coalesce("Hold_BA_Start","Hold_BA_Centroid","Hold_BA_End"),btrim("Hold_Name_ID")
    ) as position_number,
    count(*) over (
      partition by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"
    ) as hold_count
  from "Basic_Carrier_Record"."Aircraft_Holds"
  where btrim("Hold_Type")='ULD' and btrim("Hold_Name_ID") !~ '^[A-Z]{3}$'
)
select
  "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",old_name,
  case
    when old_name='F' then 'FWD'
    when old_name='A' then 'AFT'
    when position_number=1 then 'FWD'
    when position_number=hold_count then 'AFT'
    when position_number=2 then 'MID'
    else chr(64+least(position_number,26)::integer)||'LD'
  end as new_name
from ranked;

update "Basic_Carrier_Record"."Aircraft_Bays" t
set "Hold_Name_ID"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Hold_Name_ID")=m.old_name;

update "Basic_Carrier_Record"."Aircraft_Compartment_Areas" t
set "Hold_Name_ID"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Hold_Name_ID")=m.old_name;

update "Basic_Carrier_Record"."Aircraft_Compartments" t
set "Hold_Name_ID"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Hold_Name_ID")=m.old_name;

update "Basic_Carrier_Record"."Carrier_ULD_Positions" t
set "Hold_Name_ID"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Hold_Name_ID")=m.old_name;

update "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" t
set "Hold_Name_ID"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Hold_Name_ID")=m.old_name;

update "Basic_Carrier_Record"."Aircraft_Crew_Codes" t
set "Cabin_Crew_Baggage_Location"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Cabin_Crew_Baggage_Location")=m.old_name;

update "Basic_Carrier_Record"."Aircraft_Crew_Codes" t
set "Flight_Deck_Baggage_Location"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Flight_Deck_Baggage_Location")=m.old_name;

update "Basic_Carrier_Record"."Aircraft_Special_Load_Limits" t
set "Hold_Name_ID"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Hold_Name_ID")=m.old_name;

update "Basic_Carrier_Record"."Aircraft_Holds" t
set "Hold_Name_ID"=m.new_name
from d2_uld_hold_name_map m
where t."Carrier_IATA"=m."Carrier_IATA"
  and t."Aircraft_Type_IATA"=m."Aircraft_Type_IATA"
  and t."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
  and btrim(t."Hold_Name_ID")=m.old_name;

alter table "Basic_Carrier_Record"."Aircraft_Holds"
  add constraint "Aircraft_Holds_Name_check" check (
    (btrim("Hold_Type")='BLK' and btrim("Hold_Name_ID") ~ '^[A-Z0-9]$')
    or (btrim("Hold_Type")='ULD' and btrim("Hold_Name_ID") ~ '^[A-Z]{3}$')
  ),
  add constraint "Aircraft_Holds_MAX_Volume_check" check (
    (btrim("Hold_Type")='BLK' and "Hold_MAX_Volume" > 0)
    or (btrim("Hold_Type")='ULD' and ("Hold_MAX_Volume" is null or "Hold_MAX_Volume" > 0))
  );

alter table "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
  add constraint "Carrier_ULD_Position_Configurations_Hold_check"
  check ("Hold_Name_ID" ~ '^[A-Z]{3}$');

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  add constraint "Carrier_ULD_Positions_Hold_check"
  check ("Hold_Name_ID" ~ '^[A-Z]{3}$');

alter table "Basic_Carrier_Record"."Aircraft_Compartments"
  add constraint "Aircraft_Compartments_Hold_FK"
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
  references "Basic_Carrier_Record"."Aircraft_Holds"
    ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype");

alter table "Basic_Carrier_Record"."Aircraft_Compartment_Areas"
  add constraint "Aircraft_Compartment_Areas_Carrier_IATA_Aircraft_Type_IATA_fkey"
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype")
  references "Basic_Carrier_Record"."Aircraft_Compartments"
    ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype")
  on update cascade on delete cascade;

alter table "Basic_Carrier_Record"."Aircraft_Bays"
  add constraint "Aircraft_Bays_Compartment_FK"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Compartments"
      ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype"),
  add constraint "Aircraft_Bays_Hold_FK"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Holds"
      ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype");

alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes"
  add constraint "Aircraft_Crew_Codes_Cabin_Crew_Baggage_Hold_fkey"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Cabin_Crew_Baggage_Location","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Holds"
      ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    on update cascade on delete restrict,
  add constraint "Aircraft_Crew_Codes_Flight_Deck_Baggage_Hold_fkey"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Flight_Deck_Baggage_Location","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Holds"
      ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    on update cascade on delete restrict;

alter table "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
  add constraint "Carrier_ULD_Position_Configurations_Hold_fkey"
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
  references "Basic_Carrier_Record"."Aircraft_Holds"
    ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
  on update cascade on delete cascade;

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  add constraint "Carrier_ULD_Positions_Compartment_FK"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Compartments"
      ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype")
    on update cascade on delete restrict,
  add constraint "Carrier_ULD_Positions_Configuration_fkey"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code")
    references "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code")
    on update cascade on delete cascade,
  add constraint "Carrier_ULD_Positions_Hold_fkey"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Holds"
      ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    on update cascade on delete cascade;

create or replace function "Basic_Carrier_Record".save_aircraft_d2(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_values jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));section_code text:=upper(btrim(p_section));hold_type_code text;applicable boolean;rows_data jsonb;current_data jsonb;item jsonb;comp jsonb;area jsonb;hold_name text;deck_code text;compartment_id text;area_id text;max_weight integer;max_volume double precision;area_max_weight bigint;area_max_volume double precision;area_index_value double precision;balance_centroid double precision;balance_from double precision;balance_to double precision;index_value double precision;
begin
if not(private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
if section_code not in('BULK','ULD') or p_values is null or jsonb_typeof(p_values->'rows')<>'array' or jsonb_typeof(p_values->'applicable')<>'boolean' then raise exception 'Invalid D2 values' using errcode='22023';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
current_data:="Basic_Carrier_Record".get_aircraft_d2(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft D2 changed' using errcode='40001';end if;
applicable:=(p_values->>'applicable')::boolean;rows_data:=p_values->'rows';hold_type_code:=case section_code when 'BULK' then 'BLK' else 'ULD' end;
if (not applicable and jsonb_array_length(rows_data)<>0) or (applicable and jsonb_array_length(rows_data)=0) then raise exception 'Check applicable D2 rows' using errcode='22023';end if;
insert into "Basic_Carrier_Record"."Aircraft_Hold_Configuration"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Bulk_Holds_Applicable","ULD_Holds_Applicable","Bulk_Balance_Limits_Required","ULD_Balance_Limits_Required","Updated_At") values(p_iata,tc,st,case when section_code='BULK' then applicable end,case when section_code='ULD' then applicable end,false,false,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Bulk_Holds_Applicable"=case when section_code='BULK' then applicable else "Aircraft_Hold_Configuration"."Bulk_Holds_Applicable" end,"ULD_Holds_Applicable"=case when section_code='ULD' then applicable else "Aircraft_Hold_Configuration"."ULD_Holds_Applicable" end,"Updated_At"=now();
for hold_name in select btrim(h."Hold_Name_ID") from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Type")=hold_type_code and not exists(select 1 from jsonb_array_elements(rows_data) r where upper(btrim(r->>'name'))=btrim(h."Hold_Name_ID")) loop
 delete from "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_name;
 delete from "Basic_Carrier_Record"."Aircraft_Compartment_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_name;
 delete from "Basic_Carrier_Record"."Aircraft_Compartments" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_name;
 delete from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_name;
end loop;
for item in select value from jsonb_array_elements(rows_data) loop
 hold_name:=upper(btrim(item->>'name'));deck_code:=upper(btrim(item->>'deckCode'));max_weight:=(item->>'maxWeight')::integer;max_volume:=nullif(item->>'maxVolume','')::double precision;index_value:=(item->>'indexPerWeightUnit')::double precision;balance_centroid:=nullif(item->>'balanceCentroid','')::double precision;balance_from:=nullif(item->>'balanceFrom','')::double precision;balance_to:=nullif(item->>'balanceTo','')::double precision;
 if ((section_code='BULK' and hold_name !~ '^[A-Z0-9]$') or (section_code='ULD' and hold_name !~ '^[A-Z]{3}$') or max_weight<=0 or (section_code='BULK' and (max_volume is null or max_volume<=0)) or (section_code='ULD' and max_volume is not null and max_volume<=0) or index_value is null or (balance_from is null)<>(balance_to is null) or (balance_from is not null and (balance_from>balance_to or (balance_centroid is not null and balance_centroid not between balance_from and balance_to)))) then raise exception 'Invalid hold values' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Aircraft_Holds"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","Hold_MAX_Weight","Hold_MAX_Volume","Hold_BA_Centroid","Hold_BA_Start","Hold_BA_End","Hold_Index_Per_Weight_Unit","Hold_Type","Hold_Deck_Location") values(p_iata,tc,st,hold_name,max_weight,max_volume,balance_centroid,balance_from,balance_to,index_value,hold_type_code,deck_code) on conflict("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype") do update set "Hold_MAX_Weight"=excluded."Hold_MAX_Weight","Hold_MAX_Volume"=excluded."Hold_MAX_Volume","Hold_BA_Centroid"=excluded."Hold_BA_Centroid","Hold_BA_Start"=excluded."Hold_BA_Start","Hold_BA_End"=excluded."Hold_BA_End","Hold_Index_Per_Weight_Unit"=excluded."Hold_Index_Per_Weight_Unit","Hold_Type"=excluded."Hold_Type","Hold_Deck_Location"=excluded."Hold_Deck_Location";
 if jsonb_typeof(item->'compartments')<>'array' then raise exception 'Invalid compartments' using errcode='22023';end if;
 for comp in select value from jsonb_array_elements(item->'compartments') loop
  compartment_id:=upper(btrim(comp->>'id'));if compartment_id !~ '^[A-Z0-9]{1,3}$' or jsonb_typeof(comp->'areas')<>'array' then raise exception 'Invalid compartment' using errcode='22023';end if;
  insert into "Basic_Carrier_Record"."Aircraft_Compartments"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","Compartment_ID","Compartment_Max_Weight","Compartment_Max_Volume","Compartment_BA_Centroid","Compartment_BA_Start","Compartment_BA_End","Compartment_Index_Per_Weight_Unit") values(p_iata,tc,st,hold_name,compartment_id,max_weight,max_volume,balance_centroid,balance_from,balance_to,index_value) on conflict("Carrier_IATA","Aircraft_Type_IATA","Compartment_ID","Hold_Name_ID","Aircraft_Series_Subtype") do update set "Compartment_Max_Weight"=excluded."Compartment_Max_Weight","Compartment_Max_Volume"=excluded."Compartment_Max_Volume","Compartment_BA_Centroid"=excluded."Compartment_BA_Centroid","Compartment_BA_Start"=excluded."Compartment_BA_Start","Compartment_BA_End"=excluded."Compartment_BA_End","Compartment_Index_Per_Weight_Unit"=excluded."Compartment_Index_Per_Weight_Unit";
  delete from "Basic_Carrier_Record"."Aircraft_Compartment_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_name and "Compartment_ID"=compartment_id;
  if section_code='ULD' and jsonb_array_length(comp->'areas')>0 then raise exception 'ULD compartments cannot contain Areas' using errcode='22023';end if;
  for area in select value from jsonb_array_elements(comp->'areas') loop
   area_id:=upper(btrim(area->>'id'));area_max_weight:=nullif(area->>'maxWeight','')::bigint;area_max_volume:=nullif(area->>'maxVolume','')::double precision;area_index_value:=nullif(area->>'indexPerWeightUnit','')::double precision;
   if area_id !~ '^[A-Z0-9]{1,3}$' or area_max_weight is null or area_max_weight<=0 or area_max_volume is null or area_max_volume<=0 or area_index_value is null or area_index_value not between -1000000000 and 1000000000 then raise exception 'Invalid area values' using errcode='22023';end if;
   insert into "Basic_Carrier_Record"."Aircraft_Compartment_Areas"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","Compartment_ID","Area_ID","Area_Max_Weight","Area_Max_Volume","Area_Index_Per_Weight_Unit") values(p_iata,tc,st,hold_name,compartment_id,area_id,area_max_weight,area_max_volume,area_index_value);
  end loop;
 end loop;
 delete from "Basic_Carrier_Record"."Aircraft_Compartments" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and c."Hold_Name_ID"=hold_name and not exists(select 1 from jsonb_array_elements(item->'compartments') x where upper(btrim(x->>'id'))=btrim(c."Compartment_ID"));
end loop;
return "Basic_Carrier_Record".get_aircraft_d2(p_iata,tc,st);end$$;

notify pgrst,'reload schema';
commit;
