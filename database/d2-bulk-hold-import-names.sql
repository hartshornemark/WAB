do $migration$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".save_aircraft_d2(text,text,text,text,text,jsonb)'::regprocedure);updated:=definition;
 updated:=replace(updated,$old$(section_code='BULK' and hold_name !~ '^[A-Z0-9]$')$old$,$new$(section_code='BULK' and hold_name !~ '^[A-Z0-9]{1,3}$')$new$);
 updated:=replace(updated,$old$(section_code='BULK' and (max_volume is null or max_volume<=0)) or (section_code='ULD' and max_volume is not null and max_volume<=0)$old$,$new$(max_volume is not null and max_volume<=0)$new$);
 if updated=definition then raise exception 'save_aircraft_d2 validation rules changed';end if;
 execute updated;
end $migration$;
