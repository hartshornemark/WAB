begin;

create index if not exists "Aircraft_Special_Load_Exceptions_code_idx" on "Basic_Carrier_Record"."Aircraft_Special_Load_Exceptions"("Special_Load_Code");
create index if not exists "Aircraft_Special_Load_Exceptions_incompatible_idx" on "Basic_Carrier_Record"."Aircraft_Special_Load_Exceptions"("Incompatible_With");
create index if not exists "Aircraft_Special_Load_Limits_code_idx" on "Basic_Carrier_Record"."Aircraft_Special_Load_Limits"("Special_Load_Code");

do $$
declare table_name text;
begin
  foreach table_name in array array['Carrier_Aircraft_H1_Settings','Aircraft_Special_Load_Exceptions','Aircraft_Special_Load_Limits'] loop
    execute format('drop policy if exists h1_select on "Basic_Carrier_Record".%I',table_name);
    execute format('drop policy if exists h1_insert on "Basic_Carrier_Record".%I',table_name);
    execute format('drop policy if exists h1_update on "Basic_Carrier_Record".%I',table_name);
    execute format('drop policy if exists h1_delete on "Basic_Carrier_Record".%I',table_name);
    execute format('create policy h1_select on "Basic_Carrier_Record".%I for select to authenticated using (private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_VIEW'') or private.has_global_permission(''AIRCRAFT_CONFIG_VIEW''))',table_name);
    execute format('create policy h1_insert on "Basic_Carrier_Record".%I for insert to authenticated with check (private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_EDIT'') or private.has_global_permission(''AIRCRAFT_CONFIG_EDIT''))',table_name);
    execute format('create policy h1_update on "Basic_Carrier_Record".%I for update to authenticated using (private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_EDIT'') or private.has_global_permission(''AIRCRAFT_CONFIG_EDIT'')) with check (private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_EDIT'') or private.has_global_permission(''AIRCRAFT_CONFIG_EDIT''))',table_name);
    execute format('create policy h1_delete on "Basic_Carrier_Record".%I for delete to authenticated using (private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_EDIT'') or private.has_global_permission(''AIRCRAFT_CONFIG_EDIT''))',table_name);
  end loop;
end $$;

commit;
