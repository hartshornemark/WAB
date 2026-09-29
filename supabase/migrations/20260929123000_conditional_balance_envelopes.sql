begin;

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add column "TOW_Envelope_Mode" varchar(11) not null default 'STANDARD',
  add column "LAW_Envelope_Mode" varchar(11) not null default 'STANDARD',
  add column "ZFW_Envelope_Mode" varchar(11) not null default 'STANDARD',
  add constraint "basic_aircraft_tow_envelope_mode" check ("TOW_Envelope_Mode" in ('STANDARD','CONDITIONAL')),
  add constraint "basic_aircraft_law_envelope_mode" check ("LAW_Envelope_Mode" in ('STANDARD','CONDITIONAL')),
  add constraint "basic_aircraft_zfw_envelope_mode" check ("ZFW_Envelope_Mode" in ('STANDARD','CONDITIONAL'));

create table "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" (
  "Envelope_ID" uuid primary key default gen_random_uuid(),
  "Carrier_IATA" varchar(3) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(20) not null,
  "Phase" varchar(3) not null check ("Phase" in ('TOW','LAW','ZFW')),
  "Envelope_Code" varchar(24) not null check (btrim("Envelope_Code")<>''),
  "Condition_Basis" varchar(24) not null check ("Condition_Basis" in ('TAKE_OFF_FUEL','LANDING_FUEL','OTHER')),
  "Condition_Description" text not null default '',
  "Lower_Bound" integer check ("Lower_Bound" is null or "Lower_Bound">=0),
  "Lower_Inclusive" boolean not null default false,
  "Upper_Bound" integer check ("Upper_Bound" is null or "Upper_Bound">=0),
  "Upper_Inclusive" boolean not null default true,
  "Display_Order" smallint not null check ("Display_Order">=0),
  constraint "aircraft_balance_condition_bounds" check ("Lower_Bound" is null or "Upper_Bound" is null or "Lower_Bound"<"Upper_Bound"),
  constraint "aircraft_balance_condition_aircraft_fk" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data" ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade,
  constraint "aircraft_balance_condition_code_unique" unique ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Phase","Envelope_Code"),
  constraint "aircraft_balance_condition_order_unique" unique ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Phase","Display_Order")
);

create table "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" (
  "Envelope_ID" uuid not null references "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" ("Envelope_ID") on update cascade on delete cascade,
  "Carrier_IATA" varchar(3) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(20) not null,
  "Boundary" varchar(3) not null check ("Boundary" in ('FWD','AFT')),
  "Aircraft_Weight" integer not null check ("Aircraft_Weight">0),
  "Envelope_Limit_Index_Value" double precision not null check ("Envelope_Limit_Index_Value" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision) and abs("Envelope_Limit_Index_Value")<=1000000000),
  "Envelope_Limit_MAC_Value" double precision check ("Envelope_Limit_MAC_Value" is null or ("Envelope_Limit_MAC_Value" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision) and "Envelope_Limit_MAC_Value" between 0 and 100)),
  primary key ("Envelope_ID","Boundary","Aircraft_Weight")
);

create index "aircraft_balance_conditions_lookup" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Phase","Display_Order");
create index "aircraft_balance_condition_points_lookup" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" ("Envelope_ID","Boundary","Aircraft_Weight");

alter table "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" enable row level security;
alter table "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" enable row level security;
grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" to authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" to authenticated;
create policy "perm_aircraft_select" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_update" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" for update to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_select" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_update" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" for update to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

create trigger "c5_calculate_conditional_envelope_pair" before insert or update of "Aircraft_Weight","Envelope_Limit_Index_Value","Envelope_Limit_MAC_Value" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" for each row execute function private.c5_calculate_envelope_pair();

alter function "Basic_Carrier_Record".get_aircraft_c5(text,text,text) rename to get_aircraft_c5_legacy;

