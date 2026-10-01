-- Cuba Match Explorer v3.2: admin + My Data fixes
-- Requires existing profiles, applicant_cycles, program_reports and is_admin().

-- Prevent ordinary users from changing authorization fields directly.
revoke update on public.profiles from authenticated;
grant update (display_name) on public.profiles to authenticated;

-- Admins can inspect community records via existing RLS-aware table policies.
drop policy if exists cycles_own_or_admin on public.applicant_cycles;
create policy cycles_own_or_admin on public.applicant_cycles for select to authenticated
using ((select auth.uid()) = user_id or public.is_admin());

drop policy if exists cycles_own_delete on public.applicant_cycles;
create policy cycles_own_delete on public.applicant_cycles for delete to authenticated
using ((select auth.uid()) = user_id or public.is_admin());

drop policy if exists reports_own_or_admin on public.program_reports;
create policy reports_own_or_admin on public.program_reports for select to authenticated
using ((select auth.uid()) = user_id or public.is_admin());

drop policy if exists reports_own_delete on public.program_reports;
create policy reports_own_delete on public.program_reports for delete to authenticated
using ((select auth.uid()) = user_id or public.is_admin());

drop policy if exists reports_own_update on public.program_reports;
create policy reports_own_update on public.program_reports for update to authenticated
using ((select auth.uid()) = user_id or public.is_admin())
with check ((select auth.uid()) = user_id or public.is_admin());

create or replace function public.admin_site_summary()
returns jsonb
language sql
stable
security invoker
set search_path=public
as $$
  select case when public.is_admin() then jsonb_build_object(
    'users',(select count(*) from public.profiles),
    'admins',(select count(*) from public.profiles where role='admin'),
    'cycles',(select count(*) from public.applicant_cycles),
    'reports',(select count(*) from public.program_reports),
    'programs',(select count(*) from public.programs),
    'watch_subscriptions',(select count(*) from public.program_watch_subscriptions),
    'pending_verifications',(select count(*) from public.program_reports where verification_status='pending')
  ) else null end;
$$;
revoke all on function public.admin_site_summary() from public, anon;
grant execute on function public.admin_site_summary() to authenticated;

create or replace function public.admin_set_user_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'Admin required'; end if;
  if p_role not in ('user','admin') then raise exception 'Invalid role'; end if;
  if p_user_id = auth.uid() and p_role <> 'admin' then
    raise exception 'Current administrator cannot remove own admin role';
  end if;
  update public.profiles set role=p_role, updated_at=now() where id=p_user_id;
end;
$$;
revoke all on function public.admin_set_user_role(uuid,text) from public, anon;
grant execute on function public.admin_set_user_role(uuid,text) to authenticated;
