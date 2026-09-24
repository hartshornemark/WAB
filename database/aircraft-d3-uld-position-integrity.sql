-- AHM565 D3: identify every ULD position by aircraft, hold and configuration.
-- The table is currently empty, so the new required identifiers preserve all
-- existing data while preventing incomplete D3 rows from being introduced.

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  add column "Hold_Name_ID" varchar(1) not null,
  add column "ULD_Configuration_Code" varchar(20) not null default 'DEFAULT',
  add column "ULD_Position_Colour" varchar(7);

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  alter column "Carrier_IATA" type varchar(2),
  alter column "Aircraft_Type_IATA" type varchar(3),
  alter column "Aircraft_Series_Subtype" type varchar(4),
  alter column "ULD_Group_ID" type varchar(20);

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  rename column "ULD_Position_Name" to "ULD_Position_ID";

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  alter column "ULD_Position_ID" type varchar(3);

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  add constraint "Carrier_ULD_Positions_Hold_fkey"
    foreign key (
      "Carrier_IATA",
      "Aircraft_Type_IATA",
      "Hold_Name_ID",
      "Aircraft_Series_Subtype"
    )
    references "Basic_Carrier_Record"."Aircraft_Holds" (
      "Carrier_IATA",
      "Aircraft_Type_IATA",
      "Hold_Name_ID",
      "Aircraft_Series_Subtype"
    )
    on update cascade
    on delete restrict,

  add constraint "Carrier_ULD_Positions_Carrier_check"
    check ("Carrier_IATA" ~ '^[A-Z0-9]{2}$'),
  add constraint "Carrier_ULD_Positions_Aircraft_Type_check"
    check ("Aircraft_Type_IATA" ~ '^[A-Z0-9]{3}$'),
  add constraint "Carrier_ULD_Positions_Subtype_check"
    check (
      char_length(btrim("Aircraft_Series_Subtype")) between 1 and 4
      and "Aircraft_Series_Subtype" = btrim("Aircraft_Series_Subtype")
    ),
  add constraint "Carrier_ULD_Positions_Hold_check"
    check ("Hold_Name_ID" ~ '^[A-Z0-9]$'),
  add constraint "Carrier_ULD_Positions_Configuration_check"
    check (
      char_length(btrim("ULD_Configuration_Code")) between 1 and 20
      and "ULD_Configuration_Code" = btrim("ULD_Configuration_Code")
    ),
  add constraint "Carrier_ULD_Positions_Group_check"
    check (
      "ULD_Group_ID" is null
      or (
        char_length(btrim("ULD_Group_ID")) between 1 and 20
        and "ULD_Group_ID" = btrim("ULD_Group_ID")
      )
    ),
  add constraint "Carrier_ULD_Positions_ID_check"
    check (
      "ULD_Position_ID" ~ '^[A-Z0-9]{1,3}$'
    ),
  add constraint "Carrier_ULD_Positions_Max_Weight_check"
    check ("ULD_Position_Max_Weight" > 0),
  add constraint "Carrier_ULD_Positions_Volume_check"
    check ("ULD_Position_Volume" is null or "ULD_Position_Volume" > 0),
  add constraint "Carrier_ULD_Positions_Lateral_Arm_check"
    check (
      (
        "Lateral_Arm_From" is null
        and "Lateral_Arm_Centroid" is null
        and "Lateral_Arm_To" is null
      )
      or (
        "Lateral_Arm_From" is not null
        and "Lateral_Arm_Centroid" is not null
        and "Lateral_Arm_To" is not null
        and abs("Lateral_Arm_From") <= 1000000
        and abs("Lateral_Arm_Centroid") <= 1000000
        and abs("Lateral_Arm_To") <= 1000000
        and "Lateral_Arm_From" <= "Lateral_Arm_Centroid"
        and "Lateral_Arm_Centroid" <= "Lateral_Arm_To"
      )
    ),
  add constraint "Carrier_ULD_Positions_Balance_Arm_check"
    check (
      abs("Balance_Arm_Centroid") <= 1000000
      and (
        (
          "Balance_Arm_From" is null
          and "Balance_Arm_To" is null
        )
        or (
          "Balance_Arm_From" is not null
          and "Balance_Arm_To" is not null
          and abs("Balance_Arm_From") <= 1000000
          and abs("Balance_Arm_To") <= 1000000
          and "Balance_Arm_From" <= "Balance_Arm_Centroid"
          and "Balance_Arm_Centroid" <= "Balance_Arm_To"
        )
      )
    ),
  add constraint "Carrier_ULD_Positions_Index_check"
    check (
      "Index_Per_Weight_Unit" is null
      or abs("Index_Per_Weight_Unit") <= 1000000000
    ),
  add constraint "Carrier_ULD_Positions_Colour_check"
    check (
      "ULD_Position_Colour" is null
      or "ULD_Position_Colour" ~ '^#[0-9A-Fa-f]{6}$'
    ),
  add constraint "Carrier_ULD_Positions_Natural_key"
    unique (
      "Carrier_IATA",
      "Aircraft_Type_IATA",
      "Aircraft_Series_Subtype",
      "Hold_Name_ID",
      "ULD_Configuration_Code",
      "ULD_Position_ID"
    );

create index "Carrier_ULD_Positions_Hold_idx"
  on "Basic_Carrier_Record"."Carrier_ULD_Positions" (
    "Carrier_IATA",
    "Aircraft_Type_IATA",
    "Hold_Name_ID",
    "Aircraft_Series_Subtype",
    "ULD_Configuration_Code"
  );

comment on column "Basic_Carrier_Record"."Carrier_ULD_Positions"."ULD_Configuration_Code"
  is 'Identifies an alternative ULD loading configuration within an aircraft hold.';

comment on column "Basic_Carrier_Record"."Carrier_ULD_Positions"."ULD_Position_Colour"
  is 'Optional AHM565 D3 display colour. NULL means the colour checkbox is unchecked; otherwise use #RRGGBB.';
