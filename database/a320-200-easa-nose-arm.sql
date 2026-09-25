-- EASA.A.064, Issue 62, Section 1 A320 Series, item 15 (page 48).
-- https://www.easa.europa.eu/en/downloads/16507/en#page=48
-- Station zero is 2.540 m forward of the nose: nose balance arm = +2.540 m.
begin;
update "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
set "Balance_Arm_At_Nose" = 2.540
where "Aircraft_Type_IATA" = '320' and "Aircraft_Series_Subtype" = '200';
update "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
set "Balance_Arm_At_Nose" = 2.540
where "Aircraft_Type_IATA" = '320' and "Aircraft_Series_Subtype" = '200';
commit;

