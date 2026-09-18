-- Public author and reader registration for The Reader Room.
-- Safe to run more than once.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, role, password_set)
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
      when new.raw_user_meta_data ->> 'signup_role' = 'author' then 'author'::public.user_role
      else 'reader'::public.user_role
    end,
    coalesce(new.raw_user_meta_data ->> 'public_signup' = 'true', false)
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    role = case
      when public.profiles.role = 'admin'::public.user_role then public.profiles.role
      else excluded.role
    end,
    password_set = public.profiles.password_set or excluded.password_set;

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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
