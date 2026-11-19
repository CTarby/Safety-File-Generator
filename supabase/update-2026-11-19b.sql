-- =====================================================================
-- Update 19 November 2026 (b): saved companies, contractors and people
-- Run once in Supabase: SQL Editor > New query > paste > Run.
-- Run it AFTER update-2026-11-19.sql. Safe to run more than once.
-- (Already included at the end of schema.sql for new installations.)
--
-- Active staff can read and add to the saved list. Only an administrator
-- can delete a whole saved company. Every change is written to the audit log.
-- =====================================================================
create table if not exists public.directory (
  k          text primary key,
  kind       text not null check (kind in ('company', 'contractor')),
  name       text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

alter table public.directory enable row level security;

drop policy if exists directory_read   on public.directory;
drop policy if exists directory_insert on public.directory;
drop policy if exists directory_update on public.directory;
drop policy if exists directory_delete on public.directory;
create policy directory_read   on public.directory for select to authenticated using (public.is_active());
create policy directory_insert on public.directory for insert to authenticated with check (public.is_active());
create policy directory_update on public.directory for update to authenticated using (public.is_active()) with check (public.is_active());
create policy directory_delete on public.directory for delete to authenticated using (public.is_admin());

create or replace function public.directory_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;
drop trigger if exists directory_guard on public.directory;
create trigger directory_guard before insert or update on public.directory
  for each row execute function public.directory_guard();

create or replace function public.directory_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.directory;
begin
  r := coalesce(new, old);
  perform public.audit(case tg_op when 'DELETE' then 'saved_company_deleted' else 'saved_company_changed' end,
    jsonb_build_object('kind', r.kind, 'name', r.name,
      'people', coalesce(jsonb_array_length(case when jsonb_typeof(r.data->'people') = 'array' then r.data->'people' end), 0)));
  return null;
end $$;
drop trigger if exists directory_audit on public.directory;
create trigger directory_audit after insert or update or delete on public.directory
  for each row execute function public.directory_audit();

revoke all on public.directory from anon;
