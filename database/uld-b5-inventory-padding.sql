-- Approved and applied on 18 September 2026: enforce five-digit ULD inventory serials.
begin;
create or replace function private.normalise_uld_inventory_serials() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  new."ULD_Serial_Start":=lpad(new."ULD_Serial_Start",5,'0');
  new."ULD_Serial_End":=lpad(new."ULD_Serial_End",5,'0');
  return new;
end $$;
revoke all on function private.normalise_uld_inventory_serials() from public,anon,authenticated;
create trigger normalise_uld_inventory_serials before insert or update of "ULD_Serial_Start","ULD_Serial_End"
on "Basic_Carrier_Record"."Carrier_ULD_Inventory" for each row execute function private.normalise_uld_inventory_serials();
update "Basic_Carrier_Record"."Carrier_ULD_Inventory"
set "ULD_Serial_Start"=lpad("ULD_Serial_Start",5,'0'),"ULD_Serial_End"=lpad("ULD_Serial_End",5,'0')
where char_length("ULD_Serial_Start")<5 or char_length("ULD_Serial_End")<5;
notify pgrst,'reload schema';
commit;
