-- =====================================================================
-- AI assistant: usage log and daily limit
-- Run once in Supabase: SQL Editor > New query > paste > Run.
-- (Already included at the end of schema.sql for new installations.)
-- =====================================================================
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

-- A request that fails (AI error or time-out) does not use up the person's allowance
create or replace function public.ai_refund(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.ai_usage set counted = false
   where id = p_id and user_id = auth.uid() and input_tokens is null;
end $$;

create or replace function public.ai_end(p_id bigint, p_in integer, p_out integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.ai_usage set input_tokens = p_in, output_tokens = p_out
   where id = p_id and user_id = auth.uid();
end $$;

revoke execute on function public.ai_begin(text) from anon;
revoke execute on function public.ai_left() from anon;
revoke execute on function public.ai_refund(bigint) from anon;
revoke execute on function public.ai_end(bigint, integer, integer) from anon;
