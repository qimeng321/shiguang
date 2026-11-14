/* B146 full-stack observational probe, injected into page world at document start.
 * Measures only what a public iOS WKWebView can expose. Never logs game content,
 * chat, credentials, request URLs, remote hosts or WebSocket payloads.
 * Does not modify SWF execution, rendering, GPU objects, cache or timers.
 */
(function () {
  "use strict";
  if (window.__b146MonitorInstalled) return;
  window.__b146MonitorInstalled = true;

  var nativeWasm = window.WebAssembly;
  var firstTick = Date.now();
  var previousTick = firstTick;
  var seq = 0;
  var memoryObject = null;
  var memorySeenAt = 0;
  var instancesSeen = 0;
  var memoryCaptureErrors = 0;
  var wasmMinMiB = null;
  var wasmPeakMiB = null;
  var lostContexts = 0;
  var restoredContexts = 0;
  var seenCanvases = new WeakSet();
  var longTasks = 0;
  var longestTaskMs = 0;
  var jsErrors = 0;
  var lastErrorKind = "none";
  var sampleIntervalMs = 5000;
  var totalMessages = 0;

  function report(obj) {
    if (++totalMessages > 1800) return; // bounded for extended sessions
    try {
      var h = window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.gameDiagnostics;
      if (h) h.postMessage("B146:" + JSON.stringify(obj));
    } catch (_ignored) {}
  }
  function capture(value) {
    try {
      var instance = value && (value.instance || value);
      var exports = instance && instance.exports;
      if (!exports) return;
      instancesSeen++;
      var memory = exports.memory;
      if (!(memory instanceof nativeWasm.Memory)) {
        Object.keys(exports).some(function (k) {
          if (exports[k] instanceof nativeWasm.Memory) {
            memory = exports[k]; return true;
          }
          return false;
        });
      }
      if (memory instanceof nativeWasm.Memory) {
        memoryObject = memory;
        memorySeenAt = Date.now();
        report({type:"wasm-captured", epoch:memorySeenAt, exported:true, instances:instancesSeen});
      } else {
        report({type:"wasm-instance-no-exported-memory", epoch:Date.now(), instances:instancesSeen});
      }
    } catch (_e) { memoryCaptureErrors++; }
  }
  function wrapInstantiation(name) {
    try {
      if (!nativeWasm || typeof nativeWasm[name] !== "function") return;
      var original = nativeWasm[name];
      nativeWasm[name] = function () {
        var result = Reflect.apply(original, this, arguments);
        if (result && typeof result.then === "function") {
          return result.then(function (value) { capture(value); return value; });
        }
        capture(result);
        return result;
      };
    } catch (_e) { memoryCaptureErrors++; }
  }
  wrapInstantiation("instantiate");
  wrapInstantiation("instantiateStreaming");

  window.addEventListener("error", function (e) {
    jsErrors++;
    lastErrorKind = (e && e.error && e.error.name) || "JS-error";
    report({type:"js-error", epoch:Date.now(), kind:String(lastErrorKind).slice(0,48)});
  });
  window.addEventListener("unhandledrejection", function (e) {
    jsErrors++;
    lastErrorKind = (e && e.reason && e.reason.name) || "unhandled-rejection";
    report({type:"unhandled-rejection", epoch:Date.now(), kind:String(lastErrorKind).slice(0,48)});
  });
  window.addEventListener("visibilitychange", function () {
    report({type:"visibility",epoch:Date.now(),value:document.visibilityState});
  });
  window.addEventListener("pagehide", function () {
    report({type:"pagehide",epoch:Date.now()});
  });
  try {
    if (window.PerformanceObserver && PerformanceObserver.supportedEntryTypes &&
        PerformanceObserver.supportedEntryTypes.indexOf("longtask") >= 0) {
      var observer = new PerformanceObserver(function (list) {
        var entries = list.getEntries();
        longTasks += entries.length;
        entries.forEach(function (e) { longestTaskMs = Math.max(longestTaskMs,Math.round(e.duration)); });
      });
      observer.observe({entryTypes:["longtask"]});
    }
  } catch (_e) {}

  function sample() {
    var now = Date.now();
    var msSincePrevious = now - previousTick;
    previousTick = now;
    var wasmPages = null, wasmMiB = null, bufferError = null;
    if (memoryObject) {
      try {
        // Ruffle exports WebAssembly.Memory; .buffer.byteLength measures the
        // allocated linear memory, not resident size or WebKit GPU allocation.
        wasmPages = Math.round(memoryObject.buffer.byteLength / 65536);
        wasmMiB = Math.round(memoryObject.buffer.byteLength / 1048576);
        wasmMinMiB = wasmMinMiB === null ? wasmMiB : Math.min(wasmMinMiB, wasmMiB);
        wasmPeakMiB = wasmPeakMiB === null ? wasmMiB : Math.max(wasmPeakMiB, wasmMiB);
      } catch (e) { bufferError = String((e && e.name) || "memory-buffer-error"); }
    }
    var player = null, ready = null, playing = null, canvasCount = 0, largest = "none", largestPixels = 0;
    try {
      player = document.querySelector("ruffle-player,ruffle-object,ruffle-embed");
      var roots = [document];
      if (player && player.shadowRoot) roots.push(player.shadowRoot);
      roots.forEach(function (root) {
        Array.prototype.forEach.call(root.querySelectorAll("canvas"),function (c) {
          canvasCount++;
          var pixels = (c.width || 0) * (c.height || 0);
          if (pixels > largestPixels) {
            largestPixels = pixels;
            largest = String(c.width || 0) + "x" + String(c.height || 0);
          }
          if (!seenCanvases.has(c)) {
            seenCanvases.add(c);
            c.addEventListener("webglcontextlost",function () {
              lostContexts++;
              report({type:"webgl-context-lost",epoch:Date.now(),count:lostContexts});
            });
            c.addEventListener("webglcontextrestored",function () {
              restoredContexts++;
              report({type:"webgl-context-restored",epoch:Date.now(),count:restoredContexts});
            });
          }
        });
      });
      var api = player && typeof player.ruffle === "function" ? player.ruffle() : player;
      if (api) {
        ready = String(api.readyState);
        playing = Boolean(api.isPlaying);
      }
    } catch (_e) {}
    var resourceCount = null;
    try { resourceCount = performance.getEntriesByType("resource").length; } catch (_e) {}
    var docState = document.visibilityState || "unknown";
    report({
      type:"sample",epoch:now,seq:++seq,uptimeSec:Math.floor((now-firstTick)/1000),
      delayMs:msSincePrevious,expectedIntervalMs:sampleIntervalMs,
      wasmCaptured:!!memoryObject,wasmPages:wasmPages,wasmMiB:wasmMiB,
      wasmMinMiB:wasmMinMiB,wasmPeakMiB:wasmPeakMiB,
      wasmInstances:instancesSeen,wasmCaptureErrors:memoryCaptureErrors,
      wasmCapturedAgeSec:memorySeenAt?Math.floor((now-memorySeenAt)/1000):null,
      wasmBufferError:bufferError,visibility:docState,
      readyState:ready,isPlaying:playing,canvasCount:canvasCount,
      largestCanvas:largest,largestCanvasPixels:largestPixels,
      webglContextLost:lostContexts,webglContextRestored:restoredContexts,
      longTasks:longTasks,longestTaskMs:longestTaskMs,
      jsErrors:jsErrors,lastErrorKind:lastErrorKind,
      resourceTimingEntries:resourceCount,dpr:window.devicePixelRatio||null
    });
  }

  report({type:"start",epoch:firstTick,intervalMs:sampleIntervalMs,
    wasmSupported:!!nativeWasm,screenDpr:window.devicePixelRatio||null,
    note:"WASM memory is not whole WebKit process memory"});
  setInterval(sample,sampleIntervalMs);
  setTimeout(sample,1700);
})();