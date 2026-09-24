-- C11.1 calculated stabiliser rate of change.
-- The rate is physically stored by PostgreSQL and recalculated whenever any
-- source endpoint changes. It remains read-only to application clients.

alter table "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"
  add constraint "Aircraft_Stabiliser_TRIM_Settings_variation_range_check"
  check ("STAB_VAR_AFT" > "STAB_VAR_FWD");

alter table "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"
  add column "STAB_Rate_Of_Change" double precision
  generated always as (
    ("STAB_MIN_Value" - "STAB_MAX_Value")
    / nullif("STAB_VAR_AFT" - "STAB_VAR_FWD", 0)
  ) stored;

comment on column "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"."STAB_Rate_Of_Change"
  is 'Calculated stabiliser-setting change per 1 percent MAC/RC across the saved variation range.';
