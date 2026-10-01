-- Fix the function search_path reported by the Supabase security advisor.
alter function public.match_cycle_completed(integer)
  set search_path = public;
