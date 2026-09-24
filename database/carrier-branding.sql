-- Approved carrier-logo provisioning. Applied through execute_sql.
begin;
insert into application_security.permissions(permission_code,permission_name,description)
values ('CARRIER_BRANDING_EDIT','Manage carrier branding','Upload, replace and remove carrier logos');
insert into application_security.role_permissions(role_id,permission_id)
select r.role_id,p.permission_id from application_security.roles r
cross join application_security.permissions p
where r.role_code in ('SOLUTION_ADMINISTRATOR','CARRIER_ADMINISTRATOR')
and p.permission_code='CARRIER_BRANDING_EDIT';

create function "Basic_Carrier_Record".can_manage_carrier_logo(p_iata text)
returns boolean language sql stable security invoker set search_path='' as $$
  select (select auth.uid()) is not null
    and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" c where c."Carrier_IATA"=p_iata)
    and (private.has_global_permission('CARRIER_BRANDING_EDIT')
      or private.has_carrier_permission(p_iata,'CARRIER_BRANDING_EDIT'));
$$;
revoke all on function "Basic_Carrier_Record".can_manage_carrier_logo(text) from public,anon;
grant execute on function "Basic_Carrier_Record".can_manage_carrier_logo(text) to authenticated;

create table "Basic_Carrier_Record"."Carrier_Branding" (
  "Carrier_IATA" varchar primary key references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA") on delete cascade,
  logo_path text,
  updated_at timestamptz not null default now(),
  constraint carrier_logo_path check (logo_path is null or
    (split_part(logo_path,'/',1)="Carrier_IATA" and logo_path ~ '^[^/]+/[0-9a-f-]{36}\.png$'))
);
alter table "Basic_Carrier_Record"."Carrier_Branding" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Branding" from anon;
grant select,insert,update on "Basic_Carrier_Record"."Carrier_Branding" to authenticated;
create policy branding_read on "Basic_Carrier_Record"."Carrier_Branding" for select to authenticated
using (exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" c where c."Carrier_IATA"="Carrier_Branding"."Carrier_IATA"));
create policy branding_insert on "Basic_Carrier_Record"."Carrier_Branding" for insert to authenticated
with check ("Basic_Carrier_Record".can_manage_carrier_logo("Carrier_IATA"));
create policy branding_update on "Basic_Carrier_Record"."Carrier_Branding" for update to authenticated
using ("Basic_Carrier_Record".can_manage_carrier_logo("Carrier_IATA"))
with check ("Basic_Carrier_Record".can_manage_carrier_logo("Carrier_IATA"));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('carrier-logos','carrier-logos',false,2097152,array['image/png']);
create policy carrier_logo_read on storage.objects for select to authenticated
using (bucket_id='carrier-logos' and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" c where c."Carrier_IATA"=split_part(name,'/',1)));
create policy carrier_logo_insert on storage.objects for insert to authenticated
with check (bucket_id='carrier-logos' and name ~ '^[^/]+/[0-9a-f-]{36}\.png$'
  and "Basic_Carrier_Record".can_manage_carrier_logo(split_part(name,'/',1)));
create policy carrier_logo_delete on storage.objects for delete to authenticated
using (bucket_id='carrier-logos' and "Basic_Carrier_Record".can_manage_carrier_logo(split_part(name,'/',1)));
-- Unique immutable file names: replacements never overwrite an existing object.

create function "Basic_Carrier_Record".set_carrier_logo(p_iata text,p_path text)
returns text language plpgsql security invoker set search_path='' as $$
declare previous_path text;
begin
  if not "Basic_Carrier_Record".can_manage_carrier_logo(p_iata) then
    raise exception 'Carrier branding access denied' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('carrier-logo:' || p_iata,0));
  if p_path is not null and (split_part(p_path,'/',1) <> p_iata or not exists
    (select 1 from storage.objects where bucket_id='carrier-logos' and name=p_path)) then
    raise exception 'Invalid carrier logo reference' using errcode='23514';
  end if;
  select logo_path into previous_path from "Basic_Carrier_Record"."Carrier_Branding" where "Carrier_IATA"=p_iata;
  insert into "Basic_Carrier_Record"."Carrier_Branding"("Carrier_IATA",logo_path)
  values(p_iata,p_path) on conflict("Carrier_IATA") do update set logo_path=excluded.logo_path,updated_at=now();
  return previous_path;
end;
$$;
revoke all on function "Basic_Carrier_Record".set_carrier_logo(text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".set_carrier_logo(text,text) to authenticated;
notify pgrst,'reload schema';
commit;
