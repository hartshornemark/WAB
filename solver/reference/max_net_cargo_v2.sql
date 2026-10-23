-- Offline reference only. Not a migration and never applied to the shared DB.
create schema if not exists capacity_reference;
create or replace function capacity_reference.path(groups jsonb, start_id text)
returns text[] language plpgsql immutable as $$
declare id text:=start_id; result text[]:='{}'; g jsonb;
begin
 while id is not null loop
  select value into g from jsonb_array_elements(groups) where value->>'id'=id;
  if g is null or id=any(result) then raise exception 'Invalid group hierarchy';end if;
  result:=array_append(result,id);id:=g->>'parentId';
 end loop;
 return result;
end $$;

-- Integral max-flow: ULD and Bulk sources feed the hold-weight tree. A separate
-- Bulk-volume tree limits shared space before Bulk flows enter that tree.
create or replace function capacity_reference.flow(edges jsonb)
returns jsonb language plpgsql immutable as $$
declare nodes text[];n integer;res bigint[][];parents integer[];queue integer[];
 s integer;t integer;u integer;v integer;head integer;e jsonb;delta bigint;out jsonb:='[]';
begin
 select array_agg(x order by x) into nodes from(select distinct value->>'from' x from jsonb_array_elements(edges) union select distinct value->>'to' from jsonb_array_elements(edges)) q;
 n:=cardinality(nodes);res:=array_fill(0::bigint,array[n,n]);s:=array_position(nodes,'SOURCE');t:=array_position(nodes,'SINK');
 for e in select value from jsonb_array_elements(edges) loop
  u:=array_position(nodes,e->>'from');v:=array_position(nodes,e->>'to');res[u][v]:=res[u][v]+(e->>'cap')::bigint;
 end loop;
 loop
  parents:=array_fill(0,array[n]);parents[s]:=-1;queue:=array[s];head:=1;
  while head<=cardinality(queue) and parents[t]=0 loop
   u:=queue[head];head:=head+1;
   for v in 1..n loop
    if parents[v]=0 and res[u][v]>0 then parents[v]:=u;queue:=array_append(queue,v);end if;
   end loop;
  end loop;
  exit when parents[t]=0;
  delta:=9000000000000000;v:=t;
  while v<>s loop u:=parents[v];delta:=least(delta,res[u][v]);v:=u;end loop;
  v:=t;
  while v<>s loop u:=parents[v];res[u][v]:=res[u][v]-delta;res[v][u]:=res[v][u]+delta;v:=u;end loop;
 end loop;
 for e in select value from jsonb_array_elements(edges) loop
  u:=array_position(nodes,e->>'from');v:=array_position(nodes,e->>'to');
  out:=out||jsonb_build_array(e||jsonb_build_object('flow',(e->>'cap')::bigint-res[u][v]));
 end loop;
 return out;
end $$;

create or replace function capacity_reference.evaluate(p jsonb,cargo_ids jsonb,bag_assignments jsonb)
returns jsonb language plpgsql immutable as $$
declare g jsonb;r jsonb;pos jsonb;area jsonb;bag jsonb;id text;gid text;path_id text;entry record;
 weight jsonb:='{}';vol jsonb:='{}';area_weight jsonb:='{}';area_vol jsonb:='{}';
 fixed bigint:=0;w bigint;v bigint;tare bigint:=0;gross bigint;cap bigint;density bigint:=(p->>'cargoDensityGramsPerM3')::bigint;
 edges jsonb:='[]';flows jsonb;net bigint:=0;cargo jsonb:='[]';bulk jsonb:='[]';bags jsonb:='[]';cargo_tare bigint:=0;
 infinity constant bigint:=9000000000000000;
