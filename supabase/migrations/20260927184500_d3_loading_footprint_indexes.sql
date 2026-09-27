create index "Carrier_ULD_Atomic_Bays_Compartment_idx"
  on "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays"
  ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype");

create index "Carrier_ULD_Position_Occupancy_Atomic_idx"
  on "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Atomic_Bay_ID");

create index "Carrier_ULD_Position_Occupancy_Parent_idx"
  on "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy"
  ("ULD_Position_UUID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code");
