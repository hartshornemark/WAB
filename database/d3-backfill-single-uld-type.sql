begin;
with single_type as (
  select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",min("ULD_Type") as "ULD_Type"
  from "Basic_Carrier_Record"."Carrier_ULD_Specifications"
  group by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"
  having count(distinct "ULD_Type")=1
)
update "Basic_Carrier_Record"."Carrier_ULD_Positions" p
set "ULD_Type"=s."ULD_Type"
from single_type s
where p."Carrier_IATA"=s."Carrier_IATA"
  and p."Aircraft_Type_IATA"=s."Aircraft_Type_IATA"
  and p."Aircraft_Series_Subtype"=s."Aircraft_Series_Subtype"
  and p."ULD_Row_Type"='POSITION'
  and p."ULD_Type" is null;
commit;
