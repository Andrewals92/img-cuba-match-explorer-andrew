-- All available wave cycles can include an incomplete cycle: label that explicitly.
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.program_season_intelligence_v43(uuid[],integer)'::regprocedure);
 definition:=replace(definition,'Historical aggregate · cycles kept separate','Mixed available cycles · timelines kept separate');
 execute definition;
end $$;
