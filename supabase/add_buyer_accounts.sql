-- Adds optional buyer accounts, separate from (but reusing) the admin auth system.
-- Guest checkout still works exactly as before — this is purely additive.
-- Run this once in the SQL Editor.

-- Buyer-facing profile fields. Reuses the same `profiles` table as admins (a user
-- is just a row with is_admin=false unless invited) rather than a parallel table.
alter table profiles add column if not exists name text;
alter table profiles add column if not exists city text;
alter table profiles add column if not exists photo_url text;

-- Lets a signed-in user update their own display info, without touching is_admin/
-- is_owner (same reasoning as the earlier profile-escalation fix: a plain client
-- UPDATE policy can't restrict which columns change, so we go through a function
-- that only ever touches these three columns).
create or replace function public.update_own_profile(p_name text, p_city text, p_photo_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update profiles set name = p_name, city = p_city, photo_url = p_photo_url where id = auth.uid();
end;
$$;

-- Tracks which signed-in account made a purchase. Null = guest checkout, unchanged.
alter table bookings add column if not exists user_id uuid references auth.users(id);

-- A signed-in buyer can see their own bookings (guests still use get_bookings_by_codes()).
drop policy if exists "users view own bookings" on bookings;
create policy "users view own bookings" on bookings for select using (auth.uid() = user_id);
