-- The Reader Room by Vibe & Vision Collective
-- Run this entire file once in the Supabase SQL Editor.

create extension if not exists pgcrypto;

create type public.user_role as enum ('admin', 'author', 'reader');
create type public.book_status as enum ('draft', 'active', 'complete', 'archived');
create type public.invitation_status as enum ('pending', 'accepted', 'completed', 'revoked');
create type public.feedback_status as enum ('new', 'consider', 'revise', 'accepted', 'dismissed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  role public.user_role not null default 'reader',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index profiles_email_lower_idx on public.profiles (lower(email));

create table public.author_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  invited_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','revoked')),
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at timestamptz
);

create unique index author_invitations_email_lower_idx on public.author_invitations (lower(email));

create table public.books (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  author_name text not null,
  genre text,
  description text,
  status public.book_status not null default 'draft',
  overall_deadline date,
  manuscript_path text,
  manuscript_filename text,
  current_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.manuscript_versions (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  version_number integer not null,
  storage_path text,
  filename text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(book_id, version_number)
);

create table public.chapters (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  version_number integer not null default 1,
  chapter_number integer not null,
  title text not null,
  content text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(book_id, version_number, chapter_number)
);

create table public.reader_invitations (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  email text not null,
  reader_id uuid references public.profiles(id) on delete set null,
  individual_deadline date,
  status public.invitation_status not null default 'pending',
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  completed_at timestamptz,
  revoked_at timestamptz,
  unique(book_id, email)
);

create table public.reader_agreements (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.reader_invitations(id) on delete cascade,
  reader_id uuid not null references public.profiles(id) on delete cascade,
  agreement_version text not null default '1.0',
  accepted_at timestamptz not null default now(),
  unique(invitation_id, reader_id)
);

create table public.reading_progress (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.reader_invitations(id) on delete cascade,
  chapter_id uuid not null references public.chapters(id) on delete cascade,
  reader_id uuid not null references public.profiles(id) on delete cascade,
  percent integer not null default 0 check (percent between 0 and 100),
  completed boolean not null default false,
  last_opened_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(invitation_id, chapter_id, reader_id)
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  chapter_id uuid not null references public.chapters(id) on delete cascade,
  reader_id uuid not null references public.profiles(id) on delete cascade,
  sentence_index integer,
  quoted_text text,
  comment_text text not null,
  status public.feedback_status not null default 'new',
  author_private_note text,
  author_reply text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.questionnaires (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  chapter_id uuid references public.chapters(id) on delete cascade,
  title text not null,
  is_final boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.questionnaire_questions (
  id uuid primary key default gen_random_uuid(),
  questionnaire_id uuid not null references public.questionnaires(id) on delete cascade,
  position integer not null,
  prompt text not null,
  response_type text not null default 'long_text' check (response_type in ('short_text','long_text','rating','yes_no')),
  required boolean not null default true
);

create table public.questionnaire_responses (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questionnaire_questions(id) on delete cascade,
  reader_id uuid not null references public.profiles(id) on delete cascade,
  response_text text,
  response_number integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(question_id, reader_id)
);

create table public.reminder_settings (
  book_id uuid primary key references public.books(id) on delete cascade,
  days_before integer[] not null default array[7,3,0],
  invitation_subject text not null default 'You are invited to beta read',
  reminder_subject text not null default 'A reminder from The Reader Room',
  completion_message text not null default 'Thank you for completing this beta read. Your thoughtful feedback helps shape the next draft.',
  updated_at timestamptz not null default now()
);

create table public.access_logs (
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles(id) on delete set null,
  book_id uuid references public.books(id) on delete cascade,
  event_type text not null,
  event_detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.match_invited_reader()
returns trigger language plpgsql security definer set search_path = public as $$
declare matched_reader uuid;
begin
  select id into matched_reader from public.profiles where lower(email) = lower(new.email) limit 1;
  if matched_reader is not null then
    new.reader_id = matched_reader;
    new.status = 'accepted';
    new.accepted_at = now();
  end if;
  return new;
end;
$$;

create trigger match_reader_before_invitation
before insert on public.reader_invitations
for each row execute function public.match_invited_reader();

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger books_updated_at before update on public.books for each row execute function public.set_updated_at();
create trigger chapters_updated_at before update on public.chapters for each row execute function public.set_updated_at();
create trigger comments_updated_at before update on public.comments for each row execute function public.set_updated_at();
create trigger questionnaire_responses_updated_at before update on public.questionnaire_responses for each row execute function public.set_updated_at();
create trigger reminder_settings_updated_at before update on public.reminder_settings for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    lower(new.email),
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    case
      when lower(new.email) = 'thereaderroom@teejayedeloach.com' then 'admin'::public.user_role
      when exists (
        select 1 from public.author_invitations ai
        where lower(ai.email) = lower(new.email) and ai.revoked_at is null
      ) then 'author'::public.user_role
      else 'reader'::public.user_role
    end
  )
  on conflict (id) do update set email = excluded.email;

  update public.reader_invitations
  set reader_id = new.id,
      status = case when status = 'pending' then 'accepted'::public.invitation_status else status end,
      accepted_at = coalesce(accepted_at, now())
  where lower(email) = lower(new.email) and revoked_at is null;

  update public.author_invitations
  set status = 'accepted', accepted_at = coalesce(accepted_at, now())
  where lower(email) = lower(new.email) and revoked_at is null;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.profiles (id, email, full_name, role)
select id, lower(email), coalesce(raw_user_meta_data ->> 'full_name', split_part(email, '@', 1)),
       case when lower(email) = 'thereaderroom@teejayedeloach.com' then 'admin'::public.user_role else 'reader'::public.user_role end
from auth.users
on conflict (id) do update set
  email = excluded.email,
  role = case when excluded.email = 'thereaderroom@teejayedeloach.com' then 'admin'::public.user_role else public.profiles.role end;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') $$;

create or replace function public.is_author()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and role in ('admin','author')) $$;

create or replace function public.can_use_admin_portal(candidate_email text)
returns boolean language sql stable security definer set search_path = public
as $$
  select lower(trim(candidate_email)) = 'thereaderroom@teejayedeloach.com'
    or exists(
      select 1 from public.profiles
      where lower(email) = lower(trim(candidate_email)) and role = 'admin'
    )
$$;

create or replace function public.can_use_author_portal(candidate_email text)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(
      select 1 from public.author_invitations
      where lower(email) = lower(candidate_email) and revoked_at is null
    )
$$;

create or replace function public.can_use_reader_portal(candidate_email text)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(
    select 1 from public.reader_invitations
    where lower(email) = lower(candidate_email) and revoked_at is null
  )
$$;

create or replace function public.invite_author(author_email text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  insert into public.author_invitations (email, invited_by)
  values (lower(trim(author_email)), auth.uid())
  on conflict ((lower(email))) do update
  set status = 'pending', invited_by = auth.uid(), invited_at = now(), accepted_at = null, revoked_at = null;
  update public.profiles set role = 'author'::public.user_role
  where lower(email) = lower(trim(author_email));
end;
$$;

create or replace function public.revoke_author(invitation_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare target_email text;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  update public.author_invitations
  set status = 'revoked', revoked_at = now()
  where id = invitation_id returning email into target_email;
  update public.profiles set role = 'reader'::public.user_role
  where lower(email) = lower(target_email) and lower(email) <> 'thereaderroom@teejayedeloach.com';
end;
$$;

create or replace function public.set_user_role(target_user uuid, new_role public.user_role)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;
  update public.profiles set role = new_role where id = target_user;
end;
$$;

create or replace function public.can_manage_book(target_book uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_admin()
    or (public.is_author() and exists(
      select 1 from public.books where id = target_book and author_id = auth.uid()
    ))
$$;

create or replace function public.can_read_book(target_book uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.can_manage_book(target_book) or exists(
    select 1 from public.reader_invitations ri
    where ri.book_id = target_book
      and ri.revoked_at is null
      and (ri.reader_id = auth.uid() or lower(ri.email) = lower(coalesce(auth.jwt() ->> 'email','')))
  )
$$;

alter table public.profiles enable row level security;
alter table public.author_invitations enable row level security;
alter table public.books enable row level security;
alter table public.manuscript_versions enable row level security;
alter table public.chapters enable row level security;
alter table public.reader_invitations enable row level security;
alter table public.reader_agreements enable row level security;
alter table public.reading_progress enable row level security;
alter table public.comments enable row level security;
alter table public.questionnaires enable row level security;
alter table public.questionnaire_questions enable row level security;
alter table public.questionnaire_responses enable row level security;
alter table public.reminder_settings enable row level security;
alter table public.access_logs enable row level security;

create policy profiles_self_select on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy profiles_self_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy author_invitations_admin_all on public.author_invitations for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy books_read on public.books for select to authenticated using (public.can_read_book(id));
create policy books_author_insert on public.books for insert to authenticated with check (author_id = auth.uid() and public.is_author());
create policy books_author_update on public.books for update to authenticated using (public.can_manage_book(id)) with check (public.can_manage_book(id));
create policy books_author_delete on public.books for delete to authenticated using (public.can_manage_book(id));

create policy versions_read on public.manuscript_versions for select to authenticated using (public.can_read_book(book_id));
create policy versions_author_all on public.manuscript_versions for all to authenticated using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));

create policy chapters_read on public.chapters for select to authenticated using (public.can_read_book(book_id));
create policy chapters_author_all on public.chapters for all to authenticated using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));

create policy invitations_author_all on public.reader_invitations for all to authenticated using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));
create policy invitations_reader_read on public.reader_invitations for select to authenticated using (reader_id = auth.uid() or lower(email) = lower(coalesce(auth.jwt() ->> 'email','')));

