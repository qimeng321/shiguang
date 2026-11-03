/* 拾光号 iOS 1.2 Build115: an isolated map-only navigation overlay.
   The game SWF must explicitly notify us when the galaxy map opens/closes.
   No image guesses or global touch interception. */
(function() {
"use strict";
window.ShiguangGalaxyNavigation = function(player, report) {
  var visible=false, source="none", active=null, raf=0, pressed=null;
  var holdTimer=null, repeatTimer=null, steps=0;
  var host=document.createElement("div");
  host.id="sh-galaxy-arrows";
  host.style.cssText="display:none;position:fixed;inset:0;z-index:2147482790;pointer-events:none;";
  function canvasNow() {
    var root=player&&player.shadowRoot, canvases=root&&root.querySelectorAll("canvas");
    var best=null;
    if (canvases) for (var i=0;i<canvases.length;i++) {
      var r=canvases[i].getBoundingClientRect();
      if (canvases[i].isConnected&&r.width>80&&r.height>80&&(!best||r.width>best.getBoundingClientRect().width))
        best={node:canvases[i],width:r.width};
    }
    return best&&best.node;
  }
  function emit(c,type,x,y,buttons) {
    if (!c||!c.isConnected) return false;
    var r=c.getBoundingClientRect();
    x=Math.max(r.left+3,Math.min(r.right-3,x));
    y=Math.max(r.top+3,Math.min(r.bottom-3,y));
    var event=new PointerEvent(type,{bubbles:true,composed:true,cancelable:true,
      pointerId:89,pointerType:"mouse",isPrimary:true,clientX:x,clientY:y,
      button:type==="pointermove"?-1:0,buttons:buttons});
    try {
      Object.defineProperty(event,"offsetX",{configurable:true,value:(x-r.left)*(c.offsetWidth||r.width)/r.width});
      Object.defineProperty(event,"offsetY",{configurable:true,value:(y-r.top)*(c.offsetHeight||r.height)/r.height});
    } catch(_) {}
    c.dispatchEvent(event);
    return true;
  }
  function stop() {
    if (raf) { cancelAnimationFrame(raf);raf=0; }
    if (active) { emit(active.canvas,"pointerup",active.x,active.y,0);active=null; }
  }
  function stopTimers() {
    if (holdTimer!==null) {clearTimeout(holdTimer);holdTimer=null;}
    if (repeatTimer!==null) {clearInterval(repeatTimer);repeatTimer=null;}
  }
  function glide(direction) {
    if (!visible||document.hidden||active) return;
    var c=canvasNow();
    if (!c) {report("地图箭头：Canvas未就绪");return;}
    var r=c.getBoundingClientRect(),span=Math.min(190,r.width*.22);
    var x0=r.left+r.width*(direction<0?.64:.36),x1=x0+direction*span;
    var y=r.top+r.height*.54,begin=performance.now(),duration=300;
    active={canvas:c,x:x0,y:y};
    emit(c,"pointerenter",x0,y,0);
    if (!emit(c,"pointerdown",x0,y,1)) { stop();return; }
    function tick(now) {
      if (!visible||document.hidden) {stop();return;}
      var t=Math.max(0,Math.min(1,(now-begin)/duration));
      var easing=t*t*(3-2*t);
      active.x=x0+(x1-x0)*easing;
      emit(c,"pointermove",active.x,y,1);
      if (t<1) raf=requestAnimationFrame(tick);
      else {
        raf=0;stop();steps++;
        if (steps<=4||steps%20===0)
          report("地图箭头：模拟滑动 "+steps+" 次，移动方向需要真机确认");
      }
    }
    raf=requestAnimationFrame(tick);
  }
  function addArrow(direction,label,left) {
    var button=document.createElement("button");
    button.type="button";button.textContent=label;
    button.setAttribute("aria-label",direction<0?"地图向左流动":"地图向右流动");
    button.style.cssText="position:absolute;top:50%;transform:translateY(-50%);"+
      (left?"left:calc(env(safe-area-inset-left,0px) + 4px);":"right:calc(env(safe-area-inset-right,0px) + 4px);")+
      "width:46px;height:62px;pointer-events:auto;touch-action:none;"+
      "border:1px solid rgba(215,235,255,.7);border-radius:14px;"+
      "background:rgba(17,39,71,.62);color:#fff;font:bold 29px sans-serif;";
    host.appendChild(button);
    button.addEventListener("pointerdown",function(e) {
      if (!visible||pressed) return;
      e.preventDefault();e.stopPropagation();
      pressed={id:e.pointerId,direction:direction,long:false};
      try {button.setPointerCapture(e.pointerId);}catch(_) {}
      holdTimer=setTimeout(function() {
        if (!pressed||pressed.id!==e.pointerId||!visible) return;
        pressed.long=true;glide(direction);
        repeatTimer=setInterval(function() {
          if (pressed&&visible) glide(direction);
          else stopTimers();
        },340);
      },350);
    });
    button.addEventListener("pointerup",function(e) {
      if (!pressed||pressed.id!==e.pointerId)return;
      e.preventDefault();e.stopPropagation();
      var isTap=!pressed.long,direction=pressed.direction;
      pressed=null;stopTimers();
      if (isTap)glide(direction);
    });
    ["pointercancel","lostpointercapture"].forEach(function(type) {
      button.addEventListener(type,function(e) {
        if (pressed&&e.pointerId===pressed.id) {pressed=null;stopTimers();stop();}
      });
    });
    button.addEventListener("click",function(e){e.preventDefault();e.stopPropagation();});
  }
  addArrow(-1,"❮",true);addArrow(1,"❯",false);
  document.body.appendChild(host);
  function show(on,reason) {
    if (visible===!!on) return;
    visible=!!on;source=reason||"unknown";
    host.style.display=visible?"block":"none";
    if (!visible) {pressed=null;stopTimers();stop();}
    report("地图箭头："+(visible?"显示":"隐藏")+"；"+source);
  }
  document.addEventListener("visibilitychange",function(){if(document.hidden)show(false,"App进入后台");});
  window.addEventListener("pagehide",function(){show(false,"游戏退出");});
  window.addEventListener("orientationchange",function(){pressed=null;stopTimers();stop();});
  report("地图辅助Build115：默认关闭；通过SWF事件显示，三点菜单可手动测试");
  return {
    setMapVisible:show,
    toggleManual:function(){show(!visible,"三点菜单手动测试");},
    hide:function(reason){show(false,reason||"手动关闭");},
    state:function(){return{visible:visible,source:source,steps:steps};}
  };
};
})();