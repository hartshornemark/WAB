-- Approved B4 corrections; preserves existing per-piece values.
begin;
lock table "Basic_Carrier_Record"."Carrier_Bagagge_Weights_BYCLASS",
 "Basic_Carrier_Record"."Carrier_Planning_Assumptions" in access exclusive mode;
do $$ begin
if exists(select 1 from "Basic_Carrier_Record"."Carrier_Bagagge_Weights_BYCLASS")
or exists(select 1 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions") then
 raise exception 'B4 empty-table precondition changed; review records before migration';
end if;
end $$;

alter table "Basic_Carrier_Record"."Carrier_Bagagge_Weights_BYCLASS" rename to "Carrier_Baggage_Weights_BYCLASS";
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" rename column "Passenger_Weight_Set_ID" to "Baggage_Weight_Set_ID";
-- Empty copied passenger columns are replaced by an explicit passenger category.
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"
 drop column "Adult",drop column "Male",drop column "Female",drop column "Child",drop column "Infant",
 alter column "Class_Code" drop not null,
 alter column "Baggage_Weight_Per_Piece" drop not null,
 alter column "Baggage_Weight_Per_Passenger" drop not null,
 add column "Passenger_Category" text not null default 'ALL'
   check("Passenger_Category" in ('ALL','ADULT','MALE','FEMALE','CHILD','INFANT')),
 add column "Per_Piece_Method" text not null default 'INHERIT'
   check("Per_Piece_Method" in ('INHERIT','STANDARD','ACTUAL')),
 add column "Per_Passenger_Method" text not null default 'UNSET'
   check("Per_Passenger_Method" in ('UNSET','STANDARD','ACTUAL')),
 add column "Remarks" text check(char_length("Remarks")<=2000),
 add column "Is_Baseline" boolean generated always as
   ("Class_Code" is null and "Flight_Type_Variation" is null and "Passenger_Category"='ALL') stored,
 add column "Flight_Scope_Label" text generated always as
   (case when "Flight_Type_Variation" is null then 'All Flights' else "Flight_Type_Variation" end) stored,
 add column "Class_Scope_Label" text generated always as
   (case when "Class_Code" is null then 'All Classes' else "Class_Code" end) stored,
 add constraint baggage_set_unique unique nulls not distinct
   ("Carrier_IATA","Class_Code","Flight_Type_Variation","Passenger_Category"),
 add constraint baggage_piece_nonnegative check("Baggage_Weight_Per_Piece">=0),
 add constraint baggage_passenger_nonnegative check("Baggage_Weight_Per_Passenger">=0),
 add constraint baggage_piece_required check("Per_Piece_Method"<>'STANDARD' or "Baggage_Weight_Per_Piece" is not null),
 add constraint baggage_passenger_required check("Per_Passenger_Method"<>'STANDARD' or "Baggage_Weight_Per_Passenger" is not null),
 add constraint baggage_unset_only_baseline check("Per_Passenger_Method"<>'UNSET' or ("Class_Code" is null and "Flight_Type_Variation" is null and "Passenger_Category"='ALL')),
 add constraint baggage_default_piece_source check(
 "Class_Code" is not null or "Flight_Type_Variation" is not null or
 ("Per_Piece_Method"='INHERIT' and "Baggage_Weight_Per_Piece" is null));
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"
 add constraint baggage_default_source_fk foreign key("Carrier_IATA") references "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS"("Carrier_IATA") on delete restrict on update restrict,
 add constraint baggage_unset_has_no_value check("Per_Passenger_Method"<>'UNSET' or "Baggage_Weight_Per_Passenger" is null);
create index baggage_variation_fk_index on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" ("Flight_Type_Variation","Carrier_IATA");
comment on table "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" is 'B4 checked baggage. NULL class means All Classes; NULL variation means All Flights. Passenger category specifies which passengers a row applies to. No automatic precedence between overlapping variations.';
comment on column "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"."Per_Piece_Method" is 'INHERIT uses the ALLFLIGHTS per-piece configuration. Unvaried All Classes rows cannot override that authoritative default.';
comment on column "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"."Per_Passenger_Method" is 'UNSET is an unconfigured baseline, not zero and not a usable weight. STANDARD requires a numeric value; ACTUAL requires actual baggage measurement.';
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" add constraint b4_bag_adult_male_valid check("Bag_Adult_Male">=0);
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" add constraint b4_bag_adult_female_valid check("Bag_Adult_Female">=0);
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" add constraint b4_bag_adult_child_valid check("Bag_Adult_Child">=0);
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" add constraint b4_bag_standard_summer_valid check("Bag_Standard_Summer">=0);
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" add constraint b4_bag_standard_winter_valid check("Bag_Standard_Winter">=0);
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" add constraint b4_bag_standard_all_valid check("Bag_Standard_All">=0);
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS"
 add column "Per_Piece_Method" text not null default 'STANDARD' check("Per_Piece_Method" in ('STANDARD','ACTUAL')),
 add column "Remarks" text check(char_length("Remarks")<=2000);
comment on column "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS"."Bag_Adult_Male" is 'Standard checked baggage weight PER PIECE for Adult Male passengers. Preserved existing value; inactive in ACTUAL mode.';
comment on column "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS"."Bag_Adult_Female" is 'Standard checked baggage weight PER PIECE for Adult Female passengers.';
comment on column "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS"."Bag_Adult_Child" is 'Standard checked baggage weight PER PIECE for Child passengers. Legacy column name retained.';
comment on column "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS"."Per_Piece_Method" is 'ACTUAL makes retained standard values inactive. STANDARD uses configured per-piece values; seasonal selection is not inferred automatically.';

alter table "Basic_Carrier_Record"."Carrier_Planning_Assumptions"
 drop constraint "Carrier_Planning_Assumptions_pkey",
 add primary key ("Planning_Assumption_UUID"),
 alter column "Flight_Type_Variation" drop not null,
 alter column "Class_Code" drop not null,
 alter column "Average_Bags_Per_Passenger" type numeric(12,4) using "Average_Bags_Per_Passenger"::numeric,
 alter column "Average_Bag_Weight_Per_Passenger" type numeric(12,4) using "Average_Bag_Weight_Per_Passenger"::numeric,
 alter column "Average_Bag_Volume" drop default,
 alter column "Average_Bag_Volume" type numeric(12,4) using "Average_Bag_Volume"::numeric,
 add column "Remarks" text check(char_length("Remarks")<=2000),
 add constraint planning_carrier_fk foreign key("Carrier_IATA")
 references "Basic_Carrier_Record"."Basic_Carrier_Data"("Carrier_IATA") on update restrict on delete restrict,
 add constraint planning_variation_fk foreign key("Flight_Type_Variation","Carrier_IATA")
 references "Basic_Carrier_Record"."Carrier_Flight_Variations"("Flight_Type_Variation","Carrier_IATA") on update restrict on delete restrict,
 add constraint planning_scope_unique unique nulls not distinct("Carrier_IATA","Class_Code","Flight_Type_Variation"),
 add constraint planning_bags_valid check("Average_Bags_Per_Passenger">=0 and "Average_Bags_Per_Passenger"< 'Infinity'::numeric),
 add constraint planning_weight_valid check("Average_Bag_Weight_Per_Passenger">=0 and "Average_Bag_Weight_Per_Passenger"< 'Infinity'::numeric),
 add constraint planning_volume_valid check("Average_Bag_Volume">=0 and "Average_Bag_Volume"< 'Infinity'::numeric);
create index planning_variation_fk_index on "Basic_Carrier_Record"."Carrier_Planning_Assumptions"("Flight_Type_Variation","Carrier_IATA");
comment on table "Basic_Carrier_Record"."Carrier_Planning_Assumptions" is 'B4 planning averages. NULL class means All Classes; NULL variation means All Flights/Default. Weight and volume use B1 carrier units. Unknown bag volume is NULL, not zero.';

create function private.can_view_carrier_baggage(p_iata text) returns boolean
language sql stable security invoker set search_path='' as $$
select (select auth.uid()) is not null
and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
and (private.can_edit_carrier_details(p_iata) or private.has_carrier_permission(p_iata,'OPERATING_CONFIG_VIEW'));
$$;
revoke all on function private.can_view_carrier_baggage(text) from public,anon;
grant execute on function private.can_view_carrier_baggage(text) to authenticated;
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" from public,anon,authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" to authenticated;
drop policy perm_operating_select on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS";
drop policy perm_operating_insert on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS";
drop policy perm_operating_update on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS";
drop policy perm_operating_delete on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS";
create policy b4_read on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" for select to authenticated using(private.can_view_carrier_baggage("Carrier_IATA"));
create policy b4_insert on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy b4_update on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy b4_delete on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
create trigger b4_carrier_owner before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" for each row execute function private.protect_carrier_identifier();
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" from public,anon,authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" to authenticated;
create policy b4_read on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" for select to authenticated using(private.can_view_carrier_baggage("Carrier_IATA"));
create policy b4_insert on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy b4_update on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy b4_delete on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
create trigger b4_carrier_owner before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" for each row execute function private.protect_carrier_identifier();
alter table "Basic_Carrier_Record"."Carrier_Planning_Assumptions" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" from public,anon,authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" to authenticated;
create policy b4_read on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" for select to authenticated using(private.can_view_carrier_baggage("Carrier_IATA"));
create policy b4_insert on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy b4_update on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy b4_delete on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
create trigger b4_carrier_owner before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" for each row execute function private.protect_carrier_identifier();
create function private.validate_b4_class() returns trigger
language plpgsql security invoker set search_path='' as $$
declare c "Basic_Carrier_Record"."Carrier_Class_Codes"%rowtype;
begin
if current_user='authenticated' and not private.can_edit_carrier_details(new."Carrier_IATA") then raise exception 'Not authorised' using errcode='42501'; end if;
if new."Class_Code" is null then return new; end if;
-- Parent write serializes class membership with class changes, including
-- repeatable-read transactions, without changing any class values.
update "Basic_Carrier_Record"."Carrier_Class_Codes" set "Carrier_IATA"="Carrier_IATA"
where "Carrier_IATA"=new."Carrier_IATA" returning * into c;
if not found or not coalesce(new."Class_Code"=any(array[c."Carrier_Class_1_Code"::text,c."Carrier_Class_2_Code"::text,c."Carrier_Class_3_Code"::text,c."Carrier_Class_4_Code"::text]),false) then
raise exception 'Class must be saved for this carrier on B1' using errcode='23503'; end if;
return new;
end $$;
revoke all on function private.validate_b4_class() from public,anon,authenticated;
create trigger b4_class_membership before insert or update on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" for each row execute function private.validate_b4_class();
create trigger b4_class_membership before insert or update on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" for each row execute function private.validate_b4_class();

create function private.protect_b4_class_references() returns trigger
language plpgsql security invoker set search_path='' as $$
declare codes text[];
begin
if tg_op='DELETE' then codes:='{}';
else codes:=array[new."Carrier_Class_1_Code"::text,new."Carrier_Class_2_Code"::text,new."Carrier_Class_3_Code"::text,new."Carrier_Class_4_Code"::text]; end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" where "Carrier_IATA"=old."Carrier_IATA" and "Class_Code" is not null and not coalesce("Class_Code"=any(codes),false))
or exists(select 1 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" where "Carrier_IATA"=old."Carrier_IATA" and "Class_Code" is not null and not coalesce("Class_Code"=any(codes),false)) then
raise exception 'Resolve B4 baggage/planning records before removing or renaming a class' using errcode='23503'; end if;
if tg_op='DELETE' then return old; end if; return new;
end $$;
revoke all on function private.protect_b4_class_references() from public,anon,authenticated;
create trigger b4_class_references before update or delete on "Basic_Carrier_Record"."Carrier_Class_Codes" for each row execute function private.protect_b4_class_references();

create function private.protect_b4_identity() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
if tg_table_name='Carrier_Baggage_Weights_BYCLASS' then
 if tg_op='DELETE' then
  if old."Is_Baseline" then raise exception 'The All Flights / All Classes baseline cannot be removed' using errcode='23514'; end if;
  return old;
 end if;
 if new."Baggage_Weight_Set_ID" is distinct from old."Baggage_Weight_Set_ID" then raise exception 'Weight set identity cannot change' using errcode='23514'; end if;
 -- Generated columns are unavailable in BEFORE NEW; derive the new scope.
 if old."Is_Baseline" and (new."Class_Code" is not null or new."Flight_Type_Variation" is not null or new."Passenger_Category"<>'ALL') then
 raise exception 'The All Flights / All Classes identity is fixed' using errcode='23514'; end if;
else
 if new."Planning_Assumption_UUID" is distinct from old."Planning_Assumption_UUID" then raise exception 'Planning identity cannot change' using errcode='23514'; end if;
end if;
return new;
end $$;
revoke all on function private.protect_b4_identity() from public,anon,authenticated;
create trigger b4_identity before update or delete on "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" for each row execute function private.protect_b4_identity();
create trigger b4_identity before update on "Basic_Carrier_Record"."Carrier_Planning_Assumptions" for each row execute function private.protect_b4_identity();

-- Establish an unset baseline, never invented numeric per-passenger defaults.
insert into "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"("Carrier_IATA")
select "Carrier_IATA" from "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS";
create function private.create_baggage_baseline() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
insert into "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"("Carrier_IATA")
values(new."Carrier_IATA") on conflict("Carrier_IATA","Class_Code","Flight_Type_Variation","Passenger_Category") do nothing;
return new;
end $$;
revoke all on function private.create_baggage_baseline() from public,anon,authenticated;
create trigger b4_create_baseline after insert on "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" for each row execute function private.create_baggage_baseline();
notify pgrst,'reload schema';
commit;
