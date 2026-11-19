-- =====================================================================
-- Update 19 November 2026: Word download permission and export logging
-- Run once in Supabase: SQL Editor > New query > paste > Run.
-- Run it AFTER ai.sql. Safe to run more than once.
-- (Already included at the end of schema.sql for new installations.)
-- =====================================================================
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
