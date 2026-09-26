-- Permit standalone Standard Weight per Bag records while retaining legacy safeguards.
alter table "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"
  drop constraint baggage_unset_only_baseline,
  add constraint baggage_unset_requires_baseline_or_standard_piece check (
    "Per_Passenger_Method" <> 'UNSET'
    or ("Class_Code" is null and "Flight_Type_Variation" is null and "Passenger_Category" = 'ALL')
    or ("Per_Piece_Method" = 'STANDARD'
        and "Baggage_Weight_Per_Piece" is not null
        and "Baggage_Weight_Per_Piece" >= 0)
  );
comment on column "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"."Per_Passenger_Method"
  is 'Legacy per-passenger method. UNSET is permitted for the baseline or a record with a valid Standard Weight per Bag. STANDARD requires a numeric per-passenger value.';
