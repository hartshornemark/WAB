begin;

alter table "Basic_Carrier_Record"."Flight_Schedule_Imports"
  add column "Source_Carrier_IATA" varchar(2);

update "Basic_Carrier_Record"."Flight_Schedule_Imports"
set "Source_Carrier_IATA"="Carrier_IATA"
where "Source_Carrier_IATA" is null;

alter table "Basic_Carrier_Record"."Flight_Schedule_Imports"
  alter column "Source_Carrier_IATA" set not null,
  add constraint "flight_schedule_source_carrier_check"
    check ("Source_Carrier_IATA"="Carrier_IATA");

drop function "Basic_Carrier_Record".create_ssim_schedule_import(text,text,text,bigint,text,text,text,text);

create function "Basic_Carrier_Record".create_ssim_schedule_import(
  p_iata text,
  p_source_carrier_iata text,
  p_file_name text,
  p_file_sha256 text,
  p_file_size_bytes bigint,
  p_source_encoding text default 'UTF-8',
  p_ssim_edition text default null,
  p_season_code text default null,
  p_creator_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare new_id uuid;
begin
  p_iata:=upper(btrim(p_iata));
  p_source_carrier_iata:=upper(btrim(p_source_carrier_iata));
  p_file_name:=btrim(p_file_name);
  p_file_sha256:=lower(btrim(p_file_sha256));
  p_source_encoding:=upper(btrim(p_source_encoding));
  if (select auth.uid()) is null or not (
    private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_IMPORT')
    or private.has_global_permission('FLIGHT_SCHEDULE_IMPORT')
  ) then
    raise exception 'Flight schedule import access denied' using errcode='42501';
  end if;
  if not exists (
    select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact"
    where "Carrier_IATA"=p_iata
  ) then
    raise exception 'Carrier not found' using errcode='23503';
  end if;
  if p_file_name='' or char_length(p_file_name)>255 or p_file_name ~ '[[:cntrl:]]'
    or p_source_carrier_iata<>p_iata
    or p_file_sha256 !~ '^[0-9a-f]{64}$' or p_file_size_bytes<=0
    or p_source_encoding not in ('UTF-8','ISO-8859-1','WINDOWS-1252') then
    raise exception 'Invalid SSIM file metadata or source carrier' using errcode='22023';
  end if;
  insert into "Basic_Carrier_Record"."Flight_Schedule_Imports"(
    "Carrier_IATA","Source_Carrier_IATA","Original_File_Name","File_SHA256","File_Size_Bytes",
    "Source_Encoding","SSIM_Edition","Season_Code","Creator_Reference","Uploaded_By"
  ) values (
    p_iata,p_source_carrier_iata,p_file_name,p_file_sha256,p_file_size_bytes,p_source_encoding,
    nullif(btrim(p_ssim_edition),''),nullif(upper(btrim(p_season_code)),''),
    nullif(btrim(p_creator_reference),''),auth.uid()
  ) returning "Import_ID" into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'This SSIM file has already been uploaded for carrier %',p_iata using errcode='23505';
end;
$$;

revoke all on function "Basic_Carrier_Record".create_ssim_schedule_import(text,text,text,text,bigint,text,text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".create_ssim_schedule_import(text,text,text,text,bigint,text,text,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
