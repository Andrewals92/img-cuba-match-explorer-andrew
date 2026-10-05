(() => {
 'use strict';
 // Deterrents only: browsers cannot prevent OS screenshots, external cameras,
 // screen recording, DevTools extraction, or a human transcribing visible data.
 const layer=document.createElement('div');layer.id='contentWatermark';layer.setAttribute('aria-hidden','true');
 let viewId='';try{viewId=sessionStorage.getItem('cme_view_id')||crypto.randomUUID().slice(0,8);sessionStorage.setItem('cme_view_id',viewId);}catch{viewId='consulta';}
 for(let i=0;i<6;i++){const mark=document.createElement('span');mark.textContent='Cuba Match Explorer · '+viewId;layer.appendChild(mark);}document.body.appendChild(layer);
 const notice=document.createElement('div');notice.id='contentProtectionNotice';notice.setAttribute('role','status');notice.hidden=true;document.body.appendChild(notice);
 let timer;
 function message(){notice.textContent='Contenido de consulta. La copia, impresión y redistribución están restringidas.';notice.hidden=false;clearTimeout(timer);timer=setTimeout(()=>notice.hidden=true,3500);}
 const editable=target=>target instanceof Element&&!!target.closest('input,textarea,[contenteditable="true"],select');
 for(const name of ['copy','cut','contextmenu','dragstart'])document.addEventListener(name,event=>{if(editable(event.target))return;event.preventDefault();if(name!=='dragstart')message();});
 document.addEventListener('keydown',event=>{
  if(editable(event.target))return;
  if((event.ctrlKey||event.metaKey)&&['c','x','p','s'].includes(event.key.toLowerCase())){event.preventDefault();message();}
 });
 document.addEventListener('visibilitychange',()=>document.body.classList.toggle('content-hidden',document.hidden));
 document.body.classList.toggle('content-hidden',document.hidden);
})();
