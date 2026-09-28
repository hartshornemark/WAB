do $migration$
declare definition text; updated text;
begin
 definition := pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d3(text,text,text)'::regprocedure);
 updated := replace(definition, $old$'id',btrim(h."Hold_Name_ID"),'compartments'$old$, $new$'id',btrim(h."Hold_Name_ID"),'balanceCentroid',h."Hold_BA_Centroid",'compartments'$new$);
 if updated = definition then raise exception 'D3 hold projection did not match'; end if;
 execute updated;
end $migration$;
