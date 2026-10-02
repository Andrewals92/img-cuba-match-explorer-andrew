-- Fill missing directory state from the resolved, program-only source location.
-- ACGME identity must agree and conflicting locations are not guessed.
-- Existing non-null directory values and all applicant/report records are untouched.
with locations as (
 select c.program_id,min(c.state) state from cme_private.program_source_catalog_v43 c
 join public.programs p on p.id=c.program_id and p.acgme_program_id=c.acgme_program_id
 where c.source='Residency Explorer' and c.state ~ '^[A-Z]{2}$'
 group by c.program_id having count(distinct c.state)=1
)
update public.programs p set state=l.state from locations l where p.id=l.program_id and p.state is null;
