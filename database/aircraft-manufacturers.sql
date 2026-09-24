begin;

-- A manufacturer is global reference data. Use its UUID as the stable identity;
-- retain the existing table name to avoid breaking any external database users.
alter table "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  drop constraint "MASTER_Aircraft_Manufactures_pkey";

alter table "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  add constraint "MASTER_Aircraft_Manufactures_pkey"
  primary key ("Manufacturer_UUID");

alter table "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  add constraint "MASTER_Aircraft_Manufactures_Name_Not_Blank"
  check (
    "Manufacturer_Name" = btrim("Manufacturer_Name")
    and char_length("Manufacturer_Name") between 1 and 64
  );

create unique index "MASTER_Aircraft_Manufactures_Name_Case_Insensitive_Key"
  on "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  (lower("Manufacturer_Name"));

-- Existing aircraft type/subtype records remain valid until their global
-- manufacturer has been assigned.
alter table "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
  add column "Manufacturer_UUID" uuid null;

alter table "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
  add constraint "MASTER_Aircraft_Type_IATA_Manufacturer_UUID_fkey"
  foreign key ("Manufacturer_UUID")
  references "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" ("Manufacturer_UUID")
  on update restrict
  on delete restrict;

create index "MASTER_Aircraft_Type_IATA_Manufacturer_UUID_idx"
  on "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA" ("Manufacturer_UUID")
  where "Manufacturer_UUID" is not null;

-- Match the established security model for other global MASTER tables.
alter table "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  enable row level security;

revoke all on table "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  from anon, authenticated;

grant select, insert, update, delete
  on table "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  to authenticated;

create policy "perm_master_select"
  on "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  for select
  to authenticated
  using ((select private.has_any_permission('MASTER_DATA_VIEW')));

create policy "perm_master_insert"
  on "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  for insert
  to authenticated
  with check ((select private.has_global_permission('MASTER_DATA_CREATE')));

create policy "perm_master_update"
  on "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  for update
  to authenticated
  using ((select private.has_global_permission('MASTER_DATA_EDIT')))
  with check ((select private.has_global_permission('MASTER_DATA_EDIT')));

create policy "perm_master_delete"
  on "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
  for delete
  to authenticated
  using ((select private.has_global_permission('MASTER_DATA_DELETE')));

commit;
