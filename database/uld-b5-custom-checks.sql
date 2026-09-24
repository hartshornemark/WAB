begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ declare s jsonb;r jsonb;n int;begin
select count(*) into n from "Basic_Carrier_Record"."MASTER_ULD_List";
s:="Basic_Carrier_Record".get_carrier_ulds('ZZ');r:=s->'rows';
s:="Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',r||'[{"code":"Z9X","type":"NEW","isCustom":true,"isDefault":true,"tare":"90","maximum":"1500","volume":"4.25","remarks":"Rollback-only custom ULD verification"},{"code":"Z8X","type":"LD3","isCustom":true,"isDefault":false,"tare":"90","maximum":"1500","volume":"4.25","remarks":"Rollback-only shared type verification"}]');
if not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"='ZZ' and "ULD_ID"='Z9X' and "Is_Custom" and "Master_ULD_ID" is null and "ULD_Type"='NEW') then raise exception 'FAIL custom saved';end if;
if (select count(*) from "Basic_Carrier_Record"."MASTER_ULD_List")<>n or exists(select 1 from "Basic_Carrier_Record"."MASTER_ULD_List" where "ULD_ID" in ('Z9X','Z8X')) then raise exception 'FAIL master changed';end if;
begin update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "Is_Custom"=false where "ULD_ID"='Z9X';raise exception 'FAIL master link';exception when foreign_key_violation then null;end;
begin update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "ULD_Default"=true where "ULD_ID"='Z8X';raise exception 'FAIL shared default';exception when unique_violation then null;end;
begin update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "ULD_ID"='Z!X' where "ULD_ID"='Z9X';raise exception 'FAIL code format';exception when check_violation then null;end;
perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',r);
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "ULD_ID" in ('Z9X','Z8X')) then raise exception 'FAIL custom removal';end if;
end $$;
set constraints all immediate;
select 'PASS custom ULD save/read/removal, new and existing types, master unchanged, master FK retained, default and code checks' as result;
rollback;
