begin;

create function "Basic_Carrier_Record".save_manual_schedule_itinerary(p_iata text,p_import_id uuid,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb;result jsonb;leg_ids jsonb:='[]'::jsonb;position integer:=0;first_item jsonb;previous_arrival text;
begin
 p_iata:=upper(btrim(p_iata));
 if jsonb_typeof(p_values)<>'array' or jsonb_array_length(p_values) not between 1 and 20 then raise exception 'Enter between 1 and 20 itinerary segments' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_values) loop
  position:=position+1;
  if position=1 then first_item:=item;
  else
   if upper(btrim(item->>'departureAirport'))<>previous_arrival then raise exception 'Each itinerary segment must depart from the preceding arrival airport' using errcode='22023';end if;
   if (item->>'airlineDesignator',item->>'flightNumber',coalesce(item->>'operationalSuffix',''),item->>'itineraryVariation',item->>'serviceType',item->>'periodStart',item->>'periodEnd',item->>'operatingDays',item->>'aircraftType',item->>'aircraftSubtype',coalesce(item->>'aircraftConfiguration',''))
      is distinct from
      (first_item->>'airlineDesignator',first_item->>'flightNumber',coalesce(first_item->>'operationalSuffix',''),first_item->>'itineraryVariation',first_item->>'serviceType',first_item->>'periodStart',first_item->>'periodEnd',first_item->>'operatingDays',first_item->>'aircraftType',first_item->>'aircraftSubtype',coalesce(first_item->>'aircraftConfiguration','')) then raise exception 'Every itinerary segment must use the same flight, operating period and aircraft configuration' using errcode='22023';end if;
  end if;
  if coalesce((item->>'legSequence')::integer,0)<>position then raise exception 'Itinerary segments must be in consecutive order' using errcode='22023';end if;
  result:="Basic_Carrier_Record".save_manual_schedule_leg(p_iata,p_import_id,null,item);
  leg_ids:=leg_ids||jsonb_build_array(result->>'scheduleLegId');
  previous_arrival:=upper(btrim(item->>'arrivalAirport'));
 end loop;
 return jsonb_build_object('importId',p_import_id,'scheduleLegIds',leg_ids,'status','VALIDATED');
end $$;

revoke all on function "Basic_Carrier_Record".save_manual_schedule_itinerary(text,uuid,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_manual_schedule_itinerary(text,uuid,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
