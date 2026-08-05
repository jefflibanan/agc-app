-- Fixes a privilege-escalation gap: the "own profile update" policy let ANY signed-up
-- user run `supabase.from('profiles').update({is_admin:true}).eq('id', myId)` directly
-- from the browser console and grant themselves admin — the policy only checked
-- "is this your row", not which columns you're allowed to touch.
-- The app never actually uses this policy for anything real (admin status changes go
-- through the signup trigger or the set_admin_status() function instead), so the fix
-- is simply to remove it.
-- Run this once in the SQL Editor.

drop policy if exists "own profile update" on profiles;
