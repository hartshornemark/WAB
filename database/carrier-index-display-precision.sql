-- Carrier-level ordinary Index display and print precision.
-- Index Per Weight Unit remains fixed at five decimal places.
begin;
alter table "Basic_Carrier_Record"."Basic_Carrier_Data"
  add column if not exists "Carrier_Index_Decimal_Places" smallint not null default 1;
alter table "Basic_Carrier_Record"."Basic_Carrier_Data"
  drop constraint if exists "Basic_Carrier_Data_Index_Decimal_Places_check";
alter table "Basic_Carrier_Record"."Basic_Carrier_Data"
  add constraint "Basic_Carrier_Data_Index_Decimal_Places_check"
  check ("Carrier_Index_Decimal_Places" in (1,2));

create or replace function "Basic_Carrier_Record".get_carrier_details(p_iata text) returns jsonb
language sql stable security invoker set search_path='' as $$
with access as (
 select private.can_edit_carrier_details(p_iata) as edit,
 (select auth.uid()) is not null and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
 and (private.can_edit_carrier_details(p_iata) or private.has_carrier_permission(p_iata,'CARRIER_CONFIG_VIEW')) as view
), rows as (
 select a.*,c.*,b."Carrier_Unit_Weight_KG",b."Carrier_Unit_Weight_LB",b."Carrier_Unit_Volume_m3",b."Carrier_Unit_Volume_ft3",b."Carrier_Basic_Weight",b."Carrier_Dry_Operating_Weight",b."Carrier_Index_Decimal_Places",
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
 'weightMethod',case when "Carrier_Basic_Weight" then 'BASIC' when "Carrier_Dry_Operating_Weight" then 'DRY_OPERATING' else '' end,
 'indexDecimalPlaces',coalesce("Carrier_Index_Decimal_Places",1)::text)) from rows;
$$;
revoke all on function "Basic_Carrier_Record".get_carrier_details(text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_details(text) to authenticated;

create or replace function "Basic_Carrier_Record".save_carrier_details(p_iata text,p_revision text,p_values jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare current_snapshot jsonb; v jsonb := '{}'::jsonb; k text; value text; contact_exists boolean; basic_exists boolean;
begin
 if not private.can_edit_carrier_details(p_iata) then raise exception 'Carrier details access denied' using errcode='42501'; end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Invalid details' using errcode='23514'; end if;
 if exists(select 1 from jsonb_object_keys(p_values) key where key not in ('address1','address2','address3','city','state','country','telephone','email','teletype','weightUnit','volumeUnit','weightMethod','indexDecimalPlaces')) then raise exception 'Unexpected details field' using errcode='23514'; end if;
 foreach k in array array['address1','address2','address3','city','state','country','telephone','email','teletype','weightUnit','volumeUnit','weightMethod','indexDecimalPlaces'] loop
   if jsonb_typeof(p_values->k) is distinct from 'string' then raise exception 'Invalid details field' using errcode='23514'; end if;
   value := btrim(p_values->>k);
   if length(value)>64 or value ~ '[[:cntrl:]]' then raise exception 'Invalid details field' using errcode='23514'; end if;
   v := v || jsonb_build_object(k,value);
 end loop;
 if v->>'address1'='' or v->>'city'='' or v->>'country'='' then raise exception 'Required contact details missing' using errcode='23514'; end if;
 if v->>'email'<>'' and v->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Invalid email' using errcode='23514'; end if;
 if v->>'teletype'<>'' and length(v->>'teletype')<>7 then raise exception 'Invalid teletype' using errcode='23514'; end if;
 if v->>'weightUnit' not in ('KG','LB') or v->>'volumeUnit' not in ('m3','ft3') or v->>'weightMethod' not in ('BASIC','DRY_OPERATING') or v->>'indexDecimalPlaces' not in ('1','2') then raise exception 'Invalid operating preferences' using errcode='23514'; end if;
 perform pg_advisory_xact_lock(hashtextextended('carrier-details:'||p_iata,0));
 perform 1 from "Basic_Carrier_Record"."Carrier_Contact_Data" where "Carrier_IATA"=p_iata for update;
 contact_exists:=found;
 perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
 basic_exists:=found;
 current_snapshot := "Basic_Carrier_Record".get_carrier_details(p_iata);
 if p_revision is null or p_revision is distinct from current_snapshot->>'revision' then raise exception 'Carrier details changed' using errcode='40001'; end if;
 if contact_exists then
 update "Basic_Carrier_Record"."Carrier_Contact_Data" set "Address_Line_1"=v->>'address1',"Address_Line_2"=nullif(v->>'address2',''),"Address_Line_3"=nullif(v->>'address3',''),"City"=v->>'city',"State_or_Province"=nullif(v->>'state',''),"Country"=v->>'country',"Telephone_Number"=nullif(v->>'telephone',''),"Email_Address"=nullif(v->>'email',''),"TELETYPE_Address"=nullif(v->>'teletype','') where "Carrier_IATA"=p_iata;
 else
 insert into "Basic_Carrier_Record"."Carrier_Contact_Data" ("Carrier_IATA","Address_Line_1","Address_Line_2","Address_Line_3","City","State_or_Province","Country","Telephone_Number","Email_Address","TELETYPE_Address") values (p_iata,v->>'address1',nullif(v->>'address2',''),nullif(v->>'address3',''),v->>'city',nullif(v->>'state',''),v->>'country',nullif(v->>'telephone',''),nullif(v->>'email',''),nullif(v->>'teletype',''));
 end if;
 if basic_exists then
 update "Basic_Carrier_Record"."Basic_Carrier_Data" set "Carrier_Unit_Weight_KG"=(v->>'weightUnit'='KG'),"Carrier_Unit_Weight_LB"=(v->>'weightUnit'='LB'),"Carrier_Unit_Volume_m3"=(v->>'volumeUnit'='m3'),"Carrier_Unit_Volume_ft3"=(v->>'volumeUnit'='ft3'),"Carrier_Basic_Weight"=(v->>'weightMethod'='BASIC'),"Carrier_Dry_Operating_Weight"=(v->>'weightMethod'='DRY_OPERATING'),"Carrier_Index_Decimal_Places"=(v->>'indexDecimalPlaces')::smallint where "Carrier_IATA"=p_iata;
 else
 insert into "Basic_Carrier_Record"."Basic_Carrier_Data" ("Carrier_IATA","Carrier_Unit_Weight_KG","Carrier_Unit_Weight_LB","Carrier_Unit_Volume_m3","Carrier_Unit_Volume_ft3","Carrier_Basic_Weight","Carrier_Dry_Operating_Weight","Carrier_Index_Decimal_Places") values (p_iata,(v->>'weightUnit'='KG'),(v->>'weightUnit'='LB'),(v->>'volumeUnit'='m3'),(v->>'volumeUnit'='ft3'),(v->>'weightMethod'='BASIC'),(v->>'weightMethod'='DRY_OPERATING'),(v->>'indexDecimalPlaces')::smallint);
 end if;
 return "Basic_Carrier_Record".get_carrier_details(p_iata);
exception when unique_violation then raise exception 'Carrier details changed' using errcode='40001';
end $$;
revoke all on function "Basic_Carrier_Record".save_carrier_details(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_details(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
