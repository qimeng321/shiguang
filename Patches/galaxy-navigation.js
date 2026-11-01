(function(){
"use strict";
window.ShiguangGalaxyMenu=function(player,touch,log){
 var key="shiguang.navigation.v46",groups=[],gidx=0,pidx=0,level="galaxy",active=false,auto=true,cal=null,zoom=1,dx=0,dy=0,canvas=null;
 var base=[[.164,.470],[.233,.408],[.376,.376],[.517,.426],[.665,.363],[.784,.538],[.688,.681],[.577,.674],[.465,.683]];
 function defaults(){return base.map(function(a,i){return {name:"参考星系 "+(i+1),x:a[0],y:a[1],planets:[]};});}
 function valid(n){return typeof n==="number"&&isFinite(n)&&n>=0&&n<=1;}
 function clean(x,gal){if(!x||typeof x!=="object")return null;var v={name:String(x.name||"未命名").slice(0,32),x:valid(x.x)?x.x:null,y:valid(x.y)?x.y:null};if(gal)v.planets=Array.isArray(x.planets)?x.planets.slice(0,60).map(function(p){return clean(p,false);}).filter(Boolean):[];return v;}
 groups=defaults();
 try{var d=JSON.parse(localStorage.getItem(key)||"null");if(d&&Array.isArray(d.groups)&&d.groups.length&&d.groups.length<=60){groups=d.groups.map(function(p){return clean(p,true);}).filter(Boolean);if(!groups.length)groups=defaults();gidx=Math.max(0,Math.min(groups.length-1,Number(d.gidx)||0));auto=d.auto!==false;}}catch(_){}
 function save(){
  var data=JSON.stringify({groups:groups,gidx:gidx,auto:auto});
  try{localStorage.setItem(key,data);}catch(e){log("地图收藏：本地缓存写入失败 "+String(e).slice(0,90));}
  try{window.webkit.messageHandlers.galaxyBookmarks.postMessage({action:"save",data:data});}catch(_){}
 }
 function E(tag,parent,txt){var n=document.createElement(tag);if(txt!==undefined)n.textContent=txt;parent.appendChild(n);return n;}
 function B(parent,txt,fn){var b=E("button",parent,txt);b.type="button";b.onclick=function(ev){ev.preventDefault();ev.stopPropagation();fn();};return b;}
 var style=E("style",document.head);
 style.textContent=[
 "#sg-nav{position:fixed;top:85px;right:15px;width:min(335px,calc(100vw - 30px));max-height:calc(100vh - 165px);",
 "overflow:auto;display:none;background:rgba(10,31,64,.96);color:#fff;border-radius:16px;border:1px solid #7cd5ff;",
 "z-index:2147482960;box-shadow:0 5px 18px #0008;font:13px -apple-system,sans-serif}",
 "#sg-nav .section{padding:10px 12px;border-bottom:1px solid #ffffff33}",
 "#sg-nav .group{display:flex;gap:5px;flex-wrap:wrap;margin-top:7px}",
 "#sg-nav button,#sg-zoom button{background:#def3ff;color:#14416b;border:0;border-radius:8px;",
 "padding:8px;font:600 12px -apple-system,sans-serif;touch-action:manipulation}",
 "#sg-nav select,#sg-nav input{width:100%;box-sizing:border-box;background:#fff;color:#123d5e;border:0;",
 "font:14px -apple-system,sans-serif;border-radius:7px;padding:9px;margin-top:6px}",
 "#sg-nav p{margin:6px 0;font:12px -apple-system,sans-serif;line-height:1.4}",
 "#sg-nav .muted{color:#aee0f8}",
 "#sg-cal{position:fixed;inset:0;z-index:2147482970;display:none;background:rgba(0,0,0,.12);touch-action:none}",
 "#sg-cal-label{position:fixed;left:50%;top:94px;transform:translateX(-50%);display:none;pointer-events:none;",
 "z-index:2147482971;background:#07355c;color:#fff;padding:10px;border-radius:10px;font:13px -apple-system,sans-serif}",
 "#sg-zoom{position:fixed;bottom:70px;left:50%;transform:translateX(-50%);display:none;gap:4px;",
 "background:rgba(9,36,77,.92);z-index:2147482961;padding:6px;border-radius:12px}"
 ].join("");
 var panel=E("div",document.body);panel.id="sg-nav";
 var head=E("div",panel);head.className="section";
 E("strong",head,"星系 / 星球导航");
 var a=E("div",head);a.className="group";
 B(a,"关闭",close);
 B(a,"原地图点选",function(){panel.style.display="none";notice("已隐藏列表，直接用手指点原地图");});
 var autoBtn=B(a,"自动弹出：开",function(){auto=!auto;autoBtn.textContent="自动弹出："+(auto?"开":"关");save();});
 autoBtn.textContent="自动弹出："+(auto?"开":"关");
 E("p",head,"保留原地图。快捷列表可记住星系与星球名称、触摸位置；点击进入仍依赖游戏自身响应。").className="muted";
 var sg=E("div",panel);sg.className="section";
 E("strong",sg,"第一步：选择星系");
 var gsel=E("select",sg);
 gsel.onchange=function(){gidx=Number(this.value)||0;pidx=0;level="galaxy";save();render();};
 var ga=E("div",sg);ga.className="group";
 B(ga,"进入星系",function(){
  var x=groups[gidx];if(!click(x))return;
  level="planet";pidx=0;render();
  notice("已发出星系点击；请核对游戏是否已进入，再选择星球");
 });
 B(ga,"标记星系位置",function(){startCal("galaxy");});
 B(ga,"新增星系",function(){
  if(groups.length>=60)return notice("星系数量已达60");
  groups.push({name:"新星系 "+(groups.length+1),x:null,y:null,planets:[]});
  gidx=groups.length-1;pidx=0;level="galaxy";save();render();
 });
 var sn=E("div",panel);sn.className="section";
 E("strong",sn,"修改当前名称");
 var name=E("input",sn);name.placeholder="输入实际星系或星球名称";
 var nb=E("div",sn);nb.className="group";
 B(nb,"保存名称",function(){
  var v=name.value.trim().slice(0,32);if(!v)return notice("请先填写名称");
  if(level==="galaxy")groups[gidx].name=v;
  else{var p=groups[gidx].planets[pidx];if(p)p.name=v;}
  save();render();notice("名称和坐标已保存");
 });
 var sp=E("div",panel);sp.className="section";
 E("strong",sp,"第二步：选择星球");
 var psel=E("select",sp);
 psel.onchange=function(){pidx=Number(this.value)||0;level="planet";render();};
 var pa=E("div",sp);pa.className="group";
 B(pa,"进入星球",function(){var list=groups[gidx].planets;click(list[pidx]);});
 B(pa,"标记星球位置",function(){if(!groups[gidx].planets.length)return notice("先新增星球");startCal("planet");});
 B(pa,"新增星球",function(){
  var list=groups[gidx].planets;if(list.length>=60)return notice("星球数量已达60");
  list.push({name:"新星球 "+(list.length+1),x:null,y:null});
  pidx=list.length-1;level="planet";save();render();
 });
 B(pa,"返回星系列表",function(){level="galaxy";render();});
 var foot=E("div",panel);foot.className="section";
 var status=E("p",foot,"地图辅助已就绪");status.className="muted";
 var fb=E("div",foot);fb.className="group";
 B(fb,"删除当前收藏",function(){
  if(level==="planet"&&groups[gidx].planets.length){groups[gidx].planets.splice(pidx,1);pidx=0;}
  else if(level==="galaxy"&&groups.length>1){groups.splice(gidx,1);gidx=0;pidx=0;}
  else return notice("至少保留一个星系");
  level="galaxy";save();render();
 });
 B(fb,"恢复九个参考位置",function(){
  // Requires second tap on same button within six seconds.
  if(Date.now()-resetTap>6000){resetTap=Date.now();notice("会清空所有收藏。确定请六秒内再次点击");return;}
  resetTap=0;groups=defaults();gidx=pidx=0;level="galaxy";save();render();
 });
 var resetTap=0;
 var calLayer=E("div",document.body);calLayer.id="sg-cal";
 var calTip=E("div",document.body);calTip.id="sg-cal-label";
 var zoomBar=E("div",document.body);zoomBar.id="sg-zoom";
 B(zoomBar,"−",function(){zoom=Math.max(1.1,zoom-.2);applyZoom();});
 B(zoomBar,"+",function(){zoom=Math.min(2.2,zoom+.2);applyZoom();});
 B(zoomBar,"←",function(){dx+=65;applyZoom();});
 B(zoomBar,"→",function(){dx-=65;applyZoom();});
 B(zoomBar,"↑",function(){dy+=50;applyZoom();});
 B(zoomBar,"↓",function(){dy-=50;applyZoom();});
 B(zoomBar,"归中",function(){zoom=1.5;dx=dy=0;applyZoom();});
 B(zoomBar,"退出",function(){setZoom(false);});
 function notice(msg){status.textContent=msg;log("地图辅助："+msg);}
 function pointOK(p){return p&&valid(p.x)&&valid(p.y);}
 function click(p){
  if(!pointOK(p))return notice("还没有保存这个位置，请先标记"),false;
  var r=touch.getBounds();if(!r)return notice("游戏画布还没准备好"),false;
  touch.clickCanvas(r.left+p.x*r.width,r.top+p.y*r.height);
  notice("已向游戏发送坐标点击；是否进入以游戏画面为准");
  return true;
 }
 function render(){
  if(gidx>=groups.length)gidx=0;
  gsel.replaceChildren();
  groups.forEach(function(x,i){var o=E("option",gsel,x.name+(pointOK(x)?"":"（未标记）"));o.value=String(i);});
  gsel.value=String(gidx);
  var list=groups[gidx].planets;psel.replaceChildren();
  if(!list.length){var o=E("option",psel,"无已保存星球");o.value="0";}
  else list.forEach(function(x,i){var o=E("option",psel,x.name+(pointOK(x)?"":"（未标记）"));o.value=String(i);});
  if(pidx>=list.length)pidx=0;
  psel.value=String(pidx);
  sp.style.display=level==="planet"?"block":"none";
  name.value=level==="galaxy"?groups[gidx].name:((list[pidx]||{}).name||"");
 }
 function startCal(kind){
  cal=kind;panel.style.display="none";calLayer.style.display="block";calTip.style.display="block";
  calTip.textContent="点击游戏画面里的"+(kind==="galaxy"?"星系":"星球")+"中心，自动保存坐标";
 }
 calLayer.addEventListener("pointerup",function(ev){
  if(!cal)return;ev.preventDefault();ev.stopPropagation();
  var r=touch.getBounds();if(!r)return notice("画布尚未就绪");
  var x=(ev.clientX-r.left)/r.width,y=(ev.clientY-r.top)/r.height;
  if(!valid(x)||!valid(y))return notice("请点游戏画面内的位置");
  if(cal==="galaxy"){groups[gidx].x=x;groups[gidx].y=y;level="galaxy";}
  else{var q=groups[gidx].planets[pidx];if(q){q.x=x;q.y=y;level="planet";}}
  cal=null;calLayer.style.display="none";calTip.style.display="none";panel.style.display="block";
  save();render();notice("坐标已保存，支持横竖屏按比例还原");
 },true);
 var tracked=null,realClicks=0;
 function bindCanvas(){
  var c=player.shadowRoot&&player.shadowRoot.querySelector("canvas");
  if(!c||c===tracked)return;tracked=c;
  c.addEventListener("pointerup",function(ev){
   if(!active||!auto||level==="planet"||cal||!ev.isTrusted)return;
   var r=touch.getBounds();if(!r)return;
   var best=-1,dmin=1e6;
   groups.forEach(function(g,i){if(!pointOK(g))return;
    var dd=Math.hypot(g.x*r.width-(ev.clientX-r.left),g.y*r.height-(ev.clientY-r.top));
    if(dd<dmin){dmin=dd;best=i;}
   });
   if(best<0||dmin>Math.min(r.width*.06,60))return;
   gidx=best;pidx=0;save();realClicks++;
   setTimeout(function(){if(!active||cal)return;
    level="planet";panel.style.display="block";render();
    notice("检测到游戏中选中了已保存的星系坐标；请选择星球");
   },900);
  },true);
 }
 setInterval(bindCanvas,1400);
 function open(){setZoom(false);active=true;level="galaxy";bindCanvas();render();panel.style.display="block";notice("可从列表点击，也可隐藏列表直接点击原地图");}
 function close(){active=false;panel.style.display="none";cal=null;calLayer.style.display="none";calTip.style.display="none";}
 function applyZoom(){
  player.style.transform=zoom>1?"translate("+dx+"px,"+dy+"px) scale("+zoom+")":"";
  player.style.transformOrigin="center center";
  log("触控放大：倍率 "+zoom+" 平移 "+dx+","+dy);
 }
 function setZoom(on){
  if(on){close();zoom=1.5;dx=dy=0;applyZoom();zoomBar.style.display="flex";notice("放大模式：直接手指触碰画面，是真实触控事件");}
  else{zoom=1;dx=dy=0;applyZoom();zoomBar.style.display="none";}
 }
 window.ShiguangNativeBookmarks={receive:function(raw){
   try{
     var data=JSON.parse(raw);
     if(data&&Array.isArray(data.groups)&&data.groups.length&&data.groups.length<=60){
       var cleaned=data.groups.map(function(g){return clean(g,true);}).filter(Boolean);
       if(cleaned.length){
         groups=cleaned;gidx=Math.max(0,Math.min(groups.length-1,Number(data.gidx)||0));
         pidx=0;auto=data.auto!==false;autoBtn.textContent="自动弹出："+(auto?"开":"关");
         render();log("地图收藏：已从 iPad 文件夹恢复星系和星球位置");
       }
     }
   }catch(e){log("地图收藏：本机备份内容无效，继续使用当前本地缓存");}
 }};
 render();
 try{window.webkit.messageHandlers.galaxyBookmarks.postMessage({action:"load"});}catch(_){}
 log("星系收藏 v4.6 已初始化；星系→星球两级选择，书签备份到 iPad 文件夹");
 return {open:open,close:close,setZoom:setZoom,isOpen:function(){return active;}};
};
})();