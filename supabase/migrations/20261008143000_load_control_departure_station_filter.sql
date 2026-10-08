begin;

do $$
declare
  definition text;
begin
  select pg_get_functiondef('"Basic_Carrier_Record".get_daily_load_control_board(text,date,text)'::regprocedure)
  into definition;

  definition:=replace(
    definition,
    'and (airport is null or airport in(l."Departure_Airport_IATA",l."Arrival_Airport_IATA"))',
    'and (airport is null or airport=l."Departure_Airport_IATA")'
  );
  definition:=replace(
    definition,
    'and (airport is null or airport in(f."Departure_Airport_IATA",f."Arrival_Airport_IATA"))',
    'and (airport is null or airport=f."Departure_Airport_IATA")'
  );

  execute definition;
end;
$$;

commit;
