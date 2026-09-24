begin;

update "Basic_Carrier_Record"."Aircraft_Holds" as h
set
  "Hold_DOOR_Start" = doors.door_start,
  "Hold_DOOR_End" = doors.door_end,
  "Hold_DOOR_Height" = doors.door_height,
  "Hold_DOOR_Orientation" = 'R'
from (values
  ('1'::text,  7.255::double precision,  9.065::double precision, 1.24::double precision),
  ('3'::text, 21.785::double precision, 23.595::double precision, 1.23::double precision),
  ('4'::text, 21.785::double precision, 23.595::double precision, 1.23::double precision),
  ('5'::text, 25.860::double precision, 26.720::double precision, 0.89::double precision)
) as doors(hold_id, door_start, door_end, door_height)
where h."Carrier_IATA" = 'AB'
  and h."Aircraft_Type_IATA" = '320'
  and h."Aircraft_Series_Subtype" = '200'
  and btrim(h."Hold_Name_ID") = doors.hold_id;

do $$
begin
  if (
    select count(*)
    from "Basic_Carrier_Record"."Aircraft_Holds"
    where "Carrier_IATA" = 'AB'
      and "Aircraft_Type_IATA" = '320'
      and "Aircraft_Series_Subtype" = '200'
      and btrim("Hold_Name_ID") in ('1','3','4','5')
      and "Hold_DOOR_Start" is not null
      and "Hold_DOOR_End" is not null
      and "Hold_DOOR_Height" is not null
      and btrim("Hold_DOOR_Orientation") = 'R'
  ) <> 4 then
    raise exception 'Expected four AB 320-200 hold-to-door assignments';
  end if;
end $$;

commit;
