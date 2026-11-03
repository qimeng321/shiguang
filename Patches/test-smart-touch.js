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
    dispatchEvent(ev){events.push({type:ev.type,button:ev.button,buttons:ev.buttons});for(const fn of this.listeners.get(ev.type)||[])fn(ev);return true;}
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
  return {advance,events,reports,trusted,controls,clickButton(id){const queue=[doc.body];let b=null;while(queue.length){const node=queue.shift();if(node.id===id){b=node;break;}queue.push(...node.children);}assert(b,"missing button "+id);b.dispatchEvent({type:"click",preventDefault(){},stopPropagation(){}});}};
}
const count=(h,type)=>h.events.filter(x=>x.type===type).length;
{
  const h=harness();
  assert(!h.trusted("pointerdown").stopped,"default mode must not intercept original game touch");
  h.controls.setSmartHover(true);
  assert(h.trusted("pointerdown").stopped,"smart touch should intercept Ruffle native pointerdown");
  h.advance(100);
  h.trusted("pointerup");
  assert.equal(count(h,"pointerdown"),1,"short tap must keep original NoNo main-page click");
  h.advance(65);
  assert.equal(count(h,"pointerup"),1,"short tap must release exactly once");
}
{
  const h=harness();h.controls.setSmartHover(true);
  h.trusted("pointerdown");h.advance(420);
  assert.equal(count(h,"pointerdown"),0,"long press MUST NOT open NoNo main page");
  assert(count(h,"pointermove")>=2,"long press should preserve hover location");
  h.trusted("pointerup");h.advance(1000);
  assert.equal(count(h,"pointerdown"),0,"long press release must not click");
  assert.equal(count(h,"pointerup"),0,"hover release must not create an artificial mouse up");
  assert(h.reports.some(x=>x.includes("智能悬停：长按已识别")));
}
{
  const h=harness();h.controls.setSmartHover(true);
  h.trusted("pointerdown",250,140);h.advance(40);
  h.trusted("pointermove",300,140);
  assert.equal(count(h,"pointerdown"),1,"drag begins when movement exceeds 12px");
  h.advance(500);h.trusted("pointerup",330,140);
  assert.equal(count(h,"pointerup"),1,"drag ends on real release");
  assert(!h.reports.some(x=>x.includes("长按已识别")),"drag must not become long press");
}
{
  const h=harness();h.controls.setSmartHover(true);
  h.trusted("pointerdown");h.advance(200);h.trusted("pointercancel");h.advance(800);
  assert.equal(count(h,"pointerdown"),0,"cancel must not generate a click");
}
{
  const h=harness();h.controls.setSmartHover(true);
  h.trusted("pointerdown",220,140,1);
  h.trusted("pointerdown",270,140,2);
  h.advance(600);
  h.trusted("pointerup",270,140,2);h.trusted("pointerup",220,140,1);
  assert.equal(count(h,"pointerdown"),0,"two-finger gesture must not ghost click");
}
{
  const h=harness();h.controls.setSmartHover(true);h.trusted("pointerdown");
  h.controls.setSmartHover(false);h.advance(900);
  assert.equal(count(h,"pointerdown"),0,"turning off mode cancels pending long press");
  assert(!h.trusted("pointerdown").stopped,"turning off mode restores original input");
}
{
  const h=harness();h.controls.enableMouse();h.clickButton("sh-mouse-double");
  h.advance(400);
  assert.equal(count(h,"pointerdown"),2,"virtual mouse double click should press twice");
  assert.equal(count(h,"pointerup"),2,"virtual mouse double click should release twice");
  h.clickButton("sh-mouse-right");h.advance(80);
  assert(h.events.some(x=>x.type==="pointerdown"&&x.button===2),"right-click should use mouse button 2");
  assert(h.events.some(x=>x.type==="pointerup"&&x.button===2),"right-click should release mouse button 2");
}
console.log("PASS smart hover opt-in: short tap, 420ms hover without click, drag, cancel, two-finger guard, toggle cleanup, double/right mouse");
