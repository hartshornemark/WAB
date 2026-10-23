-- OFFLINE ONLY: install after max_net_cargo_v2.sql in an isolated PostgreSQL DB.
-- No truncation, heuristic packing, or approximate dominance is used.

-- A subtree's attainable integer cargo region is
-- 0<=ULD<=u, 0<=Bulk<=b, ULD+Bulk<=t, with reserved gross `base`.
create or replace function capacity_reference.cap_state(s jsonb, gross_limit bigint, bulk_limit bigint)
returns jsonb language plpgsql immutable as $$
declare u bigint; b bigint; t bigint;
begin
 if (s->>'base')::bigint>gross_limit or bulk_limit<0 then return null;end if;
 t:=least((s->>'t')::bigint,gross_limit-(s->>'base')::bigint);
 u:=least((s->>'u')::bigint,t);
 b:=least((s->>'b')::bigint,t,coalesce(bulk_limit,9000000000000000));
 t:=least(t,u+b);
 return s||jsonb_build_object('u',u,'b',b,'t',t);
end $$;

-- Compare only identical baggage-ID masks and identical live physical bays.
-- Equal summaries retain one witness. Lower reserved gross and no smaller
-- capacity region dominates for every possible ancestor/future continuation.
create or replace function capacity_reference.prune_states(states jsonb, state_limit integer)
returns jsonb language plpgsql immutable as $$
declare answer jsonb;
begin
 if jsonb_array_length(states)>state_limit then
  raise exception 'Exact capacity frontier exceeded state limit; no optimum established' using errcode='54000';
 end if;
 -- Fast exact skyline for regions T=min(U+B,K-base), independently checked
 -- within each (baggage mask, live bays, Bulk bound) partition. Otherwise use
 -- the general three-bound dominance test below.
 with rows as materialized (
  select value s,ordinality i,value->'mask' mask,value->'live' live,
   (value->>'base')::bigint base,(value->>'u')::bigint u,
   (value->>'b')::bigint b,(value->>'t')::bigint t
  from jsonb_array_elements(states) with ordinality
 ), bounds as materialized (
  select *,max(base+t) over(partition by mask,live,b) k from rows
 ), shapes as materialized (
  select *,bool_and(t=least(u+b,k-base)) over() fits from bounds
 ), dedup as materialized (
  select distinct on(mask,live,b,base) * from shapes
  order by mask,live,b,base,u desc,i
 ), skyline as (
  select *,max(u) over(partition by mask,live,b order by base rows between unbounded preceding and 1 preceding) previous_u from dedup
 ) select case when coalesce(bool_and(fits),true) then coalesce(jsonb_agg(s order by i) filter(where previous_u is null or u>previous_u),'[]') else null end into answer from skyline;
 if answer is not null then return answer;end if;
 with rows as materialized (
  select value s,ordinality i,value->'mask' mask,value->'live' live,
   (value->>'base')::bigint base,(value->>'u')::bigint u,
   (value->>'b')::bigint b,(value->>'t')::bigint t
  from jsonb_array_elements(states) with ordinality
 ), distinct_rows as materialized (
  select distinct on(mask,live,base,u,b,t) * from rows order by mask,live,base,u,b,t,i
 )
 select coalesce(jsonb_agg(a.s order by a.i),'[]') into answer from distinct_rows a
 where not exists(select 1 from distinct_rows d where d.mask=a.mask and d.live=a.live
  and d.base<=a.base and d.u>=a.u and d.b>=a.b and d.t>=a.t
  and (d.base<a.base or d.u>a.u or d.b>a.b or d.t>a.t));
 return answer;
end $$;


-- Only fully interchangeable baggage is canonicalised. Each witness still maps
-- every original load ID to a compatible physical position.
create or replace function capacity_reference.baggage_classes(p jsonb)
returns jsonb language sql immutable as $$
 with bags as materialized (
  select value->>'id' id,jsonb_build_array(value->'netWeightGrams',value->'volumeMillilitres',
   (select jsonb_agg(x order by x) from jsonb_array_elements(value->'compatiblePositionIds') x)) signature
  from jsonb_array_elements(p->'baggageUlds')
 ) select coalesce(jsonb_object_agg(a.id,(select jsonb_agg(b.id order by b.id) from bags b where b.signature=a.signature)),'{}') from bags a
