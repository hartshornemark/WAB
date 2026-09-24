begin;

create or replace function private.c7_points_valid(p_points jsonb,p_maximum integer)
returns boolean language sql immutable set search_path='' as $$
  select jsonb_typeof(p_points)='array' and (
    jsonb_array_length(p_points)=0 or (
      not exists(
        select 1 from jsonb_to_recordset(p_points) as x(weight numeric,"indexValue" numeric,"macValue" numeric)
        where weight is null or weight<=0 or weight<>trunc(weight)
           or (p_maximum is not null and weight>p_maximum)
           or ("indexValue" is null and "macValue" is null)
           or ("indexValue" is not null and abs("indexValue")>1000000000)
           or ("macValue" is not null and "macValue" not between 0 and 100)
      )
      and (select count(*)=count(distinct weight) from jsonb_to_recordset(p_points) as x(weight numeric))
    )
  );
$$;

revoke all on function private.c7_points_valid(jsonb,integer) from public,anon;
grant execute on function private.c7_points_valid(jsonb,integer) to authenticated;

notify pgrst,'reload schema';
commit;
