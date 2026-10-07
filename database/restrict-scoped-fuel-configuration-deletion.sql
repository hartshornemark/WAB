begin;

create or replace function private.restrict_scoped_fuel_configuration_deletion()
returns trigger language plpgsql set search_path='' as $$
declare override_match jsonb:=jsonb_build_array(jsonb_build_object('configurationCode',old."Configuration_Code"));
begin
 if exists(select 1 from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=old."Carrier_IATA" and "Aircraft_Type_IATA"=old."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=old."Aircraft_Series_Subtype" and (old."Configuration_Code"=any("Applicable_Fuel_Configurations") or "Fuel_Configuration_Overrides" @> override_match))
 or exists(select 1 from "Basic_Carrier_Record"."Aircraft_Compartments" where "Carrier_IATA"=old."Carrier_IATA" and "Aircraft_Type_IATA"=old."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=old."Aircraft_Series_Subtype" and (old."Configuration_Code"=any("Applicable_Fuel_Configurations") or "Fuel_Configuration_Overrides" @> override_match))
 or exists(select 1 from "Basic_Carrier_Record"."Aircraft_Compartment_Areas" where "Carrier_IATA"=old."Carrier_IATA" and "Aircraft_Type_IATA"=old."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=old."Aircraft_Series_Subtype" and (old."Configuration_Code"=any("Applicable_Fuel_Configurations") or "Fuel_Configuration_Overrides" @> override_match))
 or exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" where "Carrier_IATA"=old."Carrier_IATA" and "Aircraft_Type_IATA"=old."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=old."Aircraft_Series_Subtype" and (old."Configuration_Code"=any("Applicable_Fuel_Configurations") or "Fuel_Configuration_Overrides" @> override_match))
 or exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "Carrier_IATA"=old."Carrier_IATA" and "Aircraft_Type_IATA"=old."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=old."Aircraft_Series_Subtype" and (old."Configuration_Code"=any("Applicable_Fuel_Configurations") or "Fuel_Configuration_Overrides" @> override_match)) then
  raise exception 'Remove % hold applicability and overrides before deleting the fitted configuration.',old."Configuration_Code" using errcode='23503';
 end if;
 return old;
end $$;

revoke all on function private.restrict_scoped_fuel_configuration_deletion() from public,anon;
drop trigger if exists restrict_scoped_fuel_configuration_deletion on "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations";
create trigger restrict_scoped_fuel_configuration_deletion before delete on "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" for each row execute function private.restrict_scoped_fuel_configuration_deletion();

commit;
