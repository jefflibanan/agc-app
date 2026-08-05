-- Fixes: "infinite recursion detected in policy for relation profiles"
-- Cause: a policy on `profiles` queried `profiles` again to check is_admin, which
-- re-triggers the same policy, forever. Every other table's admin-check policy also
-- queried `profiles` directly, so the recursion broke those too.
-- Fix: move the admin check into a SECURITY DEFINER function, which reads the table
-- directly without going back through RLS, breaking the loop.
-- Run this once in the SQL Editor.

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

-- events: replace the blanket "for all" admin policy with explicit per-command ones
drop policy if exists "admins manage events" on events;
create policy "admins insert events" on events for insert with check (is_admin());
create policy "admins update events" on events for update using (is_admin()) with check (is_admin());
create policy "admins delete events" on events for delete using (is_admin());

-- bookings
drop policy if exists "admins view all bookings" on bookings;
create policy "admins view all bookings" on bookings for select using (is_admin());
drop policy if exists "admins update bookings" on bookings;
create policy "admins update bookings" on bookings for update using (is_admin());

-- checkins
drop policy if exists "admins manage checkins" on checkins;
create policy "admins insert checkins" on checkins for insert with check (is_admin());
create policy "admins select checkins" on checkins for select using (is_admin());
create policy "admins update checkins" on checkins for update using (is_admin());
create policy "admins delete checkins" on checkins for delete using (is_admin());

-- profiles: this was the actual recursion source
drop policy if exists "admins view all profiles" on profiles;
create policy "admins view all profiles" on profiles for select using (is_admin());
