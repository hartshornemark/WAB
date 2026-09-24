-- Prepared class-code constraints, administrator-only policies and invoker APIs.
-- Existing carrier values are preserved. Slot number continues to represent priority.
begin;
alter table "Basic_Carrier_Record"."MASTER_Class_Codes"
  add constraint master_class_letter check ("Class_Code" ~ '^[A-Z]$'),
  add constraint master_class_priority check ("Class_Code_Priority" between 1 and 4),
  add constraint master_class_name check (char_length(btrim("Class_Code_Name")) between 1 and 64 and "Class_Code_Name" !~ '[[:cntrl:]]');
alter table "Basic_Carrier_Record"."Carrier_Class_Codes"
  alter column "Carrier_Class_1_Code" drop not null,
  alter column "Carrier_Class_1_Name" drop not null;
alter table "Basic_Carrier_Record"."Carrier_Class_Codes"
  drop constraint "Carrier_Class_Codes_Carrier_Class_1_Name_check",
  add constraint class_1_pair check (
    ("Carrier_Class_1_Code" is null and "Carrier_Class_1_Name" is null)
    or ("Carrier_Class_1_Code" is not null and "Carrier_Class_1_Name" is not null
      and "Carrier_Class_1_Code"::text ~ '^[A-Z]$'
      and char_length(btrim("Carrier_Class_1_Name")) between 1 and 64
      and "Carrier_Class_1_Name"::text !~ '[[:cntrl:]]'));
alter table "Basic_Carrier_Record"."Carrier_Class_Codes"
  drop constraint "Carrier_Class_Codes_Carrier_Class_2_Name_check",
  add constraint class_2_pair check (
    ("Carrier_Class_2_Code" is null and "Carrier_Class_2_Name" is null)
    or ("Carrier_Class_2_Code" is not null and "Carrier_Class_2_Name" is not null
      and "Carrier_Class_2_Code"::text ~ '^[A-Z]$'
      and char_length(btrim("Carrier_Class_2_Name")) between 1 and 64
      and "Carrier_Class_2_Name"::text !~ '[[:cntrl:]]'));
alter table "Basic_Carrier_Record"."Carrier_Class_Codes"
  drop constraint "Carrier_Class_Codes_Carrier_Class_3_Name_check",
  add constraint class_3_pair check (
    ("Carrier_Class_3_Code" is null and "Carrier_Class_3_Name" is null)
    or ("Carrier_Class_3_Code" is not null and "Carrier_Class_3_Name" is not null
      and "Carrier_Class_3_Code"::text ~ '^[A-Z]$'
      and char_length(btrim("Carrier_Class_3_Name")) between 1 and 64
      and "Carrier_Class_3_Name"::text !~ '[[:cntrl:]]'));
alter table "Basic_Carrier_Record"."Carrier_Class_Codes"
  drop constraint "Carrier_Class_Codes_Carrier_Class_4_Name_check",
  add constraint class_4_pair check (
    ("Carrier_Class_4_Code" is null and "Carrier_Class_4_Name" is null)
    or ("Carrier_Class_4_Code" is not null and "Carrier_Class_4_Name" is not null
      and "Carrier_Class_4_Code"::text ~ '^[A-Z]$'
      and char_length(btrim("Carrier_Class_4_Name")) between 1 and 64
      and "Carrier_Class_4_Name"::text !~ '[[:cntrl:]]'));
