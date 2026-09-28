-- Sorting metadata only: do not populate missing engineering dimensions.
create or replace function private.aircraft_hold_sort_arm(ci text,tc text,st text,hold_id text)
returns double precision language sql stable security invoker set search_path='' as $function$
 select coalesce(h."Hold_BA_Centroid",(h."Hold_BA_Start"+h."Hold_BA_End")/2.0,
   (select (min(coalesce(p."Balance_Arm_From",p."Balance_Arm_Centroid"))+max(coalesce(p."Balance_Arm_To",p."Balance_Arm_Centroid")))/2.0
    from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
    where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."Hold_Name_ID"=hold_id and p."ULD_Row_Type"='POSITION'))
 from "Basic_Carrier_Record"."Aircraft_Holds" h
 where h."Carrier_IATA"=ci and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and h."Hold_Name_ID"=hold_id;
$function$;
revoke all on function private.aircraft_hold_sort_arm(text,text,text,text) from public,anon;
grant execute on function private.aircraft_hold_sort_arm(text,text,text,text) to authenticated,service_role;
do $migration$
declare fname text; definition text;
begin
 foreach fname in array array['get_aircraft_d2','get_aircraft_d3','get_aircraft_d4','get_aircraft_d11','get_aircraft_e2','get_aircraft_g1','get_aircraft_h1'] loop
 definition:=pg_get_functiondef(format('"Basic_Carrier_Record".%I(text,text,text)',fname)::regprocedure);
 definition:=replace(definition,'h."Hold_BA_Centroid" asc nulls last',$arm$private.aircraft_hold_sort_arm(h."Carrier_IATA"::text,h."Aircraft_Type_IATA"::text,h."Aircraft_Series_Subtype"::text,h."Hold_Name_ID"::text) asc nulls last$arm$);
 definition:=replace(definition,'select h."Hold_BA_Centroid" from',$arm$select private.aircraft_hold_sort_arm(h."Carrier_IATA"::text,h."Aircraft_Type_IATA"::text,h."Aircraft_Series_Subtype"::text,h."Hold_Name_ID"::text) from$arm$);
 if fname in ('get_aircraft_d2','get_aircraft_d3') then
 definition:=replace(definition,$old$'balanceCentroid',h."Hold_BA_Centroid"$old$,$new$'balanceCentroid',h."Hold_BA_Centroid",'sortBalanceArm',private.aircraft_hold_sort_arm(h."Carrier_IATA"::text,h."Aircraft_Type_IATA"::text,h."Aircraft_Series_Subtype"::text,h."Hold_Name_ID"::text)$new$);
 end if;
 execute definition;
 end loop;
end $migration$;
