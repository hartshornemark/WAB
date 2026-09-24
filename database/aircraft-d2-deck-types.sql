begin;

update "Basic_Carrier_Record"."MASTER_Deck_Types"
set
  "Deck_Code" = upper(btrim("Deck_Code")),
  "Deck_Display_Name" = btrim("Deck_Display_Name"),
  "Deck_Category" = case lower(btrim("Deck_Category"))
    when 'passenger' then 'Passenger'
    when 'deadload' then 'Deadload'
    else btrim("Deck_Category")
  end;

update "Basic_Carrier_Record"."Aircraft_Holds"
set "Hold_Deck_Location" = upper(btrim("Hold_Deck_Location"));

alter table "Basic_Carrier_Record"."MASTER_Deck_Types"
  drop constraint "MASTER_Deck_Types_pkey",
  alter column "Deck_Code" type varchar(5),
  alter column "Deck_Display_Name" type varchar(40),
  alter column "Deck_Display_Name" set not null,
  alter column "Deck_Category" type varchar(12),
  alter column "Deck_Category" set not null,
  add constraint "MASTER_Deck_Types_pkey" primary key ("Deck_UUID"),
  add constraint "MASTER_Deck_Types_Deck_Code_key" unique ("Deck_Code"),
  add constraint "MASTER_Deck_Types_Deck_Code_check"
    check ("Deck_Code" ~ '^[A-Z0-9]{2,5}$'),
  add constraint "MASTER_Deck_Types_Display_Name_check"
    check (
      "Deck_Display_Name" = btrim("Deck_Display_Name")
      and char_length("Deck_Display_Name") between 2 and 40
    ),
  add constraint "MASTER_Deck_Types_Category_check"
    check ("Deck_Category" in ('Passenger', 'Deadload'));

create unique index "MASTER_Deck_Types_Display_Name_ci_key"
  on "Basic_Carrier_Record"."MASTER_Deck_Types" (lower("Deck_Display_Name"));

alter table "Basic_Carrier_Record"."Aircraft_Holds"
  alter column "Hold_Deck_Location" type varchar(5),
  add constraint "Aircraft_Holds_Deck_Location_check"
    check ("Hold_Deck_Location" ~ '^[A-Z0-9]{2,5}$'),
  add constraint "Aircraft_Holds_Deck_Location_fkey"
    foreign key ("Hold_Deck_Location")
    references "Basic_Carrier_Record"."MASTER_Deck_Types" ("Deck_Code")
    on update cascade
    on delete restrict;

commit;

