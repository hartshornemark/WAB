-- B3 passenger-weight tables may cover every class in a named flight variation.
-- The existing ALLFLIGHTS row remains the fallback for flights without an override.
begin;

alter table "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS"
  alter column "Class_Code" drop not null;

comment on column "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS"."Class_Code"
  is 'NULL means All Classes; otherwise a class saved for the carrier on B1.';
comment on column "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS"."Flight_Type_Variation"
  is 'NULL means Standard Flights for a class-specific override; otherwise an explicitly selected carrier variation.';
comment on table "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS"
  is 'B3 passenger-weight overrides by carrier class and/or named flight variation. The ALLFLIGHTS table is the fallback.';

create or replace function private.validate_passenger_weight_class() returns trigger
language plpgsql security invoker set search_path='' as $$
declare c "Basic_Carrier_Record"."Carrier_Class_Codes"%rowtype;
begin
if tg_op='UPDATE' and new."Carrier_IATA" is distinct from old."Carrier_IATA" then
 raise exception 'Carrier ownership cannot change' using errcode='42501';
end if;
if current_user='authenticated' and not private.can_edit_carrier_details(new."Carrier_IATA") then
 raise exception 'Not authorised' using errcode='42501';
end if;
update "Basic_Carrier_Record"."Carrier_Class_Codes"
set "Carrier_IATA"="Carrier_IATA" where "Carrier_IATA"=new."Carrier_IATA" returning * into c;
if new."Class_Code" is not null and (not found or not coalesce(new."Class_Code"=any(array[
 c."Carrier_Class_1_Code"::text,c."Carrier_Class_2_Code"::text,
 c."Carrier_Class_3_Code"::text,c."Carrier_Class_4_Code"::text]),false)) then
 raise exception 'Save this class for the carrier on B1 first' using errcode='23503';
end if;
return new;
end $$;

create or replace function private.protect_passenger_weight_classes() returns trigger
language plpgsql security invoker set search_path='' as $$
declare codes text[];
begin
if tg_op='DELETE' then codes:='{}';
else codes:=array[new."Carrier_Class_1_Code"::text,new."Carrier_Class_2_Code"::text,new."Carrier_Class_3_Code"::text,new."Carrier_Class_4_Code"::text]; end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w
 where w."Carrier_IATA"=old."Carrier_IATA" and w."Class_Code" is not null
 and not coalesce(w."Class_Code"=any(codes),false)) then
 raise exception 'Resolve passenger weight sets before removing or renaming a class' using errcode='23503';
end if;
if tg_op='DELETE' then return old; end if;
return new;
end $$;

