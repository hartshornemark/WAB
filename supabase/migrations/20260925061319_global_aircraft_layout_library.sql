begin;
create table "Basic_Carrier_Record"."Aircraft_Layout_Versions" (
 id uuid primary key default gen_random_uuid(),
 aircraft_type text not null, aircraft_subtype text not null,
 version integer not null check(version>0),
 bucket text not null default 'aircraft-layouts' check(bucket='aircraft-layouts'),
 object_path text not null unique,
 sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 byte_size integer not null check(byte_size>0 and byte_size<=2000000),
 nose_arm_m numeric(14,6) not null,
 datum_description text not null, datum_source text not null, source_drawing text not null,
 calibration jsonb not null check(jsonb_typeof(calibration)='object'),
 created_at timestamptz not null default now(), created_by uuid default auth.uid(),
 unique(aircraft_type,aircraft_subtype,version), unique(id,aircraft_type,aircraft_subtype),
 foreign key(aircraft_type,aircraft_subtype) references "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"("Aircraft_Type_IATA","Aircraft_Series_Subtype"),
 check(object_path=aircraft_type||'/'||aircraft_subtype||'/'||sha256||'.svg'),
 check(calibration->>'typeCode'=aircraft_type and calibration->>'subtype'=aircraft_subtype),
 check(not calibration ? 'asset')
);
create table "Basic_Carrier_Record"."Aircraft_Layout_Active" (
 aircraft_type text not null, aircraft_subtype text not null,
 version_id uuid not null,
 activated_at timestamptz not null default now(), activated_by uuid default auth.uid(),
 primary key(aircraft_type,aircraft_subtype),
 foreign key(version_id,aircraft_type,aircraft_subtype) references "Basic_Carrier_Record"."Aircraft_Layout_Versions"(id,aircraft_type,aircraft_subtype)
);
comment on column "Basic_Carrier_Record"."Aircraft_Layout_Versions".nose_arm_m is 'Physical nose balance arm from datum; master default. Carrier C4 may override for seat maps.';
comment on column "Basic_Carrier_Record"."Aircraft_Layout_Versions".calibration is 'Paired SVG coordinates: noseArm is legacy hold-coordinate origin, NOT necessarily physical nose arm. tailX is nose X (nose at right); span/length is drawing units per metre. Includes image frame, centreline, hold offsets/default boundaries. Do not edit independently of SVG version.';
alter table "Basic_Carrier_Record"."Aircraft_Layout_Versions" enable row level security;
alter table "Basic_Carrier_Record"."Aircraft_Layout_Active" enable row level security;
create function private.can_view_aircraft_layout(p_type text,p_subtype text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.has_global_permission('AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT') or exists(
 select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Aircraft_Type_IATA"=p_type and a."Aircraft_Series_Subtype"=p_subtype and private.has_carrier_permission(a."Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')));
$$;
revoke all on function private.can_view_aircraft_layout(text,text) from public,anon;
grant execute on function private.can_view_aircraft_layout(text,text) to authenticated;
create policy layout_versions_read on "Basic_Carrier_Record"."Aircraft_Layout_Versions" for select to authenticated using(private.can_view_aircraft_layout(aircraft_type,aircraft_subtype));
create policy layout_active_read on "Basic_Carrier_Record"."Aircraft_Layout_Active" for select to authenticated using(private.can_view_aircraft_layout(aircraft_type,aircraft_subtype));
revoke all on "Basic_Carrier_Record"."Aircraft_Layout_Versions","Basic_Carrier_Record"."Aircraft_Layout_Active" from anon,authenticated;
grant select on "Basic_Carrier_Record"."Aircraft_Layout_Versions","Basic_Carrier_Record"."Aircraft_Layout_Active" to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('aircraft-layouts','aircraft-layouts',false,2000000,array['image/svg+xml']);
create policy aircraft_layout_object_read on storage.objects for select to authenticated using(bucket_id='aircraft-layouts' and exists(select 1 from "Basic_Carrier_Record"."Aircraft_Layout_Versions" v where v.object_path=name));
create policy aircraft_layout_object_insert on storage.objects for insert to authenticated with check(bucket_id='aircraft-layouts' and (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) and exists(select 1 from "Basic_Carrier_Record"."Aircraft_Layout_Versions" v where v.object_path=name));
-- Immutable objects: no UPDATE or DELETE policy. Publish a new version instead.
create function "Basic_Carrier_Record".aircraft_layout_library() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.has_global_permission('AIRCRAFT_CONFIG_EDIT') then raise exception 'Administrator access required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object('active',a.version_id=v.id) order by v.aircraft_type,v.version) from "Basic_Carrier_Record"."Aircraft_Layout_Versions" v left join "Basic_Carrier_Record"."Aircraft_Layout_Active" a using(aircraft_type,aircraft_subtype)),'[]');
end;$$;
create function "Basic_Carrier_Record".get_aircraft_layout(p_iata text,p_type text,p_subtype text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not(private.has_global_permission('AIRCRAFT_CONFIG_VIEW') or private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW')) then raise exception 'Access denied' using errcode='42501'; end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype) then raise exception 'Aircraft not available'; end if;
 return (select to_jsonb(v) from "Basic_Carrier_Record"."Aircraft_Layout_Active" a join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id where a.aircraft_type=p_type and a.aircraft_subtype=p_subtype);
end;$$;
create function "Basic_Carrier_Record".activate_aircraft_layout(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare v "Basic_Carrier_Record"."Aircraft_Layout_Versions";
begin
 if auth.uid() is null or not private.has_global_permission('AIRCRAFT_CONFIG_EDIT') then raise exception 'Administrator access required' using errcode='42501'; end if;
 select * into strict v from "Basic_Carrier_Record"."Aircraft_Layout_Versions" where id=p_id;
 if not exists(select 1 from storage.objects where bucket_id=v.bucket and name=v.object_path and (metadata->>'size')::bigint=v.byte_size and metadata->>'mimetype'='image/svg+xml') then raise exception 'Upload and verify the paired SVG before activation'; end if;
 insert into "Basic_Carrier_Record"."Aircraft_Layout_Active"(aircraft_type,aircraft_subtype,version_id) values(v.aircraft_type,v.aircraft_subtype,v.id)
 on conflict(aircraft_type,aircraft_subtype) do update set version_id=excluded.version_id,activated_at=now(),activated_by=auth.uid();
end;$$;
revoke all on function "Basic_Carrier_Record".aircraft_layout_library(),"Basic_Carrier_Record".get_aircraft_layout(text,text,text),"Basic_Carrier_Record".activate_aircraft_layout(uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".aircraft_layout_library(),"Basic_Carrier_Record".get_aircraft_layout(text,text,text),"Basic_Carrier_Record".activate_aircraft_layout(uuid) to authenticated;
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"(aircraft_type,aircraft_subtype,version,object_path,sha256,byte_size,nose_arm_m,datum_description,datum_source,source_drawing,calibration) values('319','100',1,'319/100/1800f1d814208e34c17d7ad7a91cc4abdd7f18f8251ae91ad8ef6ab1e1cdb4d6.svg','1800f1d814208e34c17d7ad7a91cc4abdd7f18f8251ae91ad8ef6ab1e1cdb4d6',199326,2.540,'Station 0.0 is 2.540 m forward of the airplane nose; balance arms increase aft.','EASA.A.064 Issue 62 (26 June 2026), Datum section for A319','Airbus_A319_WTF.dwg; isolated plan view','{"typeCode": "319", "subtype": "100", "length": 33.84, "noseArm": 2.54, "tailX": 330.3, "span": 192.9, "centreY": 363, "imageFrame": {"x": 102, "y": 327.25, "width": 236, "height": 72}, "cropLeft": 102, "cropRight": 338, "holdY": 352, "holdHeight": 22, "leftDoorY": 347, "rightDoorY": 377, "labelCharWidth": 0.58}'::jsonb);
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"(aircraft_type,aircraft_subtype,version,object_path,sha256,byte_size,nose_arm_m,datum_description,datum_source,source_drawing,calibration) values('320','200',1,'320/200/f5de949b13d92da8bcf889a0644390edde83e33a1ed35146279e51b19e47e0f7.svg','f5de949b13d92da8bcf889a0644390edde83e33a1ed35146279e51b19e47e0f7',260631,2.540,'Station 0.0 is 2.540 m forward of the airplane nose; balance arms increase aft.','EASA.A.064 Issue 62 (26 June 2026), Datum section for A320','Airbus_A320_WTF.dwg; isolated plan view','{"typeCode": "320", "subtype": "200", "length": 37.57, "noseArm": 0, "tailX": 337.8, "span": 214.3, "centreY": 359.5, "imageFrame": {"x": 102, "y": 327.25, "width": 236, "height": 72}, "cropLeft": 102, "cropRight": 338, "holdY": 348.5, "holdHeight": 22, "leftDoorY": 344, "rightDoorY": 374, "labelCharWidth": 0.58, "holdArmOffsets": {"3": -2.735, "4": -2.735, "5": -2.735}, "holdArmDefaults": {"1": {"to": 12.205, "from": 7.255}, "3": {"to": 24.48, "from": 21.412}, "4": {"to": 27.548, "from": 24.48}, "5": {"to": 31.212, "from": 27.548}}}'::jsonb);
commit;
