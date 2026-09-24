-- Approved B3 table and relationships. No passenger weight records are seeded.
begin;
create function private.can_view_carrier_passenger_weights(p_iata text)
returns boolean language sql stable security invoker set search_path='' as $$
select (select auth.uid()) is not null
and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
and (private.can_edit_carrier_details(p_iata) or private.has_carrier_permission(p_iata,'OPERATING_CONFIG_VIEW'));
$$;
revoke all on function private.can_view_carrier_passenger_weights(text) from public,anon;
grant execute on function private.can_view_carrier_passenger_weights(text) to authenticated;

create table "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" (
"Passenger_Weight_Set_ID" uuid primary key default gen_random_uuid(),
"Carrier_IATA" varchar(2) not null check(char_length("Carrier_IATA")=2)
 references "Basic_Carrier_Record"."Basic_Carrier_Data"("Carrier_IATA") on delete restrict on update restrict,
"Class_Code" varchar(1) not null check("Class_Code" ~ '^[A-Z]$'),
"Flight_Type_Variation" varchar(3) check(char_length("Flight_Type_Variation")=3),
"Adult" integer check("Adult">0),
"Male" integer not null check("Male">0),
"Female" integer not null check("Female">0),
"Child" integer not null check("Child">0),
"Infant" integer not null check("Infant">=0),
"Passenger_Weights_Include_Handbaggage" boolean not null default true,
"Hand_Baggage_Weight" integer check("Hand_Baggage_Weight">=0),
"Remarks" text check(char_length("Remarks")<=2000),
constraint passenger_class_set_unique unique nulls not distinct ("Carrier_IATA","Class_Code","Flight_Type_Variation"),
constraint passenger_class_variation_fk foreign key ("Flight_Type_Variation","Carrier_IATA")
 references "Basic_Carrier_Record"."Carrier_Flight_Variations"("Flight_Type_Variation","Carrier_IATA") on update restrict on delete restrict,
constraint passenger_class_separate_hand_required check(
 "Passenger_Weights_Include_Handbaggage" or "Hand_Baggage_Weight" is not null)
);
create index passenger_class_variation_lookup on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" ("Flight_Type_Variation","Carrier_IATA");
comment on column "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS"."Flight_Type_Variation" is 'NULL means Standard/Default for this class; otherwise an explicitly selected carrier variation.';
comment on table "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" is 'B3 class-specific standard passenger weights, in the carrier B1 weight unit. No automatic variation precedence.';

alter table "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" from public,anon,authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" to authenticated;
create policy passenger_class_read on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" for select to authenticated using(private.can_view_carrier_passenger_weights("Carrier_IATA"));
create policy passenger_class_insert on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy passenger_class_update on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy passenger_class_delete on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
create trigger passenger_class_owner before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" for each row execute function private.protect_carrier_identifier();

-- Touch the parent row to serialize class membership changes, including at
-- repeatable-read isolation (a read lock alone would allow a stale snapshot).
create function private.validate_passenger_weight_class() returns trigger
language plpgsql security invoker set search_path='' as $$
declare c "Basic_Carrier_Record"."Carrier_Class_Codes"%rowtype;
begin
if tg_op='UPDATE' and new."Carrier_IATA" is distinct from old."Carrier_IATA" then
 raise exception 'Carrier ownership cannot change' using errcode='42501';
end if;
-- Check before touching a parent; BEFORE triggers run before INSERT RLS.
if current_user='authenticated' and not private.can_edit_carrier_details(new."Carrier_IATA") then
 raise exception 'Not authorised' using errcode='42501';
end if;
update "Basic_Carrier_Record"."Carrier_Class_Codes"
set "Carrier_IATA"="Carrier_IATA" where "Carrier_IATA"=new."Carrier_IATA" returning * into c;
if not found or not coalesce(new."Class_Code"=any(array[
 c."Carrier_Class_1_Code"::text,c."Carrier_Class_2_Code"::text,
 c."Carrier_Class_3_Code"::text,c."Carrier_Class_4_Code"::text]),false) then
 raise exception 'Save this class for the carrier on B1 first' using errcode='23503';
end if;
return new;
end $$;
revoke all on function private.validate_passenger_weight_class() from public,anon,authenticated;
create trigger passenger_class_membership before insert or update on "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" for each row execute function private.validate_passenger_weight_class();

create function private.protect_passenger_weight_classes() returns trigger
language plpgsql security invoker set search_path='' as $$
declare codes text[];
begin
if tg_op='DELETE' then codes:='{}';
else codes:=array[new."Carrier_Class_1_Code"::text,new."Carrier_Class_2_Code"::text,new."Carrier_Class_3_Code"::text,new."Carrier_Class_4_Code"::text]; end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w
 where w."Carrier_IATA"=old."Carrier_IATA" and not coalesce(w."Class_Code"=any(codes),false)) then
 raise exception 'Resolve passenger weight sets before removing or renaming a class' using errcode='23503';
end if;
if tg_op='DELETE' then return old; end if;
return new;
end $$;
revoke all on function private.protect_passenger_weight_classes() from public,anon,authenticated;
create trigger passenger_class_references before update or delete on "Basic_Carrier_Record"."Carrier_Class_Codes" for each row execute function private.protect_passenger_weight_classes();

-- Adopted variation access is necessary for B3 relationships.
alter table "Basic_Carrier_Record"."Carrier_Flight_Variations" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Flight_Variations" from public,anon,authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Flight_Variations" to authenticated;
create policy passenger_variations_read on "Basic_Carrier_Record"."Carrier_Flight_Variations" for select to authenticated using(private.can_view_carrier_passenger_weights("Carrier_IATA"));
create policy passenger_variations_insert on "Basic_Carrier_Record"."Carrier_Flight_Variations" for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy passenger_variations_update on "Basic_Carrier_Record"."Carrier_Flight_Variations" for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy passenger_variations_delete on "Basic_Carrier_Record"."Carrier_Flight_Variations" for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
create trigger passenger_variation_owner before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Flight_Variations" for each row execute function private.protect_carrier_identifier();
alter table "Basic_Carrier_Record"."MASTER_Flight_Variations" enable row level security;
revoke all on "Basic_Carrier_Record"."MASTER_Flight_Variations" from public,anon,authenticated;
grant select on "Basic_Carrier_Record"."MASTER_Flight_Variations" to authenticated;
create policy passenger_master_variations_read on "Basic_Carrier_Record"."MASTER_Flight_Variations" for select to authenticated using(exists(
 select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" m where private.can_view_carrier_passenger_weights(m."Carrier_IATA")));
notify pgrst,'reload schema';
commit;
