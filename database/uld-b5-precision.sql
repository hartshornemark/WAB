-- B5 precision correction approved and applied on 17 September 2026.
begin;
alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
 add constraint uld_whole_weights check("ULD_Tare_Weight"=trunc("ULD_Tare_Weight") and "ULD_Max_Weight"=trunc("ULD_Max_Weight")),
 add constraint uld_volume_two_decimals check("ULD_Max_Volume"=round("ULD_Max_Volume",2));
create or replace function private.convert_carrier_ulds() returns trigger language plpgsql security invoker set search_path='' as $$
declare wf numeric;vf numeric;
begin
if row(old."Carrier_Unit_Weight_KG",old."Carrier_Unit_Weight_LB",old."Carrier_Unit_Volume_m3",old."Carrier_Unit_Volume_ft3") is not distinct from row(new."Carrier_Unit_Weight_KG",new."Carrier_Unit_Weight_LB",new."Carrier_Unit_Volume_m3",new."Carrier_Unit_Volume_ft3") then return new;end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=new."Carrier_IATA") then
if (old."Carrier_Unit_Weight_KG"::int+old."Carrier_Unit_Weight_LB"::int) is distinct from 1 or (new."Carrier_Unit_Weight_KG"::int+new."Carrier_Unit_Weight_LB"::int) is distinct from 1 or (old."Carrier_Unit_Volume_m3"::int+old."Carrier_Unit_Volume_ft3"::int) is distinct from 1 or (new."Carrier_Unit_Volume_m3"::int+new."Carrier_Unit_Volume_ft3"::int) is distinct from 1 then raise exception 'Set valid weight and volume units' using errcode='23514';end if;
wf:=(case when old."Carrier_Unit_Weight_KG" then 1 else 0.45359237 end)/(case when new."Carrier_Unit_Weight_KG" then 1 else 0.45359237 end);
vf:=(case when old."Carrier_Unit_Volume_m3" then 1 else 0.028316846592 end)/(case when new."Carrier_Unit_Volume_m3" then 1 else 0.028316846592 end);
update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "ULD_Tare_Weight"=round("ULD_Tare_Weight"*wf,0),"ULD_Max_Weight"=round("ULD_Max_Weight"*wf,0),"ULD_Max_Volume"=round("ULD_Max_Volume"*vf,2) where "Carrier_IATA"=new."Carrier_IATA";
end if;return new;
end $$;
revoke all on function private.convert_carrier_ulds() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
