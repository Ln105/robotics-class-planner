-- Safe, additive migration for session/day records.
-- This does not alter or delete existing weeks, weekly text, or weekly photos.

begin;

create table if not exists public.planner_sessions (
  id uuid primary key default gen_random_uuid(),
  month_index smallint not null check (month_index between 0 and 11),
  week_index smallint not null check (week_index between 0 and 5),
  session_date date not null,
  activity text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (month_index, week_index, session_date),
  foreign key (month_index, week_index)
    references public.planner_weeks (month_index, week_index)
    on update cascade on delete cascade
);

create table if not exists public.planner_session_images (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.planner_sessions(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  sort_order smallint not null default 0 check (sort_order between 0 and 1),
  created_at timestamptz not null default now()
);

drop trigger if exists planner_sessions_updated_at on public.planner_sessions;
create trigger planner_sessions_updated_at
before update on public.planner_sessions
for each row execute function public.set_updated_at();

create or replace function public.enforce_session_image_limit()
returns trigger language plpgsql set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.session_id::text, 0));
  if (
    select count(*)
    from public.planner_session_images
    where session_id = new.session_id
      and id <> new.id
  ) >= 2 then
    raise exception 'A session can contain at most 2 images.';
  end if;
  return new;
end;
$$;

drop trigger if exists planner_session_images_limit on public.planner_session_images;
create trigger planner_session_images_limit
before insert or update of session_id on public.planner_session_images
for each row execute function public.enforce_session_image_limit();

alter table public.planner_sessions enable row level security;
alter table public.planner_session_images enable row level security;

drop policy if exists "public can view planner sessions" on public.planner_sessions;
create policy "public can view planner sessions" on public.planner_sessions
  for select using (true);
drop policy if exists "admin can create planner sessions" on public.planner_sessions;
create policy "admin can create planner sessions" on public.planner_sessions
  for insert to authenticated with check (public.is_admin());
drop policy if exists "admin can update planner sessions" on public.planner_sessions;
create policy "admin can update planner sessions" on public.planner_sessions
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin can delete planner sessions" on public.planner_sessions;
create policy "admin can delete planner sessions" on public.planner_sessions
  for delete to authenticated using (public.is_admin());

drop policy if exists "public can view planner session images" on public.planner_session_images;
create policy "public can view planner session images" on public.planner_session_images
  for select using (true);
drop policy if exists "admin can add planner session images" on public.planner_session_images;
create policy "admin can add planner session images" on public.planner_session_images
  for insert to authenticated with check (public.is_admin());
drop policy if exists "admin can update planner session images" on public.planner_session_images;
create policy "admin can update planner session images" on public.planner_session_images
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin can delete planner session images" on public.planner_session_images;
create policy "admin can delete planner session images" on public.planner_session_images
  for delete to authenticated using (public.is_admin());

grant select on public.planner_sessions, public.planner_session_images to anon, authenticated;
grant insert, update, delete on public.planner_sessions, public.planner_session_images to authenticated;

-- The existing planner-photos bucket policies already allow public reads and
-- restrict all Storage writes to public.is_admin(). Session files use the
-- sessions/<session-id>/ path inside that same protected bucket.

do $$ begin
  alter publication supabase_realtime add table public.planner_sessions;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.planner_session_images;
exception when duplicate_object then null; end $$;

commit;