begin
 for r in select value from jsonb_array_elements(p->'fixedLoads') loop
  w:=(r->>'grossWeightGrams')::bigint;v:=(r->>'bulkVolumeMillilitres')::bigint;fixed:=fixed+w;
  if r->>'bulkAreaId' is not null then
   select value into area from jsonb_array_elements(p->'bulkAreas') where value->>'id'=r->>'bulkAreaId';
   gid:=area->>'groupId';id:=area->>'id';
   area_weight:=jsonb_set(area_weight,array[id],to_jsonb(coalesce((area_weight->>id)::bigint,0)+w));
   area_vol:=jsonb_set(area_vol,array[id],to_jsonb(coalesce((area_vol->>id)::bigint,0)+v));
  else gid:=r->>'groupId';end if;
  foreach path_id in array capacity_reference.path(p->'groups',gid) loop
   weight:=jsonb_set(weight,array[path_id],to_jsonb(coalesce((weight->>path_id)::bigint,0)+w));
   vol:=jsonb_set(vol,array[path_id],to_jsonb(coalesce((vol->>path_id)::bigint,0)+v));
  end loop;
 end loop;
 for entry in select * from jsonb_each_text(bag_assignments) loop
  select value into bag from jsonb_array_elements(p->'baggageUlds') where value->>'id'=entry.key;
  select value into pos from jsonb_array_elements(p->'positions') where value->>'id'=entry.value;
  w:=(bag->>'netWeightGrams')::bigint+(pos->>'tareWeightGrams')::bigint;fixed:=fixed+w;
  foreach path_id in array capacity_reference.path(p->'groups',pos->>'groupId') loop
   weight:=jsonb_set(weight,array[path_id],to_jsonb(coalesce((weight->>path_id)::bigint,0)+w));
  end loop;
  bags:=bags||jsonb_build_array(jsonb_build_object('loadId',entry.key,'positionId',entry.value));
 end loop;
 for id in select jsonb_array_elements_text(cargo_ids) loop
  select value into pos from jsonb_array_elements(p->'positions') where value->>'id'=id;
  w:=(pos->>'tareWeightGrams')::bigint;tare:=tare+w;
  foreach path_id in array capacity_reference.path(p->'groups',pos->>'groupId') loop
   weight:=jsonb_set(weight,array[path_id],to_jsonb(coalesce((weight->>path_id)::bigint,0)+w));
  end loop;
  edges:=edges||jsonb_build_array(jsonb_build_object('id','ULD:'||id,'from','SOURCE','to','ULD:'||id,'cap',(pos->>'maximumGrossWeightGrams')::bigint-w),jsonb_build_object('id','ULD_OUT:'||id,'from','ULD:'||id,'to','WEIGHT:'||(pos->>'groupId'),'cap',infinity));
 end loop;
 cap:=(p->>'maximumZeroFuelWeightGrams')::bigint-(p->>'dryOperatingWeightGrams')::bigint-(p->>'passengerWeightGrams')::bigint-fixed-tare;
 if cap<0 then return null;end if;
 edges:=edges||jsonb_build_array(jsonb_build_object('id','EMPTY','from','SOURCE','to','BUDGET','cap',0),jsonb_build_object('id','AIRCRAFT','from','BUDGET','to','SINK','cap',cap));
 for g in select value from jsonb_array_elements(p->'groups') loop
  id:=g->>'id';cap:=(g->>'maximumGrossWeightGrams')::bigint-coalesce((weight->>id)::bigint,0);
  if cap<0 then return null;end if;
  edges:=edges||jsonb_build_array(jsonb_build_object('id','WEIGHT:'||id,'from','WEIGHT:'||id,'to',case when g->>'parentId' is null then 'BUDGET' else 'WEIGHT:'||(g->>'parentId') end,'cap',cap));
  cap:=case when g->>'maximumBulkVolumeMillilitres' is null then infinity else floor(((g->>'maximumBulkVolumeMillilitres')::numeric-coalesce((vol->>id)::bigint,0))*density/1000000)::bigint end;
  if cap<0 then return null;end if;
  edges:=edges||jsonb_build_array(jsonb_build_object('id','SPACE:'||id,'from',case when g->>'parentId' is null then 'SOURCE' else 'SPACE:'||(g->>'parentId') end,'to','SPACE:'||id,'cap',cap));
 end loop;
 for area in select value from jsonb_array_elements(p->'bulkAreas') loop
  id:=area->>'id';w:=(area->>'maximumGrossWeightGrams')::bigint-coalesce((area_weight->>id)::bigint,0);v:=(area->>'maximumVolumeMillilitres')::bigint-coalesce((area_vol->>id)::bigint,0);
  if w<0 or v<0 then return null;end if;
  cap:=least(w,floor(v::numeric*density/1000000)::bigint);
  edges:=edges||jsonb_build_array(jsonb_build_object('id','BULK:'||id,'from','SPACE:'||(area->>'groupId'),'to','BULK:'||id,'cap',cap),jsonb_build_object('id','BULK_OUT:'||id,'from','BULK:'||id,'to','WEIGHT:'||(area->>'groupId'),'cap',infinity));
 end loop;
 flows:=capacity_reference.flow(edges);
 for r in select value from jsonb_array_elements(flows) where (value->>'flow')::bigint>0 loop
  id:=r->>'id';w:=(r->>'flow')::bigint;
  if id like 'ULD:%' then
   id:=substring(id from 5);select value into pos from jsonb_array_elements(p->'positions') where value->>'id'=id;
   cargo:=cargo||jsonb_build_array(jsonb_build_object('positionId',id,'netWeightGrams',w));net:=net+w;cargo_tare:=cargo_tare+(pos->>'tareWeightGrams')::bigint;
  elsif id like 'BULK:%' then bulk:=bulk||jsonb_build_array(jsonb_build_object('areaId',substring(id from 6),'netWeightGrams',w));net:=net+w;end if;
 end loop;
 return jsonb_build_object('cargoUlds',cargo,'baggageUlds',bags,'bulkCargo',bulk,'cargoNetWeightGrams',net,'cargoTareWeightGrams',cargo_tare,'cargoGrossWeightGrams',net+cargo_tare);
