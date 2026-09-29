begin;
create function private.c5_recalculate_conditional_envelopes() returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if new."Balance_Envelope_Input_Mode" is distinct from old."Balance_Envelope_Input_Mode" then
    if new."Balance_Envelope_Input_Mode"='INDEX' then
      update "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value" where "Carrier_IATA"=new."Carrier_IATA" and "Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype";
    else
      update "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" set "Envelope_Limit_MAC_Value"="Envelope_Limit_MAC_Value" where "Carrier_IATA"=new."Carrier_IATA" and "Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype";
    end if;
  end if;
  return new;
end $$;
create trigger "c5_recalculate_conditional_envelopes" after update of "Balance_Envelope_Input_Mode" on "Basic_Carrier_Record"."Basic_Aircraft_Data" for each row execute function private.c5_recalculate_conditional_envelopes();
commit;
