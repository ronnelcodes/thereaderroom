-- Run this once after schema.sql if the owner email was changed.

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
      when lower(new.email) = 'teejayedeloach@teejayedeloach.com'
        then 'admin'::public.user_role
      else 'reader'::public.user_role
    end
  )
  on conflict (id) do update set email = excluded.email;

  update public.reader_invitations
  set reader_id = new.id,
      status = case
        when status = 'pending' then 'accepted'::public.invitation_status
        else status
      end,
      accepted_at = coalesce(accepted_at, now())
  where lower(email) = lower(new.email)
    and revoked_at is null;

  return new;
end;
$$;

update public.profiles
set role = 'reader'::public.user_role
where lower(email) = 'teejayedeloachwrites@gmail.com'
  and lower(email) <> 'teejayedeloach@teejayedeloach.com';

update public.profiles
set role = 'admin'::public.user_role
where lower(email) = 'teejayedeloach@teejayedeloach.com';
