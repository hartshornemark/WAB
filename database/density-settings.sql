-- Proposed B1 density protections. Apply only after explicit approval.
begin;
alter table "Basic_Carrier_Record"."Carrier_Units_of_Measure" enable row level security;
alter table "Basic_Carrier_Record"."Carrier_Units_of_Measure"
 add constraint density_baggage_positive check("Density_Checked_Baggage">0 and "Density_Checked_Baggage"<'Infinity'::float8),
 add constraint density_cargo_positive check("Density_General_Cargo">0 and "Density_General_Cargo"<'Infinity'::float8),
 add constraint density_mail_positive check("Density_General_Mail">0 and "Density_General_Mail"<'Infinity'::float8),
 add constraint density_carrier_fk foreign key("Carrier_IATA") references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA") on update restrict on delete restrict;
create policy density_admin_read on "Basic_Carrier_Record"."Carrier_Units_of_Measure" for select to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
alter policy perm_carrier_insert on "Basic_Carrier_Record"."Carrier_Units_of_Measure" to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
alter policy perm_carrier_update on "Basic_Carrier_Record"."Carrier_Units_of_Measure" to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy density_admin_delete_guard on "Basic_Carrier_Record"."Carrier_Units_of_Measure" as restrictive for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
create trigger density_carrier_owner before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Units_of_Measure" for each row execute function private.protect_carrier_identifier();
revoke all on "Basic_Carrier_Record"."Carrier_Units_of_Measure" from public,anon;
revoke truncate,references,trigger on "Basic_Carrier_Record"."Carrier_Units_of_Measure" from authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Units_of_Measure" to authenticated;


-- Keep density numbers in the carrier's selected B1 weight/volume units.
create function private.convert_carrier_densities() returns trigger
language plpgsql security invoker set search_path='' as $$
declare old_weight float8; new_weight float8; old_volume float8; new_volume float8; factor float8;
begin
if row(old."Carrier_Unit_Weight_KG",old."Carrier_Unit_Weight_LB",old."Carrier_Unit_Volume_m3",old."Carrier_Unit_Volume_ft3") is not distinct from row(new."Carrier_Unit_Weight_KG",new."Carrier_Unit_Weight_LB",new."Carrier_Unit_Volume_m3",new."Carrier_Unit_Volume_ft3") then return new; end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_Units_of_Measure" where "Carrier_IATA"=new."Carrier_IATA" and ("Density_Checked_Baggage" is not null or "Density_General_Cargo" is not null or "Density_General_Mail" is not null)) then
 if (old."Carrier_Unit_Weight_KG"::int+old."Carrier_Unit_Weight_LB"::int) is distinct from 1 or (new."Carrier_Unit_Weight_KG"::int+new."Carrier_Unit_Weight_LB"::int) is distinct from 1 or (old."Carrier_Unit_Volume_m3"::int+old."Carrier_Unit_Volume_ft3"::int) is distinct from 1 or (new."Carrier_Unit_Volume_m3"::int+new."Carrier_Unit_Volume_ft3"::int) is distinct from 1 then raise exception 'Resolve weight and volume units before converting densities' using errcode='23514'; end if;
 old_weight:=case when old."Carrier_Unit_Weight_KG" then 1 else 0.45359237 end;
 new_weight:=case when new."Carrier_Unit_Weight_KG" then 1 else 0.45359237 end;
 old_volume:=case when old."Carrier_Unit_Volume_m3" then 1 else 0.028316846592 end;
 new_volume:=case when new."Carrier_Unit_Volume_m3" then 1 else 0.028316846592 end;
 factor:=old_weight/old_volume*new_volume/new_weight;
 update "Basic_Carrier_Record"."Carrier_Units_of_Measure" set "Density_Checked_Baggage"="Density_Checked_Baggage"*factor,"Density_General_Cargo"="Density_General_Cargo"*factor,"Density_General_Mail"="Density_General_Mail"*factor where "Carrier_IATA"=new."Carrier_IATA";
end if;
return new;
end $$;
revoke all on function private.convert_carrier_densities() from public,anon,authenticated;
create trigger convert_carrier_densities before update on "Basic_Carrier_Record"."Basic_Carrier_Data" for each row execute function private.convert_carrier_densities();

create function "Basic_Carrier_Record".get_carrier_densities(p_iata text) returns jsonb
language sql stable security invoker set search_path='' as $$
with access as (select private.can_edit_carrier_details(p_iata) as edit,private.can_view_carrier_classes(p_iata) as view)
select jsonb_build_object('canView',a.view,'canEdit',a.edit,'exists',d."Carrier_IATA" is not null,
'revision',case when a.view then md5(coalesce(to_jsonb(d)::text,'null')||coalesce(d.xmin::text,'')||jsonb_build_array(b."Carrier_Unit_Weight_KG",b."Carrier_Unit_Weight_LB",b."Carrier_Unit_Volume_m3",b."Carrier_Unit_Volume_ft3")::text) else '' end,
'weightUnit',case when b."Carrier_Unit_Weight_KG" and not b."Carrier_Unit_Weight_LB" then 'KG' when b."Carrier_Unit_Weight_LB" and not b."Carrier_Unit_Weight_KG" then 'LB' else '' end,
'volumeUnit',case when b."Carrier_Unit_Volume_m3" and not b."Carrier_Unit_Volume_ft3" then 'm3' when b."Carrier_Unit_Volume_ft3" and not b."Carrier_Unit_Volume_m3" then 'ft3' else '' end,
'values',jsonb_build_object('baggage',coalesce(d."Density_Checked_Baggage"::text,''),'cargo',coalesce(d."Density_General_Cargo"::text,''),'mail',coalesce(d."Density_General_Mail"::text,'')))
from access a left join "Basic_Carrier_Record"."Carrier_Units_of_Measure" d on a.view and d."Carrier_IATA"=p_iata
left join "Basic_Carrier_Record"."Basic_Carrier_Data" b on a.view and b."Carrier_IATA"=p_iata;
$$;
revoke all on function "Basic_Carrier_Record".get_carrier_densities(text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_densities(text) to authenticated;

create function "Basic_Carrier_Record".save_carrier_densities(p_iata text,p_revision text,p_values jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare current_data jsonb; key text; val text;
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501'; end if;
perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
if not found then raise exception 'Set carrier units first' using errcode='23514'; end if;
perform 1 from "Basic_Carrier_Record"."Carrier_Units_of_Measure" where "Carrier_IATA"=p_iata for update;
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
return "Basic_Carrier_Record".get_carrier_densities(p_iata);
end $$;
revoke all on function "Basic_Carrier_Record".save_carrier_densities(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_densities(text,text,jsonb) to authenticated;
comment on column "Basic_Carrier_Record"."Carrier_Units_of_Measure"."Density_Checked_Baggage" is 'Checked baggage density in the weight / volume units selected in Basic_Carrier_Data on B1. Converted when those units change. NULL means unknown.';
comment on column "Basic_Carrier_Record"."Carrier_Units_of_Measure"."Density_General_Cargo" is 'General cargo density in the B1 selected weight / volume units; converted on B1 unit changes.';
comment on column "Basic_Carrier_Record"."Carrier_Units_of_Measure"."Density_General_Mail" is 'General mail density in the B1 selected weight / volume units; converted on B1 unit changes.';
notify pgrst,'reload schema';
commit;
