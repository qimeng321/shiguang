// Formal 1.04 precise mouse regression tests; no smart-hover code present.\nconst fs=require("fs"),vm=require("vm"),assert=require("node:assert/strict");
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
  assert.equal(typeof h.controls.setSmartHover,"undefined","smart-hover API must not exist");
  assert(!h.trusted("pointerdown").stopped,"normal touch is not intercepted");
  h.advance(500);assert.equal(count(h,"pointermove"),0,"no hidden hover pulses");
}
{
  const h=harness();h.controls.enableMouse();
  h.clickButton("sh-mouse-click");h.advance(126);
  assert.equal(count(h,"pointerdown"),1,"precision mouse click down");
  assert.equal(count(h,"pointerup"),1,"precision mouse click up");
}
{
  const h=harness();h.controls.enableMouse();
  h.clickButton("sh-mouse-double");h.advance(450);
  assert.equal(count(h,"pointerdown"),2,"double click exactly two presses");
  assert.equal(count(h,"pointerup"),2,"double click exactly two releases");
}
{
  const h=harness();h.controls.enableMouse();
  h.clickButton("sh-mouse-right");h.advance(80);
  assert(h.events.some(x=>x.type==="pointerdown"&&x.button===2),"right button down");
  assert(h.events.some(x=>x.type==="pointerup"&&x.button===2),"right button up");
}
{
  const h=harness();h.controls.setDelayedTap(true);
  assert(h.trusted("pointerdown").stopped,"opt-in delayed touchscreen still works");
  h.advance(130);h.trusted("pointerup");h.advance(350);
  assert.equal(count(h,"pointerdown"),1,"delayed touch down");
  assert.equal(count(h,"pointerup"),1,"delayed touch up");
}
console.log("PASS formal 1.04: no smart-hover, precise click/double/right and delayed touchscreen");
