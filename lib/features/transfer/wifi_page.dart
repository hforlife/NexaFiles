/// Pages served to the computer's browser during a Wi-Fi transfer.
/// Self-contained (no external resources): works without Internet.
library;

const _style = r'''
:root{--bg:#F3F4F8;--card:#fff;--line:#E1E4EC;--ink:#14161C;--muted:#6A6F7E;
--accent:#6366F1;--accent2:#8B5CF6;--soft:#EEF0FF}
@media (prefers-color-scheme:dark){:root{--bg:#0D0E12;--card:#17191F;--line:#2A2D36;
--ink:#F2F3F6;--muted:#9AA0AE;--soft:#23244a}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);
font:15px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
header{display:flex;align-items:center;gap:12px;padding:18px 24px;background:var(--card);
border-bottom:1px solid var(--line);position:sticky;top:0;z-index:2}
.logo{width:36px;height:36px;border-radius:9px;background:linear-gradient(135deg,var(--accent),var(--accent2));
display:grid;place-items:center;color:#fff;font-weight:800}
h1{font-size:20px;margin:0}h1 span{color:var(--accent)}
main{max-width:980px;margin:0 auto;padding:20px 16px 80px}
.crumbs{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-bottom:14px}
.crumbs a{padding:6px 12px;border-radius:999px;background:var(--card);border:1px solid var(--line);
color:var(--ink);text-decoration:none;font-weight:600;font-size:13px}
.crumbs a:last-child{background:var(--soft);color:var(--accent);border-color:transparent}
.bar{display:flex;gap:8px;margin-bottom:14px;flex-wrap:wrap}
button,.btn{border:0;border-radius:999px;padding:10px 18px;font-weight:700;cursor:pointer;
background:var(--accent);color:#fff;font-size:14px}
button.ghost{background:var(--card);color:var(--ink);border:1px solid var(--line)}
.list{background:var(--card);border:1px solid var(--line);border-radius:18px;overflow:hidden}
.row{display:flex;align-items:center;gap:12px;padding:12px 16px;border-top:1px solid var(--line)}
.row:first-child{border-top:0}.row:hover{background:var(--soft)}
.ico{width:38px;height:38px;border-radius:11px;display:grid;place-items:center;font-size:18px;flex:none}
.dir .ico{background:#FFF4DB}.file .ico{background:var(--soft)}
.name{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-weight:600}
.name a{color:inherit;text-decoration:none}.meta{color:var(--muted);font-size:13px;white-space:nowrap}
.dl{color:var(--accent);font-weight:700;text-decoration:none;font-size:13px}
#drop{position:fixed;inset:0;background:rgba(99,102,241,.14);border:3px dashed var(--accent);
display:none;place-items:center;font-size:22px;font-weight:800;color:var(--accent);z-index:5}
#drop.on{display:grid}
#queue{position:fixed;right:16px;bottom:16px;width:min(360px,calc(100% - 32px));display:flex;
flex-direction:column;gap:8px;z-index:4}
.job{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:10px 12px;
box-shadow:0 8px 24px rgba(0,0,0,.12);font-size:13px}
.job progress{width:100%;height:6px;accent-color:var(--accent)}
.empty{padding:40px;text-align:center;color:var(--muted)}
.card{max-width:380px;margin:12vh auto;background:var(--card);border:1px solid var(--line);
border-radius:22px;padding:28px;text-align:center}
.card input{width:100%;font-size:26px;letter-spacing:6px;text-align:center;text-transform:uppercase;
padding:12px;border-radius:14px;border:1px solid var(--line);background:var(--bg);color:var(--ink);margin:16px 0}
''';

/// Asks for the session code shown on the phone.
String unlockPage() =>
    '''<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>NexaFiles</title>
<style>$_style</style></head><body>
<div class="card"><div class="logo" style="margin:0 auto 12px;width:56px;height:56px;font-size:24px">N</div>
<h1>Nexa<span>Files</span></h1>
<p style="color:var(--muted)">Saisissez le code affiché sur votre téléphone.</p>
<form onsubmit="location.href='/?k='+encodeURIComponent(this.c.value.trim());return false">
<input name="c" maxlength="6" autofocus autocomplete="off" placeholder="CODE">
<button style="width:100%">Se connecter</button></form></div></body></html>''';