$$;

-- Offline exact set-based hierarchy combination. Load after the frontier file.
create or replace function capacity_reference.merge_masks(left_mask jsonb,right_mask jsonb,classes jsonb)
returns jsonb language plpgsql immutable as $$
declare used jsonb;translation jsonb:='{}';id text;chosen text;mask jsonb;
begin
 select coalesce(jsonb_object_agg(value,true),'{}') into used from jsonb_array_elements_text(left_mask);
 for id in select value from jsonb_array_elements_text(right_mask) order by value loop
  if classes ? id then
   select value into chosen from jsonb_array_elements_text(classes->id) where not used ? value order by value limit 1;
  else chosen:=case when used ? id then null else id end;end if;
  if chosen is null then return null;end if;
  translation:=translation||jsonb_build_object(id,chosen);used:=used||jsonb_build_object(chosen,true);
 end loop;
 select coalesce(jsonb_agg(k order by k),'[]') into mask from jsonb_object_keys(used) k;
 return jsonb_build_object('mask',mask,'translation',translation);
end $$;

create or replace function capacity_reference.translate_bags(left_bags jsonb,right_bags jsonb,translation jsonb)
returns jsonb language sql immutable as $$
 select left_bags||coalesce(jsonb_object_agg(translation->>key,value),'{}') from jsonb_each(right_bags)
$$;

create or replace function capacity_reference.combine_states(left_states jsonb,right_states jsonb,gross_limit bigint,bulk_limit bigint,state_limit integer,bag_classes jsonb default '{}'::jsonb)
returns jsonb language plpgsql immutable as $$
declare answer jsonb;
begin
 if bulk_limit<0 then return '[]';end if;
 if jsonb_array_length(left_states)::bigint*jsonb_array_length(right_states)>4000000 then
  raise exception 'Exact capacity combination exceeded pair limit; no optimum established' using errcode='54000';
 end if;
 with l as materialized (
  select value s,value->'mask' mask,(value->>'base')::bigint base,(value->>'u')::bigint u,(value->>'b')::bigint b,(value->>'t')::bigint t from jsonb_array_elements(left_states)
 ), r as materialized (
  select value s,value->'mask' mask,(value->>'base')::bigint base,(value->>'u')::bigint u,(value->>'b')::bigint b,(value->>'t')::bigint t from jsonb_array_elements(right_states)
 ), masks as materialized (
  select lm.mask lm,rm.mask rm,capacity_reference.merge_masks(lm.mask,rm.mask,bag_classes) merged
  from (select distinct mask from l) lm cross join (select distinct mask from r) rm
 ), raw as (
  select l.s ls,r.s rs,m.merged,l.base+r.base base,l.u+r.u u,l.b+r.b b,least(l.t+r.t,gross_limit-l.base-r.base) t
  from l join masks m on m.lm=l.mask and m.merged is not null join r on r.mask=m.rm
  where l.base+r.base<=gross_limit
 ), clipped as (
  select *,least(u,t) cu,least(b,t,coalesce(bulk_limit,9000000000000000)) cb from raw
 ), distinct_profiles as materialized (
  select distinct on(merged->'mask',base,cu,cb,least(t,cu+cb)) * from clipped
  order by merged->'mask',base,cu,cb,least(t,cu+cb)
 ) select coalesce(jsonb_agg(jsonb_build_object('mask',merged->'mask','live','[]'::jsonb,
   'bags',capacity_reference.translate_bags(ls->'bags',rs->'bags',merged->'translation'),
   'cargo',(ls->'cargo')||(rs->'cargo'),'base',base,'u',cu,'b',cb,'t',least(t,cu+cb))),'[]') into answer from distinct_profiles;
 return capacity_reference.prune_states(answer,state_limit);
end $$;

