-- Official and community specialty capitalization differs; compare case-insensitively.
create or replace function public.program_directory_v4(
 p_query text default '', p_specialty text default null, p_kind text default 'all', p_offset integer default 0)
returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('programs',coalesce(jsonb_agg(to_jsonb(d) order by d.name,d.id),'[]'::jsonb),
 'has_more',count(*)>40) from (
 select * from cme_private.program_directory d where d.active
 and (p_specialty is null or lower(d.specialty)=lower(p_specialty))
 and (p_kind='all' or d.identity_kind=p_kind)
 and (coalesce(p_query,'')='' or concat_ws(' ',d.name,d.specialty,d.city,d.state,d.acgme_program_id,d.institution)
 ilike '%'||left(p_query,160)||'%') order by d.name,d.id
 limit 41 offset greatest(0,least(coalesce(p_offset,0),50000))) d;
$$;
revoke all on function public.program_directory_v4(text,text,text,integer) from public;
grant execute on function public.program_directory_v4(text,text,text,integer) to anon,authenticated;


notify pgrst,'reload schema';
