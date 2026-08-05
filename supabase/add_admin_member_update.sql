-- Lets an admin edit a buyer's display info (name/city/phone) from the Members
-- tab, without touching is_admin/is_owner/email — same escalation-safe pattern as
-- update_own_profile() and set_admin_status(). Run this once in the SQL Editor.

create or replace function public.admin_update_member(target_id uuid, p_name text, p_city text, p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_admin() then
    raise exception 'Only admins can edit member profiles';
  end if;
  update profiles set name = p_name, city = p_city, phone = p_phone
  where id = target_id and is_admin = false;
end;
$$;