create policy agreements_read on public.reader_agreements for select to authenticated using (reader_id = auth.uid() or exists(select 1 from public.reader_invitations ri where ri.id = invitation_id and public.can_manage_book(ri.book_id)));
create policy agreements_reader_insert on public.reader_agreements for insert to authenticated with check (reader_id = auth.uid() and exists(select 1 from public.reader_invitations ri where ri.id = invitation_id and (ri.reader_id = auth.uid() or lower(ri.email) = lower(coalesce(auth.jwt() ->> 'email',''))) and ri.revoked_at is null));

create policy progress_read on public.reading_progress for select to authenticated using (reader_id = auth.uid() or exists(select 1 from public.reader_invitations ri where ri.id = invitation_id and public.can_manage_book(ri.book_id)));
create policy progress_reader_all on public.reading_progress for all to authenticated using (reader_id = auth.uid()) with check (reader_id = auth.uid() and exists(select 1 from public.reader_invitations ri where ri.id = invitation_id and (ri.reader_id = auth.uid() or lower(ri.email) = lower(coalesce(auth.jwt() ->> 'email',''))) and ri.revoked_at is null));

create policy comments_read on public.comments for select to authenticated using (reader_id = auth.uid() or public.can_manage_book(book_id));
create policy comments_reader_insert on public.comments for insert to authenticated with check (reader_id = auth.uid() and public.can_read_book(book_id));
create policy comments_reader_update on public.comments for update to authenticated using (reader_id = auth.uid()) with check (reader_id = auth.uid());
create policy comments_author_update on public.comments for update to authenticated using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));

