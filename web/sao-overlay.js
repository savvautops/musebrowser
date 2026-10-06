// Loaded before Selkies: prevent local input racing an agent. No page-data logging.
(() => {
  const base='/sao-control'; let state=null, healthy=false, nav=false, lastG=0, moving=null;
  const defaults={h:'left',j:'down',k:'up',l:'right',gg:'top',G:'bottom'};
  let mappings={...defaults};
  try { const saved=JSON.parse(localStorage.getItem('sao-navigation')||'null'); if(saved && validMappings(saved)) mappings=saved; } catch {}
  function validMappings(value){return value && Object.keys(value).every(k=>/^[a-zA-Z]$|^gg$/.test(k)) && Object.values(value).every(v=>['left','down','up','right','top','bottom'].includes(v));}
  const host=document.createElement('div'); host.id='sao-owner-overlay';
  host.style.cssText='position:fixed;z-index:2147483647;right:8px;top:max(8px,env(safe-area-inset-top));max-width:calc(100vw - 16px);font:14px system-ui;color:white';
  const root=host.attachShadow({mode:'closed'});
  root.innerHTML=`<style>
  *{box-sizing:border-box}section{width:330px;max-width:calc(100vw - 16px);background:#101923f2;border:1px solid #536276;border-radius:14px;padding:10px;box-shadow:0 4px 24px #0008;max-height:80dvh;overflow:auto}header{display:flex;align-items:center;gap:8px;touch-action:none;cursor:move}strong{flex:1}button{font:inherit;min-height:44px;border:1px solid #596b80;border-radius:8px;color:white;background:#243447;padding:7px 10px;cursor:pointer}button:disabled{opacity:.45;cursor:default}button.active{background:#195839}.row{display:flex;gap:6px;flex-wrap:wrap;margin-top:8px}.row button{flex:1}p{margin:6px 0;line-height:1.35;font-size:12px}textarea{width:100%;min-height:90px;background:#071019;color:white;border:1px solid #697a8d;border-radius:6px;padding:8px;user-select:text}small{display:block;color:#c1d4e7}#message{color:#ffd093}details{margin-top:8px}summary{cursor:pointer;padding:8px}.collapsed #body{display:none}.collapsed{width:auto}#collapse{min-width:44px}</style>
  <section><header><strong>SAO Browser</strong><button id="collapse" aria-label="Collapse controls">−</button></header><div id="body">
  <p id="status" role="status">Connecting to browser control…</p><small id="agent"></small><p id="last"></p>
  <div class="row"><button id="take">Take over</button><button id="allow">Allow agents</button></div>
  <div class="row"><button id="nav">Navigation: off</button><button id="keyboard">Keyboard</button></div>
  <div class="row" id="shortcuts"><button data-key="ctrl+l">Address</button><button data-key="ctrl+t">New tab</button><button data-key="ctrl+shift+Tab">← Tab</button><button data-key="ctrl+Tab">Tab →</button><button data-key="shift+Tab">⇤ Field</button><button data-key="Tab">Field ⇥</button><button data-key="Return">Enter</button><button data-key="Escape">Escape</button></div>
  <div id="typing" hidden><p>Text is sent to the focused remote field.</p><textarea id="text" aria-label="Text for remote browser"></textarea><button id="send">Type text</button></div>
  <p id="message" role="alert"></p>
  <details><summary>Navigation help & shortcuts</summary><p>Take over before typing or clicking the desktop. In Navigation mode: h/j/k/l scroll, gg goes to the top, G to the bottom. Escape exits. Letter shortcuts stop when remote focus is editable or unknown. Standard shortcut buttons remain available.</p><textarea id="mapping" aria-label="Navigation mappings"></textarea><div class="row"><button id="save">Save mappings</button><button id="reset">Reset</button></div><p>Map letters to left, down, up, right, top or bottom. Settings stay on this device.</p></details>
  </div></section>`;
  const $=id=>root.getElementById(id), section=root.querySelector('section');
  function manual(){return healthy && state?.paused && !state.busy;}
  function message(text){$('message').textContent=text;}
  async function request(path,body){const response=await fetch(base+path,{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json','X-SAO-Browser':'1'}:{},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(25000)});const value=await response.json();if(!response.ok)throw Error(value.error||'Browser control unavailable');return value;}
  function render(){
    $('status').textContent=!healthy?'Disconnected · desktop input blocked':state.paused?'You have control · agents paused':'Agents enabled · take over to interact';
    $('agent').textContent=state?`${state.holder||'No active agent'} · ${state.queue.length} waiting${state.busy?' · action finishing':''}`:'';
    $('last').textContent=state?.lastAction?`Last: ${state.lastAction.name} · ${state.lastAction.outcome}`:'';
    $('allow').disabled=!healthy||state.busy; $('take').disabled=!healthy;
    for(const button of root.querySelectorAll('#shortcuts button,#nav,#keyboard,#send'))button.disabled=!manual();
    if(!manual())nav=false;
    $('nav').textContent=`Navigation: ${nav?'ON':'off'}`; $('nav').classList.toggle('active',nav);
  }
  async function update(){try{state=await request('/status');healthy=true;}catch{healthy=false;}render();}
  async function owner(path){try{state=await request('/owner/'+path,{});healthy=true;message('');render();}catch(e){message(e.message);await update();}}
  async function command(input,navigation=false){if(!manual())return message('Take over and wait until the browser is idle.');try{await request('/owner/action',{action:'control',input,navigation});message('');}catch(e){nav=false;message(e.message);}finally{await update();}}
  $('take').onclick=()=>owner('stop');$('allow').onclick=()=>owner('resume');
  $('nav').onclick=()=>{nav=!nav;render();};$('keyboard').onclick=()=>{$('typing').hidden=!$('typing').hidden;if(!$('typing').hidden)$('text').focus();};
  $('send').onclick=async()=>{const text=$('text').value;if(text){await command({action:'type',text});}};
  $('collapse').onclick=()=>{section.classList.toggle('collapsed');$('collapse').textContent=section.classList.contains('collapsed')?'+':'−';};
  for(const button of root.querySelectorAll('[data-key]'))button.onclick=()=>command({action:'key',text:button.dataset.key});
  $('mapping').value=JSON.stringify(mappings,null,2);
  $('save').onclick=()=>{try{const value=JSON.parse($('mapping').value);if(!validMappings(value))throw Error('Use letter keys (or gg) and supported navigation actions.');mappings=value;localStorage.setItem('sao-navigation',JSON.stringify(value));message('Mappings saved.');}catch(e){message(e.message);}};
  $('reset').onclick=()=>{mappings={...defaults};localStorage.removeItem('sao-navigation');$('mapping').value=JSON.stringify(mappings,null,2);};
  root.querySelector('header').addEventListener('pointerdown',e=>{if(e.target.tagName==='BUTTON')return;const box=host.getBoundingClientRect();moving={x:e.clientX-box.left,y:e.clientY-box.top};e.target.setPointerCapture(e.pointerId);});
  root.querySelector('header').addEventListener('pointermove',e=>{if(!moving)return;host.style.right='auto';host.style.left=Math.max(0,Math.min(innerWidth-host.offsetWidth,e.clientX-moving.x))+'px';host.style.top=Math.max(0,Math.min(innerHeight-48,e.clientY-moving.y))+'px';});
  root.querySelector('header').addEventListener('pointerup',()=>moving=null);
  function block(e){e.preventDefault();e.stopImmediatePropagation();}
  for(const event of ['pointerdown','pointerup','mousedown','mouseup','click','dblclick','touchstart','touchmove','touchend','wheel','keydown','keyup','keypress','beforeinput','input','paste']){
    window.addEventListener(event,e=>{
      if(e.composedPath().includes(host))return;
      if(!manual()){block(e);return;}
      if(!nav||!event.startsWith('key'))return;
      block(e); if(event!=='keydown'||e.repeat)return;
      if(e.key==='Escape'){nav=false;render();return;}
      let key=e.key;
      if(key==='g'){const now=Date.now();if(now-lastG<700)key='gg';lastG=now;}
      const action=mappings[key];if(!action)return;
      command(['top','bottom'].includes(action)?{action:'key',text:action==='top'?'ctrl+Home':'ctrl+End'}:{action:'scroll',scroll_direction:action,scroll_amount:3},true);
    },{capture:true,passive:false});
  }
  function mount(){document.body.append(host);update();setInterval(update,2000);}
  if(document.body)mount();else document.addEventListener('DOMContentLoaded',mount,{once:true});
})();
