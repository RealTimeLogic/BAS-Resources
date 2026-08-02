ideCfgCB.push(m=>{
  let b=el("li",{text:"App Upload"});
  b.onclick=()=>uploadEditor();
  m.append(b);
});

function uploadEditor(o={}) {
  let fw=o.firmware,title=o.title||"App Upload";
  if(!fw) logR('\nDrag and drop an <a target="_blank" href="https://realtimelogic.com/articles/Mastering-Xedge-Application-Deployment-From-Installation-to-Creation">application (zip file)</a> to install!\n');
  let x,st,to,iv,ac=new AbortController,busy=false,closed=false,top=el("div",{id:"FMWUpdate",html:`
<div id="fwguage"><svg width="100%" height="100%" viewBox="0 0 36 36"><path d="M18 2.0845a15.9155 15.9155 0 0 1 0 31.831a15.9155 15.9155 0 0 1 0-31.831" stroke-linecap="round" fill="none" stroke="#8F8F8F" stroke-width="1" stroke-dasharray="0,100"/><text x="18" y="18" text-anchor="middle" alignment-baseline="middle"></text></svg></div>
<div id="fwdrop"><label><input type="file" accept="${fw?'.bin,.zip':'.zip'}"><svg width="100%" height="100%" viewBox="0 0 36 36"><circle cx="18" cy="18" r="18" fill="#1f1f1f"/><polygon points="13,15 23,15 18,10"/><rect x="16" y="15" width="4" height="5"/><rect x="13" y="22" width="10" height="2"/></svg></label></div>`}),Q=(s,p=top)=>p.querySelector(s);
  createEditor(title,null,null,top,()=>{
    closed=true;
    ac.abort();
    x?.abort();
    clearTimeout(to);
    clearInterval(iv);
    st?.remove();
  });
  st=el("style",{text:`
#FMWUpdate{box-sizing:border-box;display:grid;place-items:center;overflow:hidden;width:100%;height:100%;background:#0008;padding:20px}
#fwguage,#fwdrop{position:relative;height:min(100%,650px);aspect-ratio:1}
#fwguage text{font:60% Arial;fill:#f8f8f8}
#fwdrop label{display:block;height:100%}
#fwdrop input{position:absolute;z-index:2;inset:0;opacity:0;cursor:pointer}
#fwdrop polygon,#fwdrop rect{fill:#f8f8f8;transform-origin:center;transition:.2s}
#fwdrop:hover polygon,#fwdrop:hover rect,#FMWUpdate.dragover polygon,#FMWUpdate.dragover rect{transform:scaleY(.8) scaleX(1.1);fill:#fff}`});
  document.head.append(st);
  let g=Q("#fwguage"),d=Q("#fwdrop");
  function progress(v,end="%") {
    Q("path",g).setAttribute("stroke-dasharray",`${v},100`);
    Q("text",g).textContent=v+end;
  }
  function reset() {
    busy=false;
    top.classList.remove("dragover");
    d.hidden=false;
    g.hidden=true;
    progress(0);
  }
  function fail(s) {
    alert(s);
    if(!closed) reset();
  }
  function deploy(r,fn) {
    let f=el("div",{class:"form",html:`<h2>Upload successful!</h2><p>Would you like to keep the application in deployed mode? If you intend to change the uploaded code, keep it in developer-mode.</p><fieldset><legend>Keep deployed</legend><input id="depTrue" type="radio" name="DeplCfg" value="true" checked><label for="depTrue">Use ZIP file (deployed-mode)</label><br><input id="depFalse" type="radio" name="DeplCfg" value="false"><label for="depFalse">Unpack ZIP file (developer-mode)</label><br><input id="DeplCfgSave" type="button" value="Save"></fieldset>`});
    top.replaceChildren(f);
    Q("#DeplCfgSave",f).onclick=()=>{
      let mode=Q('input[name="DeplCfg"]:checked',f).value;
      fetch("assets/loader.html",{signal:ac.signal}).then(r=>{
        if(!r.ok) throw r;
        return r.text();
      }).then(html=>{
        top.innerHTML=html;
        sendCmd("startApp",s=>{
          if(!s) {if(!closed)top.replaceChildren(f);return}
          if(closed) return;
          top.replaceChildren(el("h2",{text:s.upgrade?"App Upgraded":"App Installed"}),el("p",{text:s.info}));
          createTree();
        },{name:fn,upgrade:r.upgrade,deploy:mode});
      }).catch(e=>{
        if(!closed) {
          alert("Cannot load installation status.\n\n"+(e.statusText||e.message||e));
          top.replaceChildren(f);
        }
      });
    };
  }
  function restart() {
    progress(100);
    to=setTimeout(()=>{
      progress("RESE","T");
      log("Device is restarting\n");
      iv=setInterval(()=>{
        fetch("/",{cache:"no-store"}).then(r=>{if(r.ok||404==r.status)location.reload()}).catch(()=>{});
        log(".");
      },2000);
    },5000);
  }
  function send(file) {
    if(busy) return;
    let bin=fw&&/\.bin$/i.test(file?.name),zip=/\.zip$/i.test(file?.name);
    if(!bin&&!zip) return alert(fw?"Invalid file type. Please upload a .bin firmware file or .zip application.":"Invalid file type. Please upload an app with the .zip extension.");
    busy=true;
    let ext=bin?".bin":".zip",fn=file.name.replace(/\.[^.]+$/,ext);
    x=new XMLHttpRequest;
    x.onload=()=>{
      if((bin?204:200)!=x.status) return fail("Upload failed.\n\n"+(x.getResponseHeader("X-Error")||x.responseText));
      if(bin) return restart();
      let r;
      try {r=JSON.parse(x.responseText)} catch(e) {return fail("Upload failed.\n\nInvalid server response.")}
      if(!r.ok) return fail("Upload failed.\n\n"+(r.err||"Unknown error."));
      progress(100);
      deploy(r,fn);
    };
    x.onerror=()=>fail("Uploading "+fn+" failed!");
    x.onabort=()=>{if(!closed)reset()};
    x.upload.onprogress=e=>{if(e.lengthComputable)progress(Math.round(90*e.loaded/e.total))};
    x.open("PUT","private/command.lsp?cmd=uploadfw");
    x.setRequestHeader("X-Requested-With","upload");
    x.setRequestHeader("X-File-Name",fn);
    x.send(file);
    d.hidden=true;
    g.hidden=false;
  }
  Q("input",d).onchange=e=>send(e.target.files[0]);
  top.ondragover=e=>{e.preventDefault();top.classList.add("dragover")};
  top.ondragleave=()=>top.classList.remove("dragover");
  top.ondrop=e=>{e.preventDefault();top.classList.remove("dragover");send(e.dataTransfer.files[0])};
  reset();
}

window.uploadEditor=uploadEditor;
