/* Shiguang iPad touch assistance v4.5
 * Ruffle 0.7.1 web/src/lib.rs attaches pointer handlers to the inner CANVAS.
 * These helpers never inspect SWF memory, credentials, or network payloads.
 */
(function () {
  "use strict";
  window.ShiguangTouchControls = function install(player, report, onKeyboard) {
    var root = player && player.shadowRoot;
    var canvasWarned = false, hoverPrimed = false, clicks = 0;
    var mouseEnabled = false, mapEnabled = false, dragging = false;
    var mousePoint = null, padPointer = null, headerPointer = null;
    var speeds = [0.85, 1.45, 2.2], speedIndex = 1;
    var markers = [
      [0.164,0.47],[0.233,0.408],[0.376,0.376],
      [0.517,0.426],[0.665,0.363],[0.784,0.538],
      [0.688,0.681],[0.577,0.674],[0.465,0.683]
    ];
    var custom = false, selection = 0, marking = false;
    var mapPointer = null, statusHideTimer = null;
    try {
      var savedSpeed = parseInt(localStorage.getItem("shiguang.mouseSpeed"), 10);
      if (savedSpeed >= 0 && savedSpeed < speeds.length) speedIndex = savedSpeed;
      var savedMarkers = JSON.parse(localStorage.getItem("shiguang.mapMarkers") || "null");
      if (Array.isArray(savedMarkers) && savedMarkers.length > 0 && savedMarkers.length <= 30 &&
          savedMarkers.every(function(p){ return Array.isArray(p) && p.length===2 &&
            p.every(function(v){ return typeof v==="number" && Number.isFinite(v) && v>=0 && v<=1; }); })) {
        markers = savedMarkers; custom = true;
      }
    } catch (_) {}
    var style = document.createElement("style");
    style.id = "shiguang-touch-v45";
    style.textContent = [
      "#sh-touch-mouse{position:fixed;left:17px;top:34%;z-index:2147482800;width:239px;display:none;",
      "background:rgba(13,31,61,.89);border:1px solid rgba(133,206,255,.9);border-radius:16px;",
      "color:white;box-shadow:0 5px 19px #0008;font:13px -apple-system,sans-serif;touch-action:none;user-select:none}",
      "#sh-touch-head{display:flex;justify-content:space-between;align-items:center;padding:8px 12px;",
      "background:rgba(33,105,172,.55);border-radius:16px 16px 0 0;touch-action:none;cursor:move}",
      "#sh-touch-track{margin:8px;border-radius:10px;height:101px;background:rgba(140,190,231,.15);",
      "border:1px dashed rgba(161,217,255,.7);display:flex;align-items:center;justify-content:center;",
      "color:#b9dcf4;touch-action:none;cursor:crosshair}",
      "#sh-touch-row{display:flex;flex-wrap:wrap;gap:5px;padding:0 8px 8px}",
      "#sh-touch-row button,#sh-map-toolbar button{border:0;border-radius:8px;padding:8px 9px;",
      "background:#e4f5ff;color:#164773;font-weight:650;font-size:12px;touch-action:manipulation}",
      "#sh-touch-row button.active{background:#fbe76b;color:#1e324c}",
      "#sh-touch-cursor,#sh-map-marker{display:none;pointer-events:none;position:fixed;",
      "z-index:2147482850;transform:translate(-50%,-50%);width:21px;height:21px;",
      "border-radius:50%;border:2px solid #fff277;background:rgba(34,68,108,.3);",
      "box-shadow:0 0 0 2px #122a4a,0 0 8px #000c}",
      "#sh-touch-cursor:before,#sh-map-marker:before{content:'';position:absolute;",
      "width:3px;height:32px;background:#fff277;left:7px;top:-8px}",
      "#sh-touch-cursor:after,#sh-map-marker:after{content:'';position:absolute;",
      "height:3px;width:32px;background:#fff277;top:7px;left:-8px}",
      "#sh-map-layer{position:fixed;inset:0;display:none;z-index:2147482790;",
      "touch-action:none;background:transparent}",
      "#sh-map-toolbar{position:fixed;bottom:95px;left:50%;transform:translateX(-50%);",
      "display:none;z-index:2147482840;align-items:center;gap:5px;padding:7px;border-radius:12px;",
      "color:white;font:12px -apple-system,sans-serif;background:rgba(10,30,65,.9);",
      "box-shadow:0 4px 16px #0009;max-width:calc(100vw - 20px)}",
      "#sh-map-status{position:fixed;top:94px;left:50%;transform:translateX(-50%);",
      "display:none;z-index:2147482842;padding:7px 13px;border-radius:20px;",
      "font:12px -apple-system,sans-serif;color:white;background:rgba(11,34,70,.85);",
      "max-width:80vw;white-space:nowrap}",
      "#sh-touch-tip{position:fixed;left:50%;top:102px;transform:translateX(-50%);",
      "display:none;z-index:2147482900;color:white;background:rgba(0,0,0,.79);",
      "border-radius:12px;padding:8px 13px;font:12px -apple-system,sans-serif;pointer-events:none}"
    ].join("");
    document.head.appendChild(style);

    function element(tag, id, parent, content) {
      var e = document.createElement(tag); e.id = id;
      if (content != null) e.textContent = content;
      parent.appendChild(e); return e;
    }
    function button(id, parent, text, handler) {
      var el = element("button", id, parent, text);
      el.type = "button";
      el.addEventListener("click", function(ev){ev.preventDefault();ev.stopPropagation();handler();});
      return el;
    }
    var mouseBox = element("div", "sh-touch-mouse", document.body);
    var header = element("div", "sh-touch-head", mouseBox);
    element("span","sh-touch-title",header,"鼠标触控板 · 拖动标题可移位");
    var track = element("div","sh-touch-track",mouseBox,"手指滑动 → 移动准星");
    var mouseRow = element("div","sh-touch-row",mouseBox);
    var leftButton = button("sh-touch-click",mouseRow,"点击",function(){clickAt(mousePoint,0);});
    var dragButton = button("sh-touch-drag",mouseRow,"按住拖动",function(){setDragging(!dragging);});
    button("sh-touch-reset",mouseRow,"准星居中",function(){centerCursor();});
    var speedButton = button("sh-touch-speed",mouseRow,"速度 1.45×",function(){
      speedIndex=(speedIndex+1)%speeds.length;
      speedButton.textContent="速度 "+speeds[speedIndex]+"×";
      try {localStorage.setItem("shiguang.mouseSpeed",String(speedIndex));}catch(_){}
      showTip("鼠标速度 "+speeds[speedIndex]+"×");
    });
    button("sh-touch-exit",mouseRow,"关闭",function(){setMouseMode(false);});
    speedButton.textContent="速度 "+speeds[speedIndex]+"×";
    var cursor = element("div","sh-touch-cursor",document.body);
    var mapLayer = element("div","sh-map-layer",document.body);
    var mapMark = element("div","sh-map-marker",document.body);
    var mapBar = element("div","sh-map-toolbar",document.body);
    var mapStatus = element("div","sh-map-status",document.body);
    var tip = element("div","sh-touch-tip",document.body);
    button("sh-map-prev",mapBar,"◀ 上一个",function(){cycle(-1);});
    button("sh-map-next",mapBar,"下一个 ▶",function(){cycle(1);});
    button("sh-map-enter",mapBar,"进入",function(){enterSelected();});
    var markButton = button("sh-map-add",mapBar,"标记星球",function(){
      marking=!marking;
      markButton.textContent=marking?"点击星球标记":"标记星球";
      updateMapStatus();
      showTip(marking?"点击地图中的星球中心，完成自定义选点":"标记已取消");
    });
    button("sh-map-reset",mapBar,"恢复模板",function(){
      markers=[[0.164,0.47],[0.233,0.408],[0.376,0.376],
        [0.517,0.426],[0.665,0.363],[0.784,0.538],
        [0.688,0.681],[0.577,0.674],[0.465,0.683]];
      custom=false;marking=false;selection=0;markButton.textContent="标记星球";
      try{localStorage.removeItem("shiguang.mapMarkers");}catch(_){}
      refreshMarker();showTip("恢复截图星图的九个参考选点");
    });
    button("sh-map-exit",mapBar,"退出",function(){setMapMode(false);});

    function showTip(message) {
      tip.textContent=message;tip.style.display="block";
      clearTimeout(statusHideTimer);
      statusHideTimer=setTimeout(function(){tip.style.display="none";},2400);
    }
    function getCanvas() {
      var c=root && root.querySelector("canvas");
      if (!c || !c.isConnected || c.getBoundingClientRect().width<10) {
        if (!canvasWarned){canvasWarned=true;report("虚拟鼠标：等待 Ruffle 内部 Canvas 初始化");}
        return null;
      }
      return c;
    }
    function bounds() {
      var c=getCanvas();return c?c.getBoundingClientRect():null;
    }
    function clampPoint(point) {
      var r=bounds();
      if(!r || !point)return null;
      return {x:Math.max(r.left+2,Math.min(r.right-2,point.x)),
              y:Math.max(r.top+2,Math.min(r.bottom-2,point.y))};
    }
    function sendPointer(type,point,buttons,buttonCode) {
      var c=getCanvas(); if(!c || !point)return false;
      var p=clampPoint(point);if(!p)return false;
      // Rust web/src/lib.rs explicitly registers pointermove/down/up on canvas.
      // Host.dispatchEvent() does NOT travel downward into the shadow canvas.
      // Use one pointer event only; synthetic click/mouse events would duplicate input.
      if(!hoverPrimed){hoverPrimed=true;c.dispatchEvent(new PointerEvent("pointerenter",{
        pointerId:77,pointerType:"mouse",isPrimary:true,clientX:p.x,clientY:p.y
      }));}
      var event=new PointerEvent(type,{
        bubbles:true,composed:true,cancelable:true,
        pointerId:77,pointerType:"mouse",isPrimary:true,
        button:buttonCode===undefined ? (type==="pointermove"?-1:0) : buttonCode,
        buttons:buttons,clientX:p.x,clientY:p.y,
        screenX:p.x,screenY:p.y
      });
      c.dispatchEvent(event);
      return true;
    }
    function positionCursor(point) {
      var p=clampPoint(point);if(!p)return;
      mousePoint=p;cursor.style.left=p.x+"px";cursor.style.top=p.y+"px";
      sendPointer("pointermove",p,dragging?1:0);
    }
    function centerCursor() {
      var r=bounds();if(!r)return;
      positionCursor({x:r.left+r.width/2,y:r.top+r.height/2});
      showTip("准星已回到游戏画面中心");
    }
    function clickAt(point,buttonCode) {
      if(!point||dragging)return;
      if(!sendPointer("pointermove",point,0))return;
      sendPointer("pointerdown",point,buttonCode===2?2:1,buttonCode);
      setTimeout(function(){sendPointer("pointerup",point,0,buttonCode);},55);
      clicks++;
      if(clicks<=4||clicks%10===0)report("虚拟鼠标：已发送 Canvas 点击 "+clicks+" 次（无账号或点击内容）");
    }
    function setDragging(yes) {
      if(!mousePoint)return;
      if(yes&&!dragging){
        if(sendPointer("pointerdown",mousePoint,1,0)){
          dragging=true;dragButton.classList.add("active");
          dragButton.textContent="松开拖动";
          showTip("已按住左键，滑动触控板拖拽");
        }
      }else if(!yes&&dragging){
        dragging=false;
        sendPointer("pointerup",mousePoint,0,0);
        dragButton.classList.remove("active");
        dragButton.textContent="按住拖动";
      }
    }
    function dragBox(ev) {
      if(!headerPointer||headerPointer.id!==ev.pointerId)return;
      ev.preventDefault();
      var x=headerPointer.baseX+ev.clientX-headerPointer.startX;
      var y=headerPointer.baseY+ev.clientY-headerPointer.startY;
      x=Math.max(5,Math.min(window.innerWidth-mouseBox.offsetWidth-5,x));
      y=Math.max(5,Math.min(window.innerHeight-mouseBox.offsetHeight-5,y));
      mouseBox.style.left=x+"px";mouseBox.style.top=y+"px";
    }
    header.addEventListener("pointerdown",function(ev){
      ev.preventDefault();
      var r=mouseBox.getBoundingClientRect();
      headerPointer={id:ev.pointerId,startX:ev.clientX,startY:ev.clientY,baseX:r.left,baseY:r.top};
      try{header.setPointerCapture(ev.pointerId);}catch(_){}
    });
    header.addEventListener("pointermove",dragBox);
    header.addEventListener("pointerup",function(){headerPointer=null;});
    header.addEventListener("pointercancel",function(){headerPointer=null;});
    track.addEventListener("pointerdown",function(ev){
      ev.preventDefault();
      padPointer={id:ev.pointerId,x:ev.clientX,y:ev.clientY,total:0};
      try{track.setPointerCapture(ev.pointerId);}catch(_){}
    });
    track.addEventListener("pointermove",function(ev){
      if(!padPointer||ev.pointerId!==padPointer.id)return;
      ev.preventDefault();
      var dx=ev.clientX-padPointer.x,dy=ev.clientY-padPointer.y;
      padPointer.x=ev.clientX;padPointer.y=ev.clientY;
      padPointer.total+=Math.abs(dx)+Math.abs(dy);
      if(!mousePoint)centerCursor();
      if(mousePoint)positionCursor({x:mousePoint.x+dx*speeds[speedIndex],
                                   y:mousePoint.y+dy*speeds[speedIndex]});
    });
    track.addEventListener("pointerup",function(ev){
      if(!padPointer||ev.pointerId!==padPointer.id)return;
      var total=padPointer.total;padPointer=null;
      if(total<10)clickAt(mousePoint,0);
    });
    track.addEventListener("pointercancel",function(){padPointer=null;});
    function setMouseMode(yes) {
      if(!!yes===mouseEnabled)return;
      if(yes&&mapEnabled)setMapMode(false);
      mouseEnabled=!!yes;
      mouseBox.style.display=mouseEnabled?"block":"none";
      cursor.style.display=mouseEnabled?"block":"none";
      if(mouseEnabled){centerCursor();showTip("滑动触控板控制准星，轻点或按「点击」操作");}
      else{setDragging(false);padPointer=null;}
      report("触控辅助：鼠标面板"+(mouseEnabled?"开启":"关闭")+"，事件目标=Canvas");
    }
    function markerPosition(index) {
      var r=bounds(),m=markers[index];
      if(!r||!m)return null;
      return {x:r.left+m[0]*r.width,y:r.top+m[1]*r.height};
    }
    function updateMapStatus() {
      var name=custom?"自定义":"星图参考";
      mapStatus.textContent=marking?"标记模式：点击星球中心":
        "星图 "+name+" · "+(selection+1)+"/"+markers.length+" · 左右滑动切换";
    }
    function refreshMarker() {
      if(!mapEnabled || !markers.length)return;
      var p=markerPosition(selection);
      if(p){mapMark.style.left=p.x+"px";mapMark.style.top=p.y+"px";}
      updateMapStatus();
      if(p)sendPointer("pointermove",p,0);
    }
    function cycle(direction) {
      if(!markers.length)return;
      selection=(selection+direction+markers.length)%markers.length;
      refreshMarker();
    }
    function enterSelected() {
      var p=markerPosition(selection);
      if(p){clickAt(p,0);showTip("已向游戏发出星球点击；如未打开请自定义标记位置");}
    }
    function saveMarkerAt(clientX,clientY) {
      var r=bounds();if(!r)return;
      var p=clampPoint({x:clientX,y:clientY});if(!p)return;
      if(!custom){markers=[];selection=0;custom=true;}
      if(markers.length>=30){showTip("最多保存30个星球点");return;}
      markers.push([(p.x-r.left)/r.width,(p.y-r.top)/r.height]);
      selection=markers.length-1;
      try{localStorage.setItem("shiguang.mapMarkers",JSON.stringify(markers));}catch(_){}
      showTip("已标记第 "+markers.length+" 个星球点");
      refreshMarker();
    }
    mapLayer.addEventListener("pointerdown",function(ev){
      if(!mapEnabled)return;ev.preventDefault();
      mapPointer={id:ev.pointerId,x:ev.clientX,y:ev.clientY};
      try{mapLayer.setPointerCapture(ev.pointerId);}catch(_){}
    });
    mapLayer.addEventListener("pointerup",function(ev){
      if(!mapEnabled||!mapPointer||ev.pointerId!==mapPointer.id)return;
      ev.preventDefault();
      var p=mapPointer;mapPointer=null;
      var dx=ev.clientX-p.x,dy=ev.clientY-p.y;
      if(Math.abs(dx)>58 && Math.abs(dx)>1.25*Math.abs(dy)){
        cycle(dx<0?1:-1);
      }else if(Math.abs(dx)<20&&Math.abs(dy)<20){
        if(marking)saveMarkerAt(ev.clientX,ev.clientY);
        else{
          // Direct tap remains useful when the supplied screenshot map has
          // icons outside the reference marker set.
          clickAt({x:ev.clientX,y:ev.clientY},0);
        }
      }
    });
    mapLayer.addEventListener("pointercancel",function(){mapPointer=null;});
    function setMapMode(yes){
      if(!!yes===mapEnabled)return;
      if(yes&&mouseEnabled)setMouseMode(false);
      mapEnabled=!!yes;
      mapLayer.style.display=mapEnabled?"block":"none";
      mapBar.style.display=mapEnabled?"flex":"none";
      mapMark.style.display=mapEnabled?"block":"none";
      mapStatus.style.display=mapEnabled?"block":"none";
      if(mapEnabled){
        refreshMarker();
        showTip("左右划星图或点上一颗/下一颗；点「进入」发送真实 Canvas 点击");
      }else{mapPointer=null;marking=false;markButton.textContent="标记星球";}
      report("触控辅助：星图选点"+(mapEnabled?"开启":"关闭")+
        (custom?"（自定义星球点）":"（截图参考星图九点）"));
    }
    var resizeObserver=null;
    try {
      resizeObserver=new ResizeObserver(function(){
        if(mouseEnabled&&mousePoint){
          var clamped=clampPoint(mousePoint);
          if(clamped){mousePoint=clamped;cursor.style.left=clamped.x+"px";cursor.style.top=clamped.y+"px";}
        }
        if(mapEnabled)refreshMarker();
      });
      resizeObserver.observe(player);
    }catch(_){}
    report("触控辅助 v4.5 已安装：Canvas 定位/触控板/星图选点；保留真实游戏资源");
    return {
      enableMouse:function(){setMouseMode(true);},
      disableMouse:function(){setMouseMode(false);},
      enableMapSwipe:function(){setMapMode(true);},
      disableMapSwipe:function(){setMapMode(false);},
      resetCursor:centerCursor,
      cycleSpeed:function(){speedButton.click();},
      hideAll:function(){setMouseMode(false);setMapMode(false);}
    };
  };
})();