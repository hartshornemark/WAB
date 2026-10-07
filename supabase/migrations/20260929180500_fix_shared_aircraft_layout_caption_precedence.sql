-- Shared airframe profiles reuse a published layout whose calibration column is
-- stored as text. Cast it before using JSONB operators or concatenation.
create or replace function "Basic_Carrier_Record".get_aircraft_layout(
  p_iata text,p_type text,p_subtype text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null or not (
    private.has_global_permission('AIRCRAFT_CONFIG_VIEW')
    or private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW')
  ) then raise exception 'Access denied' using errcode='42501'; end if;
  if not exists (
    select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type
      and "Aircraft_Series_Subtype"=p_subtype
  ) then raise exception 'Aircraft not available'; end if;
  select to_jsonb(v) into result
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" a
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id
  where a.aircraft_type=p_type and a.aircraft_subtype=p_subtype;
  if result is not null then return result; end if;
  return (
    select to_jsonb(layout_version) || jsonb_build_object(
      'aircraft_type',p_type,'aircraft_subtype',p_subtype,
      'asset_aircraft_type',layout_version.aircraft_type,
      'asset_aircraft_subtype',layout_version.aircraft_subtype,
      'geometry_family_code',assignment.family_code,
      'geometry_profile_code',assignment.profile_code,
      'calibration',layout_version.calibration::jsonb || jsonb_build_object(
        'typeCode',p_type,'subtype',p_subtype,
        'diagramCaption','Shared '||family.model||' '||profile.profile_name||' airframe outline. '
          ||((layout_version.calibration::jsonb)->>'diagramCaption')
      )
    )
    from "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments" assignment
    join "Basic_Carrier_Record"."Airframe_Geometry_Families" family
      on family.family_code=assignment.family_code
    join "Basic_Carrier_Record"."Airframe_Geometry_Active" active
      on active.family_code=assignment.family_code
    join "Basic_Carrier_Record"."Airframe_Geometry_Versions" geometry_version
      on geometry_version.id=active.version_id
    join "Basic_Carrier_Record"."Airframe_Geometry_Profiles" profile
      on profile.geometry_version_id=geometry_version.id
      and profile.profile_code=assignment.profile_code
    join "Basic_Carrier_Record"."Aircraft_Layout_Versions" layout_version
      on layout_version.id=geometry_version.source_layout_version_id
    where assignment.aircraft_type=p_type and assignment.aircraft_subtype=p_subtype
  );
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_layout(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_layout(text,text,text) to authenticated;
