begin;

update "Basic_Carrier_Record"."Aircraft_Holds" as h
set
  "Hold_BA_Start" = positions.hold_start,
  "Hold_BA_End" = positions.hold_end
from (values
  ('1'::text,  7.255::double precision, 12.205::double precision),
  ('3'::text, 21.412::double precision, 24.480::double precision),
  ('4'::text, 24.480::double precision, 27.548::double precision),
  ('5'::text, 27.548::double precision, 31.212::double precision)
) as positions(hold_id, hold_start, hold_end)
where h."Carrier_IATA" = 'AB'
  and h."Aircraft_Type_IATA" = '320'
  and h."Aircraft_Series_Subtype" = '200'
  and btrim(h."Hold_Name_ID") = positions.hold_id;

do $$
begin
  if (
    select count(*)
    from "Basic_Carrier_Record"."Aircraft_Holds"
    where "Carrier_IATA" = 'AB'
      and "Aircraft_Type_IATA" = '320'
      and "Aircraft_Series_Subtype" = '200'
      and btrim("Hold_Name_ID") in ('1','3','4','5')
      and "Hold_BA_Start" is not null
      and "Hold_BA_End" is not null
  ) <> 4 then
    raise exception 'Expected four AB 320-200 hold position rows';
  end if;
end $$;

commit;