create policy questionnaires_read on public.questionnaires for select to authenticated using (public.can_read_book(book_id));
create policy questionnaires_author_all on public.questionnaires for all to authenticated using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));
create policy questions_read on public.questionnaire_questions for select to authenticated using (exists(select 1 from public.questionnaires q where q.id = questionnaire_id and public.can_read_book(q.book_id)));
create policy questions_author_all on public.questionnaire_questions for all to authenticated using (exists(select 1 from public.questionnaires q where q.id = questionnaire_id and public.can_manage_book(q.book_id))) with check (exists(select 1 from public.questionnaires q where q.id = questionnaire_id and public.can_manage_book(q.book_id)));
create policy responses_read on public.questionnaire_responses for select to authenticated using (reader_id = auth.uid() or exists(select 1 from public.questionnaire_questions qq join public.questionnaires q on q.id = qq.questionnaire_id where qq.id = question_id and public.can_manage_book(q.book_id)));
create policy responses_reader_all on public.questionnaire_responses for all to authenticated using (reader_id = auth.uid()) with check (reader_id = auth.uid() and exists(select 1 from public.questionnaire_questions qq join public.questionnaires q on q.id = qq.questionnaire_id where qq.id = question_id and public.can_read_book(q.book_id)));

create policy reminders_author_all on public.reminder_settings for all to authenticated using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));
create policy access_logs_self_insert on public.access_logs for insert to authenticated with check (user_id = auth.uid());
create policy access_logs_author_read on public.access_logs for select to authenticated using (user_id = auth.uid() or (book_id is not null and public.can_manage_book(book_id)));

