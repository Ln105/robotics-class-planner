-- Run this once in Supabase: SQL Editor > New query.
-- After creating the administrator in Authentication > Users, follow the
-- comment at the end to grant that one user editor permission.

create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.planner_weeks (
  id uuid primary key default gen_random_uuid(),
  month_index smallint not null check (month_index between 0 and 11),
  week_index smallint not null check (week_index between 0 and 5),
  objective text not null default '',
  class_details text not null default '',
  project text not null default '',
  notes text not null default '',
  start_date date not null,
  end_date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (month_index, week_index)
);

create table if not exists public.planner_images (
  id uuid primary key default gen_random_uuid(),
  month_index smallint not null check (month_index between 0 and 11),
  week_index smallint not null check (week_index between 0 and 5),
  storage_path text not null unique,
  file_name text not null,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  constraint planner_images_week_fk foreign key (month_index, week_index)
    references public.planner_weeks (month_index, week_index)
    on update cascade on delete cascade
);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists planner_weeks_updated_at on public.planner_weeks;
create trigger planner_weeks_updated_at
before update on public.planner_weeks
for each row execute function public.set_updated_at();

-- Security-definer avoids exposing the administrator list to browser clients.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

alter table public.admin_users enable row level security;
alter table public.planner_weeks enable row level security;
alter table public.planner_images enable row level security;

-- No browser role can enumerate or alter administrator records.
drop policy if exists "admin users inaccessible" on public.admin_users;
create policy "admin users inaccessible" on public.admin_users for all using (false) with check (false);

drop policy if exists "public can view published weeks" on public.planner_weeks;
create policy "public can view published weeks" on public.planner_weeks
  for select using (true);
drop policy if exists "admin can create weeks" on public.planner_weeks;
create policy "admin can create weeks" on public.planner_weeks
  for insert to authenticated with check (public.is_admin());
drop policy if exists "admin can update weeks" on public.planner_weeks;
create policy "admin can update weeks" on public.planner_weeks
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin can delete weeks" on public.planner_weeks;
create policy "admin can delete weeks" on public.planner_weeks
  for delete to authenticated using (public.is_admin());

drop policy if exists "public can view planner images" on public.planner_images;
create policy "public can view planner images" on public.planner_images
  for select using (true);
drop policy if exists "admin can add planner images" on public.planner_images;
create policy "admin can add planner images" on public.planner_images
  for insert to authenticated with check (public.is_admin());
drop policy if exists "admin can update planner images" on public.planner_images;
create policy "admin can update planner images" on public.planner_images
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin can delete planner images" on public.planner_images;
create policy "admin can delete planner images" on public.planner_images
  for delete to authenticated using (public.is_admin());

-- Public read-only photo delivery; writes remain protected by policies below.
insert into storage.buckets (id, name, public)
values ('planner-photos', 'planner-photos', true)
on conflict (id) do update set public = true;

drop policy if exists "public can view planner photo files" on storage.objects;
create policy "public can view planner photo files" on storage.objects
  for select using (bucket_id = 'planner-photos');
drop policy if exists "admin can upload planner photo files" on storage.objects;
create policy "admin can upload planner photo files" on storage.objects
  for insert to authenticated with check (bucket_id = 'planner-photos' and public.is_admin());
drop policy if exists "admin can update planner photo files" on storage.objects;
create policy "admin can update planner photo files" on storage.objects
  for update to authenticated using (bucket_id = 'planner-photos' and public.is_admin()) with check (bucket_id = 'planner-photos' and public.is_admin());
drop policy if exists "admin can delete planner photo files" on storage.objects;
create policy "admin can delete planner photo files" on storage.objects
  for delete to authenticated using (bucket_id = 'planner-photos' and public.is_admin());

-- Live updates are optional but let open viewer pages refresh immediately after
-- an administrator saves a week or photo. Duplicate-table errors are ignored.
do $$ begin
  alter publication supabase_realtime add table public.planner_weeks;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.planner_images;
exception when duplicate_object then null; end $$;

-- Session/day records are additive and leave all existing weekly data intact.
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
    select count(*) from public.planner_session_images
    where session_id = new.session_id and id <> new.id
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
create policy "public can view planner sessions" on public.planner_sessions for select using (true);
drop policy if exists "admin can create planner sessions" on public.planner_sessions;
create policy "admin can create planner sessions" on public.planner_sessions for insert to authenticated with check (public.is_admin());
drop policy if exists "admin can update planner sessions" on public.planner_sessions;
create policy "admin can update planner sessions" on public.planner_sessions for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin can delete planner sessions" on public.planner_sessions;
create policy "admin can delete planner sessions" on public.planner_sessions for delete to authenticated using (public.is_admin());

drop policy if exists "public can view planner session images" on public.planner_session_images;
create policy "public can view planner session images" on public.planner_session_images for select using (true);
drop policy if exists "admin can add planner session images" on public.planner_session_images;
create policy "admin can add planner session images" on public.planner_session_images for insert to authenticated with check (public.is_admin());
drop policy if exists "admin can update planner session images" on public.planner_session_images;
create policy "admin can update planner session images" on public.planner_session_images for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin can delete planner session images" on public.planner_session_images;
create policy "admin can delete planner session images" on public.planner_session_images for delete to authenticated using (public.is_admin());

grant select on public.planner_sessions, public.planner_session_images to anon, authenticated;
grant insert, update, delete on public.planner_sessions, public.planner_session_images to authenticated;

-- Tracks photo files until the authenticated browser confirms Storage cleanup.
-- This makes a temporary Storage failure recoverable instead of leaving an
-- untracked file after its database record has been cascade-deleted.
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

-- Delete exactly one week and compact later week numbers in the same transaction.
-- SECURITY INVOKER keeps every delete/update subject to the caller's RLS policies.
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

do $$ begin
  alter publication supabase_realtime add table public.planner_sessions;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.planner_session_images;
exception when duplicate_object then null; end $$;

-- Create your one admin in Authentication > Users, then run this once with
-- the UUID shown for that user:
-- insert into public.admin_users (user_id) values ('PASTE_AUTH_USER_UUID_HERE');
