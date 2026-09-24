begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ declare s jsonb;rows jsonb;updated jsonb;begin
  s:="Basic_Carrier_Record".get_carrier_ulds('ZZ');
  rows:=s->'rows';
  updated:=jsonb_set(rows,'{0,inventory}','[{"id":null,"carrierCode":"ZZ","serialStart":"00001","serialEnd":"00100"},{"id":null,"carrierCode":"XY","serialStart":"00201","serialEnd":"00250"}]');
  s:="Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',updated);
  if jsonb_array_length(s->'rows'->0->'inventory')<>2 then raise exception 'FAIL inventory save/read';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory" where "Carrier_IATA"='ZZ' and "ULD_IATA"='XY' and "ULD_Serial_Start"='00201') then raise exception 'FAIL alternate carrier code';end if;
  begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(s->'rows','{0,inventory,0,serialStart}','"A1"'));raise exception 'FAIL nonnumeric serial';exception when invalid_parameter_value then null;end;
  begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(s->'rows','{0,inventory,0,serialStart}','"123456"'));raise exception 'FAIL serial length';exception when invalid_parameter_value then null;end;
  begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(s->'rows','{0,inventory,0,serialStart}','"99999"'));raise exception 'FAIL reversed range';exception when invalid_parameter_value then null;end;
  begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(s->'rows','{0,inventory,0,carrierCode}','"Z"'));raise exception 'FAIL carrier code';exception when invalid_parameter_value then null;end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory") then raise exception 'FAIL unassigned read';end if;
  begin insert into "Basic_Carrier_Record"."Carrier_ULD_Inventory"("Carrier_IATA","ULD_ID","ULD_IATA","ULD_Serial_Start","ULD_Serial_End") values('ZZ','AKE','ZZ','1','2');raise exception 'FAIL unassigned insert';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory";raise exception 'FAIL anonymous access';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS ULD inventory ranges, alternate carrier codes, numeric five-character validation, ordering, RLS and anonymous denial' as result;
rollback;
