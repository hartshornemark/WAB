begin;

create index "Aircraft_Holds_Deck_Location_idx"
  on "Basic_Carrier_Record"."Aircraft_Holds" ("Hold_Deck_Location");

grant select, insert, update, delete
  on table "Basic_Carrier_Record"."MASTER_Deck_Types"
  to authenticated;

create policy "perm_master_select"
  on "Basic_Carrier_Record"."MASTER_Deck_Types"
  for select
  to authenticated
  using ((select private.has_any_permission('MASTER_DATA_VIEW')));

create policy "perm_master_insert"
  on "Basic_Carrier_Record"."MASTER_Deck_Types"
  for insert
  to authenticated
  with check ((select private.has_global_permission('MASTER_DATA_CREATE')));

create policy "perm_master_update"
  on "Basic_Carrier_Record"."MASTER_Deck_Types"
  for update
  to authenticated
  using ((select private.has_global_permission('MASTER_DATA_EDIT')))
  with check ((select private.has_global_permission('MASTER_DATA_EDIT')));

create policy "perm_master_delete"
  on "Basic_Carrier_Record"."MASTER_Deck_Types"
  for delete
  to authenticated
  using ((select private.has_global_permission('MASTER_DATA_DELETE')));

commit;
