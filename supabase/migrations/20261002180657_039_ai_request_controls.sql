-- Minimal AI telemetry: never prompts, answers, profile values or private notes.
create table if not exists cme_private.ai_requests_v50(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),finished_at timestamptz,
 mode text not null check(mode in ('assistant','research','compare','cohort','watchlist','dashboard')),
 status text not null default 'pending' check(status in ('pending','success','fallback','blocked','error')),
 error_category text check(error_category in ('provider_unavailable','provider_limit','timeout','validation','tool_failure','grounding','policy','configuration')),
 latency_ms integer check(latency_ms between 0 and 120000),tool_calls integer check(tool_calls between 0 and 8),
 input_tokens integer check(input_tokens between 0 and 60000),output_tokens integer check(output_tokens between 0 and 6000),
 feedback text check(feedback in ('helpful','not_helpful','incorrect')),feedback_at timestamptz,
 source_types text[] not null default '{}',program_ids uuid[] not null default '{}',
 check(cardinality(source_types)<=8),check(cardinality(program_ids)<=5)
);
create index if not exists ai_requests_v50_owner_time on cme_private.ai_requests_v50(user_id,created_at desc);
create index if not exists ai_requests_v50_time on cme_private.ai_requests_v50(created_at desc);
alter table cme_private.ai_requests_v50 enable row level security;
revoke all on cme_private.ai_requests_v50 from public,anon,authenticated;

create or replace function public.ai_begin_request_v50(p_mode text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare request_id uuid;n integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501';end if;
 if p_mode not in ('assistant','research','compare','cohort','watchlist','dashboard') or p_mode is null then raise exception 'Invalid mode' using errcode='22023';end if;
 -- Serialized across instances. Failed requests remain reserved: retries cannot bypass cost controls.
 perform pg_catalog.pg_advisory_xact_lock(500039);
 select count(*) into n from cme_private.ai_requests_v50 where user_id=auth.uid() and created_at>now()-interval '1 minute';
 if n>=3 then return jsonb_build_object('allowed',false,'reason','minute_limit','retry_after',60);end if;
 select count(*) into n from cme_private.ai_requests_v50 where user_id=auth.uid() and created_at>=date_trunc('day',now());
 if n>=20 then return jsonb_build_object('allowed',false,'reason','daily_limit','retry_after',3600);end if;
 select count(*) into n from cme_private.ai_requests_v50 where created_at>=date_trunc('month',now());
 if n>=100 then return jsonb_build_object('allowed',false,'reason','monthly_budget','retry_after',3600);end if;
 insert into cme_private.ai_requests_v50(user_id,mode) values(auth.uid(),p_mode) returning id into request_id;
 return jsonb_build_object('allowed',true,'answer_id',request_id,'requests_per_minute',3,'requests_per_day',20,'project_requests_per_month',100);
end $$;
revoke all on function public.ai_begin_request_v50(text) from public,anon;
grant execute on function public.ai_begin_request_v50(text) to authenticated;

create or replace function public.ai_finish_request_v50(p_answer_id uuid,p_status text,p_error text default null,
 p_latency integer default 0,p_tools integer default 0,p_input_tokens integer default 0,p_output_tokens integer default 0,
 p_source_types text[] default '{}',p_program_ids uuid[] default '{}')
returns boolean language plpgsql volatile security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501';end if;
 if p_status not in ('success','fallback','blocked','error') or p_status is null or
 exists(select 1 from unnest(p_source_types) s where s not in ('profile','community','catalog','program_guide','official_link','watchlist','tracker','product'))
 then raise exception 'Invalid telemetry' using errcode='22023';end if;
 update cme_private.ai_requests_v50 set status=p_status,error_category=p_error,finished_at=now(),latency_ms=p_latency,
 tool_calls=p_tools,input_tokens=p_input_tokens,output_tokens=p_output_tokens,source_types=p_source_types,program_ids=p_program_ids
 where id=p_answer_id and user_id=auth.uid() and finished_at is null;
 return found;
end $$;
revoke all on function public.ai_finish_request_v50(uuid,text,text,integer,integer,integer,integer,text[],uuid[]) from public,anon;
grant execute on function public.ai_finish_request_v50(uuid,text,text,integer,integer,integer,integer,text[],uuid[]) to authenticated;

create or replace function public.ai_feedback_v50(p_answer_id uuid,p_feedback text)
returns boolean language plpgsql volatile security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501';end if;
 if p_feedback is not null and p_feedback not in ('helpful','not_helpful','incorrect') then raise exception 'Invalid feedback' using errcode='22023';end if;
 update cme_private.ai_requests_v50 set feedback=p_feedback,feedback_at=case when p_feedback is null then null else now() end
 where id=p_answer_id and user_id=auth.uid() and finished_at is not null;
 return found;
end $$;
revoke all on function public.ai_feedback_v50(uuid,text) from public,anon;
grant execute on function public.ai_feedback_v50(uuid,text) to authenticated;

create or replace function public.admin_ai_operations_v50()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 select jsonb_build_object('requests_today',count(*) filter(where created_at>=date_trunc('day',now())),
  'requests_7d',count(*),'successes',count(*) filter(where status='success'),'fallbacks',count(*) filter(where status='fallback'),
  'errors',count(*) filter(where status='error'),'blocked',count(*) filter(where status='blocked'),
  'median_latency_ms',percentile_cont(.5) within group(order by latency_ms),
  'tool_failures',count(*) filter(where error_category='tool_failure'),
  'input_tokens',coalesce(sum(input_tokens),0),'output_tokens',coalesce(sum(output_tokens),0),
  'helpful',count(*) filter(where feedback='helpful'),'not_helpful',count(*) filter(where feedback='not_helpful'),
  'incorrect',count(*) filter(where feedback='incorrect'),
  'error_categories',(select coalesce(jsonb_object_agg(error_category,n),'{}'::jsonb) from
   (select error_category,count(*) n from cme_private.ai_requests_v50 where created_at>=now()-interval '7 days' and error_category is not null group by error_category)x),
  'month_reserved_requests',(select count(*) from cme_private.ai_requests_v50 where created_at>=date_trunc('month',now())),
  'monthly_limit',100,'history_stored',false,'retention_days',40,'research_cache','Public sources only; request-local, no shared AI answer cache',
  'provider','Vercel AI Gateway; model configured server-side; no prompt/answer telemetry') into result
 from cme_private.ai_requests_v50 where created_at>=now()-interval '7 days';
 return result;
end $$;
revoke all on function public.admin_ai_operations_v50() from public,anon;
grant execute on function public.admin_ai_operations_v50() to authenticated;

-- Fixed, non-user-programmable retention task; only operational metadata is expired.
do $$begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  if not exists(select 1 from cron.job where jobname='cme-ai-metadata-retention-v50') then
   perform cron.schedule('cme-ai-metadata-retention-v50','17 4 * * *',
    $cron$delete from cme_private.ai_requests_v50 where created_at<now()-interval '40 days'$cron$);
  end if;
 end if;
end $$;
notify pgrst,'reload schema';
