begin;

create or replace function "Basic_Carrier_Record".inspect_operational_uld_adoption(p_iata text,p_operational_flight_id uuid,p_uld_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare f "Basic_Carrier_Record"."Operational_Flights"%rowtype;m "Basic_Carrier_Record"."MASTER_ULD_List"%rowtype;compatible_code text;compatible_positions jsonb;
begin
 p_iata:=upper(btrim(p_iata));p_uld_code:=upper(btrim(p_uld_code));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if p_uld_code!~'^[A-Z0-9]{3}$'then raise exception 'Enter a valid ULD code' using errcode='22023';end if;
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
 select*into m from "Basic_Carrier_Record"."MASTER_ULD_List" where btrim("ULD_ID")=p_uld_code;if not found then raise exception 'ULD % is not available in the Master ULD list',p_uld_code using errcode='P0002';end if;
 select btrim(p."ULD_Code"),coalesce(jsonb_agg(jsonb_build_object('holdId',btrim(p."Hold_Name_ID"),'configurationCode',btrim(p."ULD_Configuration_Code"),'positionId',btrim(p."ULD_Position_ID"),'configuredUldCode',btrim(p."ULD_Code"),'maximumWeight',p."ULD_Position_Max_Weight")order by p."Hold_Name_ID",p."ULD_Configuration_Code",p."ULD_Position_ID"),'[]'::jsonb) into compatible_code,compatible_positions from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=f."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and p."ULD_Row_Type"='POSITION' and p."ULD_Base_Code" is not null and p."ULD_Base_Code"=m."ULD_Base_Code" group by p."ULD_Code" order by count(*)desc,btrim(p."ULD_Code") limit 1;
 if compatible_code is null then raise exception 'No configured aircraft ULD bay accepts the % base footprint',coalesce(m."ULD_Base_Code",p_uld_code) using errcode='23514';end if;
 return jsonb_build_object('code',p_uld_code,'type',btrim(m."ULD_Type"),'tareWeight',m."ULD_TARE",'maximumGrossWeight',m."ULD_Max_Gross_Weight",'volume',m."ULD_Volume",'baseCode',m."ULD_Base_Code",'compatibleUldCode',compatible_code,'compatiblePositions',compatible_positions,'status','PENDING');
end;$$;

create or replace function "Basic_Carrier_Record".propose_operational_uld_adoption(p_iata text,p_operational_flight_id uuid,p_uld_code text,p_tare_kg numeric)
returns jsonb language plpgsql security definer set search_path='' as $$
declare f "Basic_Carrier_Record"."Operational_Flights"%rowtype;m "Basic_Carrier_Record"."MASTER_ULD_List"%rowtype;compatible_code text;compatible_positions jsonb;
begin
 p_iata:=upper(btrim(p_iata));p_uld_code:=upper(btrim(p_uld_code));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if p_uld_code!~'^[A-Z0-9]{3}$'or p_tare_kg is null or p_tare_kg<0 or trunc(p_tare_kg)<>p_tare_kg then raise exception 'Enter a valid ULD code and whole-kilogram tare weight' using errcode='22023';end if;
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
 select*into m from "Basic_Carrier_Record"."MASTER_ULD_List" where btrim("ULD_ID")=p_uld_code;
 if not found then raise exception 'ULD % is not available in the Master ULD list',p_uld_code using errcode='P0002';end if;
 if p_tare_kg>m."ULD_Max_Gross_Weight" then raise exception 'Tare weight cannot exceed the Master ULD maximum gross weight' using errcode='23514';end if;
 select btrim(p."ULD_Code"),coalesce(jsonb_agg(jsonb_build_object('holdId',btrim(p."Hold_Name_ID"),'configurationCode',btrim(p."ULD_Configuration_Code"),'positionId',btrim(p."ULD_Position_ID"),'configuredUldCode',btrim(p."ULD_Code"),'maximumWeight',p."ULD_Position_Max_Weight")order by p."Hold_Name_ID",p."ULD_Configuration_Code",p."ULD_Position_ID"),'[]'::jsonb)
 into compatible_code,compatible_positions
 from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
 where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=f."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and p."ULD_Row_Type"='POSITION' and p."ULD_Base_Code" is not null and p."ULD_Base_Code"=m."ULD_Base_Code"
 group by p."ULD_Code" order by count(*)desc,btrim(p."ULD_Code") limit 1;
 if compatible_code is null then raise exception 'No configured aircraft ULD bay accepts the % base footprint',coalesce(m."ULD_Base_Code",p_uld_code) using errcode='23514';end if;
 insert into "Basic_Carrier_Record"."Carrier_ULD_Provisional_Adoptions"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID","Proposed_Tare_KG","Source_Operational_Flight_ID","Status","Proposed_By","Proposed_At","Reviewed_By","Reviewed_At")
 values(p_iata,f."Aircraft_Type_IATA",f."Aircraft_Series_Subtype",p_uld_code,p_tare_kg,p_operational_flight_id,'PENDING',auth.uid(),now(),null,null)
 on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID")do update set "Proposed_Tare_KG"=excluded."Proposed_Tare_KG","Source_Operational_Flight_ID"=excluded."Source_Operational_Flight_ID","Status"='PENDING',"Proposed_By"=auth.uid(),"Proposed_At"=now(),"Reviewed_By"=null,"Reviewed_At"=null;
 return jsonb_build_object('code',p_uld_code,'type',btrim(m."ULD_Type"),'tareWeight',p_tare_kg,'maximumGrossWeight',m."ULD_Max_Gross_Weight",'volume',m."ULD_Volume",'baseCode',m."ULD_Base_Code",'compatibleUldCode',compatible_code,'compatiblePositions',compatible_positions,'status','PENDING');
end;$$;

create or replace function "Basic_Carrier_Record".get_carrier_uld_provisional_adoptions(p_iata text,p_type text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 p_iata:=upper(btrim(p_iata));p_type:=upper(btrim(p_type));p_subtype:=upper(btrim(p_subtype));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW')or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'))then raise exception 'Not authorised' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('code',btrim(a."ULD_ID"),'type',btrim(m."ULD_Type"),'tareKg',a."Proposed_Tare_KG",'maximumGrossWeightKg',m."ULD_Max_Gross_Weight",'volumeM3',m."ULD_Volume",'sourceOperationalFlightId',a."Source_Operational_Flight_ID",'proposedAt',a."Proposed_At")order by a."Proposed_At") from "Basic_Carrier_Record"."Carrier_ULD_Provisional_Adoptions" a join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=a."ULD_ID" where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=p_type and a."Aircraft_Series_Subtype"=p_subtype and a."Status"='PENDING'),'[]'::jsonb);
end;$$;

notify pgrst,'reload schema';

commit;
