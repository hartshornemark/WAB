begin;

create or replace function private.validate_c5_f1_maximums()
returns trigger language plpgsql security invoker set search_path='' as $$
declare z integer; l integer; t integer; r integer;
begin
  select max(v."Zero_Fuel_Weight"),max(v."Landing_Weight"),max(v."Take_Off_Weight"),max(v."Ramp_Taxi_Weight") into z,l,t,r
    from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" v
    where v."Carrier_IATA"=new."Carrier_IATA" and v."Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and v."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype";
  if z is not null and (new."MZFW" is distinct from z or new."MLAW" is distinct from l or new."MTOW" is distinct from t or new."MRW" is distinct from r) then
    raise exception 'C5.1 maximum weights must equal the highest corresponding F1 registration limits' using errcode='23514';
  end if;
  return new;
end $$;

drop trigger if exists validate_c5_f1_maximums on "Basic_Carrier_Record"."Basic_Aircraft_Data";
create trigger validate_c5_f1_maximums before update of "MZFW","MLAW","MTOW","MRW" on "Basic_Carrier_Record"."Basic_Aircraft_Data" for each row execute function private.validate_c5_f1_maximums();

create or replace function private.sync_c5_from_f1()
returns trigger language plpgsql security invoker set search_path='' as $$
declare iata text:=coalesce(new."Carrier_IATA",old."Carrier_IATA"); tc text:=coalesce(new."Aircraft_Type_IATA",old."Aircraft_Type_IATA"); st text:=coalesce(new."Aircraft_Series_Subtype",old."Aircraft_Series_Subtype"); z integer; l integer; t integer; r integer;
begin
  select max(v."Zero_Fuel_Weight"),max(v."Landing_Weight"),max(v."Take_Off_Weight"),max(v."Ramp_Taxi_Weight") into z,l,t,r
    from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" v
    where v."Carrier_IATA"=iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st;
  if z is not null then
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MZFW"=z,"MLAW"=l,"MTOW"=t,"MRW"=r
      where "Carrier_IATA"=iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;

drop trigger if exists sync_c5_from_f1 on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values";
create trigger sync_c5_from_f1 after insert or update or delete on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" for each row execute function private.sync_c5_from_f1();

revoke all on function private.validate_c5_f1_maximums() from public,anon;
revoke all on function private.sync_c5_from_f1() from public,anon;

commit;
