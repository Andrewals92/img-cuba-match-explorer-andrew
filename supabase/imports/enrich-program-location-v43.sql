-- Enrich missing location from uniquely linked program sources only. No raw report rewrite.
with locations as(select program_id,min(state) state from cme_private.program_source_catalog_v43 where program_id is not null and state ~ '^[A-Z]{2}$' group by program_id having count(distinct state)=1)
update public.programs p set state=l.state from locations l where p.id=l.program_id and p.state is null;
