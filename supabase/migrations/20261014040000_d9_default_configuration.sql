begin;

alter table "Basic_Carrier_Record"."Aircraft_Configurations"
add column if not exists "Is_Default" boolean not null default false;

with selected as (
  select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Configuration_Code") configuration_code
  from (
    select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code",
      row_number() over (
        partition by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"
        order by case when btrim("Configuration_Code")='A' then 0 else 1 end,btrim("Configuration_Code")
      ) sequence
    from "Basic_Carrier_Record"."Aircraft_Configurations"
    group by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code"
  ) ranked
  where sequence=1
)
update "Basic_Carrier_Record"."Aircraft_Configurations" configuration
set "Is_Default"=true
from selected
where configuration."Carrier_IATA"=selected."Carrier_IATA"
  and configuration."Aircraft_Type_IATA"=selected."Aircraft_Type_IATA"
  and configuration."Aircraft_Series_Subtype"=selected."Aircraft_Series_Subtype"
  and btrim(configuration."Configuration_Code")=selected.configuration_code;

create or replace function private.require_one_d9_default_configuration()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  carrier text:=coalesce(new."Carrier_IATA",old."Carrier_IATA");
  type_code text:=coalesce(new."Aircraft_Type_IATA",old."Aircraft_Type_IATA");
  subtype_code text:=coalesce(new."Aircraft_Series_Subtype",old."Aircraft_Series_Subtype");
  configuration_count integer;
  default_count integer;
begin
  select count(distinct btrim("Configuration_Code")),count(distinct btrim("Configuration_Code")) filter(where "Is_Default")
  into configuration_count,default_count
  from "Basic_Carrier_Record"."Aircraft_Configurations"
  where "Carrier_IATA"=carrier and "Aircraft_Type_IATA"=type_code and "Aircraft_Series_Subtype"=subtype_code;
  if configuration_count>0 and default_count<>1 then
    raise exception 'Select exactly one default D9 cabin configuration for each aircraft type and sub-series' using errcode='23514';
  end if;
  return null;
end;
$$;

revoke all on function private.require_one_d9_default_configuration() from public,anon,authenticated;

drop trigger if exists "require_one_d9_default_configuration" on "Basic_Carrier_Record"."Aircraft_Configurations";
create constraint trigger "require_one_d9_default_configuration"
after insert or update or delete on "Basic_Carrier_Record"."Aircraft_Configurations"
deferrable initially deferred
for each row execute function private.require_one_d9_default_configuration();

create or replace function "Basic_Carrier_Record".get_aircraft_d9(p_iata text, p_type_code text, p_subtype text)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;classes jsonb;configs jsonb:='[]';physical jsonb;cfg record;rows jsonb;
begin if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowSequence',to_jsonb("Row_Sequence"),'rowFrom',"Cabin_Area_Start_Row",'rowTo',"Cabin_Area_End_Row",'centroid',"Cabin_Area_BA_Centroid",'from',"Cabin_Area_BA_Start",'to',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by "Cabin_Area_Start_Row"),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_build_array(jsonb_build_object('slot',1,'code',btrim("Carrier_Class_1_Code"),'name',btrim("Carrier_Class_1_Name")),jsonb_build_object('slot',2,'code',btrim("Carrier_Class_2_Code"),'name',btrim("Carrier_Class_2_Name")),jsonb_build_object('slot',3,'code',btrim("Carrier_Class_3_Code"),'name',btrim("Carrier_Class_3_Name")),jsonb_build_object('slot',4,'code',btrim("Carrier_Class_4_Code"),'name',btrim("Carrier_Class_4_Name"))),'[]') into classes from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"=p_iata;
 select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim(r."Seat_Row_Cabin_Area"),'rowNumber',btrim(r."Seat_Row_Number")::integer,'maximumSeats',r."Seat_Row_Seats",'grouping',coalesce(r."Seat_Grouping_Override",a."Seat_Grouping_Default")) order by btrim(r."Seat_Row_Number")::integer),'[]') into physical
 from "Basic_Carrier_Record"."Aircraft_Seat_Rows" r join "Basic_Carrier_Record"."Aircraft_Cabin_Areas" a on a."Carrier_IATA"=r."Carrier_IATA" and a."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and a."Aircraft_Series_Subtype"=r."Aircraft_Series_Subtype" and a."Cabin_Area_ID"=r."Seat_Row_Cabin_Area"
 where r."Carrier_IATA"=p_iata and r."Aircraft_Type_IATA"=tc and r."Aircraft_Series_Subtype"=st
 and btrim(r."Seat_Row_Number")::integer=any(private.cabin_row_numbers(a."Row_Sequence",a."Cabin_Area_Start_Row",a."Cabin_Area_End_Row")) and not excluded @> jsonb_build_array(btrim(r."Seat_Row_Number")::integer);
 for cfg in select btrim("Configuration_Code") code,min(btrim("Configuration_Code_Description")) description,bool_or("Is_Default") is_default from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st group by btrim("Configuration_Code") order by 1 loop
  select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim("Cabin_Area_ID"),'classSeats',jsonb_build_array("Seat_Class_Code_1",coalesce("Seat_Class_Code_2",0),coalesce("Seat_Class_Code_3",0),coalesce("Seat_Class_Code_4",0)),'blockedRows',to_jsonb("Blocked_Centre_Rows"),'totalSeats',"Total_Seats_Cabin_Area_ID",'centroid',"Cabin_Area_BA_Centroid",'from',"Cabin_Area_BA_Start",'to',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by btrim("Cabin_Area_ID")),'[]') into rows from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Configuration_Code")=cfg.code;
  configs:=configs||jsonb_build_array(jsonb_build_object('code',cfg.code,'description',cfg.description,'isDefault',cfg.is_default,'rows',rows));end loop;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||classes||configs||physical)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'classes',classes,'seatRows',physical,'configurations',configs);end
