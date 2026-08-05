-- Adds a phone number field to buyer/admin profiles, captured on sign-up.
-- Run this once in the SQL Editor.

alter table profiles add column if not exists phone text;

create or replace function public.update_own_profile(p_name text, p_city text, p_photo_url text, p_phone text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update profiles set name = p_name, city = p_city, photo_url = p_photo_url, phone = p_phone where id = auth.uid();
end;
$$;
