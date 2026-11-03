// Input sequence smoke tests only. A real game SWF is required to verify scrolling.
const fs=require("fs"),vm=require("vm"),assert=require("node:assert/strict");
const code=fs.readFileSync(__dirname+"/galaxy-navigation.js","utf8");
let time=0,next=0;const timers=new Map(),events=[],listeners={};
function timer(fn,ms,recur){const id=++next;timers.set(id,{at:time+ms,ms,recur,fn});return id;}
function advance(ms){const end=time+ms;for(let k=0;k<10000;k++){
 let first=null;for(const [id,t]of timers)if(t.at<=end&&(!first||t.at<first.t.at))first={id,t};
 if(!first)break;time=first.t.at;if(first.t.recur)first.t.at+=first.t.ms;else timers.delete(first.id);first.t.fn();
}time=end;}
function elem(){return {children:[],style:{},handlers:{},isConnected:true,offsetWidth:600,offsetHeight:350,
 appendChild(x){this.children.push(x);return x;},setAttribute(){},setPointerCapture(){},
 addEventListener(k,f){(this.handlers[k]??=[]).push(f);},
 dispatchEvent(e){if(this===canvas)events.push(e.type);for(const f of this.handlers[e.type]||[])f(e);return true;},
 getBoundingClientRect(){return {left:0,right:600,top:0,bottom:350,width:600,height:350};}};}
const document={body:elem(),hidden:false,createElement:elem,addEventListener(k,f){(listeners[k]??=[]).push(f);}};
const canvas=elem(),window={innerWidth:700,addEventListener(k,f){(listeners[k]??=[]).push(f);}};
class PE{constructor(type,fields){this.type=type;Object.assign(this,fields);}}
vm.runInNewContext(code,{document,window,PointerEvent:PE,performance:{now:()=>time},Math,
 setTimeout:(f,m)=>timer(f,m,false),clearTimeout:id=>timers.delete(id),
 setInterval:(f,m)=>timer(f,m,true),clearInterval:id=>timers.delete(id),
 requestAnimationFrame:f=>timer(()=>f(time),16,false),cancelAnimationFrame:id=>timers.delete(id)});
const ctrl=window.ShiguangGalaxyNavigation({shadowRoot:{querySelectorAll(){return[canvas];}}},()=>{});
const host=document.body.children[0],e=id=>({pointerId:id,preventDefault(){},stopPropagation(){}});
function click(b,id){b.dispatchEvent({type:"pointerdown",...e(id)});advance(70);
 b.dispatchEvent({type:"pointerup",...e(id)});advance(600);}
assert.equal(ctrl.state().visible,false);
click(host.children[0],1);assert.equal(events.length,0,"off must not touch game");
ctrl.setMapVisible(true,"map opened");click(host.children[0],2);
assert(events.filter(x=>x==="pointermove").length>1,"edge scroll must move cursor");
assert.equal(events.filter(x=>x==="pointerdown").length,0,"edge mode must not click a planet");
const before=ctrl.state().moves,right=host.children[1];
right.dispatchEvent({type:"pointerdown",...e(3)});advance(1000);
assert(ctrl.state().moves>before+2,"long hold should keep hovering edge");
right.dispatchEvent({type:"pointerup",...e(3)});const stopped=ctrl.state().moves;advance(800);
assert.equal(ctrl.state().moves,stopped,"release must stop");
ctrl.cycleMode();assert.equal(ctrl.state().mode,"drag");click(right,4);
assert.equal(events.filter(x=>x==="pointerdown").length,1);
assert.equal(events.filter(x=>x==="pointerup").length,1);
ctrl.hide("exit");assert.equal(ctrl.state().visible,false);
console.log("PASS Build116 galaxy edge-hover, hold/release, drag fallback and hide");