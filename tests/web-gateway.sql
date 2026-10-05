begin;
update cme_private.web_gateway_config set enabled=true,secret_hash=encode(extensions.digest(repeat('test-only-',10),'sha256'),'hex') where singleton;
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select set_config('request.headers','{}',true);
do $$begin
 begin perform cme_private.enforce_web_gateway(); raise exception 'direct request incorrectly allowed'; exception when insufficient_privilege then null; end;
 begin perform public.reserve_web_request('data'); raise exception 'untrusted quota reservation allowed'; exception when insufficient_privilege then null; end;
 if has_table_privilege('anon','cme_private.web_gateway_config','SELECT') or has_table_privilege('anon','cme_private.web_rate_buckets','SELECT') then raise exception 'private storage exposed';end if;
 if has_function_privilege('anon','cme_private.assert_web_gateway()','EXECUTE') then raise exception 'internal helper executable';end if;
end $$;
select set_config('request.headers',jsonb_build_object('x-cme-gateway',repeat('test-only-',10),'x-cme-client',repeat('a',64))::text,true);
do $$declare r jsonb; i integer;begin
 perform cme_private.enforce_web_gateway();
 for i in 1..12 loop r:=public.reserve_web_request('auth');if (r->>'allowed')::boolean is not true then raise exception 'legitimate burst denied at %',i;end if;end loop;
 r:=public.reserve_web_request('auth');if (r->>'allowed')::boolean is not false then raise exception 'rate limit not enforced';end if;
 r:=public.reserve_web_request('data');if (r->>'allowed')::boolean is not true then raise exception 'separate quota not available';end if;
end $$;
select set_config('request.headers',jsonb_build_object('x-cme-gateway','forged','x-cme-client',repeat('a',64))::text,true);
do $$begin
 begin perform cme_private.enforce_web_gateway();raise exception 'forged proof allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000001"}',true);
select set_config('request.headers','{}',true);
do $$begin
 begin perform cme_private.enforce_web_gateway();raise exception 'credentials without gateway proof allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'PASS: anon and authenticated direct access denied; trusted gateway allowed; rate limits enforced; private configuration inaccessible; rollback complete' as result;
