from pathlib import Path
s='''-- Carrier Details functions and administrator-only write policies.
-- Apply once; keep as a record of the approved database change.
begin;
insert into application_security.permissions(permission_code,permission_name,description)
values ('CARRIER_DETAILS_EDIT','Edit carrier details','Maintain carrier contact details and basic operating preferences');
insert into application_security.role_permissions(role_id,permission_id)
select r.role_id,p.permission_id from application_security.roles r cross join application_security.permissions p
where r.role_code in ('SOLUTION_ADMINISTRATOR','CARRIER_ADMINISTRATOR') and p.permission_code='CARRIER_DETAILS_EDIT';

create function private.can_edit_carrier_details(p_iata text) returns boolean language sql stable security invoker set search_path='' as $$
select (select auth.uid()) is not null
and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
and (private.has_global_permission('CARRIER_DETAILS_EDIT') or private.has_carrier_permission(p_iata,'CARRIER_DETAILS_EDIT'));
$$;
revoke all on function private.can_edit_carrier_details(text) from public,anon;
grant execute on function private.can_edit_carrier_details(text) to authenticated;
'''
for table in ['Carrier_Contact_Data','Basic_Carrier_Data']:
 s+=f'''
create policy details_admin_read on "Basic_Carrier_Record"."{table}" for select to authenticated
using (private.can_edit_carrier_details("Carrier_IATA"));
alter policy perm_carrier_insert on "Basic_Carrier_Record"."{table}" to authenticated
with check (private.can_edit_carrier_details("Carrier_IATA"));
alter policy perm_carrier_update on "Basic_Carrier_Record"."{table}" to authenticated
using (private.can_edit_carrier_details("Carrier_IATA")) with check (private.can_edit_carrier_details("Carrier_IATA"));
create policy details_admin_delete_guard on "Basic_Carrier_Record"."{table}" as restrictive for delete to authenticated
using (private.can_edit_carrier_details("Carrier_IATA"));
'''
s+='''
create function "Basic_Carrier_Record".get_carrier_details(p_iata text) returns jsonb
language sql stable security invoker set search_path='' as $$
with access as (
 select private.can_edit_carrier_details(p_iata) as edit,
 (select auth.uid()) is not null and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
 and (private.can_edit_carrier_details(p_iata) or private.has_carrier_permission(p_iata,'CARRIER_CONFIG_VIEW')) as view
), rows as (
 select a.*,c.*,b."Carrier_Unit_Weight_KG",b."Carrier_Unit_Weight_LB",b."Carrier_Unit_Volume_m3",b."Carrier_Unit_Volume_ft3",b."Carrier_Basic_Weight",b."Carrier_Dry_Operating_Weight",
 b."Carrier_IATA" as basic_iata,
 case when a.view then md5(coalesce(to_jsonb(c)::text,'null') || coalesce(c.xmin::text,'') || coalesce(to_jsonb(b)::text,'null') || coalesce(b.xmin::text,'')) else '' end as revision
 from access a
 left join "Basic_Carrier_Record"."Carrier_Contact_Data" c on a.view and c."Carrier_IATA"=p_iata
 left join "Basic_Carrier_Record"."Basic_Carrier_Data" b on a.view and b."Carrier_IATA"=p_iata
)
select jsonb_build_object('canView',view,'canEdit',edit,'exists',"Carrier_IATA" is not null and basic_iata is not null,'revision',revision,
 'values',jsonb_build_object(
 'address1',coalesce("Address_Line_1",''),'address2',coalesce("Address_Line_2",''),'address3',coalesce("Address_Line_3",''),
 'city',coalesce("City",''),'state',coalesce("State_or_Province",''),'country',coalesce("Country",''),
 'telephone',coalesce("Telephone_Number",''),'email',coalesce("Email_Address",''),'teletype',coalesce("TELETYPE_Address",''),
 'weightUnit',case when "Carrier_Unit_Weight_KG" then 'KG' when "Carrier_Unit_Weight_LB" then 'LB' else '' end,
 'volumeUnit',case when "Carrier_Unit_Volume_m3" then 'm3' when "Carrier_Unit_Volume_ft3" then 'ft3' else '' end,
 'weightMethod',case when "Carrier_Basic_Weight" then 'BASIC' when "Carrier_Dry_Operating_Weight" then 'DRY_OPERATING' else '' end)) from rows;
$$;
revoke all on function "Basic_Carrier_Record".get_carrier_details(text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_details(text) to authenticated;

create function "Basic_Carrier_Record".save_carrier_details(p_iata text,p_revision text,p_values jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare current_snapshot jsonb; v jsonb := '{}'::jsonb; k text; value text; contact_exists boolean; basic_exists boolean;
begin
 if not private.can_edit_carrier_details(p_iata) then raise exception 'Carrier details access denied' using errcode='42501'; end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Invalid details' using errcode='23514'; end if;
 if exists(select 1 from jsonb_object_keys(p_values) key where key not in ('address1','address2','address3','city','state','country','telephone','email','teletype','weightUnit','volumeUnit','weightMethod')) then raise exception 'Unexpected details field' using errcode='23514'; end if;
 foreach k in array array['address1','address2','address3','city','state','country','telephone','email','teletype','weightUnit','volumeUnit','weightMethod'] loop
   if jsonb_typeof(p_values->k) is distinct from 'string' then raise exception 'Invalid details field' using errcode='23514'; end if;
   value := btrim(p_values->>k);
   if length(value)>64 or value ~ '[[:cntrl:]]' then raise exception 'Invalid details field' using errcode='23514'; end if;
   v := v || jsonb_build_object(k,value);
 end loop;
 if v->>'address1'='' or v->>'city'='' or v->>'country'='' then raise exception 'Required contact details missing' using errcode='23514'; end if;
 if v->>'email'<>'' and v->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Invalid email' using errcode='23514'; end if;
 if v->>'teletype'<>'' and length(v->>'teletype')<>7 then raise exception 'Invalid teletype' using errcode='23514'; end if;
 if v->>'weightUnit' not in ('KG','LB') or v->>'volumeUnit' not in ('m3','ft3') or v->>'weightMethod' not in ('BASIC','DRY_OPERATING') then raise exception 'Invalid operating preferences' using errcode='23514'; end if;
 perform pg_advisory_xact_lock(hashtextextended('carrier-details:'||p_iata,0));
 perform 1 from "Basic_Carrier_Record"."Carrier_Contact_Data" where "Carrier_IATA"=p_iata for update;
 contact_exists:=found;
 perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
 basic_exists:=found;
 current_snapshot := "Basic_Carrier_Record".get_carrier_details(p_iata);
 if p_revision is null or p_revision is distinct from current_snapshot->>'revision' then raise exception 'Carrier details changed' using errcode='40001'; end if;
'''
contact={'Address_Line_1':'address1','Address_Line_2':'address2','Address_Line_3':'address3','City':'city','State_or_Province':'state','Country':'country','Telephone_Number':'telephone','Email_Address':'email','TELETYPE_Address':'teletype'}
values={col:(f"v->>'{key}'" if key in ['address1','city','country'] else f"nullif(v->>'{key}','')") for col,key in contact.items()}
s+=' if contact_exists then\n update "Basic_Carrier_Record"."Carrier_Contact_Data" set '+','.join(f'"{c}"={v}' for c,v in values.items())+' where "Carrier_IATA"=p_iata;\n else\n insert into "Basic_Carrier_Record"."Carrier_Contact_Data" ("Carrier_IATA",'+','.join(f'"{c}"' for c in values)+') values (p_iata,'+','.join(values.values())+');\n end if;\n'
basic={'Carrier_Unit_Weight_KG':"(v->>'weightUnit'='KG')",'Carrier_Unit_Weight_LB':"(v->>'weightUnit'='LB')",'Carrier_Unit_Volume_m3':"(v->>'volumeUnit'='m3')",'Carrier_Unit_Volume_ft3':"(v->>'volumeUnit'='ft3')",'Carrier_Basic_Weight':"(v->>'weightMethod'='BASIC')",'Carrier_Dry_Operating_Weight':"(v->>'weightMethod'='DRY_OPERATING')"}
s+=' if basic_exists then\n update "Basic_Carrier_Record"."Basic_Carrier_Data" set '+','.join(f'"{c}"={v}' for c,v in basic.items())+' where "Carrier_IATA"=p_iata;\n else\n insert into "Basic_Carrier_Record"."Basic_Carrier_Data" ("Carrier_IATA",'+','.join(f'"{c}"' for c in basic)+') values (p_iata,'+','.join(basic.values())+');\n end if;\n'
s+=''' return "Basic_Carrier_Record".get_carrier_details(p_iata);
exception when unique_violation then raise exception 'Carrier details changed' using errcode='40001';
end $$;
revoke all on function "Basic_Carrier_Record".save_carrier_details(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_details(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
'''
Path('database/carrier-details.sql').write_text(s)
