"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const source = fs.readFileSync("Patches/b146-full-monitor.js", "utf8");
const seen = [];
const scheduled = [];
const timers = [];
class FakeMemory {
  constructor(mib) { this.buffer = new ArrayBuffer(mib * 1048576); }
}
const memory = new FakeMemory(32);
const wasm = {
  Memory: FakeMemory,
  instantiate: function () {
    return Promise.resolve({instance: {exports: {memory: memory}}});
  },
  instantiateStreaming: function () {
    return Promise.resolve({instance: {exports: {memory: memory}}});
  }
};
const doc = {
  visibilityState: "visible",
  querySelector: function () { return null; },
  querySelectorAll: function () { return []; },
  addEventListener: function () {}
};
const fakeWindow = {
  WebAssembly: wasm,
  document: doc,
  devicePixelRatio: 2,
  addEventListener: function () {},
  webkit: {messageHandlers: {gameDiagnostics: {
    postMessage: function (v) { seen.push(v); }
  }}}
};
const context = {
  window: fakeWindow,
  document: doc,
  WebAssembly: wasm,
  PerformanceObserver: undefined,
  performance: {getEntriesByType:function(){return [];}},
  setInterval: function(fn,ms){timers.push({fn,ms});},
  setTimeout: function(fn){scheduled.push(fn);},
  Reflect: Reflect,
  Array: Array, Object: Object, Date: Date,
  WeakSet: WeakSet, Boolean: Boolean, String: String,
  Math: Math, JSON: JSON
};
vm.runInNewContext(source,context,{filename:"b146-full-monitor.js"});
assert.equal(fakeWindow.__b146MonitorInstalled,true);
assert.equal(timers.length,1);
assert.equal(timers[0].ms,5000);
assert.equal(scheduled.length,1);
function decode() {
  return seen.filter(x=>String(x).startsWith("B146:"))
    .map(x=>JSON.parse(x.slice("B146:".length)));
}
(async function () {
  await wasm.instantiateStreaming();
  scheduled[0]();
  const first = decode().filter(x=>x.type==="sample").at(-1);
  assert.ok(first, "No sample after wasm instantiation");
  assert.equal(first.wasmCaptured,true);
  assert.equal(first.wasmMiB,32);
  assert.equal(first.wasmPages,512);
  memory.buffer = new ArrayBuffer(96*1048576);
  timers[0].fn();
  const second = decode().filter(x=>x.type==="sample").at(-1);
  assert.equal(second.wasmMiB,96);
  assert.equal(second.wasmPeakMiB,96);
  assert.ok(second.seq>first.seq);
  assert.equal(second.dpr,2);
  assert.equal(decode().filter(x=>x.type==="wasm-captured").length,1);
  const absentSensitive = seen.join("\n");
  assert.equal(/password|authToken|cookie=|chatMessage=/i.test(absentSensitive),false);
  console.log("PASS B146: injected before instantiation, captured real WASM.Memory, reports 5s size growth, no payload logging");
})().catch(e=>{console.error(e);process.exitCode=1;});