-- Local position sweep forgets a used bay only once no unprocessed alternative
-- can claim it. This is a resource frontier, not a redesign of physical bays.
create or replace function capacity_reference.group_frontier(p jsonb,gid text,state_limit integer)
returns jsonb language plpgsql immutable as $$
declare g jsonb;area jsonb;r jsonb;s jsonb;n jsonb;bag jsonb;pos jsonb;child jsonb;
 positions jsonb;frontier jsonb;next_states jsonb;future text[];blocked text[];live text[];next_live text[];
 local_fixed bigint:=0;fixed_volume bigint:=0;bulk bigint:=0;w bigint;v bigint;bulk_limit bigint;gross_limit bigint;
 density bigint:=(p->>'cargoDensityGramsPerM3')::bigint;i integer;mask jsonb;
begin
 select value into g from jsonb_array_elements(p->'groups') where value->>'id'=gid;
 gross_limit:=(g->>'maximumGrossWeightGrams')::bigint;
 for r in select value from jsonb_array_elements(p->'fixedLoads') loop
  select value into area from jsonb_array_elements(p->'bulkAreas') where value->>'id'=r->>'bulkAreaId';
  if coalesce(area->>'groupId',r->>'groupId')=gid then local_fixed:=local_fixed+(r->>'grossWeightGrams')::bigint;end if;
  if gid=any(capacity_reference.path(p->'groups',coalesce(area->>'groupId',r->>'groupId'))) then fixed_volume:=fixed_volume+(r->>'bulkVolumeMillilitres')::bigint;end if;
 end loop;
 if g->>'maximumBulkVolumeMillilitres' is not null then
  v:=(g->>'maximumBulkVolumeMillilitres')::bigint-fixed_volume;
  if v<0 then return '[]';end if;
  bulk_limit:=floor(v::numeric*density/1000000)::bigint;
 end if;
 for area in select value from jsonb_array_elements(p->'bulkAreas') where value->>'groupId'=gid loop
  select (area->>'maximumGrossWeightGrams')::bigint-coalesce(sum((value->>'grossWeightGrams')::bigint),0),
   (area->>'maximumVolumeMillilitres')::bigint-coalesce(sum((value->>'bulkVolumeMillilitres')::bigint),0)
   into w,v from jsonb_array_elements(p->'fixedLoads') where value->>'bulkAreaId'=area->>'id';
  if w<0 or v<0 then return '[]';end if;
  bulk:=bulk+least(w,floor(v::numeric*density/1000000)::bigint);
 end loop;
 s:=capacity_reference.cap_state(jsonb_build_object('mask','[]'::jsonb,'live','[]'::jsonb,'bags','{}'::jsonb,'cargo','[]'::jsonb,'base',local_fixed,'u',0,'b',bulk,'t',bulk),gross_limit,bulk_limit);
 if s is null then return '[]';end if;
 frontier:=jsonb_build_array(s);
 select coalesce(array_agg(b),'{}') into blocked from jsonb_array_elements(p->'fixedLoads') fx(value) cross join lateral jsonb_array_elements_text(fx.value->'occupiedBayIds') b;
 select coalesce(jsonb_agg(value order by (select min(b) from jsonb_array_elements_text(value->'occupiedBayIds') b),value->>'id'),'[]') into positions from jsonb_array_elements(p->'positions') where value->>'groupId'=gid;
 for i in 0..jsonb_array_length(positions)-1 loop
  pos:=positions->i;
  select coalesce(array_agg(distinct b),'{}') into future from jsonb_array_elements(positions) with ordinality a(value,j) cross join lateral jsonb_array_elements_text(value->'occupiedBayIds') b where j>i+1;
  next_states:='[]';
  for s in select value from jsonb_array_elements(frontier) loop
   live:=array(select jsonb_array_elements_text(s->'live'));
   next_live:=array(select b from unnest(live) b where b=any(future) order by b);
   next_states:=next_states||jsonb_build_array(s||jsonb_build_object('live',to_jsonb(next_live)));
   if live && array(select jsonb_array_elements_text(pos->'occupiedBayIds')) or blocked && array(select jsonb_array_elements_text(pos->'occupiedBayIds')) then continue;end if;
   next_live:=array(select distinct b from unnest(live||array(select jsonb_array_elements_text(pos->'occupiedBayIds'))) b where b=any(future) order by b);
   if (pos->>'maximumGrossWeightGrams')::bigint>(pos->>'tareWeightGrams')::bigint then
    n:=capacity_reference.cap_state(s||jsonb_build_object('live',to_jsonb(next_live),'cargo',(s->'cargo')||jsonb_build_array(pos->>'id'),
     'base',(s->>'base')::bigint+(pos->>'tareWeightGrams')::bigint,
     'u',(s->>'u')::bigint+(pos->>'maximumGrossWeightGrams')::bigint-(pos->>'tareWeightGrams')::bigint,
     't',(s->>'t')::bigint+(pos->>'maximumGrossWeightGrams')::bigint-(pos->>'tareWeightGrams')::bigint),gross_limit,bulk_limit);
    if n is not null then next_states:=next_states||jsonb_build_array(n);end if;
   end if;
   for bag in select bag_row.value from jsonb_array_elements(p->'baggageUlds') bag_row(value) where pos->>'kind'='CONTAINER'
    and (bag_row.value->'compatiblePositionIds') ? (pos->>'id') and not (s->'bags') ? (bag_row.value->>'id')
    and (bag_row.value->>'netWeightGrams')::bigint+(pos->>'tareWeightGrams')::bigint<=(pos->>'maximumGrossWeightGrams')::bigint
    and (bag_row.value->>'volumeMillilitres')::bigint<=(pos->>'maximumVolumeMillilitres')::bigint
    and not exists(select 1 from jsonb_array_elements_text(p->'_bagClasses'->(bag_row.value->>'id')) prior where prior<(bag_row.value->>'id') and not (s->'bags') ? prior) loop
    select jsonb_agg(id order by id) into mask from jsonb_object_keys((s->'bags')||jsonb_build_object(bag->>'id',pos->>'id')) id;
    n:=capacity_reference.cap_state(s||jsonb_build_object('live',to_jsonb(next_live),'mask',mask,'bags',(s->'bags')||jsonb_build_object(bag->>'id',pos->>'id'),
     'base',(s->>'base')::bigint+(bag->>'netWeightGrams')::bigint+(pos->>'tareWeightGrams')::bigint),gross_limit,bulk_limit);
    if n is not null then next_states:=next_states||jsonb_build_array(n);end if;
   end loop;
   if jsonb_array_length(next_states)>state_limit then raise exception 'Exact capacity frontier exceeded state limit; no optimum established' using errcode='54000';end if;
  end loop;
  frontier:=capacity_reference.prune_states(next_states,state_limit);
 end loop;
 for child in select value from jsonb_array_elements(p->'groups') where value->>'parentId'=gid order by value->>'id' loop
  frontier:=capacity_reference.combine_states(frontier,capacity_reference.group_frontier(p,child->>'id',state_limit),gross_limit,bulk_limit,state_limit,p->'_bagClasses');
 end loop;
 return frontier;
