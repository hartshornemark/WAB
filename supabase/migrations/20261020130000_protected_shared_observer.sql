begin;

do $$
declare
  observer_user_id uuid;
  observer_role_id bigint;
begin
  select id into observer_user_id
  from auth.users
  where lower(email)='observer@wabiqa.com';

  if observer_user_id is null then
    raise exception 'The shared Observer Auth identity has not been created';
  end if;

  select role_id into observer_role_id
  from application_security.roles
  where role_code='OBSERVER' and active and role_scope='GLOBAL';

  if observer_role_id is null then
    raise exception 'The Observer role is not available';
  end if;

  update auth.users
  set email_confirmed_at=coalesce(email_confirmed_at,now()),
      raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('protected_observer',true),
      raw_user_meta_data=jsonb_build_object('display_name','OBSERVER'),
      updated_at=now()
  where id=observer_user_id;

  insert into application_security.application_users(user_id,display_name,active)
  values(observer_user_id,'OBSERVER',true)
  on conflict(user_id) do update set display_name='OBSERVER',active=true;

  delete from application_security.user_global_roles
  where user_id=observer_user_id and role_id<>observer_role_id;

  insert into application_security.user_global_roles(user_id,role_id,active,valid_from,valid_until)
  values(observer_user_id,observer_role_id,true,now(),null)
  on conflict(user_id,role_id) do update set active=true,valid_from=now(),valid_until=null;

  delete from application_security.user_carrier_access
  where user_id=observer_user_id;
end;
$$;

create or replace function private.protect_shared_observer_auth()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if coalesce(old.raw_app_meta_data->>'protected_observer','false')<>'true' then
    return case when tg_op='DELETE' then old else new end;
  end if;
  if tg_op='DELETE' then
    raise exception 'The shared Observer account cannot be deleted' using errcode='42501';
  end if;
  if new.email is distinct from old.email
    or new.encrypted_password is distinct from old.encrypted_password
    or new.phone is distinct from old.phone
    or new.raw_app_meta_data is distinct from old.raw_app_meta_data
    or new.raw_user_meta_data is distinct from old.raw_user_meta_data
    or new.banned_until is distinct from old.banned_until then
    raise exception 'The shared Observer account is locked' using errcode='42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_shared_observer_auth on auth.users;
create trigger protect_shared_observer_auth
before update or delete on auth.users
for each row execute function private.protect_shared_observer_auth();

create or replace function private.protect_shared_observer_assignment()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  target_user_id uuid:=case when tg_op='DELETE' then old.user_id else new.user_id end;
  observer_role_id bigint;
  is_protected boolean;
begin
  select coalesce(raw_app_meta_data->>'protected_observer','false')='true'
  into is_protected from auth.users where id=target_user_id;
  if not coalesce(is_protected,false) then
    return case when tg_op='DELETE' then old else new end;
  end if;
  select role_id into observer_role_id from application_security.roles where role_code='OBSERVER';
  if tg_table_name='user_global_roles' and tg_op='INSERT'
    and new.role_id=observer_role_id and new.active and new.valid_until is null then
    return new;
  end if;
  raise exception 'The shared Observer role assignment is locked' using errcode='42501';
end;
$$;

drop trigger if exists protect_shared_observer_global_role on application_security.user_global_roles;
create trigger protect_shared_observer_global_role
before insert or update or delete on application_security.user_global_roles
for each row execute function private.protect_shared_observer_assignment();

drop trigger if exists protect_shared_observer_carrier_access on application_security.user_carrier_access;
create trigger protect_shared_observer_carrier_access
before insert or update or delete on application_security.user_carrier_access
for each row execute function private.protect_shared_observer_assignment();

create or replace function private.protect_shared_observer_profile()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  target_user_id uuid:=case when tg_op='DELETE' then old.user_id else new.user_id end;
begin
  if exists(
    select 1 from auth.users
    where id=target_user_id
      and coalesce(raw_app_meta_data->>'protected_observer','false')='true'
  ) then
    raise exception 'The shared Observer profile is locked' using errcode='42501';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

drop trigger if exists protect_shared_observer_profile on application_security.application_users;
create trigger protect_shared_observer_profile
before update or delete on application_security.application_users
for each row execute function private.protect_shared_observer_profile();

commit;
