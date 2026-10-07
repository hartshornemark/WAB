begin;

create table "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Overlay_Kind" text not null check ("Overlay_Kind" in ('SEAT','HOLD')),
  "Offset_X" double precision not null check (abs("Offset_X") <= 5000),
  "Locked" boolean not null default true,
  "Updated_At" timestamptz not null default now(),
  "Updated_By" uuid not null default auth.uid(),
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Overlay_Kind"),
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data" ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update restrict on delete cascade
);

alter table "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations" enable row level security;
revoke all on table "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations" from public,anon,authenticated;
grant select,insert,update,delete on table "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations" to authenticated;
create policy overlay_calibration_select on "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations"
 for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy overlay_calibration_insert on "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations"
 for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy overlay_calibration_update on "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations"
 for update to authenticated
 using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
 with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy overlay_calibration_delete on "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations"
 for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

create function "Basic_Carrier_Record".get_aircraft_overlay_calibration(p_iata text,p_type_code text,p_subtype text,p_overlay_kind text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));kind text:=upper(btrim(p_overlay_kind));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');saved record;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if kind not in ('SEAT','HOLD') then raise exception 'Invalid overlay kind' using errcode='22023';end if;
 select "Offset_X","Locked","Updated_At" into saved from "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations"
 where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Overlay_Kind"=kind;
 return jsonb_build_object('canEdit',can_edit,'offsetX',saved."Offset_X",'locked',coalesce(saved."Locked",false),'updatedAt',saved."Updated_At");
end $$;

create function "Basic_Carrier_Record".save_aircraft_overlay_calibration(p_iata text,p_type_code text,p_subtype text,p_overlay_kind text,p_offset_x double precision)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));kind text:=upper(btrim(p_overlay_kind));
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if kind not in ('SEAT','HOLD') or p_offset_x is null or abs(p_offset_x)>5000 then raise exception 'Invalid overlay calibration' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Aircraft_Overlay_Calibrations"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Overlay_Kind","Offset_X","Locked","Updated_At","Updated_By")
 values(p_iata,tc,st,kind,p_offset_x,true,now(),auth.uid())
 on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Overlay_Kind") do update set
  "Offset_X"=excluded."Offset_X","Locked"=true,"Updated_At"=now(),"Updated_By"=auth.uid();
 return "Basic_Carrier_Record".get_aircraft_overlay_calibration(p_iata,tc,st,kind);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_overlay_calibration(text,text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_overlay_calibration(text,text,text,text,double precision) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_overlay_calibration(text,text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_overlay_calibration(text,text,text,text,double precision) to authenticated;

commit;
