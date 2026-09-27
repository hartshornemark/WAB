-- Keep the detailed dimensions and loading limits in the source/master data.
-- The overlay selector only needs the arrangement version number.
update "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors"
set options = (
  select jsonb_agg(
    jsonb_set(
      option,
      '{label}',
      to_jsonb('VERSION ' || substring(option->>'id' from '[0-9]+'))
    )
    order by ordinal
  )
  from jsonb_array_elements(options) with ordinality as item(option, ordinal)
)
where aircraft_type = '359'
  and aircraft_subtype = '900'
  and hold_id = 'FWD'
  and uld_type in ('LD3', 'LD8', 'LD7');
