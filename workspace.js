/* Cuba Match Explorer v4.0 — vanilla JS workspace. No credentials or applicant data persisted here. */
(() => {
  'use strict';
  // Pure computation shared with regression tests. Declared zero is authoritative.
  function personalSummary(c, reports) {
    const rows = reports.filter(r => r.applicantCycleId === c.id);
    const unique = predicate => new Set(rows.filter(predicate).map(r => r.programId || [r.program, r.specialty, r.state].join('|'))).size;
    const detailedApplications = unique(r => r.applied), detailedInterviews = unique(r => r.interview);
    const applications = c.programsApplied ?? detailedApplications;
    const interviews = c.interviewInvites ?? detailedInterviews;
    return { applications, interviews, detailedApplications, detailedInterviews,
      applicationDeclared: c.programsApplied != null, interviewDeclared: c.interviewInvites != null,
      rate: applications > 0 && interviews <= applications ? Math.round(1000 * interviews / applications) / 10 : null,
      gold: unique(r => r.signal === 'Gold'), silver: unique(r => r.signal === 'Silver'),
      attended: unique(r => r.interviewAttended), ranked: unique(r => r.ranked),
      matches: rows.filter(r => r.matched), inconsistent: interviews > applications };
  }
  window.CMEPersonalSummary = personalSummary;
  window.CMEWorkspace = ({q,esc,rpc,cloudReady,getMyData,getUserId,toast,isAdmin,getSeason,getIntelligence}) => {
    const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const key = 'cme_compare_v4';
    const read = (k, fallback) => { try { return JSON.parse(localStorage.getItem(k)) ?? fallback; } catch { return fallback; } };
    const write = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* session state still works */ } };
    const validIds = ids => [...new Set((Array.isArray(ids) ? ids : []).filter(x => typeof x === 'string' && UUID.test(x)))].slice(0,5);
    let selected = validIds(read(key, [])), labels = [], indexLoaded = false;
    let directoryRun=0, viewRun=0, offset=0, searchTimer, lastFilter='', personalId='';
    const empty = text => `<div class="empty-state" role="status">${esc(text)}</div>`;
    const metric = (v,suffix='') => v == null ? '<span class="muted">No disponible</span>' : `${esc(v)}${suffix}`;
    const sourceLabel = p => p.identity_kind === 'community_label' ? 'Nombre comunitario · identidad oficial sin verificar' : 'Directorio oficial';
    const href = id => '#/program/' + encodeURIComponent(id);
    function programLink(r) {
      const name = r.name || r.program_name || r.program || r.program_name_snapshot || 'Programa';
      const direct = r.programId || r.program_id || (r.acgme_program_id ? r.id : null);
      const spec = r.specialty, state = r.state ?? r.state_snapshot;
      const matches = spec || state != null ? labels.filter(x => x.name===name && (!spec || x.specialty===spec) && (state==null || x.state===state)) : [];
      const id = UUID.test(direct || '') ? direct : matches.length===1 ? matches[0].id : null;
      return id ? `<a class="program-link" href="${href(id)}">${esc(name)}</a>` : `<button class="program-link link-button" data-program-search="${esc(name)}">${esc(name)}</button>`;
    }
    async function loadIdentityIndex() {
      if (!cloudReady()) return;
      labels = await rpc('program_identity_index_v4'); indexLoaded=true;
    }
    const compareButton = p => `<button class="btn ghost small" data-compare-id="${esc(p.id)}" aria-pressed="${selected.includes(p.id)}">${selected.includes(p.id) ? 'Quitar de Compare' : 'Añadir a Compare'}</button>`;
    function tray() {
      q('compareTray').innerHTML = `<a class="btn primary" href="#/compare">Compare (${selected.length})</a><span>Selecciona de 2 a 5 programas</span>`;
      document.querySelectorAll('[data-compare-id]').forEach(b => { const on=selected.includes(b.dataset.compareId); b.textContent=on?'Quitar de Compare':'Añadir a Compare'; b.setAttribute('aria-pressed',String(on)); });
    }
    async function loadDirectory(reset=false) {
      if (reset) offset=0;
      const filter=[q('programSearch').value,q('programSpecialty').value,q('programOutcome').value].join('|');
      if (filter!==lastFilter) offset=0;
      lastFilter=filter;
      const run=++directoryRun;
      q('programCards').innerHTML=empty('Cargando directorio…');
      q('programPager').innerHTML='';
      if (!cloudReady()) { q('programCards').innerHTML=empty('Conecta Supabase para consultar perfiles reales.'); return; }
      try {
        const data=await rpc('program_directory_v4',{p_query:q('programSearch').value.trim(),p_specialty:q('programSpecialty').value==='all'?null:q('programSpecialty').value,p_kind:q('programOutcome').value,p_offset:offset});
        if(run!==directoryRun)return;
        const rows=(data.programs||[]).slice(0,40);
        q('programCards').innerHTML=rows.length?rows.map(p=>`<article class="program-card"><span class="eyebrow">${esc(sourceLabel(p))}</span><h3><a class="program-link" href="${href(p.id)}">${esc(p.name)}</a></h3><p class="meta">${esc(p.specialty)} · ${esc([p.city,p.state].filter(Boolean).join(', ')||'Ubicación no disponible')}</p><p class="muted">ACGME ID: ${esc(p.acgme_program_id||'Sin verificar')}</p><div class="row-actions"><a class="btn ghost small" href="${href(p.id)}">Ver perfil</a>${compareButton(p)}${getSeason().tools(p)}</div></article>`).join(''):empty('No se encontraron programas con estos filtros.');
        q('programPager').innerHTML=`<button class="btn ghost" data-page="-1" ${offset===0?'disabled':''}>Anterior</button><span>Página ${Math.floor(offset/40)+1}</span><button class="btn ghost" data-page="1" ${!data.has_more?'disabled':''}>Siguiente</button>`;
      } catch(e) { if(run===directoryRun)q('programCards').innerHTML=empty('No se pudo cargar el directorio. '+e.message)+ '<button class="btn ghost" data-workspace-retry="programs">Reintentar</button>'; }
    }
    function renderPrograms() { clearTimeout(searchTimer); searchTimer=setTimeout(()=>loadDirectory(),220); }
    function cycleOptions(value) {
      const years=new Set([...q('globalCycle').options].map(o=>o.value).filter(x=>x!=='all'));
      if(value!=='all')years.add(String(value));
      return '<option value="all">Todos los ciclos disponibles</option>'+[...years].sort().map(y=>`<option value="${esc(y)}" ${String(value)===y?'selected':''}>${esc(y)}</option>`).join('');
    }
    function route() {
      const [path,query='']=location.hash.replace(/^#\/?/,'').split('?');
      const params=new URLSearchParams(query),value=params.get('cycle')||'all';
      return {path,params,cycle:/^20\d{2}$/.test(value)?Number(value):null};
    }
    function officialLinks(p) {
      const defaults={acgme:['ACGME','https://apps.acgme.org/ads/Public/Programs/Search'],freida:['FREIDA','https://freida.ama-assn.org/'],residency_explorer:['Residency Explorer','https://www.residencyexplorer.org/']};
      return `<div class="program-website">${getIntelligence().website(p.resources||[])}</div><div class="source-links">${Object.entries(defaults).map(([source,[name,url]])=>{
        const candidate=(p.links||[]).find(l=>l.source===source)?.url;
        if(candidate && /^https:\/\//i.test(candidate))url=candidate;
        return `<a class="source-link" href="${esc(url)}" target="_blank" rel="noopener noreferrer">${name} ↗</a>`;
      }).join('')}</div>`;
    }
    function timeline(p) {
      const rows=p.timeline||[],max=Math.max(1,...rows.map(x=>x.invitations));
      return rows.length?`<ul class="program-timeline" aria-label="Invitaciones por mes">${rows.map(x=>`<li><span>${esc(x.month)}</span><div class="bar-track"><span class="bar-fill" style="display:block;width:${100*x.invitations/max}%"></span></div><b>${esc(x.invitations)}</b></li>`).join('')}</ul>`:empty('No hay actividad con fecha que alcance el umbral de privacidad. Fechas no reportadas no se interpretan como cero.');
    }
    const statsRows=[['Perfiles de ciclo reportados','applicant_profiles'],['Aplicaciones documentadas','applications'],['Invitaciones','interviews'],['Interview rate¹','interview_rate','%'],['Matches · ciclos completos','matches'],['Match rate¹ · ciclos completos','match_rate','%']];
    function privacyNote() { return '<p class="workspace-note">No disponible = sin datos suficientes, dato no reportado o muestra protegida. Perfiles y características: mínimo 5 personas; resultados y meses: mínimo 3. No se muestran filas individuales.</p><p class="workspace-note">¹ Tasas calculadas solo sobre aplicaciones detalladas de usuarios, no sobre invitaciones importadas ni totales personales. Match rate usa ciclos completos (a partir del 21 de marzo del año de Match). Las muestras comunitarias no representan a todos los solicitantes.</p>'; }
    function statGrid(p) { return `<div class="workspace-kpis">${statsRows.map(([label,k,suffix])=>`<div class="kpi"><span>${label}</span><strong>${metric(p[k],suffix||'')}</strong></div>`).join('')}</div>`; }
    function signals(p) { return `<dl class="workspace-details"><div><dt>Gold</dt><dd>${metric(p.signals?.gold)}</dd></div><div><dt>Silver</dt><dd>${metric(p.signals?.silver)}</dd></div><div><dt>Sin señal reportada</dt><dd>${metric(p.signals?.none)}</dd></div><div><dt>Señal sin tipo</dt><dd>${metric(p.signals?.other)}</dd></div></dl>`; }
    function metadata(p) { return `<p>${esc(p.specialty)} · ${esc([p.city,p.state].filter(Boolean).join(', ')||'Ubicación no disponible')}</p><p>ACGME ID: <strong>${esc(p.acgme_program_id||'Sin verificar')}</strong></p><p>Estado: ${esc(p.accreditation?.status||(p.identity_kind==='official'?(p.active?'Activo en directorio; acreditación no reportada':'Inactivo en directorio'):'Identidad oficial sin verificar'))}</p>${p.identity_kind==='community_label'?'<p class="workspace-warning">Este nombre procede de reportes comunitarios. No se ha vinculado a un programa oficial; sus métricas no se atribuyen a una entrada del catálogo ACGME.</p>':''}${officialLinks(p)}`; }
    function toolbar(type,cycle) { return `<div class="workspace-toolbar"><a class="btn ghost small" href="#/programs">← Program Explorer</a><label>Ciclo de estos datos<select id="workspaceCycle" data-workspace-cycle="${type}">${cycleOptions(cycle??'all')}</select></label><button class="btn ghost small" data-share-workspace>Copiar enlace</button></div>`; }
    async function loadView() {
      const r=route(),isCompare=r.path.split('/')[0]==='compare',target=q(isCompare?'compareContent':'programProfileContent'),run=++viewRun;
      let ids;
      if(isCompare) {
        if(r.params.has('ids')) { selected=validIds(r.params.get('ids').split(','));write(key,selected); }
        ids=selected;
        history.replaceState(null,'', '#/compare?ids='+ids.join(',')+'&cycle='+(r.cycle??'all'));
      } else ids=validIds([r.path.split('/')[1]]);
      tray();
      target.innerHTML=toolbar(isCompare?'compare':'program',r.cycle)+empty('Cargando datos protegidos…');
      if(isCompare && ids.length<2) { target.innerHTML=toolbar('compare',r.cycle)+empty('Selecciona de 2 a 5 programas en Program Explorer para comparar.') + '<a class="btn primary" href="#/programs">Elegir programas</a>';return; }
      if(!ids.length) {target.innerHTML=toolbar('program',r.cycle)+empty('Enlace de programa inválido. Abre un programa desde el directorio.');return;}
      try {
        const [rows,intel,resources]=await Promise.all([rpc('program_compare_stats',{p_ids:ids,p_cycle:r.cycle}),rpc('program_season_intelligence_v43',{p_ids:ids,p_cycle:r.cycle}),rpc('program_resources_v43',{p_ids:ids})]);
        rows.forEach(p=>{p.v43=intel.find(x=>x.id===p.id);p.resources=resources.filter(x=>x.program_id===p.id);});
        if(run!==viewRun)return;
        if(rows.length!==ids.length)throw new Error('Uno de los programas ya no está disponible. Vuelve al directorio para seleccionarlo.');
        if(!isCompare) {
          const p=rows[0],c=p.characteristics||{};
          target.innerHTML=toolbar('program',r.cycle)+`<article class="panel"><span class="eyebrow">${esc(sourceLabel(p))}</span><h2 class="workspace-title" tabindex="-1">${esc(p.name)}</h2>${metadata(p)}<div class="row-actions">${compareButton(p)}${getSeason().tools(p)}<a class="btn ghost small" href="#/compare">Abrir Compare</a></div></article>${getSeason().own(p)}${getIntelligence().resources(p.resources)}${getIntelligence().sections(p.v43)}<article class="panel"><h3>Datos comunitarios</h3>${p.data_state==='no_reports'?empty('No hay reportes comunitarios para este período.'):p.data_state==='insufficient'?empty('Datos comunitarios insuficientes.'):''}${statGrid(p)}${privacyNote()}</article><div class="grid-2"><article class="panel"><h3>Señales reportadas</h3>${signals(p)}</article><article class="panel"><h3>Características del grupo</h3><dl class="workspace-details">${[['Step 2 CK · mediana',c.step2],['YOG · mediana',c.yog],['USCE meses · mediana',c.usce],['LoRs · mediana',c.lors],['Visa requerida (%)',c.visa_percent]].map(([k,v])=>`<div><dt>${k}</dt><dd>${metric(v)}</dd></div>`).join('')}</dl></article></div><article class="panel"><h3>Invitaciones por mes</h3>${timeline(p)}<p class="workspace-note">Última actividad visible: ${esc(p.last_activity_month||'No disponible')} · Directorio actualizado: ${esc(p.directory_updated_at?.slice(0,10)||'No disponible')}</p></article>`;
        } else {
          const cross=new Set(rows.map(p=>String(p.specialty).toLowerCase())).size>1;
          const compareRows=[['Especialidad',p=>esc(p.specialty)],['Ciudad / estado',p=>esc([p.city,p.state].filter(Boolean).join(', ')||'No disponible')],['ACGME ID',p=>esc(p.acgme_program_id||'Sin verificar')],['Fuentes oficiales',officialLinks],...statsRows.map(([name,k,suffix])=>[name,p=>metric(p[k],suffix||'')]),...getIntelligence().compareRows,['Señales',signals],['Invitaciones por mes',timeline],['Última actividad visible',p=>esc(p.last_activity_month||'No disponible')],['Actualización del directorio',p=>esc(p.directory_updated_at?.slice(0,10)||'No disponible')]];
          target.innerHTML=toolbar('compare',r.cycle)+`<article class="panel"><h2>Program Compare</h2><p>Datos documentados para tu decisión. Sin puntuación global, ganadores ni rankings.</p>${cross?'<p class="workspace-warning" role="status">Comparación entre especialidades: los procesos, cupos y uso de señales difieren. Sus tasas no son directamente comparables.</p>':''}<p class="workspace-note">En móvil, desliza la tabla horizontalmente para ver todos los programas.</p><div class="compare-scroll" tabindex="0" role="region" aria-label="Comparación de programas"><table class="compare-table"><caption class="sr-only">Comparación de ${rows.length} programas</caption><thead><tr><th scope="col">Datos</th>${rows.map(p=>`<th scope="col"><a class="program-link" href="${href(p.id)}?cycle=${r.cycle??'all'}">${esc(p.name)}</a><small>${esc(sourceLabel(p))}</small>${getSeason().tools(p)}<button class="btn ghost small" data-remove-compare="${esc(p.id)}" aria-label="Quitar ${esc(p.name)}">Quitar</button></th>`).join('')}</tr></thead><tbody>${compareRows.map(([name,fn])=>`<tr><th scope="row">${name}</th>${rows.map(p=>`<td>${fn(p)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>${privacyNote()}</article>`;
        }
      } catch(e) { if(run===viewRun)target.innerHTML=toolbar(isCompare?'compare':'program',r.cycle)+empty('No se pudieron cargar los datos. '+e.message)+'<button class="btn ghost" data-workspace-retry="view">Reintentar</button>'; }
    }
    function renderPersonal() {
      const el=q('myMatchContent'),uid=getUserId(),data=getMyData();
      if(!uid) {el.innerHTML='<div class="my-match-intro"><div><span class="eyebrow">Tu espacio personal</span><h2>My Match</h2><p>Organiza tus aplicaciones, entrevistas y próximos pasos.</p></div><button class="btn primary" data-go="account">Iniciar sesión / Crear cuenta</button></div>';return;}
      if(!data.cycles.length) {el.innerHTML='<h2>My Match</h2><p>Aún no tienes un perfil de ciclo.</p><button class="btn primary" data-go="data">Create my profile · Crear mi perfil</button>';return;}
      const preference=read('cme_my_cycle_'+uid,null);
      const c=data.cycles.find(c=>c.id===(personalId||preference))||data.cycles[0];personalId=c.id;
      const s=personalSummary(c,data.reports),missing=c.missingFields||[];
      const card=(name,val,help)=>`<div class="kpi"><span>${name}</span><strong>${val}</strong><small>${help||''}</small></div>`;
      el.innerHTML=`<div class="my-match-intro"><div><span class="eyebrow">Privado · solo tu cuenta</span><h2>My Match</h2></div><label>Mi perfil de ciclo<select id="personalCycle">${data.cycles.map(x=>`<option value="${esc(x.id)}" ${x.id===c.id?'selected':''}>${esc(x.cycle)} · ${esc(x.specialty)}</option>`).join('')}</select></label></div><p class="workspace-note">Este selector es independiente del ciclo comunitario y de “Comparar con” en Applicant Explorer.</p>${missing.length?`<p class="workspace-warning">Completa ${esc(missing.join(', '))} para mejorar tu panel. <button class="program-link link-button" data-go="data">Ir a Mis datos</button></p>`:''}<div class="workspace-kpis">${card('Programs applied',s.applications,s.applicationDeclared?'Total declarado en Mis datos':'Solo programas en reportes detallados')}${card('Interview invitations',s.interviews,s.interviewDeclared?'Total declarado en Mis datos':'Solo programas en reportes detallados')}${card('Interview rate',metric(s.rate,'%'),'Sobre los totales mostrados')}${card('Gold usadas',s.gold,'Reportadas · cupo disponible desconocido')}${card('Silver usadas',s.silver,'Reportadas · cupo disponible desconocido')}${card('Entrevistas realizadas',s.attended,'Programas marcados como entrevistados')}${card('Ranked',s.ranked,'Programas marcados en tus reportes')}${card('Match',s.matches.length?'Match reportado':Number(c.cycle)>new Date().getUTCFullYear() || new Date()<new Date(Date.UTC(Number(c.cycle),2,21))?'En curso':'Sin resultado reportado',s.matches.map(programLink).join('<br>'))}</div><p class="workspace-note">Reportes detallados: ${s.detailedApplications} programas con aplicación y ${s.detailedInterviews} con invitación. Los totales declarados tienen prioridad aunque sean distintos; nunca se suman a los reportes.</p>${s.inconsistent?'<p class="workspace-warning">Las invitaciones superan las aplicaciones declaradas. Revisa los totales en Mis datos; la tasa no se calcula hasta corregirlos.</p>':''}<ol class="match-funnel" aria-label="Progreso del ciclo">${[['Applications',s.applications],['Interviews',s.interviews],['Ranked',s.ranked],['Matched',new Set(s.matches.map(r=>r.programId||r.program)).size]].map(([name,n])=>`<li><span>${name}</span><strong>${n}</strong><div class="bar-track"><span class="bar-fill" style="display:block;width:${Math.min(100,100*n/Math.max(s.applications,s.interviews,1))}%"></span></div></li>`).join('')}</ol><button class="btn ghost" data-go="data">Actualizar Mis datos</button>`;
    }
    async function health() {
      if(!isAdmin())return;
      try {const h=await rpc('program_workspace_health_v4',{},false),v43=await rpc('intelligence_health_v43',{},false);q('workspaceHealth').textContent=`v${v43.version} · ${v43.program_source_records} fuentes / ${v43.linked_source_records} vinculadas · ${v43.qualifying_program_weeks} semanas protegidas · Agregación disponible · ${h.official_programs} programas oficiales · ${h.community_labels} identidades comunitarias · ${h.programs_with_reports} programas con reportes · Actualización: ${h.last_report_update?.slice(0,10)||'—'}`;}
      catch {q('workspaceHealth').textContent='No se pudo verificar la salud de los agregados v4.0.';}
    }
    document.addEventListener('change',e=>{
      if(e.target.id==='personalCycle') {personalId=e.target.value;write('cme_my_cycle_'+getUserId(),personalId);renderPersonal();}
      if(e.target.matches('[data-workspace-cycle]')) {const r=route();r.params.set('cycle',e.target.value);location.hash='#/'+r.path+'?'+r.params.toString();}
    });
    document.addEventListener('click',async e=>{
      const add=e.target.closest('[data-compare-id]'),remove=e.target.closest('[data-remove-compare]');
      if(add || remove) {
        const id=add?.dataset.compareId||remove.dataset.removeCompare;
        if(selected.includes(id)) selected=selected.filter(x=>x!==id);
        else if(selected.length===5) return toast('Puedes comparar un máximo de 5 programas. Quita uno para añadir otro.','bad');
        else selected.push(id);
        write(key,selected);tray();
        if(remove) {history.replaceState(null,'','#/compare?ids='+selected.join(',')+'&cycle='+(route().cycle??'all'));loadView();}
      }
      const pg=e.target.closest('[data-page]');if(pg){offset=Math.max(0,offset+Number(pg.dataset.page)*40);loadDirectory();}
      const search=e.target.closest('[data-program-search]');if(search){q('programSearch').value=search.dataset.programSearch;q('programSpecialty').value='all';q('programOutcome').value='all';location.hash='#/programs';loadDirectory(true);}
      const retry=e.target.closest('[data-workspace-retry]');if(retry){retry.dataset.workspaceRetry==='view'?loadView():loadDirectory();}
      if(e.target.closest('[data-share-workspace]')) {
        try {await navigator.clipboard.writeText(location.origin+location.pathname+location.hash);toast('Enlace copiado.');}
        catch {toast('Copia el enlace desde la barra de direcciones.');}
      }
    });
    tray();
    return {renderPrograms,loadDirectory,loadView,renderPersonal,loadIdentityIndex,programLink,health,tray};
  };
})();
