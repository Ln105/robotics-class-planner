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
  created_at timestamptz not null default now()
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

do $$ begin
  alter publication supabase_realtime add table public.planner_sessions;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.planner_session_images;
exception when duplicate_object then null; end $$;

-- Create your one admin in Authentication > Users, then run this once with
-- the UUID shown for that user:
-- insert into public.admin_users (user_id) values ('PASTE_AUTH_USER_UUID_HERE');
