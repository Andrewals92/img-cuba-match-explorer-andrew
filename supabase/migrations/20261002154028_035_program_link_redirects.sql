-- Repair sign-in/soft-404 redirects; keep institution page as the durable target.
update cme_private.program_source_catalog_v43 c set website_url=x.url,website_scope='program',website_verified_at='2026-10-02' from (values
('1402500926','https://www.mclaren.org/gme-medical-education/mclaren-residency-programs/4'),
('1402500925','https://www.mclaren.org/gme-medical-education/mclaren-residency-programs/22'),
('1404500008','https://academics.lexhealth.com/graduate-medical-education/internal-medicine-residency/'),
('1404800006','https://www.parisregionalhealth.com/internal-residency-program?query=Internal+medicine')) x(acgme,url) where c.acgme_program_id=x.acgme;
