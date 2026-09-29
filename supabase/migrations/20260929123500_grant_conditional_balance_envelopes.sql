begin;
grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" to authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" to authenticated;
commit;
