-- Adds admin invites: an existing admin adds an email to an allow-list; when that
-- person signs up in the app with their own password, they're auto-granted admin.
-- (Directly creating another admin's login from the console isn't safe with Supabase's
-- client SDK — signUp() would swap the *current* admin's browser session to the new
-- account. Self-service signup + allow-list avoids that entirely.)
-- Run this once in the SQL Editor, after schema.sql and fix_rls_recursion.sql.

create table if not exists admin_invites (
  email text primary key,
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table admin_invites enable row level security;

drop policy if exists "admins manage invites" on admin_invites;
create policy "admins select invites" on admin_invites for select using (is_admin());
create policy "admins insert invites" on admin_invites for insert with check (is_admin());
create policy "admins delete invites" on admin_invites for delete using (is_admin());

-- Extend the signup trigger: if the new user's email was invited, grant admin and
-- clear the invite. Otherwise behave as before (plain, non-admin profile row).
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, is_admin)
  values (new.id, new.email, exists (select 1 from admin_invites where email = new.email));
  delete from admin_invites where email = new.email;
  return new;
end;
$$ language plpgsql security definer;

-- Public, aggregate-only "how many tickets sold per event" — safe for the anon key
-- since it returns nothing but event_id + a count, no buyer details. Used to show
-- real "X booked" numbers in the app instead of the old fake ones.
create or replace function public.get_event_seat_counts()
returns table(event_id bigint, sold bigint)
language sql
security definer
stable
set search_path = public
as $$
  select event_id, sum(qty) as sold from bookings where status = 'confirmed' group by event_id;
$$;

-- Lets an admin revoke another (non-owner) admin's console access. A plain UPDATE
-- can't do this because the "own profile update" policy only lets someone edit
-- their own row — this function is the one deliberate, narrow exception, and it
-- checks is_admin() itself before touching anything.
create or replace function public.set_admin_status(target_email text, new_status boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'not authorized';
  end if;
  update profiles set is_admin = new_status where email = target_email and is_owner = false;
end;
$$;
