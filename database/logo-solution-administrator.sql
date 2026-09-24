-- Applied restriction: logo ownership belongs to Solution Administrator.
begin;
delete from application_security.role_permissions rp using application_security.roles r, application_security.permissions p
where rp.role_id=r.role_id and rp.permission_id=p.permission_id
and p.permission_code='CARRIER_BRANDING_EDIT' and r.role_code<>'SOLUTION_ADMINISTRATOR';
create or replace function "Basic_Carrier_Record".can_manage_carrier_logo(p_iata text)
returns boolean language sql stable security invoker set search_path='' as $$
select (select auth.uid()) is not null
and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
and private.has_global_permission('CARRIER_BRANDING_EDIT');
$$;
notify pgrst,'reload schema';
commit;
