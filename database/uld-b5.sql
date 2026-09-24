-- B5 integration approved and applied on 17 September 2026.
begin;
alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
 alter column "ULD_Tare_Weight" type numeric(18,6),alter column "ULD_Max_Weight" type numeric(18,6),alter column "ULD_Max_Volume" type numeric(18,6),
 add column "ULD_Type" varchar(3);
update "Basic_Carrier_Record"."Carrier_ULD_Specifications" c set "ULD_Type"=m."ULD_Type" from "Basic_Carrier_Record"."MASTER_ULD_List" m where m."ULD_ID"=c."ULD_ID";
alter table "Basic_Carrier_Record"."MASTER_ULD_List" add constraint master_uld_code_type_unique unique("ULD_ID","ULD_Type");
alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
 alter column "ULD_Type" set not null,
 add constraint uld_type_reference foreign key("ULD_ID","ULD_Type") references "Basic_Carrier_Record"."MASTER_ULD_List"("ULD_ID","ULD_Type") on update restrict on delete restrict,
 add constraint uld_weights_ordered check("ULD_Max_Weight">="ULD_Tare_Weight"),
 add constraint uld_values_finite check("ULD_Max_Weight"<'Infinity'::numeric and "ULD_Tare_Weight"<'Infinity'::numeric and "ULD_Max_Volume"<'Infinity'::numeric),
 add constraint uld_remarks_length check(char_length("Remarks")<=2000);
create unique index carrier_uld_one_default on "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA","ULD_Type") where "ULD_Default";
create index carrier_uld_master_fk on "Basic_Carrier_Record"."Carrier_ULD_Specifications"("ULD_ID","ULD_Type");
alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_ULD_Specifications" from public,anon,authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_ULD_Specifications" to authenticated;
drop policy perm_operating_select on "Basic_Carrier_Record"."Carrier_ULD_Specifications";
drop policy perm_operating_insert on "Basic_Carrier_Record"."Carrier_ULD_Specifications";
drop policy perm_operating_update on "Basic_Carrier_Record"."Carrier_ULD_Specifications";
drop policy perm_operating_delete on "Basic_Carrier_Record"."Carrier_ULD_Specifications";
create policy uld_read on "Basic_Carrier_Record"."Carrier_ULD_Specifications" for select to authenticated using(private.can_view_carrier_baggage("Carrier_IATA"));
create policy uld_insert on "Basic_Carrier_Record"."Carrier_ULD_Specifications" for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy uld_update on "Basic_Carrier_Record"."Carrier_ULD_Specifications" for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy uld_delete on "Basic_Carrier_Record"."Carrier_ULD_Specifications" for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
create trigger uld_carrier_owner before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_ULD_Specifications" for each row execute function private.protect_carrier_identifier();
grant select on "Basic_Carrier_Record"."MASTER_ULD_List" to authenticated;
create policy uld_master_carrier_read on "Basic_Carrier_Record"."MASTER_ULD_List" for select to authenticated using((select auth.uid()) is not null and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact"));

create function private.check_uld_defaults() returns trigger language plpgsql security invoker set search_path='' as $$
declare iata text;
begin
if tg_op='DELETE' then iata:=old."Carrier_IATA";else iata:=new."Carrier_IATA";end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=iata group by "ULD_Type" having count(*) filter(where "ULD_Default")<>1) then raise exception 'Choose exactly one default for each adopted ULD type' using errcode='23514';end if;
return null;
end $$;
revoke all on function private.check_uld_defaults() from public,anon,authenticated;
create constraint trigger uld_defaults_required after insert or update or delete on "Basic_Carrier_Record"."Carrier_ULD_Specifications" deferrable initially deferred for each row execute function private.check_uld_defaults();

create function private.convert_carrier_ulds() returns trigger language plpgsql security invoker set search_path='' as $$
declare wf numeric;vf numeric;
begin
if row(old."Carrier_Unit_Weight_KG",old."Carrier_Unit_Weight_LB",old."Carrier_Unit_Volume_m3",old."Carrier_Unit_Volume_ft3") is not distinct from row(new."Carrier_Unit_Weight_KG",new."Carrier_Unit_Weight_LB",new."Carrier_Unit_Volume_m3",new."Carrier_Unit_Volume_ft3") then return new;end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=new."Carrier_IATA") then
if (old."Carrier_Unit_Weight_KG"::int+old."Carrier_Unit_Weight_LB"::int) is distinct from 1 or (new."Carrier_Unit_Weight_KG"::int+new."Carrier_Unit_Weight_LB"::int) is distinct from 1 or (old."Carrier_Unit_Volume_m3"::int+old."Carrier_Unit_Volume_ft3"::int) is distinct from 1 or (new."Carrier_Unit_Volume_m3"::int+new."Carrier_Unit_Volume_ft3"::int) is distinct from 1 then raise exception 'Set valid weight and volume units' using errcode='23514';end if;
wf:=(case when old."Carrier_Unit_Weight_KG" then 1 else 0.45359237 end)/(case when new."Carrier_Unit_Weight_KG" then 1 else 0.45359237 end);
vf:=(case when old."Carrier_Unit_Volume_m3" then 1 else 0.028316846592 end)/(case when new."Carrier_Unit_Volume_m3" then 1 else 0.028316846592 end);
update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "ULD_Tare_Weight"=round("ULD_Tare_Weight"*wf,6),"ULD_Max_Weight"=round("ULD_Max_Weight"*wf,6),"ULD_Max_Volume"=round("ULD_Max_Volume"*vf,6) where "Carrier_IATA"=new."Carrier_IATA";
end if;return new;
end $$;
revoke all on function private.convert_carrier_ulds() from public,anon,authenticated;
create trigger convert_carrier_ulds before update on "Basic_Carrier_Record"."Basic_Carrier_Data" for each row execute function private.convert_carrier_ulds();

