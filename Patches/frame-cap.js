// Experimental rAF scheduling ceiling for iOS Ruffle Web 0.7.1.
// Does NOT modify SWF frameRate or alter high-resolution callback timestamps.
// Only enabled for the explicitly selected 30/60 setting. Affects JS rAF
// callbacks in this isolated game page, including Ruffle's paint/tick loop.
// This is an experiment, not a guaranteed independent GPU render cap.
(function(){
  "use strict";
  var m=document.querySelector('meta[name="shiguang-max-fps"]');
  var cap=Number(m&&m.content);
  if(cap!==30&&cap!==60)cap=0;
  var rawRequest=window.requestAnimationFrame.bind(window);
  var rawCancel=window.cancelAnimationFrame.bind(window);
  var nextId=1000000, pending=new Map(), lastTick=-1;
  var tickTimes=[];
  var state={
    limit:cap,
    nativeRequestFrame:rawRequest,
    nativeCancelFrame:rawCancel,
    // Count distinct allowed callback times in the last second.
    getRecentUpdates:function(){
      var now=performance.now();
      while(tickTimes.length&&tickTimes[0]<now-1000)tickTimes.shift();
      return tickTimes.length;
    }
  };
  window.ShiguangFrameCap=state;
  if(!cap)return;
  var minInterval=1000/cap-0.65; // tolerate sub-ms ProMotion timestamps.
  window.requestAnimationFrame=function(callback){
    if(typeof callback!=="function")return rawRequest(callback);
    var key=nextId++, job={nativeId:0,cancelled:false};
    pending.set(key,job);
    function step(t){
      if(job.cancelled)return;
      // If multiple callbacks occur in one repaint, allow them together.
      // Never fake timestamps; Ruffle can still measure real elapsed time.
      var accept=lastTick<0 || t===lastTick || t-lastTick>=minInterval;
      if(!accept){job.nativeId=rawRequest(step);return;}
      pending.delete(key);
      if(t!==lastTick){
        lastTick=t;
        tickTimes.push(t);
        while(tickTimes.length&&tickTimes[0]<t-1000)tickTimes.shift();
      }
      callback(t);
    }
    job.nativeId=rawRequest(step);
    return key;
  };
  window.cancelAnimationFrame=function(key){
    var job=pending.get(key);
    if(!job){rawCancel(key);return;}
    pending.delete(key);job.cancelled=true;rawCancel(job.nativeId);
  };
})();
