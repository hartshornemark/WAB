-- Model all seven A350-900 forward-hold layouts shown in the carrier source.
-- Position geometry continues to come from the saved D3 rows.
insert into "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors"
  (aircraft_type, aircraft_subtype, hold_id, uld_type, label, options)
values
  ('359','900','FWD','LD3','FWD HOLD VERSION',jsonb_build_array(
    jsonb_build_object('id','FWD_V1','label','VERSION 1','includedPositionIds',jsonb_build_array('11L','11R','12L','12R','14L','14R','15L','15R','21L','21R','22L','22R','23L','23R','24L','24R','25L','25R','26L','26R')),
    jsonb_build_object('id','FWD_V2','label','VERSION 2','includedPositionIds',jsonb_build_array('11L','11R','13L','13R','15L','15R','21L','21R','22L','22R','23L','23R','24L','24R','25L','25R','26L','26R'))
  )),
  ('359','900','FWD','LD8','FWD HOLD VERSION',jsonb_build_array(
    jsonb_build_object('id','FWD_V3','label','VERSION 3','includedPositionIds',jsonb_build_array('11','12','14','15','21','22','23','24','25','26')),
    jsonb_build_object('id','FWD_V4','label','VERSION 4','includedPositionIds',jsonb_build_array('11','13','15','21','22','23','24','25','26'))
  )),
  ('359','900','FWD','LD7','FWD HOLD VERSION',jsonb_build_array(
    jsonb_build_object('id','FWD_V5','label','VERSION 5','uldCode','PAG','includedPositionIds',jsonb_build_array('11P','12P','21P','22P','23P','24P')),
    jsonb_build_object('id','FWD_V6','label','VERSION 6','uldCode','PAG','includedPositionIds',jsonb_build_array('11P','13P','21P','22P','23P','24P')),
    jsonb_build_object('id','FWD_V7','label','VERSION 7','uldCode','PMC','includedPositionIds',jsonb_build_array('11P','13P','21P','22P','23P','24P'))
  ))
on conflict (aircraft_type, aircraft_subtype, hold_id, uld_type) do update
set label=excluded.label, options=excluded.options;
