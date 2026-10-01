-- Cuba Match Explorer v3.7 production hardening
-- Prevent direct API execution of the trigger helper. The trigger itself remains functional.
revoke all on function public.force_user_source() from public;
revoke all on function public.force_user_source() from anon;
revoke all on function public.force_user_source() from authenticated;