create or replace function "Basic_Carrier_Record".save_carrier_passenger_weights(p_iata text,p_revision text,p_section text,p_values jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare snapshot jsonb; v jsonb; ids uuid[]:='{}'; id uuid; codes text[]:='{}'; code text; description text;
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501'; end if;
if p_section not in ('default','classes','variations') or p_section is null then raise exception 'Invalid section' using errcode='22023'; end if;
perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
perform 1 from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"=p_iata for update;
perform 1 from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" where "Carrier_IATA"=p_iata and "Page_Code"='B3' for update;
snapshot:="Basic_Carrier_Record".get_carrier_passenger_weights(p_iata);
if p_revision is distinct from snapshot->>'revision' then raise exception 'Passenger configuration changed' using errcode='40001'; end if;
if p_section<>'variations' and snapshot->>'unit' is null then raise exception 'Set the B1 weight unit first' using errcode='22023'; end if;
if p_section='default' then
 perform private.validate_passenger_values(p_values);
 if p_values->>'remarks'<>'' then raise exception 'Default remarks are not supported by the current table' using errcode='22023'; end if;
 insert into "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS"("Carrier_IATA","Adult","Male","Female","Child","Infant","Hand_Baggage_Weight","Passenger_Weights_Include_Handbaggage") values(p_iata,(p_values->>'adult')::integer,(p_values->>'male')::integer,(p_values->>'female')::integer,(p_values->>'child')::integer,(p_values->>'infant')::integer,(p_values->>'handBaggage')::integer,(p_values->>'includesHandBaggage')::boolean) on conflict("Carrier_IATA") do update set "Adult"=excluded."Adult","Male"=excluded."Male","Female"=excluded."Female","Child"=excluded."Child","Infant"=excluded."Infant","Hand_Baggage_Weight"=excluded."Hand_Baggage_Weight","Passenger_Weights_Include_Handbaggage"=excluded."Passenger_Weights_Include_Handbaggage";
elsif p_section='classes' then
 if jsonb_typeof(p_values) is distinct from 'array' or jsonb_array_length(p_values)>200 then raise exception 'Invalid passenger table list' using errcode='22023'; end if;
 for v in select value from jsonb_array_elements(p_values) loop
  perform private.validate_passenger_values(v);
  if not (v ? 'classCode') or
     ((v->'classCode') is distinct from 'null'::jsonb and (jsonb_typeof(v->'classCode') is distinct from 'string' or v->>'classCode' !~ '^[A-Z]$')) or
     not (v ? 'variation') or
     ((v->'variation') is distinct from 'null'::jsonb and (jsonb_typeof(v->'variation') is distinct from 'string' or v->>'variation' !~ '^[A-Z0-9]{3}$')) or
     ((v->'classCode')='null'::jsonb and (v->'variation')='null'::jsonb)
  then raise exception 'Invalid class or variation' using errcode='22023'; end if;
  if v->>'id' is null then id:=gen_random_uuid(); else id:=(v->>'id')::uuid; if not exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" where "Passenger_Weight_Set_ID"=id and "Carrier_IATA"=p_iata) then raise exception 'Unknown weight set' using errcode='22023'; end if; end if;
  if id=any(ids) then raise exception 'Duplicate row' using errcode='22023'; end if;
  ids:=array_append(ids,id);
 end loop;
 delete from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" where "Carrier_IATA"=p_iata;
 for v,id in select value,ids[ordinality::integer] from jsonb_array_elements(p_values) with ordinality loop
  insert into "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS"("Passenger_Weight_Set_ID","Carrier_IATA","Class_Code","Flight_Type_Variation","Adult","Male","Female","Child","Infant","Hand_Baggage_Weight","Passenger_Weights_Include_Handbaggage","Remarks") values(id,p_iata,v->>'classCode',v->>'variation',(v->>'adult')::integer,(v->>'male')::integer,(v->>'female')::integer,(v->>'child')::integer,(v->>'infant')::integer,(v->>'handBaggage')::integer,(v->>'includesHandBaggage')::boolean,v->>'remarks');
 end loop;
else
 if jsonb_typeof(p_values) is distinct from 'array' or jsonb_array_length(p_values)>100 then raise exception 'Invalid variation list' using errcode='22023'; end if;
 for v in select value from jsonb_array_elements(p_values) loop
  if jsonb_typeof(v->'code') is distinct from 'string' or jsonb_typeof(v->'description') is distinct from 'string' then raise exception 'Invalid variation' using errcode='22023'; end if;
  code:=v->>'code'; description:=v->>'description';
  if code !~ '^[A-Z0-9]{3}$' or char_length(description) not between 1 and 64 or description<>btrim(description) or description ~ '[[:cntrl:]]' or code=any(codes) then raise exception 'Invalid or duplicate variation' using errcode='22023'; end if;
  codes:=array_append(codes,code);
 end loop;
 delete from "Basic_Carrier_Record"."Carrier_Flight_Variations" where "Carrier_IATA"=p_iata and not ("Flight_Type_Variation"=any(codes));
 for v in select value from jsonb_array_elements(p_values) loop
  insert into "Basic_Carrier_Record"."Carrier_Flight_Variations" values(v->>'code',v->>'description',p_iata)
  on conflict("Flight_Type_Variation","Carrier_IATA") do update set "Flight_Type_Variation_Description"=excluded."Flight_Type_Variation_Description";
 end loop;
end if;
if p_section in ('variations','classes') then
 insert into "Basic_Carrier_Record"."Carrier_Configuration_Review_State"("Carrier_IATA","Page_Code","Section_Code","Review_State","Reviewed_At")
 values(p_iata,'B3',case when p_section='variations' then 'FLIGHT_VARIATIONS' else 'CLASS_PASSENGER_WEIGHTS' end,'REVIEWED',now())
 on conflict("Carrier_IATA","Page_Code","Section_Code") do update set "Review_State"='REVIEWED',"Reviewed_At"=excluded."Reviewed_At";
end if;
return "Basic_Carrier_Record".get_carrier_passenger_weights(p_iata);
end $$;

revoke all on function "Basic_Carrier_Record".save_carrier_passenger_weights(text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_passenger_weights(text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