/// The file browser itself.
String appPage() =>
    '''<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>NexaFiles · Transfert</title>
<style>$_style</style></head><body>
<header><div class="logo">N</div><h1>Nexa<span>Files</span></h1>
<span style="margin-left:auto;color:var(--muted);font-size:13px">Transfert Wi-Fi</span></header>
<main><nav class="crumbs" id="crumbs"></nav>
<div class="bar"><button onclick="pick()">⬆ Envoyer des fichiers</button>
<button class="ghost" onclick="mkdir()">＋ Nouveau dossier</button>
<button class="ghost" onclick="load(cur)">↻ Actualiser</button></div>
<div class="list" id="list"><div class="empty">Chargement…</div></div>
<p style="color:var(--muted);font-size:13px">Astuce : glissez-déposez des fichiers n’importe où sur la page pour les envoyer dans ce dossier.</p>
</main><input type="file" id="file" multiple hidden><div id="drop">Déposez pour envoyer</div><div id="queue"></div>
<script>$_script</script></body></html>''';

const _script = r'''
let cur='';
const $=s=>document.querySelector(s);
const esc=s=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function size(b){if(b==null)return'';const u=['o','Ko','Mo','Go'];let i=0;while(b>=1024&&i<3){b/=1024;i++}return(i?b.toFixed(1):b)+' '+u[i]}
function icon(n,d){if(d)return'📁';const e=n.split('.').pop().toLowerCase();
if(['jpg','jpeg','png','gif','webp','heic'].includes(e))return'🖼️';if(['mp4','mkv','mov','avi','webm'].includes(e))return'🎬';
if(['mp3','m4a','aac','flac','ogg','wav'].includes(e))return'🎵';if(e==='pdf')return'📕';if(['epub','cbz','cbr'].includes(e))return'📚';
if(['zip','rar','7z','gz','tar'].includes(e))return'🗜️';if(e==='apk')return'🤖';return'📄'}
async function load(path){cur=path;const r=await fetch('/api/list?path='+encodeURIComponent(path));
if(!r.ok){$('#list').innerHTML='<div class="empty">'+esc(await r.text())+'</div>';return}
const d=await r.json();crumbs(d.path);const l=$('#list');
if(!d.entries.length){l.innerHTML='<div class="empty">Dossier vide</div>';return}
l.innerHTML=d.entries.map(e=>{const full=(d.path?d.path+'/':'')+e.name;const q=encodeURIComponent(full);
const date=new Date(e.modified).toLocaleDateString('fr-FR');
return e.dir?`<div class="row dir"><div class="ico">${icon(e.name,1)}</div><div class="name"><a href="#" onclick="load(decodeURIComponent('${q}'));return false">${esc(e.name)}</a></div><div class="meta">${date}</div></div>`
:`<div class="row file"><div class="ico">${icon(e.name,0)}</div><div class="name"><a href="/api/download?path=${q}">${esc(e.name)}</a></div><div class="meta">${size(e.size)} · ${date}</div><a class="dl" href="/api/download?path=${q}">Télécharger</a></div>`}).join('')}
function crumbs(path){const parts=path?path.split('/'):[];let acc='';
let h='<a href="#" onclick="load(\'\');return false">📱 Stockage</a>';
for(const p of parts){acc+=(acc?'/':'')+p;const q=encodeURIComponent(acc);h+=`<a href="#" onclick="load(decodeURIComponent('${q}'));return false">${esc(p)}</a>`}
$('#crumbs').innerHTML=h}
function pick(){$('#file').click()}
$('#file').onchange=e=>{send([...e.target.files]);e.target.value=''};
function send(files){const dir=cur;let pending=files.length;for(const f of files){const job=document.createElement('div');job.className='job';
job.innerHTML=`<div>${esc(f.name)}</div><progress max="100" value="0"></progress>`;$('#queue').appendChild(job);
const x=new XMLHttpRequest();x.open('PUT','/api/upload?path='+encodeURIComponent(dir)+'&name='+encodeURIComponent(f.name));
x.upload.onprogress=ev=>{if(ev.lengthComputable)job.querySelector('progress').value=ev.loaded*100/ev.total};
x.onloadend=()=>{job.firstChild.textContent=(x.status<300?'✓ ':'✗ ')+f.name;setTimeout(()=>job.remove(),2500);
if(--pending===0&&dir===cur)load(cur)};x.send(f)}}
async function mkdir(){const n=prompt('Nom du nouveau dossier');if(!n)return;
await fetch('/api/mkdir?path='+encodeURIComponent(cur)+'&name='+encodeURIComponent(n),{method:'POST'});load(cur)}
let depth=0;addEventListener('dragenter',e=>{e.preventDefault();depth++;$('#drop').classList.add('on')});
addEventListener('dragleave',()=>{if(--depth<=0){depth=0;$('#drop').classList.remove('on')}});
addEventListener('dragover',e=>e.preventDefault());
addEventListener('drop',e=>{e.preventDefault();depth=0;$('#drop').classList.remove('on');send([...e.dataTransfer.files])});
history.replaceState(null,'','/');load('');
''';
