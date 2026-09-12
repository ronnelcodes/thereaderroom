-- Run this once in Supabase SQL Editor after the earlier Reader Room migrations.
-- Adds a separate administrator portal and makes removed access effective immediately.

create or replace function public.can_use_admin_portal(candidate_email text)
returns boolean language sql stable security definer set search_path = public as $$
  select lower(trim(candidate_email)) = 'thereaderroom@teejayedeloach.com'
    or exists (
      select 1 from public.profiles
      where lower(email) = lower(trim(candidate_email)) and role = 'admin'
    )
$$;

create or replace function public.can_use_author_portal(candidate_email text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.author_invitations
    where lower(email) = lower(trim(candidate_email)) and revoked_at is null
  )
$$;

create or replace function public.can_manage_book(target_book uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin()
    or (
      public.is_author()
      and exists (
        select 1 from public.books
        where id = target_book and author_id = auth.uid()
      )
    )
$$;

create or replace function public.can_read_book(target_book uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.can_manage_book(target_book)
    or exists (
      select 1 from public.reader_invitations
      where book_id = target_book
        and revoked_at is null
        and (reader_id = auth.uid() or lower(email) = lower(coalesce(auth.jwt() ->> 'email','')))
    )
$$;

-- Count only active invitations. Updating a revoked invitation back to active is
-- checked too, so the ten-reader cap cannot be bypassed.
create or replace function public.enforce_reader_limit()
returns trigger language plpgsql as $$
begin
  if new.revoked_at is null
     and (select count(*) from public.reader_invitations
          where book_id = new.book_id
            and revoked_at is null
            and id <> new.id) >= 10 then
    raise exception 'This book already has 10 active readers.';
  end if;
  return new;
end;
$$;

drop trigger if exists reader_limit_before_insert on public.reader_invitations;
drop trigger if exists reader_limit_before_write on public.reader_invitations;
create trigger reader_limit_before_write
before insert or update of book_id, revoked_at on public.reader_invitations
for each row execute function public.enforce_reader_limit();

drop policy if exists books_author_update on public.books;
create policy books_author_update on public.books for update to authenticated
using (public.can_manage_book(id)) with check (public.can_manage_book(id));
drop policy if exists books_author_delete on public.books;
create policy books_author_delete on public.books for delete to authenticated
using (public.can_manage_book(id));

drop policy if exists versions_author_all on public.manuscript_versions;
create policy versions_author_all on public.manuscript_versions for all to authenticated
using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));
drop policy if exists chapters_author_all on public.chapters;
create policy chapters_author_all on public.chapters for all to authenticated
using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));
drop policy if exists invitations_author_all on public.reader_invitations;
create policy invitations_author_all on public.reader_invitations for all to authenticated
using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));

drop policy if exists agreements_read on public.reader_agreements;
create policy agreements_read on public.reader_agreements for select to authenticated
using (reader_id = auth.uid() or exists (
  select 1 from public.reader_invitations ri where ri.id = invitation_id and public.can_manage_book(ri.book_id)
));
drop policy if exists progress_read on public.reading_progress;
create policy progress_read on public.reading_progress for select to authenticated
using (reader_id = auth.uid() or exists (
  select 1 from public.reader_invitations ri where ri.id = invitation_id and public.can_manage_book(ri.book_id)
));

drop policy if exists comments_read on public.comments;
create policy comments_read on public.comments for select to authenticated
using (reader_id = auth.uid() or public.can_manage_book(book_id));
drop policy if exists comments_author_update on public.comments;
create policy comments_author_update on public.comments for update to authenticated
using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));

drop policy if exists questionnaires_author_all on public.questionnaires;
create policy questionnaires_author_all on public.questionnaires for all to authenticated
using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));
drop policy if exists questions_author_all on public.questionnaire_questions;
create policy questions_author_all on public.questionnaire_questions for all to authenticated
using (exists (
  select 1 from public.questionnaires q where q.id = questionnaire_id and public.can_manage_book(q.book_id)
)) with check (exists (
  select 1 from public.questionnaires q where q.id = questionnaire_id and public.can_manage_book(q.book_id)
));
drop policy if exists responses_read on public.questionnaire_responses;
create policy responses_read on public.questionnaire_responses for select to authenticated
using (reader_id = auth.uid() or exists (
  select 1 from public.questionnaire_questions qq
  join public.questionnaires q on q.id = qq.questionnaire_id
  where qq.id = question_id and public.can_manage_book(q.book_id)
));

drop policy if exists reminders_author_all on public.reminder_settings;
create policy reminders_author_all on public.reminder_settings for all to authenticated
using (public.can_manage_book(book_id)) with check (public.can_manage_book(book_id));
drop policy if exists access_logs_author_read on public.access_logs;
create policy access_logs_author_read on public.access_logs for select to authenticated
using (user_id = auth.uid() or (book_id is not null and public.can_manage_book(book_id)));

drop policy if exists manuscript_owner_read on storage.objects;
create policy manuscript_owner_read on storage.objects for select to authenticated
using (bucket_id = 'manuscripts' and (
  public.is_admin() or (public.is_author() and (storage.foldername(name))[1] = auth.uid()::text)
));
drop policy if exists manuscript_owner_update on storage.objects;
create policy manuscript_owner_update on storage.objects for update to authenticated
using (bucket_id = 'manuscripts' and (
  public.is_admin() or (public.is_author() and (storage.foldername(name))[1] = auth.uid()::text)
));
drop policy if exists manuscript_owner_delete on storage.objects;
create policy manuscript_owner_delete on storage.objects for delete to authenticated
using (bucket_id = 'manuscripts' and (
  public.is_admin() or (public.is_author() and (storage.foldername(name))[1] = auth.uid()::text)
));

grant execute on function public.can_use_admin_portal(text) to anon, authenticated;
grant execute on function public.can_use_author_portal(text) to anon, authenticated;
grant execute on function public.can_manage_book(uuid) to authenticated;
