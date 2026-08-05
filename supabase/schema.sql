-- AGC Event App — Supabase schema
-- Run this once in your Supabase project's SQL Editor (Dashboard → SQL Editor → New query).
-- Safe to re-run: uses "if not exists" / "or replace" where possible.

-- ============================================================
-- TABLES
-- ============================================================

create table if not exists brands (
  id text primary key,
  name text not null,
  category text not null
);

create table if not exists events (
  id bigint generated always as identity primary key,
  brand_id text not null references brands(id),
  title text not null,
  event_date date not null,
  doors_time text not null default '7:00 PM onwards',
  venue text not null,
  price integer not null check (price >= 0),
  description text not null default '',
  image_url text,               -- data URL or hosted URL; null falls back to the brand's default photo client-side
  featured boolean not null default false,
  is_paused boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists bookings (
  id bigint generated always as identity primary key,
  event_id bigint not null references events(id),
  code text not null unique,          -- e.g. FR-XXXX-XXXX, shown as the QR/reference on the ticket
  qty integer not null check (qty > 0),
  total_amount integer not null check (total_amount >= 0),
  buyer_name text,
  buyer_email text,
  device_id text,                     -- locally-generated id (see app code) so a device can re-fetch its own bookings
  status text not null default 'confirmed' check (status in ('confirmed','cancelled')),
  created_at timestamptz not null default now()
);

create table if not exists checkins (
  id bigint generated always as identity primary key,
  booking_id bigint not null references bookings(id) unique,   -- unique: a booking can only be checked in once
  checked_in_at timestamptz not null default now(),
  checked_in_by uuid references auth.users(id)
);

-- One row per admin/organizer (created only for people who sign in to the console — buyers don't get a row).
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  is_admin boolean not null default false,
  is_owner boolean not null default false,
  created_at timestamptz not null default now()
);

-- Email allow-list for new admins: an existing admin adds an email here; when that
-- person signs up themselves (with their own password), they're auto-granted admin.
-- (An admin can't safely create another admin's login directly — Supabase's client
-- signUp() would swap the *current* admin's browser session to the new account.)
create table if not exists admin_invites (
  email text primary key,
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- Auto-create a profiles row whenever someone signs up via Supabase Auth.
-- Grants admin immediately if the email was on the invite list.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, is_admin)
  values (new.id, new.email, exists (select 1 from public.admin_invites where email = new.email));
  delete from public.admin_invites where email = new.email;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table brands enable row level security;
alter table events enable row level security;
alter table bookings enable row level security;
alter table checkins enable row level security;
alter table profiles enable row level security;
alter table admin_invites enable row level security;

-- Is the current user an admin? SECURITY DEFINER so this reads `profiles` directly
-- instead of going back through RLS — a policy that queries `profiles` from inside
-- a policy (including indirectly, via another table's policy) causes infinite
-- recursion once `profiles` has its own admin-check policy. Must be defined before
-- any policy below references it.
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

-- brands: readable by everyone (including the anon key), never written by the client
drop policy if exists "brands are public" on brands;
create policy "brands are public" on brands for select using (true);

-- events: readable by everyone; only admins can create/edit/delete
drop policy if exists "events are public" on events;
create policy "events are public" on events for select using (true);

-- Admin checks go through is_admin() (defined below) rather than an inline subquery on
-- `profiles`, because a policy that queries `profiles` directly causes infinite recursion
-- once `profiles` has its own admin-check policy (Postgres re-evaluates RLS on the way in).
drop policy if exists "admins manage events" on events;
create policy "admins insert events" on events for insert with check (is_admin());
create policy "admins update events" on events for update using (is_admin()) with check (is_admin());
create policy "admins delete events" on events for delete using (is_admin());

-- bookings: anyone can create one (guest checkout, no login required to buy a ticket).
-- Direct SELECT is restricted to admins — buyers look their own tickets up via the
-- get_bookings_by_codes() function below, keyed by the booking code they already hold.
drop policy if exists "anyone can book" on bookings;
create policy "anyone can book" on bookings for insert with check (true);

drop policy if exists "admins view all bookings" on bookings;
create policy "admins view all bookings" on bookings for select using (is_admin());

drop policy if exists "admins update bookings" on bookings;
create policy "admins update bookings" on bookings for update using (is_admin());

-- checkins: admin-only in both directions
drop policy if exists "admins manage checkins" on checkins;
create policy "admins insert checkins" on checkins for insert with check (is_admin());
create policy "admins select checkins" on checkins for select using (is_admin());
create policy "admins update checkins" on checkins for update using (is_admin());
create policy "admins delete checkins" on checkins for delete using (is_admin());

-- profiles: a user can see (but not edit — see set_admin_status() below) their own row;
-- admins can see everyone's. There's deliberately no client-side UPDATE policy here:
-- a policy that only checks "is this your row" doesn't restrict *which* columns you
-- change, so it would let anyone flip their own is_admin to true from devtools.
drop policy if exists "own profile" on profiles;
create policy "own profile" on profiles for select using (auth.uid() = id);

drop policy if exists "admins view all profiles" on profiles;
create policy "admins view all profiles" on profiles for select using (is_admin());

-- admin_invites: admin-only in every direction
drop policy if exists "admins select invites" on admin_invites;
create policy "admins select invites" on admin_invites for select using (is_admin());
drop policy if exists "admins insert invites" on admin_invites;
create policy "admins insert invites" on admin_invites for insert with check (is_admin());
drop policy if exists "admins delete invites" on admin_invites;
create policy "admins delete invites" on admin_invites for delete using (is_admin());

-- ============================================================
-- FUNCTIONS the app calls with the public anon key
-- ============================================================

-- A buyer's own device looks up its tickets by the codes it already has saved locally.
-- Safe to expose publicly: a code is only known to whoever received that specific ticket.
create or replace function public.get_bookings_by_codes(codes text[])
returns setof bookings
language sql
security definer
as $$
  select * from bookings where code = any(codes);
$$;

-- The gate check-in flow: look up a single booking by its code (used by the organizer console).
create or replace function public.find_booking_by_code(p_code text)
returns setof bookings
language sql
security definer
as $$
  select * from bookings where code = p_code;
$$;

-- Public, aggregate-only "how many tickets sold per event" — safe for the anon key
-- since it returns nothing but event_id + a count, no buyer details. Used to show
-- real "X booked" numbers in the app instead of fake ones.
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

-- ============================================================
-- SEED DATA — the 10 brands and 13 launch events
-- ============================================================

insert into brands (id, name, category) values
  ('billboard','Billboard Philippines','Music'),
  ('rolling','Rolling Stone Philippines','Music'),
  ('game','The GAME','Sports'),
  ('mega','MEGA','Fashion'),
  ('vman','VMAN SEA','Fashion'),
  ('delish','Delish Philippines','Food'),
  ('bluprint','BluPrint','Design'),
  ('tbm','The Business Manual','Business'),
  ('vogue','Vogue Philippines','Fashion'),
  ('allure','Allure Philippines','Beauty')
on conflict (id) do nothing;

insert into events (brand_id, title, event_date, doors_time, venue, price, description, featured) values
  ('mega','The MEGA Ball 2026','2026-10-03','6:00 PM onwards','Shangri-La The Fort, BGC',8000,
   'The most photographed night in Philippine fashion returns. A black-tie benefit gala with a live auction, a couture showcase from the country''s leading houses, and the unveiling of the MEGA Icons class of 2026.', true),
  ('billboard','Billboard PH Live: Mainstage','2026-09-12','7:00 PM onwards','Mall of Asia Arena, Pasay',2500,
   'The charts come alive. One arena night headlined by the artists topping the Billboard Philippines Hot 100, with surprise collabs you will not see anywhere else.', true),
  ('vogue','Vogue Gala: Terno Reimagined','2026-11-14','6:30 PM onwards','National Museum of Fine Arts, Manila',12000,
   'Vogue Philippines celebrates the terno — reinterpreted by a new generation of Filipino designers. An evening of fashion, heritage, and a museum after dark.', true),
  ('rolling','Rolling Stone Sessions: Anniversary Night','2026-08-22','8:00 PM onwards','123 Block, Mandaluyong',1500,
   'An intimate anniversary show taped live for Rolling Stone Philippines — stripped-down sets, long-form conversation, and a room small enough to hear the guitar strings.', false),
  ('game','The GAME Fight Night','2026-09-05','5:00 PM onwards','Araneta Coliseum, Quezon City',1800,
   'The GAME brings boxing back to the Big Dome. A full undercard of rising Filipino fighters and a main event with a national title on the line.', true),
  ('allure','Allure Beauty Summit','2026-08-29','10:00 AM onwards','Samsung Hall, SM Aura, BGC',950,
   'A full day of masterclasses with the country''s top makeup artists, derms, and beauty founders — plus first access to this year''s Best of Beauty winners.', false),
  ('delish','Delish Food Crawl: BGC Edition','2026-09-19','4:00 PM onwards','Bonifacio High Street, BGC',1200,
   'One wristband, fourteen kitchens. A guided evening crawl through BGC''s most talked-about restaurants, with off-menu bites made only for this night.', false),
  ('bluprint','BluPrint Design Forum','2026-10-10','9:00 AM onwards','SMX Convention Center, Pasay',2200,
   'Architecture and design leaders on building for a hotter, denser, more vertical Metro Manila. Keynotes, case studies, and the BluPrint Awards shortlist reveal.', false),
  ('tbm','Founders Summit 2026','2026-09-26','8:30 AM onwards','Grand Hyatt Manila, BGC',4500,
   'The Business Manual gathers 40 founders and operators for a day of tactical sessions — fundraising in a down market, hiring your first hundred, and selling to enterprise.', false),
  ('vman','VMAN SEA Cover Launch','2026-08-15','9:00 PM onwards','The Island, BGC',1000,
   'The new cover drops at midnight — be in the room when it does. A launch party with a live DJ set, a one-night gallery of outtakes, and the cover star in attendance.', false),
  ('billboard','Charting: Songwriters'' Camp','2026-09-30','1:00 PM onwards','Kantana Studios, Makati',800,
   'A working afternoon with hit songwriters behind this year''s chart-toppers. Bring a hook, leave with a demo — limited to 60 seats.', false),
  ('game','Manila Clash: Esports Finals','2026-10-24','12:00 PM onwards','SM Mall of Asia Arena, Pasay',600,
   'The GAME''s national MLBB circuit ends here. Eight teams, one champion, and the loudest crowd in Philippine esports.', false),
  ('billboard','Filipino Music Awards 2026','2026-10-21','7:00 PM onwards','Mall of Asia Arena, Pasay',3000,
   'The biggest night in OPM. Billboard Philippines honors the year''s best artists, songs, and albums — with live performances from the nominees and a few collabs you''ll only see on this stage.', true)
on conflict do nothing;

-- ============================================================
-- ONE-TIME MANUAL STEP (after you've signed up as the owner admin)
-- ============================================================
-- 1. In the app, use Supabase Auth to create your admin account (see app's sign-up flow),
--    OR create it directly: Dashboard → Authentication → Users → Add user.
-- 2. Then run this, swapping in your email, to grant yourself admin + owner rights:
--
--   update profiles set is_admin = true, is_owner = true where email = 'you@yourdomain.ph';
