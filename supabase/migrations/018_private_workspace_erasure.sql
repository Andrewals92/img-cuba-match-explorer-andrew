-- Keep the existing explicit delete-my-data action complete as private entities grow.
create or replace function public.delete_my_data() returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=(select auth.uid());
begin
 if uid is null then raise exception 'Authentication required';end if;
 delete from public.user_program_watchlist where user_id=uid;
 delete from public.interview_events where user_id=uid;
 delete from public.applicant_cycles where user_id=uid;
 delete from public.program_watch_subscriptions where user_id=uid;
 delete from public.notifications where user_id=uid;
 update public.profiles set display_name=null where id=uid;
end $$;
revoke all on function public.delete_my_data() from public,anon;
grant execute on function public.delete_my_data() to authenticated;
