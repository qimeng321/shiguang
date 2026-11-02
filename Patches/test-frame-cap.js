// Standalone deterministic scheduling test; no browser required.
// Run: node Patches/test-frame-cap.js
const fs=require("node:fs");
const vm=require("node:vm");
const assert=require("node:assert/strict");
const source=fs.readFileSync(__dirname+"/frame-cap.js","utf8");
function simulate(cap, clockHz){
  let now=0, nativeId=0, pending=new Map();
  const window={
    requestAnimationFrame(fn){const id=++nativeId;pending.set(id,fn);return id;},
    cancelAnimationFrame(id){pending.delete(id);}
  };
  const sandbox={window,document:{querySelector(){return{content:String(cap)}}},
    performance:{now(){return now;}},Map,Number};
  vm.runInNewContext(source,sandbox);
  let callbackTimes=[];
  const id=window.requestAnimationFrame(t=>callbackTimes.push(t));
  assert.ok(id>0);
  // On every physical display refresh, queued callbacks run and those that
  // didn't meet the minimum interval may request a later native display.
  for(let i=0;i<clockHz;i++){
    now=i*(1000/clockHz);
    const batch=[...pending.values()];pending.clear();
    for(const fn of batch)fn(now);
  }
  return {callbackTimes,limiter:window.ShiguangFrameCap,window,pending};
}
function loop(cap, clockHz){
  let now=0,id=0,pending=new Map();
  const window={
    requestAnimationFrame(fn){let k=++id;pending.set(k,fn);return k;},
    cancelAnimationFrame(k){pending.delete(k);}
  };
  vm.runInNewContext(source,{window,document:{querySelector(){return{content:String(cap)}}},
    performance:{now(){return now;}},Map,Number});
  let called=[];
  function tick(t){called.push(t);window.requestAnimationFrame(tick);}
  window.requestAnimationFrame(tick);
  for(let i=0;i<clockHz;i++){
    now=i*(1000/clockHz);
    let batch=[...pending.values()];pending.clear();
    for(const cb of batch)cb(now);
  }
  return {called,limiter:window.ShiguangFrameCap};
}
for(const [cap,hz,lo,hi] of [[30,120,28,31],[60,120,58,61],[30,60,28,31],[60,60,58,61],[0,120,118,121]]){
  const {called,limiter}=loop(cap,hz);
  assert.ok(called.length>=lo && called.length<=hi,
    "cap="+cap+" Hz="+hz+" delivered "+called.length+" expected "+lo+".."+hi);
  assert.equal(limiter.limit,cap);
  assert.equal(limiter.getRecentUpdates()>0,cap>0);
  // Original browser time retained; no fabricated timeline.
  for(const t of called)assert.ok(Math.abs(t*hz/1000-Math.round(t*hz/1000))<1e-5);
  console.log("PASS simulated display "+hz+"Hz cap="+cap+" delivered callbacks="+called.length);
}
// A cancellation must not produce a callback.
{
  let calls=0, queue=new Map(),seq=0;
  const win={requestAnimationFrame(fn){queue.set(++seq,fn);return seq;},cancelAnimationFrame(id){queue.delete(id);}};
  vm.runInNewContext(source,{window:win,document:{querySelector(){return{content:"30"}}},
    performance:{now(){return 0;}},Map,Number});
  const handle=win.requestAnimationFrame(()=>calls++);
  win.cancelAnimationFrame(handle);
  for(const callback of queue.values())callback(33);
  assert.equal(calls,0);
}
console.log("PASS cancellation and timestamps");
