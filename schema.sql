-- ============================================================================
-- Berbers Review — Supabase schema
-- Wordt via migrations beheerd. Zie ook Supabase Dashboard > Database > Migrations.
-- Deze file is enkel voor referentie / herhaalbaarheid op een ander project.
-- ============================================================================

-- 1. PARTICIPANTS
create table if not exists public.participants (
  id uuid primary key,
  session_id uuid not null,
  name text not null,
  email text,
  user_agent text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

-- 2. RESPONSES
create table if not exists public.responses (
  id bigserial primary key,
  participant_id uuid not null references public.participants(id) on delete cascade,
  session_id uuid not null,
  niveau text not null,
  word_idx int not null,
  nederlands text not null,
  primair text,
  thema text,
  status text not null check (status in ('primair','alternatief','eigen','open')),
  waarde text,
  is_edit boolean default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Eén rij per (deelnemer, niveau, woord) — edits zijn upserts, niet nieuwe rijen.
create unique index if not exists responses_unique_participant_word
  on public.responses(participant_id, niveau, word_idx);

create index if not exists responses_participant_idx on public.responses(participant_id);
create index if not exists responses_niveau_idx on public.responses(niveau);
create index if not exists responses_status_idx on public.responses(status);
create index if not exists responses_created_idx on public.responses(created_at desc);

-- ============================================================================
-- Row Level Security met basale validatie
-- - anon mag INSERT + UPDATE (met length/constraint checks tegen spam)
-- - alleen ingelogde users mogen SELECT (admin-dashboard)
-- ============================================================================

alter table public.participants enable row level security;
alter table public.responses   enable row level security;

drop policy if exists "public insert participants" on public.participants;
create policy "public insert participants"
  on public.participants for insert to anon, authenticated
  with check (
    length(name) between 1 and 200
    and (email is null or length(email) <= 320)
    and session_id is not null
  );

drop policy if exists "public upsert participants" on public.participants;
create policy "public upsert participants"
  on public.participants for update to anon, authenticated
  using (true)
  with check (
    length(name) between 1 and 200
    and (email is null or length(email) <= 320)
  );

drop policy if exists "public insert responses" on public.responses;
create policy "public insert responses"
  on public.responses for insert to anon, authenticated
  with check (
    length(niveau) between 1 and 50
    and length(nederlands) between 1 and 500
    and (waarde is null or length(waarde) <= 500)
    and word_idx >= 0 and word_idx < 5000
  );

drop policy if exists "auth read participants" on public.participants;
create policy "auth read participants"
  on public.participants for select to authenticated
  using (true);

drop policy if exists "auth read responses" on public.responses;
create policy "auth read responses"
  on public.responses for select to authenticated
  using (true);

-- admin (authenticated) mag rijen verwijderen (voor opschonen van testdata etc.)
drop policy if exists "auth delete participants" on public.participants;
create policy "auth delete participants"
  on public.participants for delete to authenticated
  using (true);

drop policy if exists "auth delete responses" on public.responses;
create policy "auth delete responses"
  on public.responses for delete to authenticated
  using (true);

-- ============================================================================
-- RPC's voor inserts (SECURITY DEFINER = omzeilt RLS, anon mag EXECUTE).
-- Zo kan anon schrijven zonder SELECT-permissies te hebben, en valideren we
-- extra strict server-side (lengtes, geldige status, participant bestaat).
-- ============================================================================

-- record_participant: idempotente upsert
create or replace function public.record_participant(
  p_id uuid, p_session_id uuid, p_name text, p_email text, p_user_agent text
) returns void language plpgsql security definer set search_path = 'public' as $$
begin
  if p_id is null or p_session_id is null then raise exception 'missing id or session_id'; end if;
  if p_name is null or length(trim(p_name)) < 1 or length(p_name) > 200 then raise exception 'invalid name'; end if;
  if p_email is not null and length(p_email) > 320 then raise exception 'invalid email'; end if;
  insert into public.participants (id, session_id, name, email, user_agent)
  values (p_id, p_session_id, p_name, p_email, p_user_agent)
  on conflict (id) do update
    set name = excluded.name,
        email = excluded.email,
        user_agent = excluded.user_agent;
end; $$;
grant execute on function public.record_participant(uuid, uuid, text, text, text) to anon, authenticated;

-- record_response: upsert op (participant_id, niveau, word_idx). Bij edit wordt
-- de bestaande rij bijgewerkt (is_edit = true, updated_at = now()). Zo is er
-- altijd precies één rij per (deelnemer, woord) — geen dubbele CSV-regels meer.
create or replace function public.record_response(
  p_participant_id uuid, p_session_id uuid, p_niveau text, p_word_idx integer,
  p_nederlands text, p_primair text, p_thema text, p_status text,
  p_waarde text, p_is_edit boolean
) returns void language plpgsql security definer set search_path = 'public' as $$
begin
  if p_participant_id is null then raise exception 'missing participant_id'; end if;
  if not exists (select 1 from public.participants where id = p_participant_id) then
    raise exception 'unknown participant';
  end if;
  if p_status not in ('primair','alternatief','eigen','open') then raise exception 'invalid status'; end if;
  if p_niveau is null or length(p_niveau) < 1 or length(p_niveau) > 50 then raise exception 'invalid niveau'; end if;
  if p_nederlands is null or length(p_nederlands) < 1 or length(p_nederlands) > 500 then raise exception 'invalid nederlands'; end if;
  if p_waarde is not null and length(p_waarde) > 500 then raise exception 'invalid waarde'; end if;
  if p_word_idx is null or p_word_idx < 0 or p_word_idx >= 5000 then raise exception 'invalid word_idx'; end if;

  insert into public.responses (participant_id, session_id, niveau, word_idx, nederlands, primair, thema, status, waarde, is_edit, updated_at)
  values (p_participant_id, p_session_id, p_niveau, p_word_idx, p_nederlands, p_primair, p_thema, p_status, p_waarde, coalesce(p_is_edit, false), now())
  on conflict (participant_id, niveau, word_idx) do update
    set session_id = excluded.session_id,
        nederlands = excluded.nederlands,
        primair = excluded.primair,
        thema = excluded.thema,
        status = excluded.status,
        waarde = excluded.waarde,
        is_edit = true,
        updated_at = now();
end; $$;
grant execute on function public.record_response(uuid, uuid, text, integer, text, text, text, text, text, boolean) to anon, authenticated;

-- withdraw_response: verwijder een antwoord (gebruikt bij "Terug in de lijst").
-- Anon mag dit alleen voor z'n eigen participant_id + session_id combo.
create or replace function public.withdraw_response(
  p_participant_id uuid, p_session_id uuid, p_niveau text, p_word_idx integer
) returns void language plpgsql security definer set search_path = 'public' as $$
begin
  if p_participant_id is null or p_session_id is null then raise exception 'missing id'; end if;
  if not exists (
    select 1 from public.participants where id = p_participant_id and session_id = p_session_id
  ) then
    raise exception 'invalid credentials';
  end if;
  delete from public.responses
  where participant_id = p_participant_id
    and niveau = p_niveau
    and word_idx = p_word_idx;
end; $$;
grant execute on function public.withdraw_response(uuid, uuid, text, integer) to anon, authenticated;

-- get_my_responses: deelnemer haalt z'n eigen antwoorden op (voor sync bij opstart,
-- zodat admin-wijzigingen zichtbaar worden voor de user). Vereist kennis van
-- zowel id als session_id (beide lokaal in localStorage).
create or replace function public.get_my_responses(
  p_id uuid, p_session_id uuid
) returns table (
  niveau text, word_idx integer, status text, waarde text, is_edit boolean, updated_at timestamptz
) language plpgsql security definer set search_path = 'public' as $$
begin
  if p_id is null or p_session_id is null then raise exception 'missing id'; end if;
  if not exists (
    select 1 from public.participants where id = p_id and session_id = p_session_id
  ) then
    raise exception 'invalid credentials';
  end if;
  return query
    select r.niveau, r.word_idx, r.status, r.waarde, r.is_edit, r.updated_at
    from public.responses r
    where r.participant_id = p_id;
end; $$;
grant execute on function public.get_my_responses(uuid, uuid) to anon, authenticated;

-- mark_participant_done: zet completed_at op now()
create or replace function public.mark_participant_done(p_id uuid)
returns void language plpgsql security definer set search_path = 'public' as $$
begin
  if p_id is null then raise exception 'missing id'; end if;
  update public.participants set completed_at = now() where id = p_id;
  if not found then raise exception 'unknown participant'; end if;
end; $$;
grant execute on function public.mark_participant_done(uuid) to anon, authenticated;
