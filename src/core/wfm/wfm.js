import{el,on}from"../dom.js";

const pp=p=>{
  if(typeof p!=="string")throw new TypeError("Path must be a string");
  const a=p.split("/").filter(Boolean);
  if(a.some(x=>x==="."||x===".."||x.includes("\0")||x.includes("\\")))
    throw new TypeError("Invalid path");
  return a;
};

const dp=p=>{
  const a=pp(p);
  return`/${a.join("/")}${a.length?"/":""}`;
};

function authenticationError(open,message,url=location.href){
  message=message||"Your session has expired. Sign in again to continue.";
  const b=el("button",{type:"button",textContent:"Sign in again"}),c=el("div");
  b.dataset.action="sign-in";
  b.onclick=()=>location.assign(url);
  c.append(el("p",message),b);
  open({title:"Sign-in required",content:c});
  return Object.assign(new Error(message),{name:"UnauthorizedError"});
}

async function responseError(r,open,url){
  let m=`${r.status} ${r.statusText}`;
  try{
    const t=await r.text();
    if(t){try{const x=JSON.parse(t);m=x.emsg||x.err||m}catch{m=t}}
  }catch{}
  return r.status===401?authenticationError(open,m,url):new Error(m);
}

export function mount(h,o={}){
  if(!(h instanceof Element))throw new TypeError("Host element required");

  const w=new URL(location.href);
  const b=new URL(o.url||"/fs/",location.href);
  if(b.origin!==location.origin)throw new TypeError("WFS must be same-origin");
  if(!b.pathname.endsWith("/"))b.pathname+="/";
  b.search=b.hash="";

  const s={
    d:dp(o.path||w.searchParams.get("wfm")||"/"),e:[],v:[],s:new Set,a:"",k:"n",z:0,
    c:new Map,x:new Set(["/"]),m:new Map,p:[],r:new Set,q:[],n:0,y:0,g:0,u:0,j:0,h:0,f:0
  };

  h.replaceChildren();
  const r=el("div",{className:"wfm"});
  r.innerHTML='<div class="wfm-toolbar" role="toolbar"><button type="button" data-action="refresh">Refresh</button><span data-commands></span></div><nav class="wfm-path" aria-label="Current directory"></nav><div class="wfm-body"><nav class="wfm-tree" aria-label="Folders"></nav><div><table class="wfm-list"><thead><tr><th><button type="button" data-sort="n">Name</button></th><th><button type="button" data-sort="s">Size</button></th><th><button type="button" data-sort="t">Modified</button></th></tr></thead><tbody></tbody></table></div></div><div class="wfm-status" role="status"></div><input data-upload type="file" multiple hidden><menu data-menu role="menu" hidden></menu><dialog class="wfm-dialog"><header><strong data-dialog-title></strong><button type="button" data-action="close" aria-label="Close">x</button></header><div data-dialog-body></div></dialog>';
  h.append(r);

  const q=x=>r.querySelector(x),
    tc=q("[data-commands]"),pb=q(".wfm-path"),tr=q(".wfm-tree"),
    tb=q("tbody"),st=q(".wfm-status"),fi=q("[data-upload]"),mn=q("[data-menu]"),d=q("dialog"),
    dt=d.querySelector("[data-dialog-title]"),
    db=d.querySelector("[data-dialog-body]");

  const ms=(m,e=0)=>{
    st.textContent=m;
    st.dataset.error=e?"true":"false";
  };

  const u=(p,o)=>{
    const d=p.endsWith("/"),a=pp(p).map(encodeURIComponent),
      v=new URL(a.join("/")+(d&&a.length?"/":""),b);
    if(o)for(const[k,x]of Object.entries(o))
      if(x!==undefined&&x!==false)v.searchParams.set(k,x===true?"1":x);
    return v;
  };

  const ep=(p,x)=>p+x.n+(x.s===-1?"/":"");

  async function rq(v,o){
    const c=new AbortController;
    s.r.add(c);
    try{
      const r=await fetch(v,{...o,signal:c.signal});
      if(!r.ok)throw await responseError(r,ui,b.href);
      return r;
    }finally{s.r.delete(c)}
  }

  async function ls(p){
    p=dp(p);
    const r=await rq(u(p,{cmd:"lj"}));
    s.h=r.headers.has("BaWfsSes");
    const a=await r.json();
    if(!Array.isArray(a))throw new Error("Bad directory response");
    return a.map(x=>{
      if(!x||typeof x.n!=="string"||typeof x.s!=="number"||
        typeof x.t!=="number"||!x.n||x.n==="."||x.n===".."||
        x.n.includes("/")||x.n.includes("\\")||x.n.includes("\0"))
        throw new Error("Bad directory entry");
      return{...x,path:ep(p,x)};
    });
  }

  async function ll(p,v){
    const f=v.filter(x=>x.s!==-1);
    if(!f.length)return v;
    const z=new URLSearchParams({cmd:"getlocks"});
    for(const x of f)z.append("n",x.n);
    const r=await rq(u(p),{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:z}),
      j=await r.json(),m=new Map((Array.isArray(j.files)?j.files:[]).map(x=>[x.n,x.l]));
    for(const x of f)x.l=m.get(x.n)||false;
    return v;
  }

  async function pa(p){
    let d="/";
    for(const n of pp(p)){
      if(!s.c.has(d)){
        try{s.c.set(d,await ls(d))}
        catch(e){if(e.name==="AbortError"||s.y)throw e}
      }
      d+=n+"/";
    }
  }

  function so(v){
    const k=s.k,z=s.z?-1:1;
    return[...v].sort((a,b)=>{
      if((a.s===-1)!==(b.s===-1))return a.s===-1?-1:1;
      const x=k==="n"?a.n.toLocaleLowerCase():a[k],
        y=k==="n"?b.n.toLocaleLowerCase():b[k];
      return(x<y?-1:x>y?1:0)*z;
    });
  }

  function rp(){
    pb.replaceChildren();
    let p="/";
    const add=(n,p)=>{
      const b=el("button",{textContent:n,type:"button"});
      b.dataset.path=p;
      pb.append(b);
    };
    add("Files","/");
    for(const n of s.d.split("/").filter(Boolean)){
      pb.append(el("span","/"));
      p+=n+"/";
      add(n,p);
    }
  }

  const cx=()=>({directory:s.d,listing:[...s.e],selection:a.selection()});

  function cr(p,k){
    p.replaceChildren();
    const c=cx();
    for(const x of s.m.values()){
      let v=!x.when;
      try{v=v||!!x.when(c)}catch(e){console.error("WFM command",x.id,e)}
      if(x[k]===false||(!v&&k==="menu"&&!x.showDisabled))continue;
      const b=el("button",{textContent:x.label||x.id,type:"button"});
      b.dataset.command=x.id;
      b.disabled=!v;
      if(k==="menu")b.setAttribute("role","menuitem");
      p.append(b);
    }
  }

  function rc(){cr(tc,"toolbar")}

  const hm=()=>mn.hidden=true;

  function cm(e){
    cr(mn,"menu");
    if(!mn.children.length)return;
    mn.hidden=false;
    const z=r.getBoundingClientRect();
    mn.style.left=Math.max(0,Math.min(e.clientX-z.left,z.width-mn.offsetWidth))+'px';
    mn.style.top=Math.max(0,Math.min(e.clientY-z.top,z.height-mn.offsetHeight))+'px';
  }

  function rl(){
    tb.replaceChildren();
    s.v=so(s.e);
    for(const x of s.v){
      const r=el("tr",{tabIndex:0});
      r.dataset.path=x.path;
      r.setAttribute("aria-selected",s.s.has(x.path)?"true":"false");
      const n=el("td"),f=el("span",{
        className:x.s===-1?"wfm-folder":"wfm-file",textContent:x.n
      });
      if(x.l){f.dataset.locked="true";f.title=`Locked by ${x.l}`}
      n.append(f);
      r.append(n,el("td",x.s===-1?"":String(x.s)),
        el("td",new Date(x.t*1000).toLocaleString()));
      tb.append(r);
    }
    r.querySelectorAll("[data-sort]").forEach(b=>
      b.setAttribute("aria-pressed",b.dataset.sort===s.k?"true":"false"));
    rc();
    ms(`${s.e.length} item${s.e.length===1?"":"s"}`);
  }

  function rs(){
    tb.querySelectorAll("tr[data-path]").forEach(r=>
      r.setAttribute("aria-selected",s.s.has(r.dataset.path)?"true":"false"));
    rc();
  }

  function rt(){
    const u=el("ul");
    const br=(p,n)=>{
      const i=el("li"),r=el("div"),v=s.c.get(p),
        f=v&&so(v.filter(x=>x.s===-1)),x=s.x.has(p),
        t=el("button",{
          className:"wfm-tree-toggle",textContent:x?"▾":"▸",type:"button"
        });
      t.dataset.toggle=p;
      t.setAttribute("aria-expanded",String(x));
      if(f&&!f.length)t.disabled=true;
      const b=el("button",{
        className:"wfm-tree-name",textContent:n,type:"button"
      });
      b.dataset.path=p;
      if(p===s.d)b.setAttribute("aria-current","page");
      if(p===s.g?.path)b.setAttribute("aria-selected","true");
      r.append(t,b);
      i.append(r);
      if(x&&f){
        const a=el("ul");
        for(const d of f)a.append(br(d.path,d.n));
        i.append(a);
      }
      return i;
    };
    u.append(br("/","Files"));
    tr.replaceChildren(u);
  }

  function ex(p){
    let d="/";
    s.x.add(d);
    for(const n of pp(p)){d+=n+"/";s.x.add(d)}
  }

  function se(t,e){
    const p=t.dataset.path;
    s.g=0;
    tr.querySelector('[aria-selected="true"]')?.removeAttribute("aria-selected");
    if(e.shiftKey&&s.a){
      const a=s.v.findIndex(x=>x.path===s.a),b=s.v.findIndex(x=>x.path===p);
      if(a>=0&&b>=0){
        if(!(e.ctrlKey||e.metaKey))s.s.clear();
        for(let i=Math.min(a,b);i<=Math.max(a,b);i++)s.s.add(s.v[i].path);
      }
    }else if(e.ctrlKey||e.metaKey){
      if(s.s.has(p))s.s.delete(p);else s.s.add(p);
      s.a=p;
    }else{s.s.clear();s.s.add(p);s.a=p}
    rs();
  }

  function ts(p){
    const v=pp(p);
    s.s.clear();s.a="";
    s.g={n:v.at(-1)||"Files",s:-1,t:0,path:dp(p)};
    rt();rc();
  }

  function ui(o={}){
    if(s.f)try{s.f()}catch(e){console.error("WFM dialog",e)}
    s.f=o.close||0;
    dt.textContent=o.title||"";
    db.replaceChildren();
    if(o.content instanceof Node)db.append(o.content);
    else if(o.content!==undefined)db.textContent=String(o.content);
    if(o.render)o.render(db);
    if(!d.open)d.showModal();
    return db;
  }

  function cl(){
    if(s.j){s.j=2;s.u?.abort?.()}
    const f=s.f;s.f=0;
    d.close();
    if(f)f();
  }

  const a={
    add(t,x){
      if(!x||typeof x.id!=="string")throw new TypeError("Plugin id required");
      if(t==="command"){
        if(typeof x.run!=="function")throw new TypeError("Command run required");
        s.m.set(x.id,x);rc();
        return()=>{s.m.delete(x.id);rc()};
      }
      if(t==="preview"){
        if(typeof x.match!=="function"||typeof x.render!=="function")
          throw new TypeError("Preview match/render required");
        s.p.push(x);
        return()=>{const i=s.p.indexOf(x);if(i>=0)s.p.splice(i,1)};
      }
      throw new TypeError("Unsupported plugin: "+t);
    },
    list:ls,
    async open(p){
      p=dp(p);
      const n=++s.n;
      r.setAttribute("aria-busy","true");
      ms("Loading…");
      try{
        const[v]=await Promise.all([ls(p).then(v=>ll(p,v)),pa(p)]);
        if(s.y||n!==s.n)return;
        s.d=p;s.e=v;s.c.set(p,v);ex(p);s.s.clear();s.a="";s.g=0;
        rp();rl();rt();
        if(o.history){const v=u(p);if(v.pathname!==location.pathname)history.pushState(0,"",v)}
      }catch(e){
        if(e.name==="UnauthorizedError"){ms(e.message,1);return}
        if(e.name!=="AbortError")ms(e.message,1);
        throw e;
      }finally{if(n===s.n)r.removeAttribute("aria-busy")}
    },
    refresh(){s.c.delete(s.d);return a.open(s.d)},
    url(x,o={}){
      const p=typeof x==="string"?x:x.path;
      if(typeof p!=="string")throw new TypeError("Resource path required");
      return u(p,o.download?{download:1}:undefined).href;
    },
    selection(){const v=s.e.filter(x=>s.s.has(x.path));return v.length?v:s.g?[s.g]:[]},
    directory(){return s.d},
    ui:{open:ui,close:cl}
  };

  const one=c=>c.selection.length===1,
    item=c=>one(c)&&c.selection[0].path!=="/",
    file=c=>one(c)&&c.selection[0].s!==-1,
    files=c=>c.selection.length&&c.selection.every(x=>x.s!==-1),
    name=n=>{
      n=n&&n.trim();
      if(!n||n==="."||n===".."||n.includes("/")||n.includes("\\")||n.includes("\0"))
        throw new Error("Invalid name");
      return n;
    },
    path=p=>{
      const d=p.endsWith("/"),v=pp(p);
      if(!v.length)throw new Error("Invalid target path");
      return`/${v.join("/")}${d?"/":""}`;
    },
    parent=p=>{const v=pp(p);v.pop();return`/${v.join("/")}${v.length?"/":""}`},
    sync=async(p=s.d)=>{s.c.clear();await a.open(p)};

  async function lop(c,v,time){
    const z=new URLSearchParams({cmd:c});
    if(time)z.set("time",time);
    for(const x of v)z.append("n",x.n);
    const r=await rq(u(s.d),{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:z}),
      j=await r.json();
    if(j.err)throw new Error(j.emsg||j.err);
    await sync();
  }

  function put(f,p,pg){
    return new Promise((ok,no)=>{
      const x=new XMLHttpRequest;
      s.u=x;
      x.upload.onprogress=e=>pg(e.loaded,e.lengthComputable?e.total:f.size);
      x.onload=()=>{
        let v,m=`${x.status} ${x.statusText}`;
        try{v=JSON.parse(x.responseText);m=v.emsg||v.err||m}catch{}
        if(x.status>=200&&x.status<300&&!v?.err)ok();
        else no(x.status===401?authenticationError(ui,m,b.href):new Error(m));
      };
      x.onerror=()=>no(new Error("Upload failed"));
      x.onabort=()=>no(new DOMException("Upload canceled","AbortError"));
      x.open("PUT",u(p+f.name).href);
      x.setRequestHeader("X-Requested-With","upload");
      x.send(f);
    });
  }

  async function upload(fs){
    const v=[...fs];
    if(!v.length)return;
    if(s.j){ms("Upload already in progress",1);return}
    s.j=1;rc();
    const p=s.d,n=el("strong"),c=el("span"),g=el("progress",{max:100,value:0}),
      e=el("div"),z=el("button",{type:"button",textContent:"Cancel"}),box=el("div");
    box.dataset.uploadBox="";e.dataset.uploadError="";z.dataset.action="cancel-upload";
    box.append(el("div","Uploading: ",n),g,el("div","Completed: ",c),e,z);
    ui({title:"Upload",content:box});
    const total=v.reduce((n,f)=>n+f.size,0),bad=[];
    let bytes=0,done=0,good=0,canceled=0;
    try{
      for(const f of v){
        if(s.j===2){canceled=1;break}
        n.textContent=f.name;c.textContent=`${done} / ${v.length}`;
        try{
          await put(f,p,(x,t)=>g.value=total?(bytes+x)*100/total:(done+x/(t||1))*100/v.length);
          good++;
        }catch(x){
          if(x.name==="AbortError"){canceled=1;break}
          bad.push(`${f.name}: ${x.message}`);
        }finally{s.u=0}
        bytes+=f.size;done++;
        g.value=total?bytes*100/total:done*100/v.length;
      }
      c.textContent=`${done} / ${v.length}`;
      if(good&&!s.y)await sync(p);
      if(canceled)e.textContent="Upload canceled";
      else if(bad.length)e.textContent=bad.join("\n");
      else e.textContent="Upload complete";
      e.dataset.error=canceled||bad.length?"true":"false";
      ms(canceled?"Upload canceled":`${good} file${good===1?"":"s"} uploaded`,bad.length);
    }finally{s.u=0;s.j=0;z.hidden=true;rc()}
  }

  a.add("command",{id:"open",label:"Open",when:one,
    run:c=>ac(c.selection[0])});
  a.add("command",{id:"download",label:"Download",when:file,
    run:c=>{const x=el("a",{href:a.url(c.selection[0],{download:1}),download:""});x.click()}});
  a.add("command",{id:"upload",label:"Upload",menu:false,when:()=>!s.j,run:()=>fi.click()});
  a.add("command",{id:"copy",label:"Copy URL",when:one,
    run:async c=>{
      const v=a.url(c.selection[0]);
      try{await navigator.clipboard.writeText(v);ms("URL copied")}
      catch{const x=el("input",{value:v});ui({title:"Copy URL",content:x});x.select()}
    }});
  a.add("command",{id:"ses",label:"Copy Session URL",toolbar:false,showDisabled:true,
    when:c=>one(c)&&s.h,run:async c=>{
      const e=c.selection[0],f=e.s!==-1,x=await(await rq(u(f?parent(e.path):e.path,{cmd:"sesuri"}))).json(),
        v=new URL(f?encodeURIComponent(e.n):"",new URL(x.uri,location.origin)).href;
      await navigator.clipboard.writeText(v);ms("Session URL copied");
    }});
  a.add("command",{id:"window",label:"New window",menu:false,when:()=>true,
    run:()=>{
      if(o.history){window.open(u(s.d).href,"_blank","noopener");return}
      w.searchParams.set("wfm",s.d);
      window.open(w.href,"_blank","noopener");
    }});
  a.add("command",{id:"mkdir",label:"New folder",menu:false,when:()=>true,run:async()=>{
    const n=prompt("Folder name:","New Folder");
    if(n===null)return;
    await rq(u(s.d,{cmd:"mkdirt",dir:name(n)}));
    await sync();
  }});
  a.add("command",{id:"lock",label:"Lock",toolbar:false,when:c=>files(c)&&c.selection.some(x=>!x.l),run:async c=>{
    const x=prompt("Lock until:",new Date(Date.now()+3600000).toISOString()),t=x&&Date.parse(x);
    if(x===null)return;
    if(!t||t<=Date.now())throw new Error("Enter a future expiration time");
    await lop("lock",c.selection.filter(x=>!x.l),Math.floor(t/1000));
  }});
  a.add("command",{id:"unlock",label:"Unlock",toolbar:false,when:c=>files(c)&&c.selection.some(x=>x.l),
    run:c=>lop("unlock",c.selection.filter(x=>x.l))});
  a.add("command",{id:"lockinfo",label:"Lock info",toolbar:false,when:c=>file(c)&&c.selection[0].l,run:async c=>{
    const x=c.selection[0],v=await(await rq(u(s.d,{cmd:"getlock",name:x.n}))).json();
    if(!v.owner)return sync();
    ui({title:x.n,content:`Locked by ${v.owner}. Expires ${new Date(v.time*1000).toLocaleString()}.`});
  }});
  a.add("command",{id:"move",label:"Rename / move",when:item,run:async c=>{
    const x=c.selection[0],p=prompt("New path:",x.path);
    if(p===null)return;
    let t=path(p.startsWith("/")?p:s.d+p);
    if(x.s===-1&&!t.endsWith("/"))t+="/";
    if(x.s!==-1&&t.endsWith("/"))throw new Error("File target must include a name");
    if(t===x.path)return;
    const to=decodeURIComponent(b.pathname)+pp(t).join("/")+(t.endsWith("/")?"/":"");
    await rq(u(parent(x.path),{cmd:"mv",from:x.n,to}));
    const g=!!s.g,n=g?t:s.d.startsWith(x.path)?t+s.d.slice(x.path.length):s.d;
    await sync(n);
    if(g)ts(t);
  }});
  a.add("command",{id:"delete",label:"Delete",when:c=>c.selection.length&&c.selection.every(x=>x.path!=="/"),run:async c=>{
    const v=c.selection;
    if(!confirm(`Delete ${v.length===1?v[0].n:v.length+" items"}?`))return;
    const f=[],g=!!s.g,x=v.find(x=>x.s===-1&&s.d.startsWith(x.path));
    for(const x of v)try{await rq(u(x.path),{method:"DELETE"})}catch(e){f.push([x,e])}
    if(f.length!==v.length){
      await sync(x?parent(x.path):s.d);
      if(g&&f.length)ts(f[0][0].path);
      else{s.s=new Set(f.map(x=>x[0].path));rs()}
    }
    if(f.length)throw new Error(f.map(x=>`${x[0].n}: ${x[1].message}`).join("\n"));
  }});

  async function ac(x){
    if(x.s===-1)return x.path===s.d?undefined:a.open(x.path);
    let p;
    for(const v of s.p){
      try{if(v.match(x)){p=v;break}}
      catch(e){console.error("WFM preview",v.id,e)}
    }
    if(!p)return window.open(a.url(x),"_blank","noopener");
    const c=ui({title:x.n});
    try{await p.render(c,x,a)}
    catch(e){c.textContent=e.message;if(e.name!=="UnauthorizedError")console.error("WFM preview",p.id,e)}
  }

  s.q.push(on(r,"click","button, tr",async(e,t)=>{
    try{
      if(t.dataset.action==="refresh")await a.refresh();
      else if(t.dataset.action==="close")cl();
      else if(t.dataset.action==="cancel-upload"){
        s.j=2;s.u?.abort?.();
      }
      else if(t.matches("tr[data-path]"))se(t,e);
      else if(t.dataset.path){
        const p=t.dataset.path,g=t.matches(".wfm-tree-name");
        await a.open(p);
        if(g)ts(p);
      }
      else if(t.dataset.toggle){
        const p=t.dataset.toggle;
        if(s.x.has(p))s.x.delete(p);
        else{
          if(!s.c.has(p))s.c.set(p,await ls(p));
          s.x.add(p);
        }
        rt();
      }else if(t.dataset.sort){
        if(s.k===t.dataset.sort)s.z=!s.z;
        else{s.k=t.dataset.sort;s.z=0}
        rl();
      }else if(t.dataset.command){
        const x=s.m.get(t.dataset.command);
        if(x)await x.run(cx(),a);
      }
    }catch(x){if(x.name!=="AbortError")ms(x.message,1)}
  }));

  s.q.push(on(r,"dblclick","tr[data-path]",async(e,t)=>{
    const x=s.e.find(x=>x.path===t.dataset.path);
    try{if(x)await ac(x)}catch(x){if(x.name!=="AbortError")ms(x.message,1)}
  }));

  s.q.push(on(r,"contextmenu","tr[data-path], .wfm-tree-name",(e,t)=>{
    e.preventDefault();
    if(t.matches(".wfm-tree-name"))ts(t.dataset.path);
    else if(!s.s.has(t.dataset.path)){
      s.g=0;tr.querySelector('[aria-selected="true"]')?.removeAttribute("aria-selected");
      s.s.clear();s.s.add(t.dataset.path);s.a=t.dataset.path;rs();
    }
    cm(e);
  }));

  s.q.push(on(r,"change","[data-upload]",()=>{
    const v=[...fi.files];fi.value="";
    upload(v).catch(e=>ms(e.message,1));
  }));

  const bk=e=>{
    if(s.j||e.target!==d)return;
    const x=d.getBoundingClientRect();
    if(e.clientX<x.left||e.clientX>x.right||e.clientY<x.top||e.clientY>x.bottom)cl();
  };
  d.addEventListener("click",bk);
  s.q.push(()=>d.removeEventListener("click",bk));

  let dc=0;
  const drag=e=>{
    if(!e.dataTransfer||![...e.dataTransfer.types].includes("Files"))return;
    e.preventDefault();
    if(e.type==="dragenter"){dc++;r.dataset.drop="true"}
    else if(e.type==="dragleave"){
      if(--dc<=0){dc=0;r.removeAttribute("data-drop")}
    }else if(e.type==="dragover")e.dataTransfer.dropEffect="copy";
    else{
      dc=0;r.removeAttribute("data-drop");
      upload([...e.dataTransfer.files]).catch(x=>ms(x.message,1));
    }
  };
  for(const n of["dragenter","dragover","dragleave","drop"])r.addEventListener(n,drag);
  s.q.push(()=>{for(const n of["dragenter","dragover","dragleave","drop"])r.removeEventListener(n,drag)});

  document.addEventListener("click",hm);
  s.q.push(()=>document.removeEventListener("click",hm));

  if(o.history){
    const f=()=>a.open(decodeURI(location.pathname.slice(b.pathname.length))).catch(()=>{});
    addEventListener("popstate",f);s.q.push(()=>removeEventListener("popstate",f));
  }

  for(const p of o.plugins||[]){
    try{const f=p(a);if(typeof f==="function")s.q.push(f)}
    catch(e){console.error("WFM plugin",e)}
  }

  return{
    open:a.open,refresh:a.refresh,selection:a.selection,ready:a.open(s.d),
    destroy(){
      if(s.y)return;
      s.y=1;s.n++;
      s.j=2;s.u?.abort?.();
      for(const r of s.r)r.abort();
      for(const f of s.q.reverse())try{f()}catch(e){console.error("WFM cleanup",e)}
      if(d.open)cl();
      h.replaceChildren();
    }
  };
}