$$;

create or replace function "Basic_Carrier_Record".save_aircraft_d9(p_iata text, p_type_code text, p_subtype text, p_revision text, p_original_code text, p_values jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));code text:=upper(btrim(p_values->>'code'));description text:=btrim(p_values->>'description');item jsonb;current_data jsonb;blocked integer[];physical jsonb;usable integer;expected integer;available integer;is_default boolean:=coalesce((p_values->>'isDefault')::boolean,false);
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
 current_data:="Basic_Carrier_Record".get_aircraft_d9(p_iata,tc,st);
 if code is null or code !~ '^[A-Z]$' then raise exception 'Configuration Code must be one letter' using errcode='23514';end if;
 if current_data->>'revision' is distinct from p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_values->'rows') is distinct from 'array' or jsonb_array_length(p_values->'rows')<1 then raise exception 'Rows required' using errcode='22023';end if;
 if p_original_code is not null then delete from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Configuration_Code")=upper(btrim(p_original_code));end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then is_default:=true;end if;
 if is_default then update "Basic_Carrier_Record"."Aircraft_Configurations" set "Is_Default"=false where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;end if;
 for item in select value from jsonb_array_elements(p_values->'rows') loop
  if jsonb_typeof(coalesce(item->'blockedRows','[]'::jsonb)) is distinct from 'array' then raise exception 'Invalid blocked rows' using errcode='23514';end if;
  blocked:=array(select value::integer from jsonb_array_elements_text(coalesce(item->'blockedRows','[]'::jsonb)));
  if cardinality(blocked)<>(select count(distinct n) from unnest(blocked) n) then raise exception 'Duplicate blocked row' using errcode='23514';end if;
  select coalesce(jsonb_agg(r),'[]'::jsonb) into physical from jsonb_array_elements(current_data->'seatRows') r where r->>'areaId'=item->>'areaId';
  if exists(select 1 from unnest(blocked) n where not exists(select 1 from jsonb_array_elements(physical) r where (r->>'rowNumber')::integer=n and r->>'grouping' ~ '^3(-3){0,3}$')) then raise exception 'Blocked row requires physical three-seat groups on D8' using errcode='23514';end if;
  select count(*) into expected from jsonb_array_elements(current_data->'cabinAreas') a cross join lateral unnest(private.cabin_row_numbers(case when jsonb_typeof(a->'rowSequence')='array' then array(select value::integer from jsonb_array_elements_text(a->'rowSequence')) else null end,(a->>'rowFrom')::integer,(a->>'rowTo')::integer)) n where a->>'id'=item->>'areaId' and not (current_data->'excludedRows') @> jsonb_build_array(n);
  select count(*),sum((r->>'maximumSeats')::integer-case when (r->>'rowNumber')::integer=any(blocked) then cardinality(string_to_array(r->>'grouping','-')) else 0 end) into available,usable from jsonb_array_elements(physical) r where r->>'maximumSeats' is not null;
  if expected>0 and available=expected and usable<>(item->>'totalSeats')::integer then raise exception 'D9 usable seats do not match D8 and blocked rows' using errcode='23514';end if;
  insert into "Basic_Carrier_Record"."Aircraft_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code","Configuration_Code_Description","Cabin_Area_ID","Seat_Class_Code_1","Seat_Class_Code_2","Seat_Class_Code_3","Seat_Class_Code_4","Total_Seats_Cabin_Area_ID","Cabin_Area_BA_Centroid","Cabin_Area_BA_Start","Cabin_Area_BA_End","Cabin_Area_Index_Per_Weight_Unit","Blocked_Centre_Rows","Is_Default")
  values(p_iata,tc,st,code,description,btrim(item->>'areaId'),(item->'classSeats'->>0)::integer,(item->'classSeats'->>1)::integer,(item->'classSeats'->>2)::integer,(item->'classSeats'->>3)::integer,(item->>'totalSeats')::integer,(item->>'centroid')::double precision,(item->>'from')::double precision,(item->>'to')::double precision,(item->>'index')::double precision,blocked,is_default);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d9(p_iata,tc,st);
end;
$$;

create or replace function "Basic_Carrier_Record".get_aircraft_configuration_choices(p_iata text)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(
  private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW')
  or private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')
 ) then raise exception 'Aircraft configuration access denied' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'typeCode',choice.type_code,'subtype',choice.subtype,'code',choice.code,
  'description',choice.description,'isDefault',choice.is_default
 ) order by choice.type_code,choice.subtype,choice.code)
 from (
  select c."Aircraft_Type_IATA" type_code,c."Aircraft_Series_Subtype" subtype,btrim(c."Configuration_Code") code,
    min(btrim(c."Configuration_Code_Description")) description,bool_or(c."Is_Default") is_default
  from "Basic_Carrier_Record"."Aircraft_Configurations" c
  where c."Carrier_IATA"=p_iata
  group by c."Aircraft_Type_IATA",c."Aircraft_Series_Subtype",btrim(c."Configuration_Code")
 ) choice),'[]'::jsonb);
end;
$$;

revoke all on function "Basic_Carrier_Record".get_aircraft_configuration_choices(text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_configuration_choices(text) to authenticated;

comment on column "Basic_Carrier_Record"."Aircraft_Configurations"."Is_Default" is 'Carrier-selected D9 configuration used when a schedule provides no cabin configuration.';

notify pgrst,'reload schema';
commit;