alter table "Basic_Carrier_Record"."Carrier_Class_Codes" add constraint class_at_least_one check ("Carrier_Class_1_Code" is not null or "Carrier_Class_2_Code" is not null or "Carrier_Class_3_Code" is not null or "Carrier_Class_4_Code" is not null);
alter table "Basic_Carrier_Record"."Carrier_Class_Codes" add constraint class_unique_1_2 check ("Carrier_Class_1_Code" <> "Carrier_Class_2_Code");
alter table "Basic_Carrier_Record"."Carrier_Class_Codes" add constraint class_unique_1_3 check ("Carrier_Class_1_Code" <> "Carrier_Class_3_Code");
alter table "Basic_Carrier_Record"."Carrier_Class_Codes" add constraint class_unique_1_4 check ("Carrier_Class_1_Code" <> "Carrier_Class_4_Code");
alter table "Basic_Carrier_Record"."Carrier_Class_Codes" add constraint class_unique_2_3 check ("Carrier_Class_2_Code" <> "Carrier_Class_3_Code");
alter table "Basic_Carrier_Record"."Carrier_Class_Codes" add constraint class_unique_2_4 check ("Carrier_Class_2_Code" <> "Carrier_Class_4_Code");
alter table "Basic_Carrier_Record"."Carrier_Class_Codes" add constraint class_unique_3_4 check ("Carrier_Class_3_Code" <> "Carrier_Class_4_Code");
create trigger class_carrier_identifier before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Class_Codes" for each row execute function private.protect_carrier_identifier();
alter table "Basic_Carrier_Record"."Carrier_Class_Codes" enable row level security;
alter table "Basic_Carrier_Record"."MASTER_Class_Codes" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Class_Codes" from public,anon;
revoke all on "Basic_Carrier_Record"."MASTER_Class_Codes" from public,anon;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Class_Codes" to authenticated;
grant select on "Basic_Carrier_Record"."MASTER_Class_Codes" to authenticated;
create function private.can_view_carrier_classes(p_iata text) returns boolean language sql stable security invoker set search_path='' as $$
select (select auth.uid()) is not null
and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
and (private.can_edit_carrier_details(p_iata) or private.has_carrier_permission(p_iata,'CARRIER_CONFIG_VIEW'));
$$;
revoke all on function private.can_view_carrier_classes(text) from public,anon;
grant execute on function private.can_view_carrier_classes(text) to authenticated;
alter policy perm_carrier_select on "Basic_Carrier_Record"."Carrier_Class_Codes" to authenticated using (private.can_view_carrier_classes("Carrier_IATA"));
alter policy perm_carrier_insert on "Basic_Carrier_Record"."Carrier_Class_Codes" to authenticated with check (private.can_edit_carrier_details("Carrier_IATA"));
alter policy perm_carrier_update on "Basic_Carrier_Record"."Carrier_Class_Codes" to authenticated using (private.can_edit_carrier_details("Carrier_IATA")) with check (private.can_edit_carrier_details("Carrier_IATA"));
alter policy perm_carrier_delete on "Basic_Carrier_Record"."Carrier_Class_Codes" to authenticated using (private.can_edit_carrier_details("Carrier_IATA"));
create policy master_class_defaults_read on "Basic_Carrier_Record"."MASTER_Class_Codes" for select to authenticated using (
exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" m where private.can_view_carrier_classes(m."Carrier_IATA")));

create function "Basic_Carrier_Record".get_carrier_class_codes(p_iata text) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_raw jsonb; v_xmin text; v_rows jsonb; v_defaults jsonb := '[]';
begin
if not private.can_view_carrier_classes(p_iata) then
return jsonb_build_object('canView',false,'canEdit',false,'revision','','rows','[]'::jsonb,'defaults','[]'::jsonb);
end if;
select to_jsonb(c),c.xmin::text into v_raw,v_xmin from "Basic_Carrier_Record"."Carrier_Class_Codes" c where "Carrier_IATA"=p_iata;
select coalesce(jsonb_agg(jsonb_build_object('priority',n,'code',btrim(v_raw->>('Carrier_Class_'||n||'_Code')),'description',btrim(v_raw->>('Carrier_Class_'||n||'_Name'))) order by n),'[]'::jsonb)
into v_rows from generate_series(1,4) n where v_raw->>('Carrier_Class_'||n||'_Code') is not null;
if v_raw is null then
select coalesce(jsonb_agg(jsonb_build_object('priority',"Class_Code_Priority",'code',"Class_Code",'description',btrim("Class_Code_Name")) order by "Class_Code_Priority","Class_Code"),'[]'::jsonb)
into v_defaults from "Basic_Carrier_Record"."MASTER_Class_Codes";
end if;
return jsonb_build_object('canView',true,'canEdit',private.can_edit_carrier_details(p_iata),'revision',md5(coalesce(v_raw::text,'null')||coalesce(v_xmin,'')),'rows',v_rows,'defaults',v_defaults);
end $$;

create function "Basic_Carrier_Record".save_carrier_class_codes(p_iata text,p_revision text,p_rows jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare v_snapshot jsonb; v_row jsonb; v_code text; v_name text; v_priority integer;
v_codes text[] := array[null,null,null,null]::text[]; v_names text[] := array[null,null,null,null]::text[];
v_seen text[] := '{}'; v_exists boolean;
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501'; end if;
if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Invalid classes' using errcode='22023'; end if;
if jsonb_array_length(p_rows) not between 1 and 4 then raise exception 'Keep one to four classes' using errcode='22023'; end if;
for v_row in select value from jsonb_array_elements(p_rows) loop
if jsonb_typeof(v_row)<>'object' or jsonb_typeof(v_row->'code') is distinct from 'string' or jsonb_typeof(v_row->'description') is distinct from 'string' or jsonb_typeof(v_row->'priority') is distinct from 'number' then raise exception 'Invalid class' using errcode='22023'; end if;
if btrim(v_row->>'code') !~ '^[A-Za-z]$' or (v_row->>'priority') !~ '^[1-4]$' then raise exception 'Invalid class code or priority' using errcode='22023'; end if;
v_code := upper(btrim(v_row->>'code')); v_priority := (v_row->>'priority')::integer; v_name := btrim(v_row->>'description');
if char_length(v_name) not between 1 and 64 or v_name ~ '[[:cntrl:]]' or v_code=any(v_seen) or v_codes[v_priority] is not null then raise exception 'Invalid or duplicate class' using errcode='22023'; end if;
v_seen := array_append(v_seen,v_code); v_codes[v_priority] := v_code; v_names[v_priority] := v_name;
end loop;
perform pg_advisory_xact_lock(hashtextextended('carrier-classes:'||p_iata,0));
perform 1 from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"=p_iata for update;
v_exists := found;
v_snapshot := "Basic_Carrier_Record".get_carrier_class_codes(p_iata);
if p_revision is distinct from v_snapshot->>'revision' then raise exception 'Classes changed' using errcode='40001'; end if;
if v_exists then
update "Basic_Carrier_Record"."Carrier_Class_Codes" set
"Carrier_Class_1_Code"=v_codes[1], "Carrier_Class_1_Name"=v_names[1],
"Carrier_Class_2_Code"=v_codes[2], "Carrier_Class_2_Name"=v_names[2],
"Carrier_Class_3_Code"=v_codes[3], "Carrier_Class_3_Name"=v_names[3],
"Carrier_Class_4_Code"=v_codes[4], "Carrier_Class_4_Name"=v_names[4]
where "Carrier_IATA"=p_iata;
else
insert into "Basic_Carrier_Record"."Carrier_Class_Codes"("Carrier_IATA","Carrier_Class_1_Code","Carrier_Class_1_Name","Carrier_Class_2_Code","Carrier_Class_2_Name","Carrier_Class_3_Code","Carrier_Class_3_Name","Carrier_Class_4_Code","Carrier_Class_4_Name")
values(p_iata,v_codes[1],v_names[1],v_codes[2],v_names[2],v_codes[3],v_names[3],v_codes[4],v_names[4]);
end if;
return "Basic_Carrier_Record".get_carrier_class_codes(p_iata);
exception when unique_violation then raise exception 'Classes changed' using errcode='40001';
end $$;
revoke all on function "Basic_Carrier_Record".get_carrier_class_codes(text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_carrier_class_codes(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_class_codes(text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_carrier_class_codes(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
