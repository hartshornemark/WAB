begin;
create or replace function "Basic_Carrier_Record".save_carrier_uld_applicability(p_iata text,p_type text,p_subtype text,p_revision text,p_utilises boolean) returns jsonb language plpgsql security invoker set search_path='' as $$declare s jsonb;begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;if not found then raise exception 'Aircraft unavailable' using errcode='23503';end if;
perform 1 from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
s:="Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);if p_revision is distinct from s->>'revision' then raise exception 'ULD settings changed' using errcode='40001';end if;
if not p_utilises then delete from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype;end if;
insert into "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" values(p_iata,p_type,p_subtype,p_utilises,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Utilises_ULDs"=excluded."Utilises_ULDs","Updated_At"=now();
return "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);end$$;
notify pgrst,'reload schema';commit;
