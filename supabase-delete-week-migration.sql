-- Safe, non-destructive schema migration for the Delete Week feature.
-- Run once in Supabase SQL Editor before publishing the matching website files.
-- This migration does not delete or modify any existing planner content.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'planner_images_week_fk'
      and conrelid = 'public.planner_images'::regclass
  ) then
    alter table public.planner_images
      add constraint planner_images_week_fk
      foreign key (month_index, week_index)
      references public.planner_weeks (month_index, week_index)
      on update cascade on delete cascade
      not valid;
  end if;
end
$$;

alter table public.planner_images
  validate constraint planner_images_week_fk;

create table if not exists public.planner_storage_cleanup (
  storage_path text primary key,
  created_at timestamptz not null default now()
);

alter table public.planner_storage_cleanup enable row level security;

drop policy if exists "admin can view pending storage cleanup" on public.planner_storage_cleanup;
create policy "admin can view pending storage cleanup" on public.planner_storage_cleanup
  for select to authenticated using (public.is_admin());
drop policy if exists "admin can add pending storage cleanup" on public.planner_storage_cleanup;
create policy "admin can add pending storage cleanup" on public.planner_storage_cleanup
  for insert to authenticated with check (public.is_admin());
drop policy if exists "admin can clear pending storage cleanup" on public.planner_storage_cleanup;
create policy "admin can clear pending storage cleanup" on public.planner_storage_cleanup
  for delete to authenticated using (public.is_admin());

grant select, insert, delete on public.planner_storage_cleanup to authenticated;

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
  on conflict (storage_path) do nothing;

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
