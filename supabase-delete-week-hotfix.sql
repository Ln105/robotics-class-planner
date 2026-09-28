-- Replaces only the Delete Week function. Does not delete or modify planner data.
begin;

create or replace function public.delete_planner_week(
  p_month_index smallint,
  p_week_index smallint
)
returns table(storage_path text)
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_paths text[];
  v_next smallint;
begin
  if not public.is_admin() then
    raise exception 'Only the planner administrator can delete weeks.'
      using errcode = '42501';
  end if;

  select coalesce(array_agg(files.path order by files.path), '{}'::text[])
  into v_paths
  from (
    select image.storage_path as path
    from public.planner_images as image
    where image.month_index = p_month_index
      and image.week_index = p_week_index
    union all
    select image.storage_path as path
    from public.planner_session_images as image
    join public.planner_sessions as session on session.id = image.session_id
    where session.month_index = p_month_index
      and session.week_index = p_week_index
  ) as files;

  insert into public.planner_storage_cleanup (storage_path)
  select unnest(v_paths)
  on conflict do nothing;

  delete from public.planner_weeks
  where month_index = p_month_index
    and week_index = p_week_index;

  if not found then
    raise exception 'The selected week does not exist.';
  end if;

  for v_next in
    select week_index
    from public.planner_weeks
    where month_index = p_month_index
      and week_index > p_week_index
    order by week_index
  loop
    update public.planner_weeks
    set week_index = v_next - 1
    where month_index = p_month_index
      and week_index = v_next;
  end loop;

  return query select unnest(v_paths);
end;
$$;

revoke all on function public.delete_planner_week(smallint, smallint) from public;
revoke all on function public.delete_planner_week(smallint, smallint) from anon;
grant execute on function public.delete_planner_week(smallint, smallint) to authenticated;

commit;
