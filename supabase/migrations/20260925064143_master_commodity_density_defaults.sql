begin;
create table "Basic_Carrier_Record"."MASTER_Commodity_Density" (
 "Commodity_Code" text primary key check("Commodity_Code" in ('BAG','CARGO','MAIL')),
 "Density_Kg_Per_M3" numeric(14,6) not null check("Density_Kg_Per_M3">0 and "Density_Kg_Per_M3"<100000000),
 "Source" text not null,
 "Updated_At" timestamptz not null default now()
);
alter table "Basic_Carrier_Record"."MASTER_Commodity_Density" enable row level security;
revoke all on "Basic_Carrier_Record"."MASTER_Commodity_Density" from public,anon,authenticated;
grant select on "Basic_Carrier_Record"."MASTER_Commodity_Density" to authenticated;
create policy master_density_read on "Basic_Carrier_Record"."MASTER_Commodity_Density" for select to authenticated using((select auth.uid()) is not null);
insert into "Basic_Carrier_Record"."MASTER_Commodity_Density"("Commodity_Code","Density_Kg_Per_M3","Source") values
 ('BAG',177,'Application owner approved defaults, 25 September 2026'),
 ('CARGO',210,'Application owner approved defaults, 25 September 2026'),
 ('MAIL',210,'Application owner approved defaults, 25 September 2026');
comment on table "Basic_Carrier_Record"."MASTER_Commodity_Density" is 'Suggested commodity densities stored in kg/m3. Suggestions never replace saved carrier values and require explicit carrier review/save.';
create or replace function "Basic_Carrier_Record".get_carrier_densities(p_iata text) returns jsonb
language sql stable security invoker set search_path='' as $$
with access as (select private.can_edit_carrier_details(p_iata) as edit,private.can_view_carrier_classes(p_iata) as view),
master as (select coalesce(jsonb_object_agg("Commodity_Code","Density_Kg_Per_M3"),'{}'::jsonb) as values from "Basic_Carrier_Record"."MASTER_Commodity_Density")
select jsonb_build_object('canView',a.view,'canEdit',a.edit,'exists',d."Carrier_IATA" is not null,
'revision',case when a.view then md5(coalesce(to_jsonb(d)::text,'null')||coalesce(d.xmin::text,'')||jsonb_build_array(b."Carrier_Unit_Weight_KG",b."Carrier_Unit_Weight_LB",b."Carrier_Unit_Volume_m3",b."Carrier_Unit_Volume_ft3")::text||m.values::text) else '' end,
'weightUnit',case when b."Carrier_Unit_Weight_KG" and not b."Carrier_Unit_Weight_LB" then 'KG' when b."Carrier_Unit_Weight_LB" and not b."Carrier_Unit_Weight_KG" then 'LB' else '' end,
'volumeUnit',case when b."Carrier_Unit_Volume_m3" and not b."Carrier_Unit_Volume_ft3" then 'm3' when b."Carrier_Unit_Volume_ft3" and not b."Carrier_Unit_Volume_m3" then 'ft3' else '' end,
'values',jsonb_build_object('baggage',coalesce(d."Density_Checked_Baggage"::text,''),'cargo',coalesce(d."Density_General_Cargo"::text,''),'mail',coalesce(d."Density_General_Mail"::text,'')),
'defaults',jsonb_build_object(
'baggage',coalesce(trim_scale(round((m.values->>'BAG')::numeric*f.factor,6))::text,''),
'cargo',coalesce(trim_scale(round((m.values->>'CARGO')::numeric*f.factor,6))::text,''),
'mail',coalesce(trim_scale(round((m.values->>'MAIL')::numeric*f.factor,6))::text,'')))
from access a cross join master m
left join "Basic_Carrier_Record"."Carrier_Units_of_Measure" d on a.view and d."Carrier_IATA"=p_iata
left join "Basic_Carrier_Record"."Basic_Carrier_Data" b on a.view and b."Carrier_IATA"=p_iata
cross join lateral (select
 (case when b."Carrier_Unit_Volume_m3" and not b."Carrier_Unit_Volume_ft3" then 1::numeric when b."Carrier_Unit_Volume_ft3" and not b."Carrier_Unit_Volume_m3" then 0.028316846592::numeric end)
 / (case when b."Carrier_Unit_Weight_KG" and not b."Carrier_Unit_Weight_LB" then 1::numeric when b."Carrier_Unit_Weight_LB" and not b."Carrier_Unit_Weight_KG" then 0.45359237::numeric end) as factor) f;
$$;
notify pgrst,'reload schema';
commit;
