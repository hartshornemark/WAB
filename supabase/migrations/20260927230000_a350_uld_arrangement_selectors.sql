-- Store aircraft-type ULD display alternatives independently from the
-- immutable, versioned SVG. D3 remains the source of each position's geometry.
create table if not exists "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors" (
  aircraft_type text not null,
  aircraft_subtype text not null,
  hold_id text not null,
  uld_type text not null,
  label text not null,
  options jsonb not null check(jsonb_typeof(options) = 'array' and jsonb_array_length(options) > 0),
  primary key (aircraft_type, aircraft_subtype, hold_id, uld_type),
  foreign key (aircraft_type, aircraft_subtype)
    references "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"("Aircraft_Type_IATA", "Aircraft_Series_Subtype")
);

alter table "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors" enable row level security;
revoke all on "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors" from anon, authenticated;

insert into "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors"
  (aircraft_type, aircraft_subtype, hold_id, uld_type, label, options)
values ('359', '900', 'FWD', 'LD8', 'FWD HOLD ARRANGEMENT', jsonb_build_array(
  jsonb_build_object('id','11P_PAG','label','88″ PALLET AT 11P','referencePositionId','11P','referenceUldCode','PAG','excludedPositionIds',jsonb_build_array('11','12','14')),
  jsonb_build_object('id','11P_PMC','label','96″ PALLET AT 11P','referencePositionId','11P','referenceUldCode','PMC','excludedPositionIds',jsonb_build_array('11','12','13'))
))
on conflict (aircraft_type, aircraft_subtype, hold_id, uld_type) do update
set label = excluded.label, options = excluded.options;

create or replace function "Basic_Carrier_Record".get_aircraft_layout(p_iata text, p_type text, p_subtype text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null or not(private.has_global_permission('AIRCRAFT_CONFIG_VIEW') or private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW')) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype) then
    raise exception 'Aircraft not available';
  end if;
  select to_jsonb(v) || jsonb_build_object(
    'calibration', v.calibration || case when count(selector.*) = 0 then '{}'::jsonb else jsonb_build_object(
      'uldArrangementSelectors', jsonb_agg(jsonb_build_object(
        'holdId',selector.hold_id,'uldType',selector.uld_type,'label',selector.label,'options',selector.options
      ) order by selector.hold_id,selector.uld_type)
    ) end
  ) into result
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" active
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=active.version_id
  left join "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors" selector
    on selector.aircraft_type=active.aircraft_type and selector.aircraft_subtype=active.aircraft_subtype
  where active.aircraft_type=p_type and active.aircraft_subtype=p_subtype
  group by v.id;
  return result;
end;$$;
