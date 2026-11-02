// Deterministic simulation for the opt-in iOS direct-touch delayed release.
// Run: node Patches/test-direct-touch.js
const fs=require("fs"),vm=require("vm"),assert=require("node:assert/strict");
const source=fs.readFileSync(__dirname+"/touch-controls.js","utf8");
function harness(){
  let time=0,next=0;const timers=new Map(),events=[],reports=[];
  const listeners=new Map(),ids=new Map();
  function on(owner,type,fn){if(!owner.listeners.has(type))owner.listeners.set(type,[]);owner.listeners.get(type).push(fn);}
  class Elem{
    constructor(tag,id=""){this.tagName=tag.toUpperCase();this.id=id;this.listeners=new Map();this.style={};this.children=[];this.offsetWidth=673;this.offsetHeight=393;this.isConnected=true;this.classList={add(){},remove(){}};if(id)ids.set(id,this);}
    addEventListener(type,fn){on(this,type,fn);}
    appendChild(node){this.children.push(node);return node;}
    dispatchEvent(ev){events.push(ev.type);for(const fn of this.listeners.get(ev.type)||[])fn(ev);return true;}
    setPointerCapture(){}
    getBoundingClientRect(){return this.id==="sh-mouse"?{left:17,top:120,width:239,height:160,right:256,bottom:280}:
      {left:0,top:0,width:673,height:393,right:673,bottom:393};}
  }
  const doc=new Elem("document");
  doc.createElement=tag=>new Elem(tag);
  doc.getElementById=id=>ids.get(id);
  doc.body=new Elem("body");doc.head=new Elem("head");
  const canvas=new Elem("canvas");
  const player=new Elem("ruffle-player");
  player.shadowRoot={querySelectorAll(){return[canvas];}};
  const window={innerWidth:800,innerHeight:450,addEventListener(type,fn){on(window,type,fn);},
    listeners:new Map(),ResizeObserver:class{observe(){}},};
  const localStorage={getItem(){return null;},setItem(){}};
  function timer(fn,ms){const id=++next;timers.set(id,{at:time+ms,fn});return id;}
  function advance(ms){const end=time+ms;while(true){let first=null;for(const [id,t]of timers){if(t.at<=end&&(!first||t.at<first.t.at)){first={id,t};}}if(!first)break;timers.delete(first.id);time=first.t.at;first.t.fn();}time=end;}
  class PE{constructor(type,data){this.type=type;Object.assign(this,data);this.isTrusted=false;}}
  vm.runInNewContext(source,{window,document:doc,PointerEvent:PE,ResizeObserver:window.ResizeObserver,
    localStorage,Math,Number,setTimeout:timer,clearTimeout:id=>timers.delete(id),performance:{now:()=>time}});
  const controls=window.ShiguangTouchControls(player,s=>reports.push(s));
  function trusted(type,x=300,y=140,id=1){
    const ev={type,pointerId:id,pointerType:"touch",isTrusted:true,clientX:x,clientY:y,
      cancelable:true,preventDefault(){this.prevented=true;},stopImmediatePropagation(){this.stopped=true;},
      composedPath(){return[canvas,player,doc];}};
    for(const fn of doc.listeners.get(type)||[]) {fn(ev);if(ev.stopped)break;}
    return ev;
  }
  return {advance,events,reports,trusted,controls};
}
{
  const h=harness();h.controls.setDelayedTap(true);
  assert(h.trusted("pointerdown").stopped,"direct pointerdown must be intercepted");
  h.advance(80);assert(!h.events.includes("pointerdown"),"must hover before press");
  assert(h.trusted("pointerup").stopped,"native pointerup must be intercepted");
  h.advance(40);
  assert.equal(h.events.filter(t=>t==="pointerdown").length,1);
  h.advance(349);
  assert.equal(h.events.filter(t=>t==="pointerup").length,0);
  h.advance(1);
  assert.equal(h.events.filter(t=>t==="pointerup").length,1,"tap auto releases at 350ms");
  assert(h.reports.some(x=>x.includes("触屏延迟：已释放")));
}
{
  const h=harness();assert(!h.trusted("pointerdown").stopped,"default off must leave trusted input alone");
  h.controls.setDelayedTap(true);
  h.trusted("pointerdown",250,140);
  h.advance(10);
  assert(h.trusted("pointermove",285,140).stopped);
  assert.equal(h.events.filter(t=>t==="pointerdown").length,1,"swipe begins immediately");
  h.trusted("pointerup",290,140);
  assert.equal(h.events.filter(t=>t==="pointerup").length,1,"swipe releases immediately");
  h.advance(1000);
  assert.equal(h.events.filter(t=>t==="pointerup").length,1);
}
{
  const h=harness();h.controls.setDelayedTap(true);h.trusted("pointerdown");
  h.trusted("pointercancel");h.advance(900);
  assert.equal(h.events.filter(t=>t==="pointerdown").length,0,"cancel must not invent a tap");
}
{
  const h=harness();h.controls.setDelayedTap(true);h.trusted("pointerdown");
  h.controls.setDelayedTap(false);h.advance(900);
  assert.equal(h.events.filter(t=>t==="pointerdown").length,0,"disabling feature clears queued touch");
}
console.log("PASS direct touchscreen 120ms hover / 350ms release, opt-out, swipe, cancellation and toggle cleanup");
