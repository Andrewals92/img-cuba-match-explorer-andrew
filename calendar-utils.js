/* v4.1: IANA local wall time -> fixed instants, RFC 5545 exports. */
(() => {
 'use strict';
 function parts(instant,zone){return Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(instant)).filter(p=>p.type!=='literal').map(p=>[p.type,p.value]));}
 function wall(instant,zone){const p=parts(instant,zone);return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;}
 function toUTC(local,zone,choice='reject'){
  if(zone!=='UTC'&&!/^[A-Za-z_+-]+\/[A-Za-z0-9_+/-]+$/.test(zone))throw Error('Usa una zona IANA como America/New_York, no EST.');
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(local))throw Error('Introduce fecha y hora válidas.');
  const base=Date.parse(local+'Z');if(!Number.isFinite(base))throw Error('Fecha inválida.');
  const matches=[];for(let m=-840;m<=840;m+=15){const n=base+m*60000;if(wall(n,zone)===local)matches.push(n);}
  if(!matches.length)throw Error('Esta hora no existe en esa zona por el cambio de horario. Elige otra hora.');
  if(matches.length>1&&choice==='reject')throw Error('Esta hora ocurre dos veces por el cambio de horario. Selecciona la primera o segunda ocurrencia.');
  return new Date(choice==='later'?matches.at(-1):matches[0]).toISOString();
 }
 const escape=s=>String(s||'').replace(/\\/g,'\\\\').replace(/\r?\n/g,'\\n').replace(/;/g,'\\;').replace(/,/g,'\\,');
 const stamp=d=>new Date(d).toISOString().replace(/[-:]/g,'').replace(/\.\d{3}/,'');
 function fold(line){let out='',row='',n=0;for(const c of line){const size=new TextEncoder().encode(c).length;if(n+size>75){out+=row+'\r\n';row=' ';n=1;}row+=c;n+=size;}return out+row;}
 function end(e){return e.end_at||new Date(Date.parse(e.start_at)+3600000).toISOString();}
 const title=e=>(e.event_type==='social'?'Social':e.event_type==='second_look'?'Second look':'Interview')+' · '+e.program_name_snapshot;
 function ics(events,includeMeeting=false){const lines=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Cuba Match Explorer//v4.1//ES','CALSCALE:GREGORIAN','METHOD:PUBLISH'];
  for(const e of events.filter(e=>e.start_at)){lines.push('BEGIN:VEVENT','UID:'+e.id+'@cuba-match-explorer','DTSTAMP:'+stamp(e.updated_at||e.created_at||new Date()),'DTSTART:'+stamp(e.start_at),'DTEND:'+stamp(end(e)),'SUMMARY:'+escape(title(e)),'DESCRIPTION:'+escape(`${e.specialty||''}\nZona de la entrevista: ${e.timezone}\nFormato: ${e.format}`),'LOCATION:'+escape(e.location||''),'STATUS:'+(e.status==='cancelled'||e.status==='declined'?'CANCELLED':'CONFIRMED'));if(includeMeeting&&/^https?:\/\//.test(e.meeting_url||''))lines.push('URL:'+escape(e.meeting_url));lines.push('END:VEVENT');}
  lines.push('END:VCALENDAR');return lines.map(fold).join('\r\n')+'\r\n';
 }
 function google(e,includeMeeting=false){const p=new URLSearchParams({action:'TEMPLATE',text:title(e),dates:stamp(e.start_at)+'/'+stamp(end(e)),ctz:e.timezone,location:e.location||'',details:`${e.specialty||''}\n${e.format}`+(includeMeeting&&e.meeting_url?'\n'+e.meeting_url:'')});return 'https://calendar.google.com/calendar/render?'+p;}
 window.CMECalendar={wall,toUTC,ics,google,end,title};
})();
