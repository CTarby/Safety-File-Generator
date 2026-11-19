-- =====================================================================
-- Site Specific Safety File Generator (online) – Supabase database schema
-- Run once in Supabase: SQL Editor > New query > paste > Run.
-- Every table has row level security (RLS) switched on. Nothing is
-- readable without a signed-in, active user.
-- =====================================================================
create extension if not exists pgcrypto;

-- ---------- Users (one row per login, created automatically) ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  full_name  text,
  role       text not null default 'staff' check (role in ('admin','staff')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select active from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select active and role = 'admin' from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', new.email))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Audit log (who did what, when) ----------
create table if not exists public.audit_log (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  user_id uuid,
  email   text,
  action  text not null,
  detail  jsonb not null default '{}'::jsonb
);

create or replace function public.audit(p_action text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, email, action, detail)
  values (auth.uid(), (select email from public.profiles where id = auth.uid()), p_action, coalesce(p_detail, '{}'::jsonb));
end $$;
revoke all on function public.audit(text, jsonb) from public, anon, authenticated;

-- Called by the app (sign-in, file opened, PDF downloaded, letters created)
create or replace function public.log_event(p_action text, p_detail jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_action not in ('sign_in','sign_out','open_file','download_pdf','create_letters','view_audit','password_changed') then
    raise exception 'unknown action';
  end if;
  perform public.audit(p_action, p_detail);
end $$;

-- ---------- Company files ----------
create table if not exists public.pack_files (
  id         uuid primary key default gen_random_uuid(),
  key        text not null unique,            -- company|site|revision
  owner      uuid not null default auth.uid() references public.profiles(id),
  prefix     text,
  company    text not null,
  site       text,
  rev        text,
  data       jsonb not null,                  -- form, team, generated documents
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create table if not exists public.pack_shares (
  file_id uuid not null references public.pack_files(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (file_id, user_id)
);

create or replace function public.can_open(f uuid, o uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    o = auth.uid() or public.is_admin()
    or exists (select 1 from public.pack_shares s where s.file_id = f and s.user_id = auth.uid()))
$$;

create or replace function public.pack_files_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if not public.is_admin() then new.owner := old.owner; end if;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;
drop trigger if exists pack_files_guard on public.pack_files;
create trigger pack_files_guard before insert or update on public.pack_files
  for each row execute function public.pack_files_guard();

create or replace function public.pack_files_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.pack_files;
begin
  r := coalesce(new, old);
  perform public.audit(case tg_op when 'INSERT' then 'file_created' when 'UPDATE' then 'file_saved' else 'file_deleted' end,
    jsonb_build_object('file', r.id, 'company', r.company, 'site', r.site, 'rev', r.rev));
  return null;
end $$;
drop trigger if exists pack_files_audit on public.pack_files;
create trigger pack_files_audit after insert or update or delete on public.pack_files
  for each row execute function public.pack_files_audit();

create or replace function public.pack_shares_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.pack_shares;
begin
  r := coalesce(new, old);
  perform public.audit(case tg_op when 'INSERT' then 'file_shared' else 'file_unshared' end,
    jsonb_build_object('file', r.file_id, 'user', r.user_id));
  return null;
end $$;
drop trigger if exists pack_shares_audit on public.pack_shares;
create trigger pack_shares_audit after insert or delete on public.pack_shares
  for each row execute function public.pack_shares_audit();

create or replace function public.profiles_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role or new.active is distinct from old.active then
    perform public.audit('user_changed', jsonb_build_object('user', new.id, 'email', new.email, 'role', new.role, 'active', new.active));
  end if;
  return null;
end $$;
drop trigger if exists profiles_audit on public.profiles;
create trigger profiles_audit after update on public.profiles
  for each row execute function public.profiles_audit();

-- ---------- Document numbering (shared, so numbers never clash) ----------
create table if not exists public.numbering (
  prefix     text primary key,
  version    integer not null default 0,
  counters   jsonb not null default '{}'::jsonb,
  fixed      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create or replace function public.get_numbering(p_prefix text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.numbering;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  insert into public.numbering (prefix) values (p_prefix) on conflict (prefix) do nothing;
  select * into r from public.numbering where prefix = p_prefix;
  return jsonb_build_object('version', r.version, 'counters', r.counters, 'fixed', r.fixed);
end $$;

-- Saves numbers only if nobody else issued numbers in the meantime.
-- Staff can move a counter up but never down; only an admin can lower one.
create or replace function public.commit_numbering(p_prefix text, p_base integer, p_counters jsonb, p_fixed jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.numbering; k text; v jsonb; merged jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into r from public.numbering where prefix = p_prefix for update;
  if not found or r.version <> p_base then
    return jsonb_build_object('ok', false);
  end if;
  merged := r.counters;
  for k, v in select * from jsonb_each(coalesce(p_counters, '{}'::jsonb)) loop
    if jsonb_typeof(v) = 'number' then
      if public.is_admin() or not (merged ? k) then
        merged := merged || jsonb_build_object(k, v);
      else
        merged := merged || jsonb_build_object(k, greatest((merged->>k)::numeric, (v#>>'{}')::numeric));
      end if;
    end if;
  end loop;
  update public.numbering
     set version = version + 1, counters = merged,
         fixed = case when public.is_admin() then r.fixed || coalesce(p_fixed, '{}'::jsonb) else coalesce(p_fixed, '{}'::jsonb) || r.fixed end,  -- staff cannot renumber an existing document
         updated_at = now(), updated_by = auth.uid()
   where prefix = p_prefix;
  return jsonb_build_object('ok', true, 'version', r.version + 1, 'counters', merged);
end $$;

-- ---------- Company logo per document prefix (letterhead column is unused) ----------
create table if not exists public.branding (
  prefix     text primary key,
  logo       text,
  letterhead text,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

-- ---------- Row level security ----------
alter table public.profiles    enable row level security;
alter table public.audit_log   enable row level security;
alter table public.pack_files  enable row level security;
alter table public.pack_shares enable row level security;
alter table public.numbering   enable row level security;
alter table public.branding    enable row level security;

drop policy if exists profiles_read  on public.profiles;
drop policy if exists profiles_admin on public.profiles;
create policy profiles_read  on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy profiles_admin on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists audit_read on public.audit_log;
create policy audit_read on public.audit_log for select to authenticated using (public.is_admin());

drop policy if exists files_read   on public.pack_files;
drop policy if exists files_insert on public.pack_files;
drop policy if exists files_update on public.pack_files;
drop policy if exists files_delete on public.pack_files;
create policy files_read   on public.pack_files for select to authenticated using (public.can_open(id, owner));
create policy files_insert on public.pack_files for insert to authenticated with check (public.is_active() and owner = auth.uid());
create policy files_update on public.pack_files for update to authenticated using (public.can_open(id, owner)) with check (public.is_active());
create policy files_delete on public.pack_files for delete to authenticated using (public.is_active() and (owner = auth.uid() or public.is_admin()));

drop policy if exists shares_read  on public.pack_shares;
drop policy if exists shares_admin on public.pack_shares;
create policy shares_read  on public.pack_shares for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy shares_admin on public.pack_shares for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists branding_read  on public.branding;
drop policy if exists branding_write on public.branding;
drop policy if exists branding_edit  on public.branding;
create policy branding_read  on public.branding for select to authenticated using (public.is_active());
create policy branding_write on public.branding for insert to authenticated with check (public.is_active());
create policy branding_edit  on public.branding for update to authenticated using (public.is_active()) with check (public.is_active());
-- numbering has no policies: it is reached only through get_numbering / commit_numbering.

-- Nothing for visitors who are not signed in
revoke all on all tables in schema public from anon;
revoke execute on all functions in schema public from anon;

-- Per-person AI access, switched on by an administrator (administrators always have it)
alter table public.profiles add column if not exists ai_enabled boolean not null default false;
-- Total AI uses allowed for a staff member (administrators have a daily limit instead)
alter table public.profiles add column if not exists ai_quota integer not null default 5;

create or replace function public.ai_allowed() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or coalesce((select active and ai_enabled from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.profiles_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role or new.active is distinct from old.active or new.ai_enabled is distinct from old.ai_enabled or new.ai_quota is distinct from old.ai_quota then
    perform public.audit('user_changed', jsonb_build_object('user', new.id, 'email', new.email, 'role', new.role, 'active', new.active, 'ai', new.ai_enabled, 'ai_allowance', new.ai_quota));
  end if;
  return null;
end $$;

create table if not exists public.ai_usage (
  id            bigserial primary key,
  at            timestamptz not null default now(),
  user_id       uuid not null default auth.uid(),
  task          text not null,
  input_tokens  integer,
  output_tokens integer
);
alter table public.ai_usage add column if not exists counted boolean not null default true;
alter table public.ai_usage enable row level security;
drop policy if exists ai_usage_read on public.ai_usage;
create policy ai_usage_read on public.ai_usage for select to authenticated using (public.is_admin());

-- Called by the ai-assist function before every AI request.
-- Checks the person is signed in, active and switched on for AI, applies their allowance,
-- records the request in the activity log, and returns a usage id.
create or replace function public.ai_begin(p_task text) returns bigint
language plpgsql security definer set search_path = public as $$
declare n integer; i bigint; q integer; c boolean := true;
  admin_limit constant integer := 40;   -- AI uses per administrator per 24 hours
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.ai_allowed() then raise exception 'AI not enabled for this user'; end if;
  if p_task not in ('read_spec','annex','gap_check','improve_doc','analyse_scope','she_plan') then raise exception 'unknown task'; end if;
  -- Writing the SHE plan after a scope analysis is part of the same use (up to 3 times within 24 hours)
  if p_task = 'she_plan'
     and exists (select 1 from public.ai_usage where user_id = auth.uid() and task = 'analyse_scope' and at > now() - interval '24 hours')
     and (select count(*) from public.ai_usage where user_id = auth.uid() and task = 'she_plan' and not counted and at > now() - interval '24 hours') < 3 then
    c := false;
  end if;
  if public.is_admin() then
    select count(*) into n from public.ai_usage where user_id = auth.uid() and at > now() - interval '24 hours';
    if n >= admin_limit then raise exception 'daily AI limit reached'; end if;
  elsif c then
    select ai_quota into q from public.profiles where id = auth.uid();
    select count(*) into n from public.ai_usage where user_id = auth.uid() and counted;
    if n >= coalesce(q, 0) then raise exception 'AI allowance used'; end if;
  end if;
  insert into public.ai_usage (user_id, task, counted) values (auth.uid(), p_task, c) returning id into i;
  perform public.audit('ai_request', jsonb_build_object('task', p_task, 'counted', c));
  return i;
end $$;

-- How many AI uses the signed-in person has left (null = administrator, daily limit applies)
create or replace function public.ai_left() returns integer
language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then null
              else greatest(0, coalesce((select ai_quota from public.profiles where id = auth.uid()), 0)
                    - (select count(*)::integer from public.ai_usage where user_id = auth.uid() and counted)) end
$$;

create or replace function public.ai_end(p_id bigint, p_in integer, p_out integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.ai_usage set input_tokens = p_in, output_tokens = p_out
   where id = p_id and user_id = auth.uid();
end $$;

revoke execute on function public.ai_begin(text) from anon;
revoke execute on function public.ai_left() from anon;
revoke execute on function public.ai_end(bigint, integer, integer) from anon;

-- ---------- Word download permission and export logging ----------
alter table public.profiles add column if not exists word_enabled boolean not null default false;

create or replace function public.profiles_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role or new.active is distinct from old.active
     or new.ai_enabled is distinct from old.ai_enabled or new.ai_quota is distinct from old.ai_quota
     or new.word_enabled is distinct from old.word_enabled then
    perform public.audit('user_changed', jsonb_build_object('user', new.id, 'email', new.email, 'role', new.role,
      'active', new.active, 'ai', new.ai_enabled, 'ai_allowance', new.ai_quota, 'word', new.word_enabled));
  end if;
  return null;
end $$;

create or replace function public.log_event(p_action text, p_detail jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_action not in ('sign_in','sign_out','open_file','download_pdf','download_zip','download_word',
                      'create_letters','view_audit','password_changed') then
    raise exception 'unknown action';
  end if;
  perform public.audit(p_action, p_detail);
end $$;

-- ---------- First admin ----------
-- After you have invited yourself and signed in once, run (with your email):
-- update public.profiles set role = 'admin' where email = 'you@yourcompany.co.za';
