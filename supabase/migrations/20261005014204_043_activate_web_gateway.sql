-- Gateway and BotID deployed and allowed browser requests verified before activation.
-- Permit trusted maintenance to execute the pre-request hook without exposing
-- private tables or introducing service credentials in the frontend.
grant usage on schema cme_private to service_role;
grant execute on function cme_private.enforce_web_gateway() to service_role;

do $$begin
 if not exists(select 1 from cme_private.web_gateway_config where singleton and secret_hash is not null) then
  raise exception 'Configure the server gateway secret before activation';
 end if;
end $$;
update cme_private.web_gateway_config set enabled=true where singleton;
alter role authenticator set pgrst.db_pre_request='cme_private.enforce_web_gateway';
notify pgrst,'reload config';
notify pgrst,'reload schema';
