begin;

alter table "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings"
  add column if not exists "Records_ULD_Inventory" boolean not null default false;

update "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" s
set "Records_ULD_Inventory" = true
where exists (
  select 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory" i
  where i."Carrier_IATA"=s."Carrier_IATA"
    and i."Aircraft_Type_IATA"=s."Aircraft_Type_IATA"
    and i."Aircraft_Series_Subtype"=s."Aircraft_Series_Subtype"
);

do $$
begin
  if to_regprocedure('"Basic_Carrier_Record".get_carrier_ulds_without_inventory_flag(text,text,text)') is null then
    alter function "Basic_Carrier_Record".get_carrier_ulds(text,text,text)
      rename to get_carrier_ulds_without_inventory_flag;
  end if;
end $$;

create or replace function "Basic_Carrier_Record".get_carrier_ulds(p_iata text,p_type text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  result jsonb;
  records_inventory boolean;
begin
  result := "Basic_Carrier_Record".get_carrier_ulds_without_inventory_flag(p_iata,p_type,p_subtype);
  select coalesce(s."Records_ULD_Inventory",false) into records_inventory
  from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" s
  where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=p_type and s."Aircraft_Series_Subtype"=p_subtype;
  records_inventory := coalesce(records_inventory,false);
  return result || jsonb_build_object(
    'recordsInventory',records_inventory,
    'revision',md5(coalesce(result->>'revision','')||records_inventory::text)
  );
end $$;

create or replace function "Basic_Carrier_Record".save_carrier_uld_applicability(p_iata text,p_type text,p_subtype text,p_revision text,p_utilises boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s jsonb;
begin
  if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
  if not found then raise exception 'Aircraft unavailable' using errcode='23503';end if;
  perform 1 from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
  perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
  perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
  s := "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);
  if p_revision is distinct from s->>'revision' then raise exception 'ULD settings changed' using errcode='40001';end if;
  if not p_utilises then delete from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype;end if;
  insert into "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings"(
    "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Utilises_ULDs","Records_ULD_Inventory","Updated_At"
  ) values(p_iata,p_type,p_subtype,p_utilises,case when p_utilises then coalesce((s->>'recordsInventory')::boolean,false) else false end,now())
  on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
    "Utilises_ULDs"=excluded."Utilises_ULDs",
    "Records_ULD_Inventory"=excluded."Records_ULD_Inventory",
    "Updated_At"=now();
  return "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);
end $$;

create or replace function "Basic_Carrier_Record".save_carrier_uld_inventory_applicability(p_iata text,p_type text,p_subtype text,p_revision text,p_records boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s jsonb;
begin
  if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
  if not found then raise exception 'Aircraft unavailable' using errcode='23503';end if;
  perform 1 from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
  perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
  s := "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);
  if p_revision is distinct from s->>'revision' then raise exception 'ULD settings changed' using errcode='40001';end if;
  if p_records and not (s->>'utilisesUlds')::boolean then raise exception 'B5 is skipped' using errcode='23514';end if;
  if not p_records then delete from "Basic_Carrier_Record"."Carrier_ULD_Inventory" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype;end if;
  update "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" set "Records_ULD_Inventory"=p_records,"Updated_At"=now()
  where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype;
  return "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);
end $$;

notify pgrst,'reload schema';
commit;
