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
    dispatchEvent(ev){events.push({type:ev.type,button:ev.button,buttons:ev.buttons,at:time,x:ev.clientX,y:ev.clientY});for(const fn of this.listeners.get(ev.type)||[])fn(ev);return true;}
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
      changedTouches:[{identifier:id,clientX:x,clientY:y}],
      touches:type==="touchend"||type==="touchcancel"?[]:[{identifier:id,clientX:x,clientY:y}],
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
{
  const h=harness();h.controls.setSmartHover(true);
  assert(h.trusted("touchstart",280,170,7).stopped,"TouchEvent-only start must be intercepted");
  h.advance(125);h.trusted("touchend",280,170,7);h.advance(70);
  assert.equal(count(h,"pointerdown"),1,"TouchEvent-only tap must produce one click");
  assert.equal(count(h,"pointerup"),1,"TouchEvent-only tap must release");
}
{
  const h=harness();h.controls.setSmartHover(true);
  h.trusted("touchstart",280,170,8);h.advance(880);
  assert.equal(count(h,"pointerdown"),0,"TouchEvent-only long hold must not click");
  assert(count(h,"pointermove")>=4,"TouchEvent-only long hold must send hover pulse");
  h.trusted("touchend",280,170,8);h.advance(1000);
  assert.equal(count(h,"pointerdown"),0,"TouchEvent-only long hold release must not click");
}
{
  // A nearby ring icon short tap must not press too soon and accidentally
  // collapse the hover ring before Flash processes the mouseover.
  const h=harness();h.controls.setSmartHover(true);
  h.trusted("pointerdown",300,170);h.advance(480);
  h.trusted("pointerup",300,170);h.advance(60);
  h.trusted("pointerdown",350,185);h.advance(55);h.trusted("pointerup",350,185);
  const before=count(h,"pointerdown");h.advance(100);
  assert.equal(count(h,"pointerdown"),before,"ring press needs a mouseover lead-in");
  h.advance(20);assert.equal(count(h,"pointerdown"),before+1,"ring press after 110ms");
  h.advance(195);assert.equal(count(h,"pointerup"),1,"ring press must release after hold");
}
{
  // Long-press NoNo, slide onto the icon and release without lifting in between.
  const h=harness();h.controls.setSmartHover(true);
  h.trusted("pointerdown",300,170);h.advance(460);
  h.trusted("pointermove",350,185);h.trusted("pointerup",350,185);
  h.advance(120);assert.equal(count(h,"pointerdown"),1,"hold-slide-release selects ring icon");
  h.advance(200);assert.equal(count(h,"pointerup"),1,"hold-slide-release releases click");
}
{
  // Switching off must cancel a pending ring click: no ghost presses.
  const h=harness();h.controls.setSmartHover(true);
  h.trusted("pointerdown",300,170);h.advance(450);h.trusted("pointerup",300,170);
  h.trusted("pointerdown",325,170);h.advance(45);h.trusted("pointerup",325,170);
  h.controls.setSmartHover(false);h.advance(600);
  assert.equal(count(h,"pointerdown"),0,"disabling ring mode cancels deferred tap");
}
console.log("PASS Build117 NoNo ring click timing, hold-slide-release, cancellation, smart hover and fallback");
