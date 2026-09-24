-- B3 configuration-completion review state and read model.
-- Operational passenger-weight records are not changed by this migration.
begin;

-- Explicit saves of optional sections record deliberate review after validation,
-- including when a section remains empty.
create or replace function "Basic_Carrier_Record".get_carrier_passenger_weights(p_iata text) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare d jsonb; rows jsonb; variations jsonb; masters jsonb; classes jsonb; unit text; rev text; rawclass jsonb;
declare variations_reviewed boolean; class_weights_reviewed boolean;
begin
if not private.can_view_carrier_passenger_weights(p_iata) then
return jsonb_build_object('canView',false,'canEdit',false,'revision','','unit',null,'defaultWeights',null,'rows','[]'::jsonb,'variations','[]'::jsonb,'masterVariations','[]'::jsonb,'classes','[]'::jsonb,'variationsReviewed',false,'classWeightsReviewed',false);
end if;
select to_jsonb(t) into d from "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS" t where "Carrier_IATA"=p_iata;
select case when "Carrier_Unit_Weight_KG" and not "Carrier_Unit_Weight_LB" then 'KG' when "Carrier_Unit_Weight_LB" and not "Carrier_Unit_Weight_KG" then 'LB' end into unit from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata;
select to_jsonb(t) into rawclass from "Basic_Carrier_Record"."Carrier_Class_Codes" t where "Carrier_IATA"=p_iata;
select coalesce(jsonb_agg(jsonb_build_object('code',btrim(rawclass->>('Carrier_Class_'||n||'_Code')),'description',btrim(rawclass->>('Carrier_Class_'||n||'_Name'))) order by n),'[]'::jsonb)
into classes from generate_series(1,4) n where rawclass->>('Carrier_Class_'||n||'_Code') is not null;
select coalesce(jsonb_agg(private.passenger_weight_values(to_jsonb(t)) || jsonb_build_object('id',"Passenger_Weight_Set_ID",'classCode',"Class_Code",'variation',"Flight_Type_Variation") order by "Class_Code","Flight_Type_Variation" nulls first),'[]'::jsonb) into rows
from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" t where "Carrier_IATA"=p_iata;
select coalesce(jsonb_agg(jsonb_build_object('code',"Flight_Type_Variation",'description',"Flight_Type_Variation_Description") order by "Flight_Type_Variation"),'[]'::jsonb) into variations
from "Basic_Carrier_Record"."Carrier_Flight_Variations" where "Carrier_IATA"=p_iata;
select coalesce(jsonb_agg(jsonb_build_object('code',"Flight_Type_Variation",'description',"Flight_Type_Variation_Description") order by "Flight_Type_Variation"),'[]'::jsonb) into masters
from "Basic_Carrier_Record"."MASTER_Flight_Variations";
select exists(select 1 from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" where "Carrier_IATA"=p_iata and "Page_Code"='B3' and "Section_Code"='FLIGHT_VARIATIONS' and "Review_State"='REVIEWED') into variations_reviewed;
select exists(select 1 from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" where "Carrier_IATA"=p_iata and "Page_Code"='B3' and "Section_Code"='CLASS_PASSENGER_WEIGHTS' and "Review_State"='REVIEWED') into class_weights_reviewed;
select md5(coalesce(string_agg(v,'|' order by v),'')||coalesce(unit,'')||coalesce(rawclass::text,'')) into rev from (
select 'd:'||xmin::text||to_jsonb(t)::text v from "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS" t where "Carrier_IATA"=p_iata
union all select 'c:'||xmin::text||to_jsonb(t)::text from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" t where "Carrier_IATA"=p_iata
union all select 'v:'||xmin::text||to_jsonb(t)::text from "Basic_Carrier_Record"."Carrier_Flight_Variations" t where "Carrier_IATA"=p_iata
union all select 'r:'||xmin::text||to_jsonb(t)::text from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" t where "Carrier_IATA"=p_iata and "Page_Code"='B3'
) q;
return jsonb_build_object('canView',true,'canEdit',private.can_edit_carrier_details(p_iata),'revision',rev,'unit',unit,'defaultWeights',case when d is null then null else private.passenger_weight_values(d) end,'rows',rows,'variations',variations,'masterVariations',masters,'classes',classes,'variationsReviewed',variations_reviewed,'classWeightsReviewed',class_weights_reviewed);
end $$;

-- Keep the established validation and data-replacement behaviour, adding only
-- the explicit optional-section review record after a successful save.
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
if jsonb_typeof(p_values) is distinct from 'array' or jsonb_array_length(p_values)>200 then raise exception 'Invalid class list' using errcode='22023'; end if;
for v in select value from jsonb_array_elements(p_values) loop
 perform private.validate_passenger_values(v);
 if jsonb_typeof(v->'classCode') is distinct from 'string' or v->>'classCode' !~ '^[A-Z]$' or not (v ? 'variation') or (v->'variation'<>'null'::jsonb and (jsonb_typeof(v->'variation') is distinct from 'string' or v->>'variation' !~ '^[A-Z0-9]{3}$')) then raise exception 'Invalid class or variation' using errcode='22023'; end if;
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

revoke all on function "Basic_Carrier_Record".get_carrier_passenger_weights(text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_carrier_passenger_weights(text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_passenger_weights(text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_carrier_passenger_weights(text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