end $$;

-- Exhaustive, intentionally simple database reference; no pallet-count priority.
-- Execution timeout is owned by the comparison harness. No partial maximum is
-- returned after cancellation. Call only in the isolated benchmark database.
create or replace function capacity_reference.exhaustive_net_cargo_v2(p jsonb)
returns jsonb language plpgsql immutable as $$
declare candidate record;answer jsonb;best jsonb;blocked text[];
begin
 if p->>'rulesVersion' is distinct from 'A350_MAX_NET_CARGO_V2' or p->>'aircraftType' is distinct from '359' or p->>'mode' is distinct from 'CARGO_CAPACITY' then raise exception 'Explicit A350 V2 snapshot required';end if;
 select coalesce(array_agg(b),'{}') into blocked from jsonb_array_elements(p->'fixedLoads') r cross join lateral jsonb_array_elements_text(r->'occupiedBayIds') b;
 for candidate in
 with recursive positions as (select value pos,ordinality i from jsonb_array_elements(p->'positions') with ordinality),
 states(i,bays,cargo,bags) as (
  select 0::bigint,blocked,'[]'::jsonb,'{}'::jsonb
  union all
  select s.i+1,case when o.kind='UNUSED' then s.bays else s.bays||array(select jsonb_array_elements_text(pos->'occupiedBayIds')) end,
   case when o.kind='CARGO' then s.cargo||jsonb_build_array(pos->>'id') else s.cargo end,
   case when o.kind='BAG' then s.bags||jsonb_build_object(o.bag_id,pos->>'id') else s.bags end
  from states s join positions on positions.i=s.i+1 cross join lateral (
   select 'UNUSED' kind,null::text bag_id union all select 'CARGO',null
   union all select 'BAG',b->>'id' from jsonb_array_elements(p->'baggageUlds') b
    where pos->>'kind'='CONTAINER' and (b->'compatiblePositionIds') ? (pos->>'id') and not s.bags ? (b->>'id')
    and (b->>'netWeightGrams')::bigint+(pos->>'tareWeightGrams')::bigint<=(pos->>'maximumGrossWeightGrams')::bigint
    and (b->>'volumeMillilitres')::bigint<=(pos->>'maximumVolumeMillilitres')::bigint
  ) o where o.kind='UNUSED' or not (s.bays && array(select jsonb_array_elements_text(pos->'occupiedBayIds')))
 ) select cargo,bags from states where i=jsonb_array_length(p->'positions') and (select count(*) from jsonb_object_keys(bags))=jsonb_array_length(p->'baggageUlds')
 loop
  answer:=capacity_reference.evaluate(p,candidate.cargo,candidate.bags);
  if answer is not null and (best is null or (answer->>'cargoNetWeightGrams')::bigint>(best->>'cargoNetWeightGrams')::bigint) then best:=answer;end if;
 end loop;
 return jsonb_build_object('mode','CARGO_CAPACITY','aircraftType','359','rulesVersion','A350_MAX_NET_CARGO_V2','inputRevision',p->>'inputRevision','status',case when best is null then 'INFEASIBLE' else 'OPTIMAL' end,'arrangement',best);
end $$;
