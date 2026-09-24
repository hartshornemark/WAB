begin;

create table if not exists "Basic_Carrier_Record"."Carrier_Configuration_Review_State"(
  "Carrier_IATA" varchar not null,
  "Page_Code" varchar(8) not null,
  "Section_Code" varchar(64) not null,
  "Review_State" varchar(20) not null,
  "Reviewed_At" timestamptz not null default now(),
  primary key("Carrier_IATA","Page_Code","Section_Code"),
  constraint carrier_configuration_review_carrier_fk foreign key("Carrier_IATA") references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA") on update restrict on delete restrict,
  constraint carrier_configuration_review_page check("Page_Code" ~ '^[A-Z][A-Z0-9.]*$'),
  constraint carrier_configuration_review_section check("Section_Code" ~ '^[A-Z][A-Z0-9_]*$'),
  constraint carrier_configuration_review_state check("Review_State" in ('REVIEWED','APPLIES','NOT_APPLICABLE'))
);

alter table "Basic_Carrier_Record"."Carrier_Configuration_Review_State" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Configuration_Review_State" from public,anon;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Configuration_Review_State" to authenticated;

create policy carrier_configuration_review_read on "Basic_Carrier_Record"."Carrier_Configuration_Review_State"
for select to authenticated using(private.can_view_carrier_classes("Carrier_IATA"));
create policy carrier_configuration_review_insert on "Basic_Carrier_Record"."Carrier_Configuration_Review_State"
for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy carrier_configuration_review_update on "Basic_Carrier_Record"."Carrier_Configuration_Review_State"
for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy carrier_configuration_review_delete on "Basic_Carrier_Record"."Carrier_Configuration_Review_State"
for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));

create or replace function "Basic_Carrier_Record".get_carrier_densities(p_iata text) returns jsonb
language sql stable security invoker set search_path='' as $$
with access as (select private.can_edit_carrier_details(p_iata) as edit,private.can_view_carrier_classes(p_iata) as view)
select jsonb_build_object('canView',a.view,'canEdit',a.edit,'exists',d."Carrier_IATA" is not null,
'reviewed',coalesce(r."Review_State"='REVIEWED',false),
'revision',case when a.view then md5(coalesce(to_jsonb(d)::text,'null')||coalesce(d.xmin::text,'')||coalesce(to_jsonb(r)::text,'null')||coalesce(r.xmin::text,'')||jsonb_build_array(b."Carrier_Unit_Weight_KG",b."Carrier_Unit_Weight_LB",b."Carrier_Unit_Volume_m3",b."Carrier_Unit_Volume_ft3")::text) else '' end,
'weightUnit',case when b."Carrier_Unit_Weight_KG" and not b."Carrier_Unit_Weight_LB" then 'KG' when b."Carrier_Unit_Weight_LB" and not b."Carrier_Unit_Weight_KG" then 'LB' else '' end,
'volumeUnit',case when b."Carrier_Unit_Volume_m3" and not b."Carrier_Unit_Volume_ft3" then 'm3' when b."Carrier_Unit_Volume_ft3" and not b."Carrier_Unit_Volume_m3" then 'ft3' else '' end,
'values',jsonb_build_object('baggage',coalesce(d."Density_Checked_Baggage"::text,''),'cargo',coalesce(d."Density_General_Cargo"::text,''),'mail',coalesce(d."Density_General_Mail"::text,'')))
from access a left join "Basic_Carrier_Record"."Carrier_Units_of_Measure" d on a.view and d."Carrier_IATA"=p_iata
left join "Basic_Carrier_Record"."Basic_Carrier_Data" b on a.view and b."Carrier_IATA"=p_iata
left join "Basic_Carrier_Record"."Carrier_Configuration_Review_State" r on a.view and r."Carrier_IATA"=p_iata and r."Page_Code"='B1' and r."Section_Code"='COMMODITY_DENSITIES';
$$;

create or replace function "Basic_Carrier_Record".save_carrier_densities(p_iata text,p_revision text,p_values jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare current_data jsonb; key text; val text;
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501'; end if;
perform pg_advisory_xact_lock(hashtextextended('b1-densities:'||p_iata,0));
perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
if not found then raise exception 'Set carrier units first' using errcode='23514'; end if;
perform 1 from "Basic_Carrier_Record"."Carrier_Units_of_Measure" where "Carrier_IATA"=p_iata for update;
perform 1 from "Basic_Carrier_Record"."Carrier_Configuration_Review_State" where "Carrier_IATA"=p_iata and "Page_Code"='B1' and "Section_Code"='COMMODITY_DENSITIES' for update;
current_data:="Basic_Carrier_Record".get_carrier_densities(p_iata);
if p_revision is distinct from current_data->>'revision' then raise exception 'Density settings changed' using errcode='40001'; end if;
if current_data->>'weightUnit'='' or current_data->>'volumeUnit'='' then raise exception 'Set weight and volume units first' using errcode='23514'; end if;
if jsonb_typeof(p_values) is distinct from 'object' then raise exception 'Invalid densities' using errcode='22023'; end if;
foreach key in array array['baggage','cargo','mail'] loop
 val:=p_values->>key;
 if val is null or jsonb_typeof(p_values->key)<>'string' or (val<>'' and (val !~ '^[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$' or val::float8<=0 or val::float8>='Infinity'::float8)) then raise exception 'Invalid density' using errcode='22023'; end if;
end loop;
insert into "Basic_Carrier_Record"."Carrier_Units_of_Measure"("Carrier_IATA","Density_Checked_Baggage","Density_General_Cargo","Density_General_Mail") values(p_iata,nullif(p_values->>'baggage','')::float8,nullif(p_values->>'cargo','')::float8,nullif(p_values->>'mail','')::float8)
on conflict("Carrier_IATA") do update set "Density_Checked_Baggage"=excluded."Density_Checked_Baggage","Density_General_Cargo"=excluded."Density_General_Cargo","Density_General_Mail"=excluded."Density_General_Mail";
insert into "Basic_Carrier_Record"."Carrier_Configuration_Review_State"("Carrier_IATA","Page_Code","Section_Code","Review_State","Reviewed_At")
values(p_iata,'B1','COMMODITY_DENSITIES','REVIEWED',now())
on conflict("Carrier_IATA","Page_Code","Section_Code") do update set "Review_State"='REVIEWED',"Reviewed_At"=excluded."Reviewed_At";
return "Basic_Carrier_Record".get_carrier_densities(p_iata);
end $$;

revoke all on function "Basic_Carrier_Record".get_carrier_densities(text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_carrier_densities(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_densities(text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_carrier_densities(text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
