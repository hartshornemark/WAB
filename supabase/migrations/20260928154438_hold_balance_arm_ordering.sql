-- Use ascending D2 hold balance arm in every hold list; keep unknown arms last.
do $migration$
declare definition text; updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d11(text,text,text)'::regprocedure);
 updated:=replace(definition,$old$btrim(h."Hold_Type"),btrim(h."Hold_Name_ID")$old$,$new$h."Hold_BA_Centroid" asc nulls last,btrim(h."Hold_Name_ID")$new$);
 if updated=definition then raise exception 'get_aircraft_d11 ordering expression changed';end if;
 definition:=updated;
 execute definition;
end $migration$;
do $migration$
declare definition text; updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d2(text,text,text)'::regprocedure);
 updated:=replace(definition,$old$btrim(h."Hold_Type"),h."Hold_Deck_Location",h."Hold_Display_Name"$old$,$new$h."Hold_BA_Centroid" asc nulls last,btrim(h."Hold_Name_ID")$new$);
 if updated=definition then raise exception 'get_aircraft_d2 ordering expression changed';end if;
 definition:=updated;
 execute definition;
end $migration$;
do $migration$
declare definition text; updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d3(text,text,text)'::regprocedure);
 updated:=replace(definition,$old$order by btrim(h."Hold_Name_ID")$old$,$new$order by h."Hold_BA_Centroid" asc nulls last,btrim(h."Hold_Name_ID")$new$);
 if updated=definition then raise exception 'get_aircraft_d3 ordering expression changed';end if;
 definition:=updated;
 execute definition;
end $migration$;
do $migration$
declare definition text; updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d4(text,text,text)'::regprocedure);
 updated:=replace(definition,$old$case when upper(btrim(h."Hold_Type"))='ULD' then 0 else 1 end,
    $old$,$new$$new$);
 if updated=definition then raise exception 'get_aircraft_d4 ordering expression changed';end if;
 definition:=updated;
 execute definition;
end $migration$;
do $migration$
declare definition text; updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_e2(text,text,text)'::regprocedure);
 updated:=replace(definition,$old$order by h."Hold_Name_ID"$old$,$new$order by h."Hold_BA_Centroid" asc nulls last,btrim(h."Hold_Name_ID")$new$);
 if updated=definition then raise exception 'get_aircraft_e2 ordering expression changed';end if;
 definition:=updated;
 execute definition;
end $migration$;
do $migration$
declare definition text; updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_h1(text,text,text)'::regprocedure);
 updated:=replace(definition,$old$case when btrim(h."Hold_Type")='BLK' then 0 else 1 end,btrim(h."Hold_Name_ID")$old$,$new$h."Hold_BA_Centroid" asc nulls last,btrim(h."Hold_Name_ID")$new$);
 if updated=definition then raise exception 'get_aircraft_h1 ordering expression changed';end if;
 definition:=updated;
 updated:=replace(definition,$old$x.item order by x.sort_hold,x.sort_location$old$,$new$x.item order by h."Hold_BA_Centroid" asc nulls last,x.sort_hold,x.sort_location$new$);
 if updated=definition then raise exception 'get_aircraft_h1 ordering expression changed';end if;
 definition:=updated;
 updated:=replace(definition,$old$  ) x;
  select coalesce(jsonb_agg$old$,$new$  ) x left join "Basic_Carrier_Record"."Aircraft_Holds" h on h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Name_ID")=x.sort_hold;
  select coalesce(jsonb_agg$new$);
 if updated=definition then raise exception 'get_aircraft_h1 ordering expression changed';end if;
 definition:=updated;
 updated:=replace(definition,$old$order by btrim(l."Hold_Name_ID"),$old$,$new$order by (select h."Hold_BA_Centroid" from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=l."Carrier_IATA" and h."Aircraft_Type_IATA"=l."Aircraft_Type_IATA" and h."Aircraft_Series_Subtype"=l."Aircraft_Series_Subtype" and h."Hold_Name_ID"=l."Hold_Name_ID") asc nulls last,btrim(l."Hold_Name_ID"),$new$);
 if updated=definition then raise exception 'get_aircraft_h1 ordering expression changed';end if;
 definition:=updated;
 execute definition;
end $migration$;
do $migration$
declare definition text; updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_g1(text,text,text)'::regprocedure);
 updated:=replace(definition,$old$order by x.hold_id,x.bay_id$old$,$new$order by h."Hold_BA_Centroid" asc nulls last,x.hold_id,x.balance_arm asc nulls last,x.bay_id$new$);
 if updated=definition then raise exception 'get_aircraft_g1 ordering expression changed';end if;
 definition:=updated;
 updated:=replace(definition,$old$select distinct btrim(p."Hold_Name_ID") hold_id,btrim(p."ULD_Position_ID") bay_id$old$,$new$select btrim(p."Hold_Name_ID") hold_id,btrim(p."ULD_Position_ID") bay_id,min(p."Balance_Arm_Centroid") balance_arm$new$);
 if updated=definition then raise exception 'get_aircraft_g1 ordering expression changed';end if;
 definition:=updated;
 updated:=replace(definition,$old$and p."ULD_Row_Type"='POSITION'
  ) x;$old$,$new$and p."ULD_Row_Type"='POSITION'
    group by btrim(p."Hold_Name_ID"),btrim(p."ULD_Position_ID")
  ) x left join "Basic_Carrier_Record"."Aircraft_Holds" h on h."Carrier_IATA"=ci and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Name_ID")=x.hold_id;$new$);
 if updated=definition then raise exception 'get_aircraft_g1 ordering expression changed';end if;
 definition:=updated;
 execute definition;
end $migration$;
