begin;

create table "Basic_Carrier_Record"."Aircraft_Dashboard_Status_Snapshots" (
  "Carrier_IATA" varchar(3) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(20) not null,
  "Overall_Status" text not null check ("Overall_Status" in ('configured','partial','incomplete')),
  "Attention_Pages" jsonb not null default '[]'::jsonb check (jsonb_typeof("Attention_Pages")='array'),
  "Page_Statuses" jsonb not null default '{}'::jsonb check (jsonb_typeof("Page_Statuses")='object'),
  "Page_Progress" jsonb not null default '{}'::jsonb check (jsonb_typeof("Page_Progress")='object'),
  "Calculation_Version" integer not null check ("Calculation_Version">0),
  "Updated_At" timestamptz not null default now(),
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
  constraint "aircraft_dashboard_status_aircraft_fk"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update cascade on delete cascade
);

comment on table "Basic_Carrier_Record"."Aircraft_Dashboard_Status_Snapshots" is
  'Derived, non-authoritative page and overall completion status. Rebuilt from carrier configuration data after saves.';

alter table "Basic_Carrier_Record"."Aircraft_Dashboard_Status_Snapshots" enable row level security;

grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Dashboard_Status_Snapshots" to authenticated;

create policy "perm_aircraft_status_select"
  on "Basic_Carrier_Record"."Aircraft_Dashboard_Status_Snapshots"
  for select to authenticated
  using (
    (select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW'))
    or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW'))
  );

create policy "perm_aircraft_status_insert"
  on "Basic_Carrier_Record"."Aircraft_Dashboard_Status_Snapshots"
  for insert to authenticated
  with check (
    (select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT'))
    or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))
  );

create policy "perm_aircraft_status_update"
  on "Basic_Carrier_Record"."Aircraft_Dashboard_Status_Snapshots"
  for update to authenticated
  using (
    (select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT'))
    or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))
  )
  with check (
    (select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT'))
    or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))
  );

create policy "perm_aircraft_status_delete"
  on "Basic_Carrier_Record"."Aircraft_Dashboard_Status_Snapshots"
  for delete to authenticated
  using (
    (select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT'))
    or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))
  );

notify pgrst,'reload schema';
commit;
