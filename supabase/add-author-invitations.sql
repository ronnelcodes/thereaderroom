-- Run this once after the original Reader Room schema.

create table if not exists public.author_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  invited_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','revoked')),
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at timestamptz
);

create unique index if not exists author_invitations_email_lower_idx
on public.author_invitations (lower(email));

alter table public.author_invitations enable row level security;

drop policy if exists author_invitations_admin_all on public.author_invitations;
create policy author_invitations_admin_all on public.author_invitations
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.can_use_author_portal(candidate_email text)
returns boolean language sql stable security definer set search_path = public
as $$
  select lower(candidate_email) = 'thereaderroom@teejayedeloach.com'
    or exists(
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

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
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
  on conflict (id) do update set
    email = excluded.email,
    role = excluded.role;

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

grant select, insert, update, delete on public.author_invitations to authenticated;
grant execute on function public.can_use_author_portal(text), public.can_use_reader_portal(text) to anon, authenticated;
grant execute on function public.invite_author(text), public.revoke_author(uuid) to authenticated;
