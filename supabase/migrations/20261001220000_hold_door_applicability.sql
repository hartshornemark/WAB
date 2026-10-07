begin;

alter table "Basic_Carrier_Record"."Aircraft_Holds"
  add column if not exists "Hold_Has_Door" boolean;

do $$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d2(text,text,text)'::regprocedure);
 updated:=replace(definition,
  $old$'indexPerWeightUnit',h."Hold_Index_Per_Weight_Unit",'compartments'$old$,
  $new$'indexPerWeightUnit',h."Hold_Index_Per_Weight_Unit",'hasDoor',h."Hold_Has_Door",'compartments'$new$);
 if updated=definition then raise exception 'get_aircraft_d2 hold projection changed';end if;
 execute updated;
end $$;

do $$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".save_aircraft_d2(text,text,text,text,text,jsonb)'::regprocedure);
 updated:=replace(definition,
  $old$if jsonb_typeof(item->'compartments')<>'array' then$old$,
  $new$update "Basic_Carrier_Record"."Aircraft_Holds" set
   "Hold_Has_Door"=nullif(item->>'hasDoor','')::boolean,
   "Hold_DOOR_Start"=case when coalesce(nullif(item->>'hasDoor','')::boolean,true) then "Hold_DOOR_Start" else null end,
   "Hold_DOOR_End"=case when coalesce(nullif(item->>'hasDoor','')::boolean,true) then "Hold_DOOR_End" else null end,
   "Hold_DOOR_Height"=case when coalesce(nullif(item->>'hasDoor','')::boolean,true) then "Hold_DOOR_Height" else null end,
   "Hold_DOOR_Orientation"=case when coalesce(nullif(item->>'hasDoor','')::boolean,true) then "Hold_DOOR_Orientation" else null end
  where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id;
 if jsonb_typeof(item->'compartments')<>'array' then$new$);
 if updated=definition then raise exception 'save_aircraft_d2 hold persistence changed';end if;
 execute updated;
end $$;

do $$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d4(text,text,text)'::regprocedure);
 updated:=replace(definition,
  $old$where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;$old$,
  $new$where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st
    and coalesce(h."Hold_Has_Door",true);$new$);
 if updated=definition then raise exception 'get_aircraft_d4 hold filter changed';end if;
 execute updated;
end $$;

do $$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".save_aircraft_d4(text,text,text,text,jsonb)'::regprocedure);
 updated:=replace(definition,
  $old$where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st
  ) then$old$,
  $new$where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st
      and coalesce("Hold_Has_Door",true)
  ) then$new$);
 updated:=replace(updated,
  $old$and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id;$old$,
  $new$and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id
      and coalesce("Hold_Has_Door",true);$new$);
 if updated=definition then raise exception 'save_aircraft_d4 hold filter changed';end if;
 execute updated;
end $$;

notify pgrst,'reload schema';
commit;
