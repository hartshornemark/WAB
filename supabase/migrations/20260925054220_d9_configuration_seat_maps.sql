begin;
alter table "Basic_Carrier_Record"."Aircraft_Configurations" add column "Blocked_Centre_Rows" integer[] not null default '{}';
-- Move BC's previously shared blocked seats to configuration B only.
update "Basic_Carrier_Record"."Aircraft_Configurations" set "Configuration_Code"=case btrim("Configuration_Code") when '1' then 'A' when '2' then 'B' end
where "Carrier_IATA"='BC' and "Aircraft_Type_IATA"='320' and "Aircraft_Series_Subtype"='200' and btrim("Configuration_Code") in ('1','2');
update "Basic_Carrier_Record"."Aircraft_Configurations" set "Seat_Class_Code_2"=30,"Total_Seats_Cabin_Area_ID"=30
where "Carrier_IATA"='BC' and "Aircraft_Type_IATA"='320' and "Aircraft_Series_Subtype"='200' and btrim("Configuration_Code")='A' and btrim("Cabin_Area_ID")='0A';
update "Basic_Carrier_Record"."Aircraft_Configurations" set "Configuration_Code_Description"='Y162'
where "Carrier_IATA"='BC' and "Aircraft_Type_IATA"='320' and "Aircraft_Series_Subtype"='200' and btrim("Configuration_Code")='A';
update "Basic_Carrier_Record"."Aircraft_Configurations" set "Blocked_Centre_Rows"=array[1,2,3]
where "Carrier_IATA"='BC' and "Aircraft_Type_IATA"='320' and "Aircraft_Series_Subtype"='200' and btrim("Configuration_Code")='B' and btrim("Cabin_Area_ID")='0A';
update "Basic_Carrier_Record"."Aircraft_Seat_Rows" set "Seat_Grouping_Override"=null,"Seat_Row_Seats"=6
where "Carrier_IATA"='BC' and "Aircraft_Type_IATA"='320' and "Aircraft_Series_Subtype"='200' and btrim("Seat_Row_Number") in ('1','2','3');
alter table "Basic_Carrier_Record"."Aircraft_Configurations" drop constraint "Aircraft_Configurations_Code_check",
add constraint "Aircraft_Configurations_Code_check" check (btrim("Configuration_Code") ~ '^[A-Z]$');
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".get_aircraft_d9(p_iata text, p_type_code text, p_subtype text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;classes jsonb;configs jsonb:='[]';physical jsonb;cfg record;rows jsonb;
begin if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowFrom',"Cabin_Area_Start_Row",'rowTo',"Cabin_Area_End_Row",'centroid',"Cabin_Area_BA_Centroid",'from',"Cabin_Area_BA_Start",'to',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by "Cabin_Area_Start_Row"),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_build_array(jsonb_build_object('slot',1,'code',btrim("Carrier_Class_1_Code"),'name',btrim("Carrier_Class_1_Name")),jsonb_build_object('slot',2,'code',btrim("Carrier_Class_2_Code"),'name',btrim("Carrier_Class_2_Name")),jsonb_build_object('slot',3,'code',btrim("Carrier_Class_3_Code"),'name',btrim("Carrier_Class_3_Name")),jsonb_build_object('slot',4,'code',btrim("Carrier_Class_4_Code"),'name',btrim("Carrier_Class_4_Name"))),'[]') into classes from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"=p_iata;
 select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim(r."Seat_Row_Cabin_Area"),'rowNumber',btrim(r."Seat_Row_Number")::integer,'maximumSeats',r."Seat_Row_Seats",'grouping',coalesce(r."Seat_Grouping_Override",a."Seat_Grouping_Default")) order by btrim(r."Seat_Row_Number")::integer),'[]') into physical
 from "Basic_Carrier_Record"."Aircraft_Seat_Rows" r join "Basic_Carrier_Record"."Aircraft_Cabin_Areas" a on a."Carrier_IATA"=r."Carrier_IATA" and a."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and a."Aircraft_Series_Subtype"=r."Aircraft_Series_Subtype" and a."Cabin_Area_ID"=r."Seat_Row_Cabin_Area"
 where r."Carrier_IATA"=p_iata and r."Aircraft_Type_IATA"=tc and r."Aircraft_Series_Subtype"=st
 and not excluded @> jsonb_build_array(btrim(r."Seat_Row_Number")::integer);
 for cfg in select btrim("Configuration_Code") code,min(btrim("Configuration_Code_Description")) description from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st group by btrim("Configuration_Code") order by 1 loop
  select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim("Cabin_Area_ID"),'classSeats',jsonb_build_array("Seat_Class_Code_1",coalesce("Seat_Class_Code_2",0),coalesce("Seat_Class_Code_3",0),coalesce("Seat_Class_Code_4",0)),'blockedRows',to_jsonb("Blocked_Centre_Rows"),'totalSeats',"Total_Seats_Cabin_Area_ID",'centroid',"Cabin_Area_BA_Centroid",'from',"Cabin_Area_BA_Start",'to',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by btrim("Cabin_Area_ID")),'[]') into rows from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Configuration_Code")=cfg.code;
  configs:=configs||jsonb_build_array(jsonb_build_object('code',cfg.code,'description',cfg.description,'rows',rows));end loop;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||classes||configs||physical)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'classes',classes,'seatRows',physical,'configurations',configs);end $function$;

CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".save_aircraft_d9(p_iata text,p_type_code text,p_subtype text,p_revision text,p_original_code text,p_values jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE
 tc text:=upper(btrim(p_type_code));
 st text:=upper(btrim(p_subtype));
 code text:=upper(btrim(p_values->>'code'));
 description text:=btrim(p_values->>'description');
 item jsonb;
 current_data jsonb;
 blocked integer[];
 physical jsonb;
 usable integer;
 expected integer;
 available integer;
BEGIN
 IF NOT (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') OR private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) THEN
  RAISE EXCEPTION 'Not authorised' USING errcode='42501';
 END IF;
 PERFORM 1 FROM "Basic_Carrier_Record"."Basic_Aircraft_Data" WHERE "Carrier_IATA"=p_iata AND "Aircraft_Type_IATA"=tc AND "Aircraft_Series_Subtype"=st FOR UPDATE;
 current_data:="Basic_Carrier_Record".get_aircraft_d9(p_iata,tc,st);
 IF code IS NULL OR code !~ '^[A-Z]$' THEN RAISE EXCEPTION 'Configuration Code must be one letter' USING errcode='23514'; END IF;
 IF current_data->>'revision' IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Conflict' USING errcode='40001'; END IF;
 IF jsonb_typeof(p_values->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(p_values->'rows')<1 THEN RAISE EXCEPTION 'Rows required' USING errcode='22023'; END IF;
 IF p_original_code IS NOT NULL THEN
  DELETE FROM "Basic_Carrier_Record"."Aircraft_Configurations" WHERE "Carrier_IATA"=p_iata AND "Aircraft_Type_IATA"=tc AND "Aircraft_Series_Subtype"=st AND btrim("Configuration_Code")=upper(btrim(p_original_code));
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_values->'rows') LOOP
  IF jsonb_typeof(coalesce(item->'blockedRows','[]'::jsonb)) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid blocked rows' USING errcode='23514'; END IF;
  blocked:=ARRAY(SELECT value::integer FROM jsonb_array_elements_text(coalesce(item->'blockedRows','[]'::jsonb)));
  IF cardinality(blocked)<>(SELECT count(DISTINCT n) FROM unnest(blocked) n) THEN RAISE EXCEPTION 'Duplicate blocked row' USING errcode='23514'; END IF;
  SELECT coalesce(jsonb_agg(r),'[]'::jsonb) INTO physical FROM jsonb_array_elements(current_data->'seatRows') r WHERE r->>'areaId'=item->>'areaId';
  IF EXISTS(SELECT 1 FROM unnest(blocked) n WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(physical) r WHERE (r->>'rowNumber')::integer=n AND r->>'grouping' ~ '^3(-3){0,3}$')) THEN
   RAISE EXCEPTION 'Blocked row requires physical three-seat groups on D8' USING errcode='23514';
  END IF;
  SELECT count(*) INTO expected FROM jsonb_array_elements(current_data->'cabinAreas') a CROSS JOIN LATERAL generate_series((a->>'rowFrom')::integer,(a->>'rowTo')::integer) n WHERE a->>'id'=item->>'areaId' AND NOT (current_data->'excludedRows') @> jsonb_build_array(n);
  SELECT count(*),sum((r->>'maximumSeats')::integer-CASE WHEN (r->>'rowNumber')::integer=ANY(blocked) THEN cardinality(string_to_array(r->>'grouping','-')) ELSE 0 END) INTO available,usable FROM jsonb_array_elements(physical) r WHERE r->>'maximumSeats' IS NOT NULL;
  IF expected>0 AND available=expected AND usable<>(item->>'totalSeats')::integer THEN RAISE EXCEPTION 'D9 usable seats do not match D8 and blocked rows' USING errcode='23514'; END IF;
  INSERT INTO "Basic_Carrier_Record"."Aircraft_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code","Configuration_Code_Description","Cabin_Area_ID","Seat_Class_Code_1","Seat_Class_Code_2","Seat_Class_Code_3","Seat_Class_Code_4","Total_Seats_Cabin_Area_ID","Cabin_Area_BA_Centroid","Cabin_Area_BA_Start","Cabin_Area_BA_End","Cabin_Area_Index_Per_Weight_Unit","Blocked_Centre_Rows")
  VALUES(p_iata,tc,st,code,description,btrim(item->>'areaId'),(item->'classSeats'->>0)::integer,(item->'classSeats'->>1)::integer,(item->'classSeats'->>2)::integer,(item->'classSeats'->>3)::integer,(item->>'totalSeats')::integer,(item->>'centroid')::double precision,(item->>'from')::double precision,(item->>'to')::double precision,(item->>'index')::double precision,blocked);
 END LOOP;
 RETURN "Basic_Carrier_Record".get_aircraft_d9(p_iata,tc,st);
END;
$function$;

commit;
