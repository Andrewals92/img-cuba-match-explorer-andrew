-- Program-only link maintenance. No applicant rows, rates, fields, identity or ACL changes.
-- Official program evidence is versioned in residency-links-037.json.
-- Keep original institutional URLs for remaining cases until a matching residency page is verified.
with verified(acgme_program_id,website_url) as (values
('1400300541','https://www.abrazohealth.com/health-professionals/abrazo-health-residency-programs/abrazo-internal-medicine-residency-program'),
('1403531248','https://www.amc.edu/education/residencies-fellowships/internal-medicine-residency/'),
('1401611122','https://medicaleducation.ascension.org/illinois-internal-medicine-saint-joseph-chicago'),
('1401711135','https://medicaleducation.ascension.org/indiana/st-vincent-internal-medicine-residency'),
('1405621446','https://www.aurorahealthcare.org/education/gme/internal-medicine-residency'),
('1402500923','https://authorityhealth.org/graduate-medical-education/internal-medicine-residency-program/'),
('1403511253','https://www.bassett.org/medical-education/residency-fellowship-programs/internal-medicine-residency-program'),
('1403511272','https://flushinghospital.org/education/internal-medicine/'),
('1401100928','https://hcahealthcaregme.com/locations/hca-florida-oak-hill-hospital/internal-medicine-residency/'),
('1400100002','https://www.flowershospitalgme.com/internal-medicine-residency/'),
('1403400248','https://www.mountainviewregional.com/graduate-medical-education-internal-medicine'),
('1403300541','https://www.inspirahealthnetwork.org/services-treatments/graduate-medical-education/medical-residency/mullica-hill-medical-residency/internal-medicine'),
('1403600002','https://www.iredellgme.org/overview/'),
('1400531031','https://www.kernmedical.com/academics/residency-fellowship-programs/internal-medicine/'),
('1404800008','https://www.methodistsaim.com/'),
('1403511258','https://www.montefiorenewrochelle.org/for-health-professionals/academics-and-training'),
('1402411176','https://mountauburnhospital.org/research-education/medical-education/residency/internal-medicine'),
('1402700213','https://www.nmhs.net/for-medical-professionals/training-programs/graduate-medical-education/internal-medicine-residency-program'),
('1400521047','https://www.uclaoliveview.org/'),
('1401131102','https://www.orlandohealth.com/medical-professionals/graduate-medical-education/residency-programs/internal-medicine-residency'),
('1400700074','https://www.uchealth.org/professionals/residencies/uchealth-parkview-internal-medicine-residency-program/'),
('1404031355','https://gme.providence.org/oregon/providence-portland-internal-medicine-residency/'),
('1401600545','https://www.riversidehealthcare.org/professional-education/gme/internal-medicine-residency-program'),
('1403500926','https://samaritanhealth.com/careers/careers-education/graduate-medical-education/internal-medicine/'),
('1401200001','https://www.sgmc.org/graduate-medical-education/internal-medicine-residency/'),
('1405431436','https://spokaneteachinghealth.org/internal-medicine/'),
('1402100002','https://www.fmolhs.org/research-education/graduate-medical-education/st-francis-internal-medicine-residency-program'),
('1403321522','https://stjosephshealth.org/education/graduate-medical-education/residency-programs/internal-medicine/im-overview/'),
('1404131360','https://www.slhn.org/gme/residencies/internal-medicine-residency-bethlehem'),
('1403321531','https://www.saintpetershcs.com/graduate-medical-education/internal-medicine-residency-program'),
('1401600544','https://www.endeavorhealth.org/academics-medical-education/residency-programs/swedish-hospital-internal-medicine-residency-swedish-hospital'),
('1404821519','https://www.ttuhsc.edu/programs/internal-medicine-residency-permian-basin'),
('1401512544','https://uwboisemedres.uw.edu/'),
('1400200001','https://akmedres.uw.edu/'),
('1403511317','https://www.wmcimresidency.org/'),
('1400811076','https://learning.nuvancehealth.org/residency-programs/internal-medicine-residency-program-at-danbury-hospital/'),
('1400500921','https://collegemedicalcenter.com/internal-medicine-home/'),
('1401112101','https://www.msmc.com/education/residency-programs/internal-medicine/'),
('1402521194','https://www.wsumed.com/'),
('1402511200','https://www.trinityhealthmichigan.org/graduate-medical-education/oakland/internal-medicine'),
('1403521485','https://www.sbhny.org/healthcare-professionals/residency-programs/internal-medicine-residency-program/'),
('1403512265','https://www.tbh.org/professional-medical-education/graduate-medical-education/internal-medicine'),
('1404711413','https://meharry.edu/residency-program/internal-medicine/'),
('1404231525','https://mayaguezmedical.com/educacion-medica-graduada/programa-de-residencia-de-medicina-interna/'),
('1404221397','https://md.rcm.upr.edu/medicine/program-overview/'),
('1404100906','https://jeffneinternal.com/'),
('1402411175','https://www.challiance.org/academics/medicine/internal-medicine-residency'),
('1403800002','https://www.wrhe-edu.org/internal-medicine'),
('1403511264','https://onebrooklynhealth.org/healthcare-professionals/internal-medicine-residency-brookdale'),
('1401611123','https://imr.bsd.uchicago.edu'),
('1400500017','https://www.sarh.org/sarh-residency-program'),
('1403521285','https://einsteinmed.edu/departments/medicine/education/residency/wakefield-internal-medicine/virtual-recruitment'),
('1404800010','https://www.dhrhealth.com/education/graduate-medical-education/internal-medicine-residency-program/'))
update cme_private.program_source_catalog_v43 c
set website_url=v.website_url,website_scope='program',website_verified_at=date '2026-10-02'
from verified v
join public.programs p on p.acgme_program_id=v.acgme_program_id
where c.acgme_program_id=v.acgme_program_id and c.program_id=p.id
and (c.website_url,c.website_scope,c.website_verified_at) is distinct from
    (v.website_url,'program',date '2026-10-02');
