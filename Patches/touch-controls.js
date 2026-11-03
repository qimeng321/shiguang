/* Shiguang v6.0 test-only smart long-press hover + opt-in direct-screen delayed release.
   Ruffle 0.7.1 reads PointerEvent.offsetX/Y from its inner canvas. */
(function(){
"use strict";
window.ShiguangTouchControls=function(player,report){
  var root=player&&player.shadowRoot,canvas=null,hover=false,enabled=false,drag=false;
  var pos=null,padGesture=null,headerGesture=null,clickPending=null,clickTimer=null;
  var pressDelayTimer=null,delayedTap=false;
  var directTouch=null,directPressTimer=null,directReleaseTimer=null;
  var lastDirectTouchAt=0,directTapCount=0;
  // Opt-in test gesture: short touch -> click, hold -> hover only, swipe -> drag.
  // Keep it independent from the old delayed release path for safe rollback.
  var smartHover=false,smartTouch=null,smartHoldTimer=null,smartTapTimer=null;
  var smartTapPending=null,smartPointers=new Set(),smartMultiTouch=false;
  var smartLongCount=0;
  var count=0,recoveries=0,lastMissing=false,speedIndex=1;
  var speeds=[0.85,1.45,2.2],tipTimer=null;
  try{
    var saved=Number(localStorage.getItem("shiguang.mouseSpeed"));
    if(Number.isInteger(saved)&&saved>=0&&saved<speeds.length)speedIndex=saved;
  }catch(e){}
  var style=document.createElement("style");style.id="sh-mouse-v48";
  style.textContent=[
    "#sh-mouse{position:fixed;top:34%;left:17px;width:239px;display:none;z-index:2147482800;",
    "background:rgba(13,31,61,.91);color:#fff;border:1px solid #8bc6ff;border-radius:16px;",
    "box-shadow:0 5px 18px #0008;font:13px -apple-system,sans-serif;user-select:none;touch-action:none}",
    "#sh-mouse,#sh-mouse *{-webkit-user-select:none!important;user-select:none!important;",
    "-webkit-touch-callout:none!important;-webkit-tap-highlight-color:transparent}",
    "#sh-mouse-head{padding:9px 12px;border-radius:15px 15px 0 0;background:rgba(33,105,172,.58);",
    "cursor:move;touch-action:none}",
    "#sh-mouse-track{height:101px;margin:8px;border:1px dashed #a1d9ff;border-radius:10px;",
    "display:flex;align-items:center;justify-content:center;background:#9bc9f125;color:#cbe8f9;",
    "touch-action:none;cursor:crosshair}",
    "#sh-mouse-row{padding:0 8px 8px;display:flex;flex-wrap:wrap;gap:5px}",
    "#sh-mouse-row button{border:0;border-radius:8px;padding:8px 9px;background:#e4f5ff;",
    "color:#164773;font-weight:650;font-size:12px;touch-action:manipulation}",
    "#sh-mouse-row button.active{background:#fbe76b}",
    "#sh-mouse-cursor{position:fixed;display:none;pointer-events:none;z-index:2147482850;",
    "transform:translate(-50%,-50%);width:21px;height:21px;border:2px solid #fff277;",
    "border-radius:50%;background:rgba(34,68,108,.30);box-shadow:0 0 0 2px #122a4a,0 0 8px #000c}",
    "#sh-mouse-cursor:before{content:'';position:absolute;width:3px;height:32px;",
    "background:#fff277;left:7px;top:-8px}",
    "#sh-mouse-cursor:after{content:'';position:absolute;height:3px;width:32px;",
    "background:#fff277;left:-8px;top:7px}",
    "#sh-mouse-tip{position:fixed;display:none;pointer-events:none;z-index:2147482900;",
    "top:102px;left:50%;transform:translateX(-50%);padding:8px 12px;background:#000c;",
    "color:#fff;border-radius:12px;font:12px -apple-system,sans-serif;white-space:nowrap}"
  ].join("");
  document.head.appendChild(style);
  function el(tag,id,parent,text){
    var x=document.createElement(tag);x.id=id;
    if(text!==undefined)x.textContent=text;parent.appendChild(x);return x;
  }
  function btn(id,parent,label,callback){
    var x=el("button",id,parent,label);x.type="button";
    x.addEventListener("click",function(ev){ev.preventDefault();ev.stopPropagation();callback();});
    return x;
  }
  var box=el("div","sh-mouse",document.body);
  // Scope selection suppression to the custom pad. Never break login textfields.
  ["contextmenu","selectstart","dragstart"].forEach(function(type){
    box.addEventListener(type,function(e){e.preventDefault();e.stopPropagation();},true);
  });
  var header=el("div","sh-mouse-head",box,"鼠标触控板 · 拖动标题可移位");
  var track=el("div","sh-mouse-track",box,"滑动移动准星，轻点点击");
  var row=el("div","sh-mouse-row",box);
  btn("sh-mouse-click",row,"点击",click);
  btn("sh-mouse-double",row,"双击",doubleClick);
  btn("sh-mouse-right",row,"右键",rightClick);
  var dragBtn=btn("sh-mouse-drag",row,"按住拖动",function(){setDrag(!drag);});
  btn("sh-mouse-center",row,"准星居中",center);
  var speedBtn=btn("sh-mouse-speed",row,"速度 "+speeds[speedIndex]+"×",function(){
    speedIndex=(speedIndex+1)%speeds.length;
    speedBtn.textContent="速度 "+speeds[speedIndex]+"×";
    try{localStorage.setItem("shiguang.mouseSpeed",String(speedIndex));}catch(e){}
    tip("速度 "+speeds[speedIndex]+"×");
  });
  btn("sh-mouse-close",row,"关闭",function(){setMode(false);});
  var cursor=el("div","sh-mouse-cursor",document.body);
  var toast=el("div","sh-mouse-tip",document.body);
  function tip(text){
    toast.textContent=text;toast.style.display="block";
    if(tipTimer!==null)clearTimeout(tipTimer);
    tipTimer=setTimeout(function(){toast.style.display="none";},2400);
  }
  function canvasNow(){
    var candidates=root&&root.querySelectorAll("canvas"),best=null;
    if(candidates)for(var i=0;i<candidates.length;i++){
      var c=candidates[i],r=c.getBoundingClientRect();
      if(c.isConnected&&r.width>80&&r.height>80&&(!best||r.width>best.getBoundingClientRect().width))best=c;
    }
    if(!best){
      if(!lastMissing){lastMissing=true;report("鼠标：Ruffle Canvas 尚未就绪");}
      return null;
    }
    lastMissing=false;
    if(best!==canvas){
      canvas=best;hover=false;
      canvas.addEventListener("pointerdown",function(ev){
        if(!ev.isTrusted)return;
        hover=false;
        endClick();
        if(drag)endDrag();
        if(enabled&&++recoveries<=5)report("鼠标：检测到真实手指点击，自动重新同步鼠标进入状态");
      },true);
      ["pointerup","pointercancel","pointerleave"].forEach(function(type){
        canvas.addEventListener(type,function(ev){if(ev.isTrusted)hover=false;},true);
      });
    }
    return canvas;
  }
  function bounds(){var c=canvasNow();return c?c.getBoundingClientRect():null;}
  function clamp(point){
    var r=bounds();if(!r||!point)return null;
    return {x:Math.max(r.left+2,Math.min(r.right-2,point.x)),
            y:Math.max(r.top+2,Math.min(r.bottom-2,point.y))};
  }
  function emit(type,point,buttons,code){
    var c=canvasNow(),p=clamp(point);if(!c||!p)return false;
    var r=c.getBoundingClientRect();
    var x=(p.x-r.left)*(c.offsetWidth||r.width)/r.width;
    var y=(p.y-r.top)*(c.offsetHeight||r.height)/r.height;
    // A second pointerenter on press resets Flash hover menus such as NoNo.
    if(!hover){
      hover=true;
      c.dispatchEvent(new PointerEvent("pointerenter",{
        pointerId:77,pointerType:"mouse",isPrimary:true,clientX:p.x,clientY:p.y
      }));
    }
    var ev=new PointerEvent(type,{
      bubbles:true,composed:true,cancelable:true,pointerId:77,pointerType:"mouse",
      isPrimary:true,button:code===undefined?(type==="pointermove"?-1:0):code,
      buttons:buttons,clientX:p.x,clientY:p.y,screenX:p.x,screenY:p.y
    });
    try{
      Object.defineProperty(ev,"offsetX",{configurable:true,value:x});
      Object.defineProperty(ev,"offsetY",{configurable:true,value:y});
    }catch(e){if(count<2)report("鼠标：局部坐标设置异常 "+String(e).slice(0,90));}
    c.dispatchEvent(ev);return true;
  }
  function move(point){
    if(pressDelayTimer!==null)endClick();
    var p=clamp(point);if(!p)return;
    pos=p;cursor.style.left=p.x+"px";cursor.style.top=p.y+"px";
    emit("pointermove",p,drag?1:0);
  }
  function center(){var r=bounds();if(r)move({x:r.left+r.width/2,y:r.top+r.height/2});}
  function endClick(){
    if(pressDelayTimer!==null){clearTimeout(pressDelayTimer);pressDelayTimer=null;}
    if(clickTimer!==null){clearTimeout(clickTimer);clickTimer=null;}
    if(!clickPending)return;
    var p=clickPending;clickPending=null;
    emit("pointerup",p,0,0);
  }
  function pressAt(p){
    if(!enabled||drag||!emit("pointerdown",p,1,0))return;
    clickPending=p;
    // Default 125ms retains existing behavior. Optional longer hold can
    // expose Flash hover-menu click targets without forcing the whole UI slow.
    clickTimer=setTimeout(endClick,delayedTap?350:125);
  }
  function click(){
    if(!enabled||drag||!pos)return;
    endClick();
    var target={x:pos.x,y:pos.y};
    if(!emit("pointermove",target,0))return;
    // Do not reset 'hover' here: NoNo's hover menu must survive pointerdown.
    if(delayedTap){
      pressDelayTimer=setTimeout(function(){
        pressDelayTimer=null;
        if(enabled&&!drag)pressAt(target);
      },120);
    }else{pressAt(target);}
    count++;
    if(count<=5||count%15===0)report("鼠标：已点击 "+count+" 次"+(delayedTap?"（延迟抬起）":"")+"；手指交替可继续使用");
  }
  function releaseSmartTap(){
    if(smartTapTimer!==null){clearTimeout(smartTapTimer);smartTapTimer=null;}
    if(smartTapPending){emit("pointerup",smartTapPending,0,0);smartTapPending=null;}
  }
  function smartClick(point){
    releaseSmartTap();
    if(!emit("pointermove",point,0)||!emit("pointerdown",point,1,0))return;
    smartTapPending=point;
    smartTapTimer=setTimeout(releaseSmartTap,65);
  }
  function doubleClick(){
    if(!enabled||drag||!pos)return;
    endClick();releaseSmartTap();
    var p={x:pos.x,y:pos.y};
    smartClick(p);
    setTimeout(function(){if(enabled&&!drag){releaseSmartTap();smartClick(p);}},160);
  }
  function rightClick(){
    if(!enabled||drag||!pos)return;
    endClick();releaseSmartTap();
    var p={x:pos.x,y:pos.y};
    emit("pointermove",p,0);
    if(emit("pointerdown",p,2,2)){
      setTimeout(function(){emit("pointerup",p,0,2);},75);
    }
  }
  function clearSmartHold(){
    if(smartHoldTimer!==null){clearTimeout(smartHoldTimer);smartHoldTimer=null;}
  }
  function cancelSmartTouch(){
    clearSmartHold();
    if(smartTouch&&smartTouch.pressed)emit("pointerup",smartTouch.point,0,0);
    smartTouch=null;
  }
  function smartPointerDown(ev){
    if(!smartHover||!ev.isTrusted||ev.pointerType!=="touch"||!gameTarget(ev))return;
    blockNative(ev);lastDirectTouchAt=performance.now();
    releaseSmartTap();smartPointers.add(ev.pointerId);
    if(smartPointers.size>1){smartMultiTouch=true;cancelSmartTouch();return;}
    if(smartMultiTouch)return;
    var p={x:ev.clientX,y:ev.clientY};
    var t={id:ev.pointerId,start:p,point:p,dragging:false,pressed:false,long:false};
    smartTouch=t;
    // Establish mouse hover without down so the original NoNo ring can appear.
    emit("pointermove",p,0);
    clearSmartHold();
    smartHoldTimer=setTimeout(function(){
      smartHoldTimer=null;
      if(smartHover&&smartTouch===t&&!t.dragging&&!t.pressed){
        t.long=true;emit("pointermove",t.point,0);
        smartLongCount++;
        if(smartLongCount<=3)tip("已触发悬停 · 松手后点圆环功能");
        if(smartLongCount<=5||smartLongCount%20===0)report("智能悬停：长按已识别 "+smartLongCount+" 次");
      }
    },420);
  }
  function smartPointerMove(ev){
    if(!smartHover||!ev.isTrusted||ev.pointerType!=="touch"||!smartPointers.has(ev.pointerId))return;
    blockNative(ev);lastDirectTouchAt=performance.now();
    var t=smartTouch;
    if(!t||t.id!==ev.pointerId||smartMultiTouch)return;
    t.point={x:ev.clientX,y:ev.clientY};
    if(t.long){emit("pointermove",t.point,0);return;}
    if(Math.hypot(t.point.x-t.start.x,t.point.y-t.start.y)>12){
      if(!t.dragging){
        clearSmartHold();t.dragging=true;
        t.pressed=emit("pointerdown",t.start,1,0);
      }
      if(t.pressed)emit("pointermove",t.point,1,0);
    }
  }
  function smartPointerEnd(ev,cancelled){
    if(!smartHover||!ev.isTrusted||ev.pointerType!=="touch"||!smartPointers.has(ev.pointerId))return;
    blockNative(ev);lastDirectTouchAt=performance.now();
    smartPointers.delete(ev.pointerId);
    var t=smartTouch;
    if(t&&t.id===ev.pointerId){
      clearSmartHold();smartTouch=null;
      if(t.pressed){emit("pointerup",t.point,0,0);}
      else if(!cancelled&&!smartMultiTouch){
        if(t.long){emit("pointermove",t.point,0);}
        else{smartClick({x:ev.clientX,y:ev.clientY});}
      }
    }
    if(smartPointers.size===0)smartMultiTouch=false;
  }
  document.addEventListener("pointerdown",smartPointerDown,true);
  document.addEventListener("pointermove",smartPointerMove,true);
  document.addEventListener("pointerup",function(ev){smartPointerEnd(ev,false);},true);
  document.addEventListener("pointercancel",function(ev){smartPointerEnd(ev,true);},true);
  function setSmartHover(on){
    endClick();finishDirect(true);cancelSmartTouch();releaseSmartTap();
    smartPointers.clear();smartMultiTouch=false;
    smartHover=!!on;
    if(smartHover)delayedTap=false;
    report("智能悬停："+(smartHover?"开启（短按点击/长按420ms仅悬停/滑动拖动）":"关闭（恢复原生触控）"));
  }
  // Optional direct-screen touch-to-mouse bridge. This is separate from the
  // on-screen trackpad; it runs only when the user turns delayed tap ON.
  // Capture before Ruffle processes trusted touches to avoid double clicks.
  function gameTarget(ev){
    var path=typeof ev.composedPath==="function"?ev.composedPath():[];
    if(path.indexOf(player)<0)return false;
    for(var i=0;i<path.length;i++){
      var node=path[i],name=node&&node.tagName;
      if(name&&/^(INPUT|TEXTAREA|SELECT|BUTTON)$/.test(name))return false;
      if(node&&node.id==="sh-mouse")return false;
    }
    return !!canvasNow();
  }
  function blockNative(ev){
    if(ev.cancelable)ev.preventDefault();
    ev.stopImmediatePropagation();
  }
  function clearDirectTimers(){
    if(directPressTimer!==null){clearTimeout(directPressTimer);directPressTimer=null;}
    if(directReleaseTimer!==null){clearTimeout(directReleaseTimer);directReleaseTimer=null;}
  }
  function finishDirect(cancelled){
    clearDirectTimers();
    var t=directTouch;
    if(!t)return;
    directTouch=null;
    if(t.pressed)emit("pointerup",t.point,0,0);
    if(!cancelled){
      directTapCount++;
      if(directTapCount<=5||directTapCount%15===0)
        report("触屏延迟：已释放 "+directTapCount+" 次"+(t.moved?"（滑动，不延迟）":"（按住350ms）"));
    }
  }
  function queueDirectRelease(t){
    if(directTouch!==t||!t.pressed)return;
    if(t.moved){finishDirect(false);return;}
    var remaining=Math.max(0,350-(performance.now()-t.pressedAt));
    if(remaining<1){finishDirect(false);return;}
    if(directReleaseTimer!==null)clearTimeout(directReleaseTimer);
    directReleaseTimer=setTimeout(function(){
      directReleaseTimer=null;
      if(directTouch===t)finishDirect(false);
    },remaining);
  }
  function pressDirect(t){
    if(directTouch!==t||t.pressed)return;
    if(directPressTimer!==null){clearTimeout(directPressTimer);directPressTimer=null;}
    // Flash hover targets (NoNo) need the cursor movement BEFORE press.
    if(!emit("pointermove",t.point,0)) { finishDirect(true);return; }
    if(!emit("pointerdown",t.point,1,0)) { finishDirect(true);return; }
    t.pressed=true;t.pressedAt=performance.now();
    if(t.released)queueDirectRelease(t);
  }
  function directPointerDown(ev){
    if(!delayedTap||!ev.isTrusted||ev.pointerType!=="touch"||!gameTarget(ev))return;
    blockNative(ev);
    lastDirectTouchAt=performance.now();
    if(directTouch)finishDirect(true);
    var t={id:ev.pointerId,startX:ev.clientX,startY:ev.clientY,
      point:{x:ev.clientX,y:ev.clientY},moved:false,pressed:false,released:false,pressedAt:0};
    directTouch=t;
    // Hover first, then delay press. Very short taps still get a full click.
    emit("pointermove",t.point,0);
    directPressTimer=setTimeout(function(){directPressTimer=null;pressDirect(t);},120);
  }
  function directPointerMove(ev){
    var t=directTouch;
    if(!delayedTap||!t||!ev.isTrusted||ev.pointerType!=="touch"||ev.pointerId!==t.id)return;
    blockNative(ev);
    if(t.released)return;
    t.point={x:ev.clientX,y:ev.clientY};
    if(Math.hypot(ev.clientX-t.startX,ev.clientY-t.startY)>12)t.moved=true;
    if(t.moved&&!t.pressed)pressDirect(t);
    emit("pointermove",t.point,t.pressed?1:0);
  }
  function directPointerUp(ev){
    var t=directTouch;
    if(!delayedTap||!t||!ev.isTrusted||ev.pointerType!=="touch"||ev.pointerId!==t.id)return;
    blockNative(ev);
    lastDirectTouchAt=performance.now();
    t.point={x:ev.clientX,y:ev.clientY};
    t.released=true;
    // A swipe ends on the physical release; only a tap holds for 350ms.
    if(t.pressed)queueDirectRelease(t);
  }
  function directPointerCancel(ev){
    var t=directTouch;
    if(!delayedTap||!t||!ev.isTrusted||ev.pointerType!=="touch"||ev.pointerId!==t.id)return;
    blockNative(ev);finishDirect(true);
  }
  // Document CAPTURE is earlier than Ruffle's canvas/shadow listeners. The
  // events created by emit() are untrusted and bypass these interceptors.
  document.addEventListener("pointerdown",directPointerDown,true);
  document.addEventListener("pointermove",directPointerMove,true);
  document.addEventListener("pointerup",directPointerUp,true);
  document.addEventListener("pointercancel",directPointerCancel,true);
  ["pointerout","pointerleave"].forEach(function(type){
    document.addEventListener(type,function(ev){
      if(delayedTap&&directTouch&&ev.isTrusted&&ev.pointerType==="touch"&&ev.pointerId===directTouch.id)blockNative(ev);
    },true);
  });
  // iOS dispatches compatibility touch/mouse events in addition to pointer
  // events. Consume only those belonging to the Flash surface while active.
  ["touchstart","touchmove","touchend","touchcancel"].forEach(function(type){
    document.addEventListener(type,function(ev){
      if((delayedTap||smartHover)&&ev.isTrusted&&(directTouch||smartPointers.size>0||gameTarget(ev))){
        lastDirectTouchAt=performance.now();
        blockNative(ev);
      }
    },true);
  });
  ["mousedown","mouseup","click"].forEach(function(type){
    document.addEventListener(type,function(ev){
      if((delayedTap||smartHover)&&ev.isTrusted&&performance.now()-lastDirectTouchAt<700&&gameTarget(ev))
        blockNative(ev);
    },true);
  });
  function setDelayedTap(on){
    endClick();
    finishDirect(true);
    delayedTap=!!on;
    if(delayedTap){smartHover=false;cancelSmartTouch();releaseSmartTap();smartPointers.clear();smartMultiTouch=false;}
    report("触屏延迟：自动抬起"+(delayedTap?
      "已开启（手指直点及精准鼠标，悬停120ms + 保持按下350ms）":
      "已关闭（触屏恢复原生，精准鼠标保持125ms）"));
  }
  function endDrag(){
    if(!drag)return;
    drag=false;emit("pointerup",pos,0,0);
    dragBtn.textContent="按住拖动";dragBtn.classList.remove("active");
  }
  function setDrag(v){
    if(!enabled||!pos)return;
    if(!v){endDrag();return;}
    if(drag)return;
    endClick();hover=false;emit("pointermove",pos,0);
    if(emit("pointerdown",pos,1,0)){
      drag=true;dragBtn.textContent="松开拖动";dragBtn.classList.add("active");
    }
  }
  header.addEventListener("pointerdown",function(e){
    e.preventDefault();var r=box.getBoundingClientRect();
    headerGesture={id:e.pointerId,x:e.clientX,y:e.clientY,left:r.left,top:r.top};
    try{header.setPointerCapture(e.pointerId);}catch(_){}
  });
  header.addEventListener("pointermove",function(e){
    if(!headerGesture||e.pointerId!==headerGesture.id)return;
    e.preventDefault();
    var x=headerGesture.left+e.clientX-headerGesture.x;
    var y=headerGesture.top+e.clientY-headerGesture.y;
    box.style.left=Math.max(5,Math.min(window.innerWidth-box.offsetWidth-5,x))+"px";
    box.style.top=Math.max(5,Math.min(window.innerHeight-box.offsetHeight-5,y))+"px";
  });
  ["pointerup","pointercancel"].forEach(function(type){
    header.addEventListener(type,function(){headerGesture=null;});
  });
  track.addEventListener("pointerdown",function(e){
    e.preventDefault();padGesture={id:e.pointerId,x:e.clientX,y:e.clientY,distance:0};
    try{track.setPointerCapture(e.pointerId);}catch(_){}
  });
  track.addEventListener("pointermove",function(e){
    if(!padGesture||e.pointerId!==padGesture.id)return;
    e.preventDefault();
    var dx=e.clientX-padGesture.x,dy=e.clientY-padGesture.y;
    padGesture.x=e.clientX;padGesture.y=e.clientY;
    padGesture.distance+=Math.abs(dx)+Math.abs(dy);
    if(!pos)center();
    if(pos)move({x:pos.x+dx*speeds[speedIndex],y:pos.y+dy*speeds[speedIndex]});
  });
  track.addEventListener("pointerup",function(e){
    if(!padGesture||e.pointerId!==padGesture.id)return;
    var distance=padGesture.distance;padGesture=null;
    if(distance<10)click();
  });
  track.addEventListener("pointercancel",function(){padGesture=null;});
  function setMode(on){
    if(enabled===!!on){
      if(on){hover=false;if(pos)move(pos);}
      return;
    }
    enabled=!!on;
    box.style.display=enabled?"block":"none";
    cursor.style.display=enabled?"block":"none";
    if(enabled){hover=false;if(pos)move(pos);else center();tip("手指点完游戏后，可继续操作触控板");}
    else{endClick();endDrag();padGesture=null;hover=false;}
    report("鼠标："+(enabled?"开启":"关闭")+"；真实触摸后的状态自动恢复");
  }
  document.addEventListener("visibilitychange",function(){if(document.hidden){endClick();endDrag();finishDirect(true);cancelSmartTouch();releaseSmartTap();smartPointers.clear();smartMultiTouch=false;}});
  window.addEventListener("pagehide",function(){endClick();endDrag();finishDirect(true);cancelSmartTouch();releaseSmartTap();smartPointers.clear();smartMultiTouch=false;});
  try{new ResizeObserver(function(){
    if(enabled&&pos){var p=clamp(pos);if(p){pos=p;cursor.style.left=p.x+"px";cursor.style.top=p.y+"px";}}
  }).observe(player);}catch(e){}
  report("鼠标 v6.0 测试：智能悬停默认关闭；长按仅移动鼠标触发 NoNo 圆环，虚拟鼠标支持双击/右键");
  return {enableMouse:function(){setMode(true);},disableMouse:function(){setMode(false);},
    hideAll:function(){setMode(false);},resetCursor:center,
    cycleSpeed:function(){speedBtn.click();},setDelayedTap:setDelayedTap,setSmartHover:setSmartHover};
};
})();