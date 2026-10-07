-- The A350 D2 model now stores forward and aft hold sections as FLF/FLA and
-- ALF/ALA. Publish an immutable calibration that moves both split families
-- inward on the drawing, keeping ALB/Hold 5 attached to the aft family.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
    (aircraft_type,aircraft_subtype,version,bucket,object_path,sha256,byte_size,
     nose_arm_m,datum_description,datum_source,source_drawing,calibration)
  select aircraft_type,aircraft_subtype,8,bucket,'359/900/82f539486093c2fab3a0ffc93fe051a1c3b95ede76d80a9fc4f437ea35b9ef76.svg','82f539486093c2fab3a0ffc93fe051a1c3b95ede76d80a9fc4f437ea35b9ef76',1129633,
    nose_arm_m,datum_description,
    'Carrier-reviewed A350-900 drawing alignment: split forward and aft ULD hold families moved inward, with ALB retained in the aft family, while retaining the confirmed 1.84 m datum, 1 October 2026.',
    source_drawing,
    jsonb_set(
      jsonb_set(calibration,'{holdArmOffsets}','{"FWD":3.4,"AFT":-3.4,"ALB":-3.4}'::jsonb,true),
      '{diagramCaption}',
      to_jsonb('Airbus A350-900 outline derived from the supplied Airbus plan drawing. Split FWD and AFT hold families use inward drawing corrections; Hold 5 follows the taper of the aft fuselage.'::text),
      true)
  from "Basic_Carrier_Record"."Aircraft_Layout_Versions" source
  where source.aircraft_type='359' and source.aircraft_subtype='900' and source.version=7
  on conflict (aircraft_type,aircraft_subtype,version) do update
    set calibration=excluded.calibration,datum_source=excluded.datum_source;

update "Basic_Carrier_Record"."Aircraft_Layout_Active" active
set version_id=version.id,activated_at=now(),activated_by=null
from "Basic_Carrier_Record"."Aircraft_Layout_Versions" version
where active.aircraft_type='359' and active.aircraft_subtype='900'
  and version.aircraft_type='359' and version.aircraft_subtype='900' and version.version=8;
