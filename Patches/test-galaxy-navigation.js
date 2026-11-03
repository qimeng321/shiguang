// Automated event-sequence checks, not a real SWF/phone runtime.
const fs=require("fs"),vm=require("vm"),assert=require("node:assert/strict");
const source=fs.readFileSync(__dirname+"/galaxy-navigation.js","utf8");
let time=0,next=0;const timers=new Map(),events=[],listeners={};
function addTimer(fn,ms,recur){const id=++next;timers.set(id,{at:time+ms,ms,recur,fn});return id;}
function advance(ms){const end=time+ms;for(let step=0;step<1000;step++){
 let first=null;for(const [id,t] of timers)if(t.at<=end&&(!first||t.at<first.t.at))first={id,t};
 if(!first)break;time=first.t.at;
 if(first.t.recur)first.t.at+=first.t.ms;else timers.delete(first.id);
 first.t.fn();
}time=end;}
function elem(){return {children:[],style:{},isConnected:true,offsetWidth:600,offsetHeight:350,
  handlers:{},appendChild(el){this.children.push(el);return el;},setAttribute(){},setPointerCapture(){},
  addEventListener(t,f){(this.handlers[t]??=[]).push(f);},dispatchEvent(e){
    if(this===canvas)events.push(e.type);for(const f of this.handlers[e.type]||[])f(e);return true;},
  getBoundingClientRect(){return{left:0,top:0,width:600,height:350,right:600,bottom:350};}};}
const document={body:elem(),hidden:false,createElement:elem,
 addEventListener(t,f){(listeners[t]??=[]).push(f);}};
const canvas=elem(),window={addEventListener(t,f){(listeners[t]??=[]).push(f);}};
class PointerEvent{constructor(type,values){this.type=type;Object.assign(this,values);}}
vm.runInNewContext(source,{document,window,PointerEvent,Math,performance:{now:()=>time},
 setTimeout:(f,n)=>addTimer(f,n,false),clearTimeout:n=>timers.delete(n),
 setInterval:(f,n)=>addTimer(f,n,true),clearInterval:n=>timers.delete(n),
 requestAnimationFrame:f=>addTimer(()=>f(time),16,false),cancelAnimationFrame:n=>timers.delete(n)});
const control=window.ShiguangGalaxyNavigation({shadowRoot:{querySelectorAll(){return[canvas];}}},()=>{});
assert.equal(control.state().visible,false);
const host=document.body.children[0];
const e=id=>({pointerId:id,preventDefault(){},stopPropagation(){}});
function click(b,id){b.dispatchEvent({type:"pointerdown",...e(id)});advance(80);
 b.dispatchEvent({type:"pointerup",...e(id)});advance(400);}
click(host.children[0],1);
assert.equal(events.filter(x=>x==="pointerdown").length,0);
control.setMapVisible(true,"test");
click(host.children[0],2);
assert.equal(events.filter(x=>x==="pointerdown").length,1);
assert.equal(events.filter(x=>x==="pointerup").length,1);
const right=host.children[1];right.dispatchEvent({type:"pointerdown",...e(3)});
advance(1200);right.dispatchEvent({type:"pointerup",...e(3)});advance(400);
assert(control.state().steps>=2);
control.hide("exit");
assert.equal(control.state().visible,false);
console.log("PASS map arrows: default hidden, explicit activation, single click, hold, hide");