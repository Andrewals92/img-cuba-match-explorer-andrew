/* v5.3 — Public professional education evidence, served through the protected gateway. */
(() => {
 'use strict';
 const roles={resident:'Residente',chief:'Chief resident',fellow:'Fellow',faculty:'Faculty',leadership:'Dirección del programa',alumnus:'Egresado/a'};
 const times={current:'Actual según la fuente',historical:'Histórico / Alumni',last_seen_unknown:'Vigencia por confirmar'};
 const education={attended:'Estudios en Cuba · título no confirmado en Cuba',graduated:'Graduación en Cuba documentada',medical_education:'Formación médica en Cuba documentada'};
 const safeUrl=value=>{try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password?u.href:null;}catch{return null;}};
 window.CMEPresence=({q,esc,rpc,getSeason,getWorkspace})=>{
  let offset=0,run=0,optionsLoaded=false,restoring=false;
  const form=q('presenceFilters');
  const select=(name,label,options)=>`<label>${label}<select name="${name}">${Object.entries(options).map(([v,t])=>`<option value="${v}">${t}</option>`).join('')}</select></label>`;
  form.innerHTML=`<label>Programa o institución<input name="query" maxlength="160" placeholder="Nombre o ACGME ID"></label><label>Especialidad<input name="specialty" list="specialtyList" placeholder="Todas las especialidades"></label><label>Estado<input name="state" maxlength="2" placeholder="FL, NY, IL…" autocapitalize="characters"></label><label>Ciudad<input name="city" maxlength="100" placeholder="Todas las ciudades"></label>
   ${select('evidence','Formación en Cuba',{documented:'Con evidencia documentada',all:'Todo el catálogo',unknown:'Pendiente / evidencia desconocida',no_public_evidence:'Revisado, sin evidencia encontrada'})}
   ${select('time','Período',{all:'Actual e histórico',...times})}${select('role','Rol profesional',{all:'Todos los roles',...roles})}
   ${select('school','Escuela de medicina',{all:'Todas las escuelas en Cuba'})}${select('education','Evidencia de formación',{all:'Cualquier formación médica',graduated:'Graduación documentada',attended:'Estudios cursados',medical_education:'Escuela documentada; grado sin precisar'})}
   ${select('minimum','Personas documentadas',{0:'Sin mínimo',1:'Al menos una',2:'Dos o más',5:'Cinco o más'})}
   ${select('latino','Presencia latina institucional',{all:'Sin filtro',aggregate_evidence:'Con datos institucionales agregados'})}
   <label>Año de clase o período<input name="year" type="number" min="1900" max="2100" placeholder="Ej. 2029"></label>
   <details class="presence-extra"><summary>Combinar con métricas de entrevista y signals</summary><div class="season-form-grid"><label>Tasa de entrevista Non-US IMG mínima (%)<input name="img_min" type="number" min="0" max="100" step="0.1" placeholder="Sin mínimo"></label>${select('signal','Grupo de la tasa',{all:'General',gold:'Gold signal',silver:'Silver signal',none:'Sin signal'})}<label>Tasa de entrevista mínima (%)<input name="signal_min" type="number" min="0" max="100" step="0.1" placeholder="Sin mínimo"></label></div><p class="workspace-note">Solo se incluyen programas con esa métrica reportada en la guía importada. Son tasas observadas en la fuente, no probabilidades personales ni medidas de presencia.</p></details>
   <div class="row-actions presence-submit"><button class="btn primary" type="submit">Buscar programas</button><button class="btn ghost" type="reset">Restablecer</button></div>`;
  const empty=message=>`<div class="empty-state">${esc(message)}</div>`;
  const n=value=>value==null?'Por verificar':esc(value);
  const date=value=>value?esc(value.slice(0,10)):'Pendiente';
  const link=(url,label)=>{const safe=safeUrl(url);return safe?`<a href="${esc(safe)}" target="_blank" rel="noopener noreferrer">${esc(label)} ↗</a>`:esc(label);};
  function badge(s){
   if(!s)return '<p class="workspace-note">Evidencia profesional por verificar.</p>';
   const status=s.status==='documented'?'<span class="presence-badge">Formación médica en Cuba</span>':`<span class="presence-badge subtle">${s.status==='no_public_evidence'?'Sin evidencia en las fuentes revisadas':'Revisión pendiente / parcial'}</span>`;
   return `<div class="presence-summary">${status}${s.latino_status==='aggregate_evidence'?'<span class="presence-badge aggregate">Presencia latina · dato agregado</span>':''}${s.status==='documented'?`<p><b>${n(s.total_count)}</b> personas documentadas · ${n(s.current_count)} actuales · ${n(s.historical_count)} históricas${s.unknown_count?` · ${n(s.unknown_count)} por confirmar`:''}</p>`:''}<small>Verificación: ${date(s.verified_at)}</small></div>`;
  }
  function source(s){return s?`<li>${link(s.url,s.name||'Fuente profesional')}<p>${esc(s.note||'')}</p><small>Verificada: ${date(s.verified_at)} · Fuente ${s.type==='institutional'?'institucional':'profesional'}</small></li>`:'';}
  function person(p){
   const linkedin=safeUrl(p.linkedin_url);
   const validLinkedin=linkedin&&/^https:\/\/(?:[a-z]+\.)?linkedin\.com\/in\/[^/?#]+\/?$/.test(linkedin);
   return `<article class="presence-person"><div class="presence-person-head"><h4>${esc(p.full_name)}</h4><span class="presence-badge subtle">${esc(roles[p.role]||'Rol por verificar')}</span></div><p>${esc(p.school_name)} · Cuba</p><p class="workspace-note">${esc(education[p.education_status]||'Formación por verificar')}${p.pgy?` · PGY-${esc(p.pgy)}`:''}${p.class_year?` · Clase ${esc(p.class_year)}`:''}${p.start_year||p.end_year?` · Período ${esc(p.start_year||'?')}–${esc(p.end_year||'?')}`:''}</p><details><summary>Ver evidencia · confianza ${p.confidence==='high'?'alta':'moderada'}</summary><ul class="presence-sources">${source(p.education_source)}${p.source?.url===p.education_source?.url&&p.source?.note===p.education_source?.note?'':source(p.source)}</ul></details><div class="presence-linkedin">${validLinkedin?link(linkedin,'LinkedIn · identidad contrastada'):'LinkedIn: no identificado públicamente con confianza.'}<small>Búsqueda: ${date(p.linkedin_checked_at)}</small></div><p class="workspace-note">Vínculo verificado: ${date(p.verified_at)}</p></article>`;
  }
  function sections(record){
   if(!record)return `<article class="panel">${empty('La evidencia profesional no pudo cargarse. Vuelve a abrir el perfil para reintentar.')}</article>`;
   const s=record.presence||{},people=record.people||[],agg=record.aggregates||[];
   return `<article class="panel presence-detail"><span class="eyebrow">Evidencia profesional</span><h3>Formación en Cuba y presencia latina institucional</h3>${badge(s)}<p class="workspace-note">La formación médica en Cuba no implica nacionalidad cubana. Los conteos son personas distintas documentadas, no el total del programa.</p>${Object.entries(times).map(([key,label])=>{const group=people.filter(p=>p.effective_status===key);return group.length?`<section class="presence-group"><h4>${label}</h4><div class="presence-people">${group.map(person).join('')}</div></section>`:'';}).join('')}${!people.length?empty(s.status==='no_public_evidence'?'No se encontraron casos en las fuentes revisadas. Esto no demuestra que nunca los haya habido.':'Aún no hay evidencia individual publicada para este programa. La revisión está pendiente o es parcial.'):''}${agg.length?`<section class="presence-group"><h4>Presencia latina · información institucional agregada</h4>${agg.map(a=>`<div class="presence-aggregate"><strong>${a.percentage==null?'Dato agregado':esc(a.percentage)+'%'}</strong><div><p>${esc(a.scope)}</p><p>${esc(a.period_label)} · Consultado ${date(a.verified_at)}</p><ul class="presence-sources">${source(a.source)}</ul></div></div>`).join('')}</section>`:'<p class="workspace-note">Presencia latina: dato institucional agregado no identificado. No se clasifican personas por etnia o nacionalidad.</p>'}<details class="presence-method"><summary>Alcance de la revisión</summary><p>${esc(record.review?.notes||'Programa pendiente de revisión. No se interpreta como ausencia de personas formadas en Cuba.')}</p><p>Cobertura: ${esc({high:'amplia',medium:'intermedia',limited:'limitada'}[s.completeness]||'limitada')}. Próxima revisión prevista: ${date(s.next_review_at)}.</p><p>La confianza de cada evidencia y la cobertura del programa son distintas. Un caso bien documentado no equivale a un censo completo.</p></details><a class="btn ghost small" href="#/presence">Abrir búsqueda avanzada</a></article>`;
  }
  const compareRows=[['Formación médica en Cuba',p=>badge(p.professional?.presence)],['Personas actuales documentadas',p=>n(p.professional?.presence?.current_count)],['Personas históricas documentadas',p=>n(p.professional?.presence?.historical_count)],['Total de personas distintas',p=>n(p.professional?.presence?.total_count)],['Evidencia profesional',p=>`<a href="#/program/${esc(p.id)}">Ver personas, escuelas y fuentes</a>`]];
  function filters(){return Object.fromEntries([...new FormData(form)].filter(([,v])=>v!==''));}
  function readHash(){
   const params=new URLSearchParams(location.hash.split('?')[1]||'');
   restoring=true;form.reset();restoring=false;
   for(const [k,v] of params){const el=form.elements.namedItem(k);if(el&&typeof el.value==='string')el.value=v;}
   // A school URL can arrive before the option list. Preserve it until the overview loads.
   return Object.fromEntries([...params].filter(([k])=>!!form.elements.namedItem(k)).length?[...params].filter(([k])=>!!form.elements.namedItem(k)):Object.entries(filters()));
  }
  function navigate(f){offset=0;const hash='#/presence?'+new URLSearchParams(f).toString();if(location.hash===hash)load();else location.hash=hash;}
  const breakdown=(title,rows)=>`<div><h4>${title}</h4>${rows.length?`<ul class="presence-breakdown">${rows.map(x=>`<li><span>${esc(x.label)}</span><b>${esc(x.count)}</b></li>`).join('')}</ul>`:'<p class="muted">Sin registros documentados con estos filtros.</p>'}</div>`;
  function analytics(d){
   const t=d.totals,c=d.coverage;
   q('presenceAnalytics').innerHTML=`<article class="panel"><div class="panel-head"><div><span class="eyebrow">Mapa de evidencia</span><h3>Programas que coinciden con tu búsqueda</h3></div><button class="btn ghost small" data-presence-florida>Vista Florida</button></div><div class="workspace-kpis">${[['Programas con formación en Cuba',t.programs],['Con presencia actual',t.current],['Con presencia histórica',t.historical],['Personas distintas documentadas',t.people],['Con dato latino agregado',t.latino]].map(([label,value])=>`<div class="kpi"><span>${label}</span><strong>${esc(value)}</strong></div>`).join('')}</div><p class="workspace-note">Los indicadores describen todos los casos documentados de los programas encontrados. Una misma persona puede aparecer en más de un programa; se cuenta una sola vez en el total de personas.</p><details><summary>Distribución por estado, especialidad y escuela</summary><div class="presence-distributions">${breakdown('Estados · programas',d.states)}${breakdown('Especialidades · programas',d.specialties)}${breakdown('Escuelas · personas distintas',d.schools)}</div><h4>Programas con más casos documentados</h4><ol class="presence-top">${d.top_programs.map(p=>`<li><a href="#/program/${esc(p.id)}">${esc(p.name)}</a> <b>${esc(p.count)}</b></li>`).join('')}</ol><p class="workspace-note">Cantidad documentada, no ranking de calidad ni de probabilidad de Match.</p></details><p class="presence-coverage">Cobertura del catálogo oficial: <b>${esc(c.reviewed)}</b> de <b>${esc(c.catalog)}</b> programas con alguna fuente revisada; <b>${esc(c.complete_reviews)}</b> revisiones completas. Los demás están pendientes.</p></article>`;
   if(!optionsLoaded){const el=form.elements.namedItem('school'),value=new URLSearchParams(location.hash.split('?')[1]||'').get('school')||el.value;el.innerHTML='<option value="all">Todas las escuelas en Cuba</option>'+d.school_options.map(x=>`<option value="${esc(x.id)}">${esc(x.name)}</option>`).join('');el.value=value;optionsLoaded=true;}
  }
  async function load(fromHash=true){
   const current=++run,f=fromHash?readHash():filters();
   q('presenceResults').innerHTML=empty('Consultando evidencia profesional…');q('presencePager').innerHTML='';q('presenceAnalytics').innerHTML='';
   try{
    const [d,a]=await Promise.all([rpc('presence_directory_v53',{p_filters:f,p_offset:offset,p_limit:40}),rpc('presence_overview_v53',{p_filters:f})]);
    if(current!==run)return;analytics(a);
    q('presenceResults').innerHTML=`<p class="workspace-note">${esc(d.total)} programas encontrados · ${offset+1>Number(d.total)?0:offset+1}–${Math.min(offset+40,d.total)}. Los conteos no representan todos los médicos del programa.</p><div class="card-grid">${d.programs.map(p=>`<article class="program-card presence-program"><span class="eyebrow">${esc(p.specialty)}</span><h3><a class="program-link" href="#/program/${esc(p.id)}">${esc(p.name)}</a></h3><p class="meta">${esc([p.city,p.state].filter(Boolean).join(', ')||'Ubicación por verificar')}</p>${badge(p.presence)}<div class="row-actions"><a class="btn primary small" href="#/program/${esc(p.id)}">Ver personas y evidencia</a><button class="btn ghost small" data-compare-id="${esc(p.id)}">Añadir a Compare</button>${getSeason().tools(p)}</div></article>`).join('')}</div>${d.programs.length?'':empty('No hay programas con evidencia que coincida con estos filtros. Amplía la búsqueda; no significa que esa trayectoria no exista.')}`;
    q('presencePager').innerHTML=`<button class="btn ghost" data-presence-page="-1" ${offset===0?'disabled':''}>Anterior</button><span>Página ${Math.floor(offset/40)+1}</span><button class="btn ghost" data-presence-page="1" ${!d.has_more?'disabled':''}>Siguiente</button>`;getWorkspace().tray();
   }catch(e){if(current===run){q('presenceResults').innerHTML=empty('No se pudo consultar la evidencia. '+e.message)+'<button class="btn ghost" data-presence-retry>Reintentar</button>';q('presenceAnalytics').innerHTML='';}}
  }
  form.addEventListener('submit',e=>{e.preventDefault();navigate(filters());});
  form.addEventListener('reset',e=>{if(!restoring){e.preventDefault();navigate({evidence:'documented'});}});
  document.addEventListener('click',e=>{
   const pg=e.target.closest('[data-presence-page]');if(pg){offset=Math.max(0,offset+40*Number(pg.dataset.presencePage));load(false);}
   if(e.target.closest('[data-presence-retry]'))load(false);
   if(e.target.closest('[data-presence-florida]'))navigate({...filters(),state:'FL'});
   if(e.target.closest('[data-presence-latino]'))navigate({evidence:'all',latino:'aggregate_evidence'});
  });
  window.addEventListener('hashchange',()=>{offset=0;});
  return {load,sections,badge,compareRows,safeUrl};
 };
})();