export function search(a){
  let n=0;
  const off=a.add("command",{id:"search",label:"Search",menu:false,run:c=>{
    n++;
    const s=c.selection.length===1&&c.selection[0].s===-1?c.selection[0].path:c.directory,
      q=el("input",{type:"search",required:true,placeholder:"Name"}),
      b=el("button",{type:"submit",textContent:"Start"}),
      f=el("input",{type:"checkbox",checked:true}),d=el("input",{type:"checkbox",checked:true}),
      m=el("div",`Search from: ${s}`),r=el("div",{className:"wfm-results"}),
      x=el("form",{className:"wfm-search"}),box=el("div");
    x.append(q,b,el("label",null,f,"Files"),el("label",null,d,"Dirs"));box.append(x,m,r);
    let id=0;
    const stop=()=>{n++;if(id)m.textContent="Stopped";id=0;b.textContent="Start"};
    x.onsubmit=async e=>{
      e.preventDefault();
      if(id)return stop();
      const t=q.value.trim();
      if(!t||(!f.checked&&!d.checked))return;
      id=++n;b.textContent="Stop";r.replaceChildren();
      const v=[s];let count=0,seen=0;
      while(id===n&&v.length){
        const p=v.pop();m.textContent=`${seen}: ${p}`;
        let z;
        try{z=await a.list(p)}catch(e){if(e.name!=="AbortError")m.textContent=e.message;continue}
        if(id!==n)return;
        for(const o of z){
          seen++;
          if(o.s===-1)v.push(o.path);
          if(o.n.includes(t)&&(o.s===-1?d.checked:f.checked)){
            count++;
            const g=el("button",{type:"button",textContent:o.path});
            g.onclick=async()=>{await a.open(o.s===-1?o.path:o.path.slice(0,o.path.lastIndexOf("/")+1));a.ui.close()};
            r.append(g);
          }
        }
      }
      if(id===n){id=0;b.textContent="Start";m.textContent=`${count} result${count===1?"":"s"}`}
    };
    a.ui.open({title:"Search",content:box,close:stop});q.focus();
  }});
  return()=>{n++;off()};
}

export function text(a){
  return a.add("preview",{id:"text",match:x=>x.n.endsWith(".txt"),async render(c,x){
    const r=await fetch(a.url(x));
    if(!r.ok)throw await responseError(r,a.ui.open,a.url("/"));
    c.textContent=await r.text();
  }});
}
