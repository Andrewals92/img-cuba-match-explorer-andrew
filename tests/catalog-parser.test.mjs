import test from 'node:test';import assert from 'node:assert/strict';
import {parseAcgmePrograms,parseAamcPrograms,selectTargets} from '../supabase/functions/acgme-program-monitor/catalog-parser.mjs';
const acgme=(flags,icons='')=>`<select id="statusFilter"></select><table class="listview"><tr data-status-matches='${JSON.stringify(flags)}'><td></td><td>1400123456</td><td>Internal medicine</td><td>Program</td><td>Miami</td><td>${icons}</td></tr></table>`;
const er=(rows,season=2027,total=rows.length)=>`<h2>ERAS ${season} Participating Specialties</h2><table>${rows.map(([name,id,status])=>`<tr><td>Florida</td><td>Miami</td><td></td><td>${name}</td><td>${id}</td><td>${status}</td></tr>`).join('')}<tfoot><tr><td>${total} Programs</td></tr></tfoot></table>`;
const spec={name:'Internal Medicine',source_url:'https://systems.aamc.org/eras/erasstats/par/display.cfm?SPEC_CD=140'};
test('ACGME distinguishes withdrawn, unaccredited, future and hidden icons',()=>{
 assert.equal(parseAcgmePrograms(acgme({'5':1,'9':1}),'IM')[0].status,'Withdrawn');
 assert.equal(parseAcgmePrograms(acgme({'4':1}),'IM')[0].status,'Unaccredited Combined');
 assert.equal(parseAcgmePrograms(acgme({'1':1},'<span class="hidden" data-bs-content="Future Accredited"></span>'),'IM')[0].status,'Accredited');
 assert.equal(parseAcgmePrograms(acgme({'1':1},'<span class="icon-time" data-bs-content="Future Accredited"></span>'),'IM')[0].status,'Future Accredited');
});
test('ACGME permits explicit empty results and rejects broken pages',()=>{
 assert.deepEqual(parseAcgmePrograms('<select id="statusFilter"></select><div class="listview">No Programs found for the input and/or selected search criteria.</div>','IM'),[]);
 assert.throws(()=>parseAcgmePrograms('<html>unavailable</html>','IM'));
});
test('ERAS preserves conflicting preliminary/categorical tracks under one ID',()=>{
 const rows=parseAamcPrograms(er([['Preliminary','1400123456','Not Participating'],['Categorical','1400123456','Participating']]),spec,2027);
 assert.equal(rows.length,1);assert.equal(rows[0].status,'Mixed participation');assert.equal(rows[0].tracks.length,2);assert.equal(rows[0].state,'FL');
});
test('ERAS rejects wrong season, truncated tables and unrecognized statuses',()=>{
 assert.throws(()=>parseAamcPrograms(er([],2026),spec,2027));
 assert.throws(()=>parseAamcPrograms(er([['Program','1400123456','Participating']],2027,2),spec,2027));
 assert.throws(()=>parseAamcPrograms(er([['Program','1400123456','Unknown']]),spec,2027));
});
test('failed attempts rotate instead of starving unsynced specialties',()=>{
 const states=[{name:'Failed',last_attempt_at:new Date().toISOString()},{name:'Pending',last_attempt_at:null}];
 assert.equal(selectTargets(states,1)[0].name,'Pending');
});

test('ACGME accepts official medical-related M-prefixed IDs',()=>{assert.equal(parseAcgmePrograms(acgme({'1':1}).replace('1400123456','M010100001'),'Genetics')[0].acgme_program_id,'M010100001');});
