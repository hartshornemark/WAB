begin;

alter table "Basic_Carrier_Record"."MASTER_Carrier_Contact"
  add constraint master_carrier_iata_format check ("Carrier_IATA" ~ '^[A-Z0-9]{2}$'),
  add constraint master_carrier_icao_format check ("Carrier_ICAO" ~ '^[A-Z]{3}$'),
  add constraint master_carrier_name_format check (
    "Carrier_Name" = btrim("Carrier_Name")
    and char_length("Carrier_Name") between 1 and 64
  );

create unique index master_carrier_name_ci_unique
  on "Basic_Carrier_Record"."MASTER_Carrier_Contact" (lower("Carrier_Name"));
create unique index master_carrier_icao_ci_unique
  on "Basic_Carrier_Record"."MASTER_Carrier_Contact" (lower("Carrier_ICAO"));

create function "Basic_Carrier_Record".can_create_carrier()
returns boolean language sql stable security invoker set search_path='' as $$
  select (select auth.uid()) is not null
    and private.has_global_permission('MASTER_DATA_CREATE');
$$;
revoke all on function "Basic_Carrier_Record".can_create_carrier() from public,anon;
grant execute on function "Basic_Carrier_Record".can_create_carrier() to authenticated;

create function "Basic_Carrier_Record".create_carrier(
  p_iata text,
  p_name text,
  p_icao text
)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  iata text:=upper(btrim(p_iata));
  carrier_name text:=btrim(p_name);
  icao text:=upper(btrim(p_icao));
begin
  if (select auth.uid()) is null or not private.has_global_permission('MASTER_DATA_CREATE') then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  if iata !~ '^[A-Z0-9]{2}$' then
    raise exception 'Invalid carrier IATA code' using errcode='22023',detail='iata';
  end if;
  if icao !~ '^[A-Z]{3}$' then
    raise exception 'Invalid carrier ICAO code' using errcode='22023',detail='icao';
  end if;
  if char_length(carrier_name) not between 1 and 64 then
    raise exception 'Invalid carrier name' using errcode='22023',detail='name';
  end if;
  if exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=iata) then
    raise exception 'Carrier IATA code already exists' using errcode='23505',detail='iata';
  end if;
  if exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where lower("Carrier_ICAO")=lower(icao)) then
    raise exception 'Carrier ICAO code already exists' using errcode='23505',detail='icao';
  end if;
  if exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where lower("Carrier_Name")=lower(carrier_name)) then
    raise exception 'Carrier name already exists' using errcode='23505',detail='name';
  end if;

  begin
    insert into "Basic_Carrier_Record"."MASTER_Carrier_Contact"
      ("Carrier_IATA","Carrier_Name","Carrier_ICAO")
    values (iata,carrier_name,icao);
  exception when unique_violation then
    raise exception 'Carrier identity already exists' using errcode='23505',detail='duplicate';
  end;

  return jsonb_build_object('iata',iata,'name',carrier_name,'icao',icao);
end;
$$;
revoke all on function "Basic_Carrier_Record".create_carrier(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".create_carrier(text,text,text) to authenticated;

commit;
