-- Applied identity protection; execution record, not an idempotent migration.
begin;
alter table "Basic_Carrier_Record"."Basic_Carrier_Data"
 alter column "Carrier_Name" type varchar using rtrim("Carrier_Name"),
 alter column "Carrier_ICAO" type varchar using rtrim("Carrier_ICAO");
update "Basic_Carrier_Record"."Basic_Carrier_Data" b
set "Carrier_Name"=m."Carrier_Name","Carrier_ICAO"=m."Carrier_ICAO"
from "Basic_Carrier_Record"."MASTER_Carrier_Contact" m where b."Carrier_IATA"=m."Carrier_IATA";
alter table "Basic_Carrier_Record"."MASTER_Carrier_Contact" add constraint master_carrier_identity_unique unique ("Carrier_IATA","Carrier_Name","Carrier_ICAO");
alter table "Basic_Carrier_Record"."Basic_Carrier_Data" add constraint carrier_identity_matches_master foreign key ("Carrier_IATA","Carrier_Name","Carrier_ICAO") references "Basic_Carrier_Record"."MASTER_Carrier_Contact" ("Carrier_IATA","Carrier_Name","Carrier_ICAO") on update cascade on delete restrict;
create function private.initialise_carrier_identity() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 select m."Carrier_Name",m."Carrier_ICAO" into new."Carrier_Name",new."Carrier_ICAO" from "Basic_Carrier_Record"."MASTER_Carrier_Contact" m where m."Carrier_IATA"=new."Carrier_IATA";
 if not found then raise exception 'Authorised master carrier required' using errcode='42501'; end if;
 return new;
end $$;
revoke all on function private.initialise_carrier_identity() from public,anon,authenticated;
create trigger initialise_carrier_identity before insert on "Basic_Carrier_Record"."Basic_Carrier_Data" for each row execute function private.initialise_carrier_identity();
create function private.protect_carrier_identifier() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new."Carrier_IATA" is distinct from old."Carrier_IATA" then raise exception 'IATA changes require a coordinated administrator migration' using errcode='42501'; end if;
 return new;
end $$;
revoke all on function private.protect_carrier_identifier() from public,anon,authenticated;
create trigger protect_carrier_identifier before update of "Carrier_IATA" on "Basic_Carrier_Record"."Basic_Carrier_Data" for each row execute function private.protect_carrier_identifier();
create trigger protect_carrier_identifier before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Contact_Data" for each row execute function private.protect_carrier_identifier();
notify pgrst,'reload schema';
commit;
