begin;

-- Before explicit review states were introduced, a null D6 applicability value
-- meant that the section had been reviewed and left inactive. Preserve that
-- meaning for aircraft which already have a saved D6 settings record.
update "Basic_Carrier_Record"."Carrier_Aircraft_D6_Settings"
set
  "Potable_Water_Applicable" = coalesce("Potable_Water_Applicable", false),
  "Galley_Other_Applicable" = coalesce("Galley_Other_Applicable", false),
  "Updated_At" = now()
where "Potable_Water_Applicable" is null
   or "Galley_Other_Applicable" is null;

-- Aircraft already reviewed through the final H1 page necessarily passed D11
-- under the former rules. Record their previous no-section-selected decision
-- explicitly. Aircraft still being configured, such as a newly added type,
-- retain the new unreviewed/incomplete state.
insert into "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" (
  "Carrier_IATA",
  "Aircraft_Type_IATA",
  "Aircraft_Series_Subtype",
  "Combined_Load_Limits_Applicable",
  "Floor_Loading_Limits_Applicable",
  "Asymmetrical_Load_Limits_Applicable",
  "Updated_At"
)
select
  aircraft."Carrier_IATA",
  aircraft."Aircraft_Type_IATA",
  aircraft."Aircraft_Series_Subtype",
  false,
  false,
  false,
  now()
from "Basic_Carrier_Record"."Basic_Aircraft_Data" aircraft
where exists (
  select 1
  from "Basic_Carrier_Record"."Carrier_Aircraft_H1_Settings" h1
  where h1."Carrier_IATA" = aircraft."Carrier_IATA"
    and h1."Aircraft_Type_IATA" = aircraft."Aircraft_Type_IATA"
    and h1."Aircraft_Series_Subtype" = aircraft."Aircraft_Series_Subtype"
)
on conflict ("Carrier_IATA", "Aircraft_Type_IATA", "Aircraft_Series_Subtype")
do nothing;

commit;
