/* 拾光号 iOS Build116 — galaxy arrows. Edge-hover first, drag fallback.
   Auto visibility requires a trusted game SWF map-open/close notification.
   Never infer screen state from resource requests or image recognition. */
(function(){"use strict";
window.ShiguangGalaxyNavigation=function(player,report){
  var visible=false,mode="edge",pressed=null,holdTimer=null,repeatTimer=null;
  var motionTimer=null,frame=0,dragging=null,moves=0,lastTarget=null;
  var host=document.createElement("div");host.id="sh-galaxy-arrows";
  host.style.cssText="position:fixed;inset:0;z-index:2147482790;pointer-events:none;display:none;";
  function canvasNow(){
    var root=player&&player.shadowRoot,cs=root&&root.querySelectorAll("canvas"),best=null;
    if(cs)for(var i=0;i<cs.length;i++){
      var c=cs[i],r=c.getBoundingClientRect();
      if(c.isConnected&&r.width>80&&r.height>80&&(!best||r.width>best.r.width))best={c:c,r:r};
    }
    return best;
  }
  function pointer(c,type,x,y,buttons){
    if(!c||!c.isConnected)return false;
    var r=c.getBoundingClientRect();
    x=Math.max(r.left+3,Math.min(r.right-3,x));
    y=Math.max(r.top+3,Math.min(r.bottom-3,y));
    var e=new PointerEvent(type,{bubbles:true,composed:true,cancelable:true,
      pointerId:89,pointerType:"mouse",isPrimary:true,clientX:x,clientY:y,
      button:type==="pointermove"?-1:0,buttons:buttons});
    try{
      Object.defineProperty(e,"offsetX",{configurable:true,value:(x-r.left)*(c.offsetWidth||r.width)/r.width});
      Object.defineProperty(e,"offsetY",{configurable:true,value:(y-r.top)*(c.offsetHeight||r.height)/r.height});
    }catch(_){}
    c.dispatchEvent(e);return true;
  }
  function stopTimers(){
    if(holdTimer!==null){clearTimeout(holdTimer);holdTimer=null;}
    if(repeatTimer!==null){clearInterval(repeatTimer);repeatTimer=null;}
    if(motionTimer!==null){clearTimeout(motionTimer);motionTimer=null;}
  }
  function releaseDrag(){
    if(frame){cancelAnimationFrame(frame);frame=0;}
    if(dragging){pointer(dragging.c,"pointerup",dragging.x,dragging.y,0);dragging=null;}
  }
  function centerCursor(){
    if(lastTarget){var info=canvasNow();if(info){
      pointer(info.c,"pointermove",info.r.left+info.r.width/2,info.r.top+info.r.height/2,0);
    }}
    lastTarget=null;
  }
  function stopMotion(){stopTimers();releaseDrag();centerCursor();}
  // Moving the cursor near the edge matches many original Flash galaxy maps.
  // No artificial mouse-down: do not accidentally select a planet.
  function hoverEdge(direction){
    var info=canvasNow();if(!info){report("地图箭头：找不到 Ruffle 画布");return false;}
    var r=info.r,x=r.left+r.width*(direction<0?.055:.945),y=r.top+r.height*.58;
    if(!lastTarget||lastTarget!==info.c)pointer(info.c,"pointerenter",x,y,0);
    lastTarget=info.c;pointer(info.c,"pointermove",x,y,0);moves++;return true;
  }
  function swipe(direction){
    if(dragging||!visible||document.hidden)return;
    var info=canvasNow();if(!info)return;
    var c=info.c,r=info.r,dx=Math.min(190,r.width*.22);
    var x0=r.left+r.width*(direction<0?.64:.36),x1=x0+dx*direction;
    var y=r.top+r.height*.56,started=performance.now();
    dragging={c:c,x:x0,y:y};
    pointer(c,"pointerenter",x0,y,0);
    pointer(c,"pointermove",x0,y,0);
    if(!pointer(c,"pointerdown",x0,y,1)){releaseDrag();return;}
    function tick(now){
      if(!visible||document.hidden){releaseDrag();return;}
      var p=Math.max(0,Math.min(1,(now-started)/300)),e=p*p*(3-2*p);
      if(!dragging)return;
      dragging.x=x0+(x1-x0)*e;pointer(c,"pointermove",dragging.x,y,1);
      if(p<1)frame=requestAnimationFrame(tick);
      else{frame=0;releaseDrag();moves++;}
    }
    frame=requestAnimationFrame(tick);
  }
  function startMotion(direction,continuous){
    if(!visible||document.hidden)return;
    if(mode==="edge"){
      hoverEdge(direction);
      if(continuous)repeatTimer=setInterval(function(){
        if(visible&&pressed)hoverEdge(direction);else stopMotion();
      },120);
      else motionTimer=setTimeout(function(){motionTimer=null;centerCursor();},560);
    }else{
      swipe(direction);
      if(continuous)repeatTimer=setInterval(function(){
        if(visible&&pressed)swipe(direction);else stopMotion();
      },330);
    }
    report("地图箭头："+(direction<0?"左":"右")+"，"+(mode==="edge"?"边缘悬停":"模拟拖拽")+"；需要实机验证地图是否流动");
  }
  function layout(){
    var info=canvasNow(),r=info&&info.r;if(!r)return;
    leftButton.style.left=Math.max(4,r.left+6)+"px";
    rightButton.style.right=Math.max(4,window.innerWidth-r.right+6)+"px";
  }
  function arrow(dir,label){
    var b=document.createElement("button");b.type="button";b.textContent=label;
    b.setAttribute("aria-label",dir<0?"地图向左流动":"地图向右流动");
    b.style.cssText="position:absolute;top:53%;transform:translateY(-50%);"+
      "width:48px;height:64px;pointer-events:auto;touch-action:none;"+
      "-webkit-user-select:none;-webkit-tap-highlight-color:transparent;"+
      "border:1px solid rgba(220,238,255,.85);border-radius:15px;"+
      "background:rgba(14,40,81,.76);color:white;font:bold 30px sans-serif;"+
      "box-shadow:0 3px 9px #0007";
    host.appendChild(b);
    b.addEventListener("pointerdown",function(ev){
      if(!visible||pressed)return;
      ev.preventDefault();ev.stopPropagation();stopMotion();
      pressed={id:ev.pointerId,dir:dir,long:false};
      try{b.setPointerCapture(ev.pointerId);}catch(_){}
      holdTimer=setTimeout(function(){
        holdTimer=null;if(!pressed||pressed.id!==ev.pointerId||!visible)return;
        pressed.long=true;startMotion(dir,true);
      },350);
    });
    b.addEventListener("pointerup",function(ev){
      if(!pressed||pressed.id!==ev.pointerId)return;
      ev.preventDefault();ev.stopPropagation();
      var single=!pressed.long,direction=pressed.dir;pressed=null;
      if(single){stopTimers();startMotion(direction,false);}else stopMotion();
    });
    ["pointercancel","lostpointercapture"].forEach(function(type){
      b.addEventListener(type,function(ev){
        if(pressed&&ev.pointerId===pressed.id){pressed=null;stopMotion();}
      });
    });
    b.addEventListener("click",function(ev){ev.preventDefault();ev.stopPropagation();});
    return b;
  }
  var leftButton=arrow(-1,"❮"),rightButton=arrow(1,"❯");
  var close=document.createElement("button");close.type="button";close.textContent="关闭地图箭头";
  close.style.cssText="position:absolute;bottom:calc(env(safe-area-inset-bottom,0px) + 12px);"+
    "left:50%;transform:translateX(-50%);pointer-events:auto;touch-action:manipulation;"+
    "font:12px -apple-system,sans-serif;border-radius:12px;padding:7px 12px;"+
    "border:1px solid #cde5ff90;background:#122c55cc;color:white";
  close.addEventListener("click",function(e){e.preventDefault();e.stopPropagation();show(false,"游戏内关闭按钮");});
  host.appendChild(close);document.body.appendChild(host);
  function show(on,origin){
    visible=!!on;stopMotion();host.style.display=visible?"block":"none";
    if(visible)layout();
    report("地图箭头："+(visible?"显示":"隐藏")+"；"+(origin||"未知")+"；模式="+mode);
  }
  function cycleMode(){
    stopMotion();mode=mode==="edge"?"drag":"edge";
    report("地图流动方式切换："+(mode==="edge"?"边缘悬停（推荐）":"手势拖拽（备选）"));
    return mode;
  }
  document.addEventListener("visibilitychange",function(){if(document.hidden)show(false,"后台隐藏");});
  window.addEventListener("pagehide",function(){show(false,"页面退出");});
  window.addEventListener("resize",function(){if(visible)layout();});
  window.addEventListener("orientationchange",function(){stopMotion();if(visible)layout();});
  report("地图Build116：默认边缘悬停、拖拽可切换；无SWF地图事件时仅手动显示");
  return {setMapVisible:show,hide:function(why){show(false,why||"用户隐藏");},
    toggleManual:function(){show(!visible,"菜单手动测试");},cycleMode:cycleMode,
    state:function(){return {visible:visible,mode:mode,moves:moves};}};
};
})();