create function "Basic_Carrier_Record".get_carrier_ulds(p_iata text) returns jsonb language sql stable security invoker set search_path='' as $$
with access as(select private.can_view_carrier_baggage(p_iata) as view,private.can_edit_carrier_details(p_iata) as edit),
basic as(select b.* from "Basic_Carrier_Record"."Basic_Carrier_Data" b,access a where a.view and b."Carrier_IATA"=p_iata),
rows as(select coalesce(jsonb_agg(jsonb_build_object('code',"ULD_ID",'type',"ULD_Type",'isDefault',"ULD_Default",'tare',"ULD_Tare_Weight"::text,'maximum',"ULD_Max_Weight"::text,'volume',"ULD_Max_Volume"::text,'remarks',coalesce("Remarks",'')) order by "ULD_ID"),'[]'::jsonb) as list,coalesce(string_agg(to_jsonb(c)::text||c.xmin::text,',' order by "ULD_ID"),'') as rev from "Basic_Carrier_Record"."Carrier_ULD_Specifications" c,access a where a.view and c."Carrier_IATA"=p_iata),
master as(select coalesce(jsonb_agg(jsonb_build_object('code',"ULD_ID",'type',"ULD_Type",'tare',"ULD_TARE"::text,'maximum',"ULD_Max_Gross_Weight"::text,'volume',coalesce("ULD_Volume"::text,''),'mainDeckOnly',"Main_Deck_Only") order by "ULD_ID"),'[]'::jsonb) as list from "Basic_Carrier_Record"."MASTER_ULD_List",access a where a.view)
select jsonb_build_object('canView',a.view,'canEdit',a.edit,'weightUnit',case when b."Carrier_Unit_Weight_KG" and not b."Carrier_Unit_Weight_LB" then 'KG' when b."Carrier_Unit_Weight_LB" and not b."Carrier_Unit_Weight_KG" then 'LB' else '' end,'volumeUnit',case when b."Carrier_Unit_Volume_m3" and not b."Carrier_Unit_Volume_ft3" then 'm3' when b."Carrier_Unit_Volume_ft3" and not b."Carrier_Unit_Volume_m3" then 'ft3' else '' end,'rows',r.list,'master',m.list,'revision',case when a.view then md5(r.rev||m.list::text||jsonb_build_array(b."Carrier_Unit_Weight_KG",b."Carrier_Unit_Weight_LB",b."Carrier_Unit_Volume_m3",b."Carrier_Unit_Volume_ft3")::text) else '' end) from access a left join basic b on true cross join rows r cross join master m;
$$;
revoke all on function "Basic_Carrier_Record".get_carrier_ulds(text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_ulds(text) to authenticated;
create function "Basic_Carrier_Record".save_carrier_ulds(p_iata text,p_revision text,p_rows jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare s jsonb;row jsonb;k text;v text;
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
if not found then raise exception 'Save B1 units first' using errcode='23514';end if;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata for update;
s:="Basic_Carrier_Record".get_carrier_ulds(p_iata);
if p_revision is distinct from s->>'revision' then raise exception 'ULD settings changed' using errcode='40001';end if;
if s->>'weightUnit'='' or s->>'volumeUnit'='' then raise exception 'Save B1 units first' using errcode='23514';end if;
if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>200 then raise exception 'Invalid ULD list' using errcode='22023';end if;
for row in select value from jsonb_array_elements(p_rows) loop
if jsonb_typeof(row) is distinct from 'object' or jsonb_typeof(row->'isDefault') is distinct from 'boolean' or jsonb_typeof(row->'remarks') is distinct from 'string' or char_length(row->>'remarks')>2000 then raise exception 'Invalid ULD entries' using errcode='22023';end if;
foreach k in array array['tare','maximum','volume'] loop
v:=row->>k;if v is null or v !~ '^[0-9]+([.][0-9]{1,6})?$' then raise exception 'Invalid ULD value' using errcode='22023';end if;
end loop;
if not exists(select 1 from "Basic_Carrier_Record"."MASTER_ULD_List" where "ULD_ID"=row->>'code') then raise exception 'ULD not in master' using errcode='23503';end if;
end loop;
-- Atomic replacement permits default changes and removals together; any failure rolls back.
delete from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata;
insert into "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA","ULD_ID","ULD_Type","ULD_Default","ULD_Tare_Weight","ULD_Max_Weight","ULD_Max_Volume","Remarks")
select p_iata,r->>'code',m."ULD_Type",(r->>'isDefault')::boolean,(r->>'tare')::numeric,(r->>'maximum')::numeric,(r->>'volume')::numeric,nullif(r->>'remarks','') from jsonb_array_elements(p_rows) r join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=r->>'code';
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata group by "ULD_Type" having count(*) filter(where "ULD_Default")<>1) then raise exception 'Choose one default per ULD type' using errcode='23514';end if;
return "Basic_Carrier_Record".get_carrier_ulds(p_iata);
end $$;
revoke all on function "Basic_Carrier_Record".save_carrier_ulds(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_ulds(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
