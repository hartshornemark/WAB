begin;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".save_carrier_contacts(p_iata text, p_revision text, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare current_snapshot jsonb; v jsonb := '{}'::jsonb; k text; value text; contact_exists boolean;
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
 perform pg_advisory_xact_lock(hashtextextended('carrier-details:'||p_iata,0));
 perform 1 from "Basic_Carrier_Record"."Carrier_Contact_Data" where "Carrier_IATA"=p_iata for update;
 contact_exists:=found;
 current_snapshot := "Basic_Carrier_Record".get_carrier_details(p_iata);
 if p_revision is null or p_revision is distinct from current_snapshot->>'revision' then raise exception 'Carrier details changed' using errcode='40001'; end if;
 if contact_exists then
 update "Basic_Carrier_Record"."Carrier_Contact_Data" set "Address_Line_1"=v->>'address1',"Address_Line_2"=nullif(v->>'address2',''),"Address_Line_3"=nullif(v->>'address3',''),"City"=v->>'city',"State_or_Province"=nullif(v->>'state',''),"Country"=v->>'country',"Telephone_Number"=nullif(v->>'telephone',''),"Email_Address"=nullif(v->>'email',''),"TELETYPE_Address"=nullif(v->>'teletype','') where "Carrier_IATA"=p_iata;
 else
 insert into "Basic_Carrier_Record"."Carrier_Contact_Data" ("Carrier_IATA","Address_Line_1","Address_Line_2","Address_Line_3","City","State_or_Province","Country","Telephone_Number","Email_Address","TELETYPE_Address") values (p_iata,v->>'address1',nullif(v->>'address2',''),nullif(v->>'address3',''),v->>'city',nullif(v->>'state',''),v->>'country',nullif(v->>'telephone',''),nullif(v->>'email',''),nullif(v->>'teletype',''));
 end if;
 return "Basic_Carrier_Record".get_carrier_details(p_iata);
exception when unique_violation then raise exception 'Carrier details changed' using errcode='40001';
end $function$
;
revoke all on function "Basic_Carrier_Record".save_carrier_contacts(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_contacts(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
