-- Install before deploying the gateway. Enforcement is activated separately
-- only after the deployed gateway can serve permitted browser requests.
create table cme_private.web_gateway_config (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 secret_hash text check(secret_hash ~ '^[a-f0-9]{64}$')
);
insert into cme_private.web_gateway_config(singleton) values(true);
create table cme_private.web_rate_buckets (
 actor text not null,
 bucket text not null,
 window_seconds integer not null,
 window_start bigint not null,
 hits integer not null default 1,
 primary key(actor,bucket,window_seconds,window_start)
);
alter table cme_private.web_gateway_config enable row level security;
alter table cme_private.web_rate_buckets enable row level security;
revoke all on cme_private.web_gateway_config,cme_private.web_rate_buckets from public,anon,authenticated;

create function cme_private.assert_web_gateway() returns void
language plpgsql stable security definer set search_path='' as $$
declare
 h jsonb := coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}');
 expected text;
begin
 select secret_hash into expected from cme_private.web_gateway_config where singleton;
 if expected is null or coalesce(h->>'x-cme-gateway','')='' or
    encode(extensions.digest(coalesce(h->>'x-cme-gateway',''),'sha256'),'hex')<>expected then
  raise sqlstate '42501' using message='Acceso directo no permitido. Abre cubamatchexplorer.org en tu navegador.';
 end if;
end $$;
revoke all on function cme_private.assert_web_gateway() from public,anon,authenticated;

create function cme_private.enforce_web_gateway() returns void
language plpgsql stable security definer set search_path='' as $$
begin
 -- Service credentials are never present in the browser. Trusted scheduled
 -- maintenance keeps its existing access; user JWTs cannot claim this role.
 if coalesce(auth.role(),'')='service_role' then return; end if;
 if exists(select 1 from cme_private.web_gateway_config where singleton and enabled) then
  perform cme_private.assert_web_gateway();
 end if;
end $$;
revoke all on function cme_private.enforce_web_gateway() from public;

create function cme_private.reserve_web_request(p_bucket text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare
 h jsonb:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}');
 uid uuid:=auth.uid(); actor text; actors text[]; duration integer;
 cap integer; count_now integer; stamp bigint; allowed boolean:=true;
begin
 perform cme_private.assert_web_gateway();
 if p_bucket not in ('auth','session','data','assistant') or p_bucket is null then
  raise sqlstate '22023' using message='invalid_bucket';
 end if;
 if coalesce(h->>'x-cme-client','') !~ '^[a-f0-9]{64}$' then
  raise sqlstate '42501' using message='gateway_client_required';
 end if;
 actors:=array['ip:'||(h->>'x-cme-client')];
 if uid is not null then actors:=array_append(actors,'user:'||uid::text); end if;
 foreach actor in array actors loop
  foreach duration in array array[60,3600] loop
   cap:=case p_bucket when 'auth' then case duration when 60 then 12 else 40 end
         when 'assistant' then case duration when 60 then 6 else 40 end
         when 'session' then case duration when 60 then 120 else 1200 end
         else case duration when 60 then 240 else 3000 end end;
   stamp:=floor(extract(epoch from clock_timestamp())/duration)::bigint*duration;
   insert into cme_private.web_rate_buckets as b(actor,bucket,window_seconds,window_start,hits)
    values(actor,p_bucket,duration,stamp,1)
    on conflict on constraint web_rate_buckets_pkey do update set hits=b.hits+1
    returning hits into count_now;
   if count_now>cap then allowed:=false; end if;
  end loop;
 end loop;
 return jsonb_build_object('allowed',allowed,'retry_after',case when allowed then 0 else 60 end);
end $$;
revoke all on function cme_private.reserve_web_request(text) from public;
-- Only these two narrow helpers are executable. Private table ACLs and RLS
-- remain deny-all. cme_private is not an exposed PostgREST schema.
grant usage on schema cme_private to anon,authenticated;
grant execute on function cme_private.enforce_web_gateway(),cme_private.reserve_web_request(text) to anon,authenticated;
create function public.reserve_web_request(p_bucket text) returns jsonb
language sql volatile security invoker set search_path='' as $$
 select cme_private.reserve_web_request(p_bucket);
$$;
revoke all on function public.reserve_web_request(text) from public;
grant execute on function public.reserve_web_request(text) to anon,authenticated;
select cron.schedule('cme-web-rate-cleanup','17 * * * *',
 $$delete from cme_private.web_rate_buckets where window_start < extract(epoch from now()-interval '2 hours')::bigint$$);
notify pgrst,'reload schema';
