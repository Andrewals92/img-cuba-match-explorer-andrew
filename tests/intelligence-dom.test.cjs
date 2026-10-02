const {JSDOM}=require('jsdom'),fs=require('fs'),assert=require('assert');
(async()=>{
 const d=new JSDOM(fs.readFileSync('v43/index.html','utf8'),{url:'https://cubamatchexplorer.org/#/waves',runScripts:'outside-only'}),w=d.window,q=id=>w.document.getElementById(id);
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let uid=null,fail=false,calls=[];
 const p={id:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',name:'Safe <script>program</script>',specialty:'Internal Medicine',timeline:[],signals:[{signal:'Gold',state:'insufficient',applications:null,rate:null}],activity:'Insufficient data',context:'Current / incomplete cycle'};
 const rpc=async(name,args)=>{calls.push({name,args});if(fail)throw Error('offline');return name==='specialty_wave_overview_v43'?{programs:[p]}:name==='program_source_directory_v43'?{programs:[{name:'External program',source:'Residency Explorer',program_url:'https://www.residencyexplorer.org/',fields:{'Interview Rate — Gold Signal':.26}}]}:[p];};
 w.eval(fs.readFileSync('v43/intelligence.js','utf8'));
 const i=w.CMEIntelligence({q,esc,rpc,getSeason:()=>({tools:()=>'',getSaved:()=>[p]}),getMyData:()=>({cycles:[{id:'cycle',cycle:2027}]}),getUserId:()=>uid});
 await i.load();assert(q('waveResults').textContent.includes('Datos insuficientes'));assert(!q('waveResults').querySelector('script'));assert(!q('waveResults').textContent.includes('null'));assert.equal(calls[0].args.p_cycle,2027);
 q('waveCycle').value='all';await i.load();assert.equal(calls.at(-1).args.p_cycle,null);
 await i.loadSources();assert(q('sourceResults').textContent.includes('26.0%'));assert(!q('sourceResults').textContent.includes('My Interview'));
 assert(!/Residency Explorer|Match A Resident|abrir fuente/.test(q('sourceResults').textContent));
 const resources=[{kind:'interview_rates',source_cycle:2026,website_url:'https://hospital.example/residency',website_scope:'program',fields:{'Interview Rate — Gold Signal':.3,'Interview Rate — Silver Signal':.1,'Interview Rate — No Signal':0,'Interview Rate (Average Likelihood)':'!','Interview Rate — DO':Infinity}}];
 const html=i.resources(resources);assert(html.includes('30.0%')&&html.includes('10.0%')&&html.includes('0.0%'));assert(html.includes('+30.0 puntos')&&html.includes('+20.0 puntos'));assert(!html.includes('Infinity')&&!html.includes('>!</dd>'));assert(html.includes('Dato no disponible'));assert(html.includes('no son tu probabilidad personal'));
 assert(i.resources([{...resources[0],website_url:'javascript:alert(1)'}]).indexOf('href="javascript:')===-1);
 assert(i.resources([{...resources[0],website_scope:'institution'}]).includes('Web de la institución'));
 assert(i.strategy([{fields:{'Interview Rate — Gold Signal':'!'}}]).includes('No hay suficientes tasas'));
 assert(i.compareRows.filter(r=>r[0].includes('tasa del programa')).length===3);
 const callsBefore=calls.length;await i.loadSources();assert.equal(calls.length,callsBefore+1);
 
 await i.saved();assert(q('matchIntelligence').textContent.includes('Interview Wave Tracker'));assert.equal(calls.filter(c=>c.name==='program_season_intelligence_v43').length,0);
 uid='own-user';await i.saved();assert(q('matchIntelligence').textContent.includes('0 guardados'));assert.equal(calls.at(-1).args.p_cycle,2027);
 const safe=i.signals({...p,signals:[{signal:'Gold',state:'available',applications:6,interviews:3,rate:50}]});assert(safe.includes('n=6')&&safe.includes('3 entrevistas / 6 aplicaciones'));
 fail=true;await i.load();assert(q('waveResults').querySelector('[data-wave-retry]'));d.window.close();
 console.log('PASS guide: grouped cards, neutral provider labels, zero vs missing rates, signal differences, safe URLs, one batched request; wave cycle semantics, suppression UI, escaped source text, typed rates, private dashboard guard, denominators, error retry');
})();
