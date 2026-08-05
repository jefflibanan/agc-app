-- Fixes signup silently failing with an empty {} error.
-- Cause: handle_new_user() (the trigger that fires on every new Supabase Auth signup)
-- referenced `admin_invites` without schema-qualifying it and without pinning the
-- function's search_path. Triggers on auth.users don't reliably inherit `public` in
-- their search_path, so the reference couldn't resolve, the trigger raised an error,
-- and the entire signup transaction rolled back — surfaced to the client as an opaque
-- error with no useful message.
-- Run this once in the SQL Editor.

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, is_admin)
  values (new.id, new.email, exists (select 1 from public.admin_invites where email = new.email));
  delete from public.admin_invites where email = new.email;
  return new;
end;
$$ language plpgsql security definer set search_path = public;