create function "Basic_Carrier_Record".get_aircraft_c5(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));payload jsonb;aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype;condition_data jsonb;
begin
  payload:="Basic_Carrier_Record".get_aircraft_c5_legacy(p_iata,tc,st);
  select * into aircraft from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  select jsonb_build_object(
    'tow',coalesce(jsonb_agg(item order by display_order) filter(where phase='TOW'),'[]'::jsonb),
    'law',coalesce(jsonb_agg(item order by display_order) filter(where phase='LAW'),'[]'::jsonb),
    'zfw',coalesce(jsonb_agg(item order by display_order) filter(where phase='ZFW'),'[]'::jsonb)
  ) into condition_data from (
    select c."Phase" phase,c."Display_Order" display_order,jsonb_build_object(
      'id',c."Envelope_ID",'code',c."Envelope_Code",'conditionBasis',c."Condition_Basis",'conditionDescription',c."Condition_Description",
      'lowerBound',c."Lower_Bound",'lowerInclusive',c."Lower_Inclusive",'upperBound',c."Upper_Bound",'upperInclusive',c."Upper_Inclusive",
      'boundary',jsonb_build_object(
        'fwd',coalesce((select jsonb_agg(jsonb_build_object('weight',p."Aircraft_Weight",'indexValue',p."Envelope_Limit_Index_Value",'macValue',p."Envelope_Limit_MAC_Value") order by p."Aircraft_Weight") from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" p where p."Envelope_ID"=c."Envelope_ID" and p."Boundary"='FWD'),'[]'::jsonb),
        'aft',coalesce((select jsonb_agg(jsonb_build_object('weight',p."Aircraft_Weight",'indexValue',p."Envelope_Limit_Index_Value",'macValue',p."Envelope_Limit_MAC_Value") order by p."Aircraft_Weight") from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" p where p."Envelope_ID"=c."Envelope_ID" and p."Boundary"='AFT'),'[]'::jsonb)
      )) item
    from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st
  ) conditions;
  payload:=jsonb_set(payload,'{values}',(payload->'values')||jsonb_build_object(
    'envelopeModes',jsonb_build_object('tow',aircraft."TOW_Envelope_Mode",'law',aircraft."LAW_Envelope_Mode",'zfw',aircraft."ZFW_Envelope_Mode"),
    'conditionalEnvelopes',coalesce(condition_data,jsonb_build_object('tow','[]'::jsonb,'law','[]'::jsonb,'zfw','[]'::jsonb))
  ));
  payload:=payload-'revision';
  return payload||jsonb_build_object('revision',md5(payload::text));
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c5(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c5(text,text,text) to authenticated;

create function "Basic_Carrier_Record".save_aircraft_c5_envelope(p_iata text,p_type_code text,p_subtype text,p_revision text,p_phase text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));phase text:=upper(btrim(p_phase));mode text;maximum integer;current_data jsonb;variant jsonb;variant_id uuid;side text;points jsonb;position integer:=0;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
  if phase not in ('TOW','LAW','ZFW') then raise exception 'Invalid envelope phase' using errcode='22023';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C5.1 changed' using errcode='40001';end if;
  mode:=p_values#>>array['envelopeModes',lower(phase)];if mode not in ('STANDARD','CONDITIONAL') then raise exception 'Invalid envelope mode' using errcode='22023';end if;
  if mode='STANDARD' then
    perform "Basic_Carrier_Record".save_aircraft_c5(p_iata,tc,st,p_revision,lower(phase),p_values);
  end if;
  execute format('update "Basic_Carrier_Record"."Basic_Aircraft_Data" set %I=$1 where "Carrier_IATA"=$2 and "Aircraft_Type_IATA"=$3 and "Aircraft_Series_Subtype"=$4',phase||'_Envelope_Mode') using mode,p_iata,tc,st;
  if mode='CONDITIONAL' then
    maximum:=case phase when 'TOW' then (p_values#>>'{maximumWeights,tow}')::integer when 'LAW' then (p_values#>>'{maximumWeights,law}')::integer else (p_values#>>'{maximumWeights,zfw}')::integer end;
    if maximum is null or maximum<=0 or jsonb_typeof(p_values#>array['conditionalEnvelopes',lower(phase)])<>'array' then raise exception 'Invalid conditional envelope data' using errcode='22023';end if;
    delete from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Phase"=phase;
    for variant in select value from jsonb_array_elements(p_values#>array['conditionalEnvelopes',lower(phase)]) loop
      if coalesce(btrim(variant->>'code'),'')='' or variant->>'conditionBasis' not in ('TAKE_OFF_FUEL','LANDING_FUEL','OTHER') then raise exception 'Check every conditional envelope' using errcode='23514';end if;
      variant_id:=coalesce(nullif(variant->>'id','')::uuid,gen_random_uuid());
      insert into "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" ("Envelope_ID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Phase","Envelope_Code","Condition_Basis","Condition_Description","Lower_Bound","Lower_Inclusive","Upper_Bound","Upper_Inclusive","Display_Order") values (variant_id,p_iata,tc,st,phase,upper(btrim(variant->>'code')),variant->>'conditionBasis',coalesce(variant->>'conditionDescription',''),nullif(variant->>'lowerBound','')::integer,coalesce((variant->>'lowerInclusive')::boolean,false),nullif(variant->>'upperBound','')::integer,coalesce((variant->>'upperInclusive')::boolean,false),position);
      foreach side in array array['fwd','aft'] loop
        points:=variant#>array['boundary',side];if not private.c5_points_saveable(points,maximum) then raise exception 'Check every conditional envelope point' using errcode='23514';end if;
        insert into "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" ("Envelope_ID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Boundary","Aircraft_Weight","Envelope_Limit_Index_Value","Envelope_Limit_MAC_Value") select variant_id,p_iata,tc,st,upper(side),x.weight,x."indexValue",x."macValue" from jsonb_to_recordset(points) as x(weight integer,"indexValue" double precision,"macValue" double precision);
      end loop;
      position:=position+1;
    end loop;
  end if;
  return "Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c5_envelope(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c5_envelope(text,text,text,text,text,jsonb) to authenticated;

create function private.c5_prune_conditional_points() returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if new."MTOW" is distinct from old."MTOW" and new."MTOW" is not null then delete from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" p using "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" c where p."Envelope_ID"=c."Envelope_ID" and c."Carrier_IATA"=new."Carrier_IATA" and c."Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype" and c."Phase"='TOW' and p."Aircraft_Weight">new."MTOW";end if;
  if new."MLAW" is distinct from old."MLAW" and new."MLAW" is not null then delete from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" p using "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" c where p."Envelope_ID"=c."Envelope_ID" and c."Carrier_IATA"=new."Carrier_IATA" and c."Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype" and c."Phase"='LAW' and p."Aircraft_Weight">new."MLAW";end if;
  if new."MZFW" is distinct from old."MZFW" and new."MZFW" is not null then delete from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" p using "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" c where p."Envelope_ID"=c."Envelope_ID" and c."Carrier_IATA"=new."Carrier_IATA" and c."Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype" and c."Phase"='ZFW' and p."Aircraft_Weight">new."MZFW";end if;
  return new;
end $$;
create trigger "c5_prune_conditional_points" after update of "MTOW","MLAW","MZFW" on "Basic_Carrier_Record"."Basic_Aircraft_Data" for each row execute function private.c5_prune_conditional_points();

notify pgrst,'reload schema';
commit;
