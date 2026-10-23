-- Read-only verification of the previously frozen physical occupancy and volumes.
select jsonb_build_object(
 'capturedAt',clock_timestamp(),
 'masterVolumes',(select jsonb_agg(jsonb_build_object('ULD_ID',"ULD_ID",'ULD_Volume',"ULD_Volume")) from "Basic_Carrier_Record"."MASTER_ULD_List" where "ULD_ID" in ('AKE','PAG')),
 'occupancy',(select jsonb_agg(jsonb_build_object('positionId',p."ULD_Position_UUID",'bays',
   (select jsonb_agg(p."Hold_Name_ID"||':'||o."Atomic_Bay_ID" order by o."Atomic_Bay_ID") from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" o where o."ULD_Position_UUID"=p."ULD_Position_UUID")) order by p."ULD_Position_UUID")
   from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"='ZZ' and p."Aircraft_Type_IATA"='359' and p."Aircraft_Series_Subtype"='900' and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Code") in('AKE','PAG'))
) verification;