end $$;

create or replace function capacity_reference.frontier_net_cargo_v2(p jsonb,state_limit integer default 20000)
returns jsonb language plpgsql immutable as $$
declare blocked text[];bag jsonb;g jsonb;r jsonb;area jsonb;frontier jsonb;s jsonb;best jsonb;answer jsonb;
 reason text;required bigint:=0;min_tare bigint;fixed bigint;aircraft_limit bigint;
begin
 if p->>'rulesVersion' is distinct from 'A350_MAX_NET_CARGO_V2' or p->>'aircraftType' is distinct from '359' or p->>'mode' is distinct from 'CARGO_CAPACITY' then raise exception 'Explicit A350 V2 snapshot required';end if;
 if state_limit<1 or state_limit>200000 or state_limit is null then raise exception 'Invalid frontier state limit';end if;
 -- Full contract validation remains the caller's responsibility. Guard the
 -- decomposition boundary explicitly; never silently separate overlapping bays.
 for g in select value from jsonb_array_elements(p->'groups') loop perform capacity_reference.path(p->'groups',g->>'id');end loop;
 if exists(select 1 from jsonb_array_elements(p->'positions') a cross join lateral jsonb_array_elements_text(a->'occupiedBayIds') b group by b having count(distinct a->>'groupId')>1) then
  raise exception 'Physical bay claimed across different groups; configuration review required';
 end if;
 select coalesce(array_agg(b),'{}') into blocked from jsonb_array_elements(p->'fixedLoads') fx(value) cross join lateral jsonb_array_elements_text(fx.value->'occupiedBayIds') b;
 if jsonb_array_length(p->'baggageUlds')>(select count(*) from jsonb_array_elements(p->'positions') where value->>'kind'='CONTAINER') then reason:='BAGGAGE_POSITION_COUNT';end if;
 if reason is null then
  for bag in select value from jsonb_array_elements(p->'baggageUlds') loop
   select min((value->>'tareWeightGrams')::bigint) into min_tare from jsonb_array_elements(p->'positions')
    where value->>'kind'='CONTAINER' and (bag->'compatiblePositionIds') ? (value->>'id')
    and not (blocked && array(select jsonb_array_elements_text(value->'occupiedBayIds')))
    and (bag->>'netWeightGrams')::bigint+(value->>'tareWeightGrams')::bigint<=(value->>'maximumGrossWeightGrams')::bigint
    and (bag->>'volumeMillilitres')::bigint<=(value->>'maximumVolumeMillilitres')::bigint;
   if min_tare is null then reason:='BAGGAGE_NO_COMPATIBLE_POSITION';exit;end if;
   required:=required+(bag->>'netWeightGrams')::bigint+min_tare;
  end loop;
 end if;
 select coalesce(sum((value->>'grossWeightGrams')::bigint),0) into fixed from jsonb_array_elements(p->'fixedLoads');
 aircraft_limit:=(p->>'maximumZeroFuelWeightGrams')::bigint-(p->>'dryOperatingWeightGrams')::bigint-(p->>'passengerWeightGrams')::bigint;
 if reason is null and required+fixed>aircraft_limit then reason:='AIRCRAFT_RESERVATION_WEIGHT';end if;
 if reason is null then
  -- Fixed-area violations are independent of any ULD arrangement.
  for area in select value from jsonb_array_elements(p->'bulkAreas') loop
   if (select coalesce(sum((value->>'grossWeightGrams')::bigint),0)>(area->>'maximumGrossWeightGrams')::bigint or coalesce(sum((value->>'bulkVolumeMillilitres')::bigint),0)>(area->>'maximumVolumeMillilitres')::bigint from jsonb_array_elements(p->'fixedLoads') where value->>'bulkAreaId'=area->>'id') then reason:='FIXED_BULK_AREA_LIMIT';exit;end if;
  end loop;
 end if;
 if reason is null then
  p:=p||jsonb_build_object('_bagClasses',capacity_reference.baggage_classes(p));
  frontier:=jsonb_build_array(jsonb_build_object('mask','[]'::jsonb,'live','[]'::jsonb,'bags','{}'::jsonb,'cargo','[]'::jsonb,'base',0,'u',0,'b',0,'t',0));
  for g in select value from jsonb_array_elements(p->'groups') where value->>'parentId' is null order by value->>'id' loop
   frontier:=capacity_reference.combine_states(frontier,capacity_reference.group_frontier(p,g->>'id',state_limit),aircraft_limit,null,state_limit,p->'_bagClasses');
  end loop;
  select value into best from jsonb_array_elements(frontier) where jsonb_array_length(value->'mask')=jsonb_array_length(p->'baggageUlds') order by (value->>'t')::bigint desc,(value->>'base')::bigint,value->'mask' limit 1;
  if best is not null then
   answer:=capacity_reference.evaluate(p,best->'cargo',best->'bags');
   if answer is null or (answer->>'cargoNetWeightGrams')::bigint<>(best->>'t')::bigint then raise exception 'Capacity frontier reconstruction mismatch; no optimum established';end if;
  end if;
 end if;
 return jsonb_build_object('mode','CARGO_CAPACITY','aircraftType','359','rulesVersion','A350_MAX_NET_CARGO_V2','inputRevision',p->>'inputRevision',
  'status',case when answer is null then 'INFEASIBLE' else 'OPTIMAL' end,'arrangement',answer,
  'diagnostics',jsonb_build_object('algorithm','EXACT_GROUP_FRONTIER','earlyRejection',reason));
end $$;

create or replace function capacity_reference.max_net_cargo_v2(p jsonb)
returns jsonb language sql immutable as $$select capacity_reference.frontier_net_cargo_v2(p)$$;
