/* Shiguang v4.7 - compact map bookmarks.
 * Never claims to know the private server's current scene or teleport API.
 * Stores only user-chosen names and normalized positions in galaxy-bookmarks.json.
 */
(function(){
"use strict";
window.ShiguangGalaxyMenu=function(player,touch,log){
  var key="shiguang.navigation.v46", groups=[], gidx=0, mode="galaxy", active=false, shown=false;
  var auto=true, lastTap=null, ignoreUntil=0, calibration=null;
  var selected=0, resetAt=0, deleteAt=0, watcher=null, boundCanvas=null, drawerTimer=null;
  var coords=[[.164,.47],[.233,.408],[.376,.376],[.517,.426],
              [.665,.363],[.784,.538],[.688,.681],[.577,.674],[.465,.683]];
  function isNum(v){return typeof v==="number"&&isFinite(v)&&v>=0&&v<=1;}
  function clean(item,galaxy){
    if(!item||typeof item!=="object")return null;
    var z={name:String(item.name||"未命名").slice(0,40),x:isNum(item.x)?item.x:null,
      y:isNum(item.y)?item.y:null};
    if(galaxy)z.planets=Array.isArray(item.planets)?item.planets.slice(0,60).map(function(x){
      return clean(x,false);
    }).filter(Boolean):[];
    return z;
  }
  function fromStored(raw){
    try{
      var obj=JSON.parse(raw);
      if(!obj||!Array.isArray(obj.groups)||obj.groups.length>60)return false;
      groups=obj.groups.map(function(x){return clean(x,true);}).filter(Boolean);
      gidx=Math.max(0,Math.min(groups.length-1,Math.floor(Number(obj.gidx)||0)));
      auto=obj.auto!==false;selected=0;
      return true;
    }catch(e){return false;}
  }
  try{fromStored(localStorage.getItem(key)||"");}catch(e){}
  function save(){
    var raw=JSON.stringify({schema:2,groups:groups,gidx:gidx,auto:auto});
    try{localStorage.setItem(key,raw);}catch(e){}
    try{window.webkit.messageHandlers.galaxyBookmarks.postMessage({action:"save",data:raw});}catch(e){}
  }
  function E(tag,parent,text){
    var el=document.createElement(tag);if(text!==undefined)el.textContent=text;
    if(parent)parent.appendChild(el);return el;
  }
  function B(parent,label,cb){
    var e=E("button",parent,label);e.type="button";
    e.addEventListener("click",function(ev){ev.preventDefault();ev.stopPropagation();cb();});
    return e;
  }
  var css=E("style",document.head);
  css.textContent=[
    "#sg47-drawer{position:fixed;z-index:2147482970;top:82px;right:16px;",
    "width:min(312px,calc(100vw - 32px));max-height:calc(100vh - 165px);display:none;",
    "overflow:auto;-webkit-overflow-scrolling:touch;color:#f2f9ff;background:rgba(9,28,58,.95);",
    "font:13px -apple-system,sans-serif;border:1px solid #6fb5e2;",
    "border-radius:16px;box-shadow:0 5px 21px #0009}",
    "#sg47-drawer .sg47-row{display:flex;align-items:center;gap:6px;flex-wrap:wrap}",
    "#sg47-drawer .sg47-head{padding:10px 12px;background:#174974}",
    "#sg47-drawer .sg47-body{padding:10px 12px}",
    "#sg47-drawer .sg47-muted{color:#b5d5eb;font-size:12px;line-height:1.45}",
    "#sg47-drawer button{border:0;border-radius:9px;font:600 12px -apple-system,sans-serif;",
    "padding:8px 10px;background:#d7edff;color:#153d64;touch-action:manipulation}",
    "#sg47-drawer button.sg47-on{background:#82e2e1;color:#123c52}",
    "#sg47-drawer button.sg47-entry{flex:1;min-width:0;text-align:left;padding:12px 10px;",
    "font-size:13px;background:#163d68;color:#f5fbff;border:1px solid #426e95}",
    "#sg47-drawer button.sg47-edit{background:#cde0ef}",
    "#sg47-drawer input{width:100%;box-sizing:border-box;border:0;border-radius:8px;",
    "padding:9px 11px;font:14px -apple-system,sans-serif;background:#fff;color:#173a60}",
    "#sg47-drawer .sg47-scroll{max-height:min(39vh,320px);overflow:auto;",
    "-webkit-overflow-scrolling:touch;display:flex;flex-direction:column;gap:6px;margin:8px 0}",
    "#sg47-drawer .sg47-note{font-size:11px;color:#b2d3e8;margin:6px 0}",
    "#sg47-calibrate{position:fixed;inset:0;display:none;touch-action:none;",
    "z-index:2147482981;background:rgba(0,15,40,.11)}",
    "#sg47-guide{position:fixed;z-index:2147482982;top:90px;left:50%;",
    "transform:translateX(-50%);display:none;padding:10px 14px;background:#124d78;",
    "color:#fff;border-radius:12px;font:13px -apple-system,sans-serif;pointer-events:none}",
    "#sg47-zoom{position:fixed;z-index:2147482970;display:none;gap:6px;",
    "left:50%;bottom:70px;transform:translateX(-50%);padding:8px;",
    "background:rgba(13,43,81,.91);border-radius:12px}",
    "#sg47-zoom button{border:0;border-radius:8px;padding:8px 10px;",
    "background:#dcefff;color:#163c63;font-weight:600}"
  ].join("");
  var panel=E("div",document.body);panel.id="sg47-drawer";
  var head=E("div",panel);head.className="sg47-head sg47-row";
  var title=E("strong",head,"星图收藏");
  var closeBtn=B(head,"收起",hide);
  var body=E("div",panel);body.className="sg47-body";
  var tabs=E("div",body);tabs.className="sg47-row";
  var gtab=B(tabs,"星系",function(){mode="galaxy";selected=gidx;render();});
  var ptab=B(tabs,"星球",function(){mode="planet";selected=0;render();});
  var nativeBtn=B(tabs,"看原地图",function(){hide();showTip("可直接点击原地图，系统会记录最近一次点击位置");});
  var search=E("input",body);search.placeholder="搜索已收藏的星系或星球";
  search.addEventListener("input",render);
  var hint=E("div",body);hint.className="sg47-muted";
  var items=E("div",body);items.className="sg47-scroll";
  var quick=E("div",body);quick.className="sg47-row";
  var saveGalaxy=B(quick,"⭐保存刚才点击为星系",function(){addFromTap("galaxy");});
  var savePlanet=B(quick,"⭐保存为星球",function(){addFromTap("planet");});
  var editArea=E("div",body);
  E("p",editArea,"收藏管理（仅在需要时使用）").className="sg47-note";
  var editName=E("input",editArea);editName.placeholder="更改当前收藏名称";
  var editBtns=E("div",editArea);editBtns.className="sg47-row";editBtns.style.marginTop="6px";
  B(editBtns,"重命名",function(){
    var item=selectedItem(),v=editName.value.trim().slice(0,40);
    if(!item||!v){note("请选中一项并填写名称");return;}
    item.name=v;save();render();note("已保存新名称");
  });
  B(editBtns,"校准位置",function(){startCalibration();});
  B(editBtns,"删除",function(){
    if(Date.now()-deleteAt>5000){deleteAt=Date.now();note("再次点删除，确认移除当前收藏");return;}
    deleteAt=0;removeSelected();
  });
  var footer=E("div",body);footer.className="sg47-muted";footer.style.marginTop="8px";
  var autoButton=B(body,"自动显示星球收藏：开",function(){
    auto=!auto;autoButton.textContent="自动显示星球收藏："+(auto?"开":"关");save();
  });
  autoButton.style.marginTop="9px";
  var layer=E("div",document.body);layer.id="sg47-calibrate";
  var guide=E("div",document.body);guide.id="sg47-guide";
  var cancelCal=B(document.body,"取消校准",function(){
    calibration=null;layer.style.display="none";guide.style.display="none";
    cancelCal.style.display="none";show();note("已取消校准");
  });
  cancelCal.style.cssText="position:fixed;top:126px;right:30px;display:none;"+
    "z-index:2147482983;padding:12px 16px;background:#e2f5ff;"+
    "color:#133a63;border:0;border-radius:10px;font-weight:bold";
  var zoomBar=E("div",document.body);zoomBar.id="sg47-zoom";
  var zoom=1,panX=0,panY=0;
  function btnZoom(t,fn){return B(zoomBar,t,fn);}
  btnZoom("－",function(){zoom=Math.max(1,+(zoom-.2).toFixed(2));applyZoom();});
  btnZoom("＋",function(){zoom=Math.min(2.2,+(zoom+.2).toFixed(2));applyZoom();});
  btnZoom("←",function(){panX+=55;applyZoom();});
  btnZoom("→",function(){panX-=55;applyZoom();});
  btnZoom("↑",function(){panY+=45;applyZoom();});
  btnZoom("↓",function(){panY-=45;applyZoom();});
  btnZoom("归位",function(){zoom=1.5;panX=panY=0;applyZoom();});
  btnZoom("退出",function(){setZoom(false);});
  var flashTimer=null;
  function showTip(s){
    log("地图收藏："+s);
    guide.textContent=s;guide.style.display="block";
    if(flashTimer)clearTimeout(flashTimer);
    flashTimer=setTimeout(function(){if(!calibration)guide.style.display="none";},2200);
  }
  function note(s){footer.textContent=s;log("地图收藏："+s);}
  function selectedGroup(){return groups[gidx]||null;}
  function selectedItem(){
    if(mode==="galaxy")return groups[selected]||null;
    var g=selectedGroup();return g&&g.planets[selected]||null;
  }
  function pointOK(p){return p&&isNum(p.x)&&isNum(p.y);}
  function setTabState(){
    gtab.className=mode==="galaxy"?"sg47-on":"";
    ptab.className=mode==="planet"?"sg47-on":"";
    autoButton.textContent="自动显示星球收藏："+(auto?"开":"关");
  }
  function render(){
    setTabState();
    var g=selectedGroup();
    title.textContent=mode==="galaxy"?"星系收藏":"星球收藏";
    hint.textContent=mode==="galaxy"?
      "点收藏名称即可尝试进入星系；不需要每次校准。":
      ("当前星系："+(g?g.name:"尚未收藏星系")+" · 点收藏名称即可尝试进入");
    items.replaceChildren();
    var list=mode==="galaxy"?groups:(g?g.planets:[]);
    var filter=search.value.trim().toLowerCase(),visible=0;
    list.forEach(function(item,i){
      if(filter&&item.name.toLowerCase().indexOf(filter)===-1)return;
      visible++;
      var r=E("div",items);r.className="sg47-row";
      var label=item.name+(pointOK(item)?"  ✓":"  未定位置");
      var b=B(r,label,function(){choose(i);});b.className="sg47-entry";
      var edit=B(r,"编辑",function(){selected=i;if(mode==="galaxy"){gidx=i;save();}editName.value=item.name;note("已选中："+item.name);});
      edit.className="sg47-edit";
    });
    if(!visible){
      var p=E("p",items,filter?"找不到收藏，请换关键词。":
        (mode==="galaxy"?"暂无收藏。先在原地图点击星系，再回来保存刚才的点击。":
          "这个星系尚无星球收藏。进入星系并点一次星球，再保存位置。"));
      p.className="sg47-muted";
    }
    savePlanet.style.display=g?"inline-block":"none";
    editName.value=selectedItem()?selectedItem().name:"";
    footer.textContent=(lastTap?"已记录游戏画面上的最近一次点击，可一键收藏。":
      "第一次收藏：先点「看原地图」，点目标，再从 ··· 打开地图选择保存。");
  }
  function coordinates(ev){
    var r=touch.getBounds();if(!r)return null;
    var nx=(ev.clientX-r.left)/r.width,ny=(ev.clientY-r.top)/r.height;
    if(!isNum(nx)||!isNum(ny))return null;
    return {x:nx,y:ny,at:Date.now(),trusted:!!ev.isTrusted};
  }
  function goClick(item){
    if(!pointOK(item)){note("这个收藏还没坐标，请先在地图上点击目标并保存");return false;}
    var r=touch.getBounds();
    if(!r){note("游戏画面尚未准备完成");return false;}
    ignoreUntil=Date.now()+650;
    touch.clickCanvas(r.left+item.x*r.width,r.top+item.y*r.height);
    log("地图快捷点击："+item.name+"；Canvas 比例坐标 "+item.x.toFixed(3)+","+item.y.toFixed(3));
    return true;
  }
  function choose(i){
    var list=mode==="galaxy"?groups:(selectedGroup()||{planets:[]}).planets;
    if(!list[i])return;
    if(mode==="galaxy"){
      gidx=i;selected=i;save();
      var g=groups[i];
      if(!goClick(g))return;
      hide();
      if(auto){
        clearTimeout(drawerTimer);
        drawerTimer=setTimeout(function(){
          if(!active)return;
          mode="planet";selected=0;show();
          note("已尝试进入「"+g.name+"」。确认游戏已显示星系内部后，选择星球。");
        },850);
      }
    }else{
      selected=i;
      if(goClick(list[i])){hide();showTip("已向游戏点击「"+list[i].name+"」");}
    }
  }
  function addFromTap(which){
    if(!lastTap){note("还没有记录到点击：先点原地图的目标，再回来保存");return;}
    if(Date.now()-lastTap.at>180000){
      note("上次点击已超过3分钟，为避免误收藏请重新点一次目标");return;
    }
    // The point comes from the user's actual or working virtual mouse click.
    var place={x:lastTap.x,y:lastTap.y};
    if(which==="galaxy"){
      if(groups.length>=60){note("最多保存60个星系");return;}
      groups.push({name:"我的星系 "+(groups.length+1),x:place.x,y:place.y,planets:[]});
      gidx=groups.length-1;mode="galaxy";selected=gidx;
    }else{
      var g=selectedGroup();
      if(!g){note("请先保存一个星系，或在星系列表选中归属");return;}
      if(g.planets.length>=60){note("每个星系最多保存60个星球");return;}
      g.planets.push({name:"我的星球 "+(g.planets.length+1),x:place.x,y:place.y});
      mode="planet";selected=g.planets.length-1;
    }
    search.value="";save();render();
    editName.focus();editName.select();
    note("位置已保存，改个容易记住的名字即可。");
  }
  function removeSelected(){
    if(mode==="galaxy"){
      if(!groups.length)return;
      groups.splice(selected,1);
      gidx=Math.max(0,Math.min(gidx,groups.length-1));
      selected=gidx;
    }else{
      var g=selectedGroup();if(!g||!g.planets[selected])return;
      g.planets.splice(selected,1);selected=Math.max(0,selected-1);
    }
    save();render();note("已删除所选收藏，其他收藏不受影响");
  }
  function startCalibration(){
    if(!selectedItem()){note("请先选择收藏项");return;}
    calibration={mode:mode,idx:selected,group:gidx};
    panel.style.display="none";layer.style.display="block";
    cancelCal.style.display="block";
    guide.textContent="在原地图上点需要校准的星系/星球中心";guide.style.display="block";
  }
  layer.addEventListener("pointerup",function(ev){
    if(!calibration)return;ev.preventDefault();ev.stopPropagation();
    var point=coordinates(ev);
    if(!point){note("请点击游戏画面内");return;}
    var tar=calibration.mode==="galaxy"?groups[calibration.idx]:
      ((groups[calibration.group]||{planets:[]}).planets[calibration.idx]);
    if(tar){tar.x=point.x;tar.y=point.y;save();}
    calibration=null;layer.style.display="none";guide.style.display="none";
    cancelCal.style.display="none";show();
    note("点击位置已更新。");
  },true);
  function nearestGalaxy(p){
    var r=touch.getBounds();if(!r)return -1;
    var dist=55,index=-1;
    groups.forEach(function(g,i){
      if(!pointOK(g))return;
      var d=Math.hypot((g.x-p.x)*r.width,(g.y-p.y)*r.height);
      if(d<dist){dist=d;index=i;}
    });
    return index;
  }
  function trackTouch(ev){
    if(Date.now()<ignoreUntil||calibration)return;
    var p=coordinates(ev);if(!p)return;
    lastTap=p;
    if(!active||!auto||mode==="planet")return;
    var i=nearestGalaxy(p);if(i<0)return;
    gidx=i;save();
    clearTimeout(drawerTimer);
    drawerTimer=setTimeout(function(){
      if(!active||calibration)return;
      mode="planet";selected=0;show();
      note("检测到点击了收藏的星系「"+groups[i].name+"」，请核对画面，再选择星球。");
    },900);
  }
  function bind(){
    var c=player&&player.shadowRoot&&player.shadowRoot.querySelector("canvas");
    if(!c||c===boundCanvas)return;
    boundCanvas=c;c.addEventListener("pointerup",trackTouch,true);
    log("地图收藏：已监听 Ruffle Canvas 的真实或虚拟鼠标点击位置");
  }
  watcher=setInterval(bind,1200);
  function show(){
    bind();shown=true;panel.style.display="block";render();
  }
  function hide(){shown=false;panel.style.display="none";}
  function open(){
    setZoom(false);active=true;mode="galaxy";selected=gidx;
    search.value="";show();note("直接点收藏名称即可选择；也能返回原地图。");
  }
  function close(){
    active=false;hide();calibration=null;layer.style.display="none";
    guide.style.display="none";cancelCal.style.display="none";clearTimeout(drawerTimer);
  }
  function applyZoom(){
    player.style.transform=zoom>1?"translate("+panX+"px,"+panY+"px) scale("+zoom+")":"";
    player.style.transformOrigin="center center";
  }
  function setZoom(yes){
    if(yes){
      close();zoom=1.5;panX=panY=0;applyZoom();zoomBar.style.display="flex";
      showTip("触控放大已开启：直接手指点屏幕，使用真实触摸");
    }else{
      zoom=1;panX=panY=0;applyZoom();zoomBar.style.display="none";
    }
  }
  window.ShiguangNativeBookmarks={receive:function(raw){
    if(fromStored(raw)){
      render();log("地图收藏：已从 iPad 本机文件恢复星系/星球收藏");
    }else log("地图收藏：本机文件格式不兼容，保留当前收藏");
  }};
  try{window.webkit.messageHandlers.galaxyBookmarks.postMessage({action:"load"});}catch(e){}
  render();
  log("地图收藏 v4.7 已就绪：轻量收藏抽屉、真实点击位置捕获、星系内星球面板");
  return {open:open,close:close,setZoom:setZoom,isOpen:function(){return active;}};
};
})();