revoke all on public.profiles, public.author_invitations, public.books, public.manuscript_versions, public.chapters,
  public.reader_invitations, public.reader_agreements, public.reading_progress,
  public.comments, public.questionnaires, public.questionnaire_questions,
  public.questionnaire_responses, public.reminder_settings, public.access_logs
from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (full_name) on public.profiles to authenticated;
grant select, insert, update, delete on public.author_invitations to authenticated;
grant select, insert, update, delete on public.books, public.manuscript_versions, public.chapters,
  public.reader_invitations, public.reader_agreements, public.reading_progress,
  public.comments, public.questionnaires, public.questionnaire_questions,
  public.questionnaire_responses, public.reminder_settings, public.access_logs
to authenticated;
grant usage, select on sequence public.access_logs_id_seq to authenticated;
grant execute on function public.is_admin(), public.is_author(), public.can_manage_book(uuid), public.can_read_book(uuid), public.set_user_role(uuid, public.user_role) to authenticated;
grant execute on function public.can_use_admin_portal(text), public.can_use_author_portal(text), public.can_use_reader_portal(text) to anon, authenticated;
grant execute on function public.invite_author(text), public.revoke_author(uuid) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('manuscripts', 'manuscripts', false, 20971520, array['application/vnd.openxmlformats-officedocument.wordprocessingml.document','text/plain','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 20971520;

create policy manuscript_upload on storage.objects for insert to authenticated
with check (bucket_id = 'manuscripts' and (storage.foldername(name))[1] = auth.uid()::text and public.is_author());
create policy manuscript_owner_read on storage.objects for select to authenticated
using (bucket_id = 'manuscripts' and (public.is_admin() or (public.is_author() and (storage.foldername(name))[1] = auth.uid()::text)));
create policy manuscript_owner_update on storage.objects for update to authenticated
using (bucket_id = 'manuscripts' and (public.is_admin() or (public.is_author() and (storage.foldername(name))[1] = auth.uid()::text)));
create policy manuscript_owner_delete on storage.objects for delete to authenticated
using (bucket_id = 'manuscripts' and (public.is_admin() or (public.is_author() and (storage.foldername(name))[1] = auth.uid()::text)));

-- Limit every book to ten active, non-revoked reader invitations.
create or replace function public.enforce_reader_limit()
returns trigger language plpgsql as $$
begin
  if new.revoked_at is null
     and (select count(*) from public.reader_invitations
          where book_id = new.book_id and revoked_at is null and id <> new.id) >= 10 then
    raise exception 'This book already has 10 active readers.';
  end if;
  return new;
end;
$$;

create trigger reader_limit_before_write before insert or update of book_id, revoked_at on public.reader_invitations
for each row execute function public.enforce_reader_limit();
