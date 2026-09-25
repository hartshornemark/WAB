-- Publish master datum and paired SVG calibration together. Existing carrier C4 overrides remain intact.
begin;
create or replace function "Basic_Carrier_Record".activate_aircraft_layout(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v "Basic_Carrier_Record"."Aircraft_Layout_Versions";
begin
 if auth.uid() is null or not private.has_global_permission('AIRCRAFT_CONFIG_EDIT') then raise exception 'Administrator access required' using errcode='42501'; end if;
 select * into strict v from "Basic_Carrier_Record"."Aircraft_Layout_Versions" where id=p_id;
 if not exists(select 1 from storage.objects where bucket_id=v.bucket and name=v.object_path and (metadata->>'size')::bigint=v.byte_size and metadata->>'mimetype'='image/svg+xml') then raise exception 'Upload and verify the paired SVG before activation'; end if;
 update "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA" set "Balance_Arm_At_Nose"=v.nose_arm_m where "Aircraft_Type_IATA"=v.aircraft_type and "Aircraft_Series_Subtype"=v.aircraft_subtype;
 insert into "Basic_Carrier_Record"."Aircraft_Layout_Active"(aircraft_type,aircraft_subtype,version_id) values(v.aircraft_type,v.aircraft_subtype,v.id)
 on conflict(aircraft_type,aircraft_subtype) do update set version_id=excluded.version_id,activated_at=now(),activated_by=auth.uid();
end;$$;
commit;
