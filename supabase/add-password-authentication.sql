-- Run this once in Supabase SQL Editor after the earlier Reader Room migrations.
-- Existing accounts will be required to verify their email and create a password.

alter table public.profiles
add column if not exists password_set boolean not null default false;

create or replace function public.mark_password_set()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.profiles set password_set = true where id = auth.uid();
end;
$$;

grant execute on function public.mark_password_set() to authenticated;
