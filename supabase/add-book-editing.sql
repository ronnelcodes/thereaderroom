-- Adds atomic, version-preserving manuscript editing to an existing installation.
-- Safe to run more than once.

create or replace function public.save_book_revision(
  p_book_id uuid,
  p_title text,
  p_author_name text,
  p_genre text,
  p_description text,
  p_overall_deadline date,
  p_status text,
  p_chapters jsonb
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  previous_version integer;
  next_version integer;
  existing_path text;
  existing_filename text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.can_manage_book(p_book_id) then
    raise exception 'You are not authorized to edit this book';
  end if;

  if nullif(trim(p_title), '') is null or nullif(trim(p_author_name), '') is null then
    raise exception 'Book title and author name are required';
  end if;

  if nullif(trim(p_genre), '') is null then
    raise exception 'Genre is required';
  end if;

  if p_status not in ('draft', 'active', 'complete', 'archived') then
    raise exception 'Invalid book status';
  end if;

  if p_chapters is null or jsonb_typeof(p_chapters) <> 'array' or jsonb_array_length(p_chapters) = 0 then
    raise exception 'At least one chapter is required';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_chapters) chapter
    where nullif(trim(chapter ->> 'title'), '') is null
       or nullif(trim(chapter ->> 'content'), '') is null
  ) then
    raise exception 'Every chapter needs a title and content';
  end if;

  select current_version, manuscript_path, manuscript_filename
  into previous_version, existing_path, existing_filename
  from public.books
  where id = p_book_id
  for update;

  if not found then
    raise exception 'Book not found';
  end if;

  next_version := previous_version + 1;

  insert into public.manuscript_versions (
    book_id, version_number, storage_path, filename, created_by
  ) values (
    p_book_id, next_version, existing_path, existing_filename, auth.uid()
  );

  insert into public.chapters (
    book_id, version_number, chapter_number, title, content
  )
  select
    p_book_id,
    next_version,
    chapter.ordinality::integer,
    trim(chapter.value ->> 'title'),
    trim(chapter.value ->> 'content')
  from jsonb_array_elements(p_chapters) with ordinality as chapter(value, ordinality);

  update public.books
  set title = trim(p_title),
      author_name = trim(p_author_name),
      genre = trim(p_genre),
      description = nullif(trim(p_description), ''),
      overall_deadline = p_overall_deadline,
      status = p_status::public.book_status,
      current_version = next_version
  where id = p_book_id;

  return next_version;
end;
$$;

revoke all on function public.save_book_revision(uuid, text, text, text, text, date, text, jsonb) from public, anon;
grant execute on function public.save_book_revision(uuid, text, text, text, text, date, text, jsonb) to authenticated;
