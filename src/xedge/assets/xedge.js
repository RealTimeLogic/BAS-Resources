import {el,q,qa} from "./dom.js";

let trLog;
let trLogErr;
let nodisk;

function play(id) {
    try{q(id)?.play();}catch(e){}
};

function log() {
    trLog(Array.from(arguments).join(' '));
};

function logR(nosound) {
    trLogErr(Array.from(arguments).join(' '));
};
function logErr(nosound) {
    play("#sound-error");
    trLogErr(Array.from(arguments).join(' '));
};

function alertErr() {
    const e=Array.from(arguments).join(' ');
    logErr(e,"\n");
};

function strMatch(str,pat) {
    const match = str.match(pat);
    return match ? match[1] : null;
};

function getFileExt(n){
    return strMatch(n,/\.([^.]+)$/);
};

/* Object, created in on("load"), with 3 funcs:
   login: Show login dialog
   spinner: Show spinner
   remove: remove spinner or login
*/
let loader;
let afterLogin; // Function set when creating loader obj.
function login() {afterLogin();}; //called by /rtl/login/index.lsp
function authenticate() {loader.login();} //Called by TraceLogger
Object.assign(window,{login,authenticate});

// Small Fetch wrapper used by Xedge requests.
function request(url,o={}) {
    let data=o.data;
    const method=(o.type || "GET").toUpperCase();
    if(data && false !== o.processData) {
	data=new URLSearchParams(data);
	if("GET" == method || "HEAD" == method) {
	    url+=(url.includes("?") ? "&" : "?")+data;
	    data=undefined;
	}
    }
    else if(data && "string" == typeof data)
	data=new Blob([data]); // Do not add a content type when saving a file.
    return fetch(url,{method:method,body:data,cache:o.cache,headers:{"X-Requested-With":"XMLHttpRequest"}});
};

function loadScript(url) {
    return request(url,{cache:"no-store"}).then(r=>{
	if(!r.ok) throw r;
	return r.text();
    }).then(js=>{
	let s=document.createElement("script");
	s.text=js;
	document.head.append(s);
    }).catch(e=>alertErr("Cannot load plugin: "+(e.statusText || e.message || e)));
};

// JSON callback wrapper with centralized error and login-retry handling.
function jsonReq(settings,cb,emsg) {
    if(!emsg) emsg='Request failed: ';
	request(settings.url,settings).then(r=>{
	    if(!r.ok) throw r;
	    return r.json();
	}).then((rsp)=>{
	if(!rsp.err && !rsp.emsg) {cb(rsp);return;}
	alert(emsg+"\n\n"+(rsp.emsg || rsp.err));
	cb(false,rsp);
    }).catch(async x=>{
	let r=x instanceof Response ? await x.text() : "";
	let err=x.statusText || x.message || "Error";
	if(401 == x.status) {
	    loader.login(()=>jsonReq(settings,cb,emsg));
	}
	else if(loader.isActive()) {
	    //Just reload everything if it fails at startup (TCP glitch)
	    location.reload();
	}
	else {
	    if(r) try {let e=JSON.parse(r);r=e.emsg || e.err} catch(e){}
	    alert(emsg+(r ? "\n\n"+r : " "+err));
	    cb(false);
	    loader.remove();
	}
    });
};

//Send command to private/command.lsp
function sendCmd(cmd, cb, data) {
    if(!data) data={}
    data.cmd=cmd;
    jsonReq({url:"private/command.lsp",data:data},cb);
};

//ACME specific commands
function sendAcmeCmd(acmd, cb, data) {
    if(!data) data={}
    data.acmd=acmd;
    sendCmd("acme", cb, data)
};

/* Shows the 'TreeDia' div at the x,y location of event 'e'
*/
function diaShow(e) {
    const t=q("#TreeDia"),s=t.style;
    let r=e.target?.getBoundingClientRect(),x=e.pageX??r?.right??0,y=e.pageY??r?.bottom??15;
    s.left=s.right='auto';
    s.top=Math.max(y-8,15)+'px';
    innerWidth-x>200 ? s.left=x+10+'px' : s.right='10px';
    setTimeout(()=>s.display='flex',1);
    return t;
};

function diaHide() {
    q("#TreeDia").style.display='none';
};


/* DOM form builder.
   list: build DOM based on data in list.
   olist: output list, where key is element ID and value is the element
   pe: Optional parent element
*/
function mkForm(list,olist={},pe=el("div",{class:"form"})) {
    list.forEach(o=>{
	if(undefined != o.html) { // Non form element
	    let e=el(o.el,{class:o.class || "",id:o.id || ""});
	    if(o.children)
		mkForm(o.children,olist,e);
	    else
		e.innerHTML=o.html; // Form definitions explicitly mark trusted HTML.
	    pe.append(e);
	    if(o.id) olist[o.id]=e;
	    return;
	}
	let a={...o};
	for(const k of ["el","children","label","description","rname"])
	    delete a[k];
	if(o.label) a.id=o.label;
	let e=el(o.el,a);
	if(e.id) olist[e.id]=e;
	if("radio" == o.type) {
	    pe.append(e,el("label",{text:o.rname,for:o.label}));
	    return;
	}
	let l=o.label ? el("label",{text:o.name,for:o.label}) : el("span");
	const tt=o.description ? el("div",{class:"tooltip",text:"?"},el("span",{text:o.description})) : el("span");
	if("switch"==o.class)
	    pe.append(el("div",{class:"frow"},el("div",{class:"switch"},e,l),el("div",{text:o.name}),tt));
	else if("checkbox"==o.type)
	    pe.append(el("div",{class:"frow"},e,l,tt));
	else if(o.label)
	    pe.append(el("div",{class:"frow"},l,tt),e);
	else {
	    if(o.children) {
		mkForm(o.children,olist,e);
		pe.append(e);
	    }
	    else
		pe.append(el("div",{},e));
	}
    });
    return pe;
};


/* ".appcfg" form data desigend for function mkForm. Used by function appCfg */
const appFormObj = [
    {
	el:"h2",
	html:"Application Configuration"
    },
    {
	el:"input",
	type: "checkbox",
	class:"switch",
	label: "AppCfgRunning",
	name: "Running",
	description: "Turn app on or off",
    },
    {
	el:"input",
	type: "checkbox",
	class:"switch",
	label: "AppCfgAutostart",
	name: "Auto Start",
	description: "Automatically launch the application upon system startup; keep it off during development",
    },
    {
	el: "input",
	type: "text",
	label: "AppCfgName",
	name: "Name",
	description: "A short name such as app1 used as the app's virtual root directory name",
	placeholder: "Enter a short name such as app1",
    },
    {
	el: "input",
	type: "text",
	label: "AppCfgURL",
	name: "URL",
	description: "The path to the app's root directory or the HTTP URL to the Web File Server if using the NET IO",
	placeholder: "Enter the path to the apps's root directory",
    },
    {
	el: "input",
	type: "text",
	label: "startprio",
	name: "Startup Priority",
	description: "Set optional startup priority if the app must start before another app; Max priority is 0",
	placeholder: "Enter optional startup priority",
    },
    {
	el:"input",
	type: "checkbox",
	class:"switch",
	label: "AppCfgLspApp",
	name: "LSP App",
	description: "An app can be Lua enabled or LSP enabled (Lua + web app)",
    },
    {
	el:"div",
	id: "AppCfgLspAppDetails",
	style:"display:none",
	class:"fcol",
	children:[
	    {
		el: "input",
		type: "text",
		label: "AppCfgDirName",
		name: "Directory Name",
		description: "The LSP app's base URL; if 'myapp', then root URL is http://address/myapp/",
		placeholder: "Enter the app's base URL or leave blank if root app",
	    },
	    {
		el: "input",
		type: "text",
		label: "AppCfgDomainName",
		name: "Domain Name",
		description: "Enable the domain name filter and filter out names that do not match the domain name",
		placeholder: "Leave blank unless you want to enable a domain name filter",
	    },
	    {
		el: "input",
		type: "text",
		label: "AppCfgPriority",
		name: "Priority",
		value: "0",
		description: "The LSP app priority is used when multiple apps have the same directory name or if you have multiple root apps",
		placeholder: "Enter a value between -127 and +127",
	    }
	]
    },
    {
	id: "AppCfgSave",
	el: "input",
	type: "button",
	value: "Save"
    }
];


/* Run when context menu "New App" or "Configure App" is clicked. The
   function opens ".appcfg" in the editor pane by using mkForm and the
   data provided in appFormObj. The function sets callbacks for the
   various options.
   pn: path+name
   cfg: the configuration object from JSON or empty if new app
   isNewNet: if configuring a new "net" app (if right click on "net" -> New App)
*/
function appCfg(pn,cfg,isNewNet) {
    let elems={};
    let editorId=createEditor(cfg ? pn : ".appcfg",null,null,mkForm(appFormObj,elems));
    if(cfg) { // Configure existing app
	if(cfg.err)
	    logErr(`App ${pn} is not configured correctly:\n`,cfg.err);
	elems.AppCfgRunning.checked=cfg.running;
	elems.AppCfgAutostart.checked=cfg.autostart;
	elems.AppCfgName.value=cfg.name;
	elems.AppCfgURL.value=cfg.url;
	elems.startprio.value=isNaN(cfg.startprio) ? "" : cfg.startprio+"";
	if(undefined !== cfg.dirname) {
	    elems.AppCfgLspApp.checked=true;
	    elems.AppCfgDirName.value=cfg.dirname;
	    elems.AppCfgDomainName.value=cfg.domainname || "";
	    elems.AppCfgPriority.value=cfg.priority ?? "0";
	    elems.AppCfgLspAppDetails.style.display="";
	}
    }
    else { //Configure new app
	let n=strMatch(pn,/\/([^/]+)(?:\.zip)?\/?$/)
	if(n) {
	    elems.AppCfgName.value=n;
	    elems.AppCfgDirName.value=n;
	}
	elems.AppCfgURL.value=pn;
    }
    elems.AppCfgLspApp.onclick=()=>elems.AppCfgLspAppDetails.style.display=elems.AppCfgLspApp.checked ? "" : "none";
    function saveCfg() {
	function err() {alertErr("Invalid settings");return false;};
	let ncfg={
	    name:elems.AppCfgName.value.trim(),
	    url:elems.AppCfgURL.value.trim(),
	    running:elems.AppCfgRunning.checked,
	    autostart:elems.AppCfgAutostart.checked
	};
	let startprio=elems.startprio.value.trim();
	if(startprio.length > 0) {
	  startprio=parseInt(startprio)
	  if(isNaN(startprio) || startprio < 0)
	    return alertErr("Invalid Startup Priority");
	  ncfg.startprio=startprio
	}
	if(elems.AppCfgLspApp.checked) {
	    ncfg.dirname=elems.AppCfgDirName.value.trim();
	    let dn=elems.AppCfgDomainName.value.trim();
	    if(dn) {
	      if(ncfg.dirname)
		return alertErr("Directory name must be blank when using domain name filter.");
	      ncfg.domainname=dn;
	    }
	    ncfg.priority=elems.AppCfgPriority.value.trim();
	}
	if(ncfg.name.length == 0 || ncfg.url.length == 0) return err();
	savefile(fsBase+(isNewNet ? "net/.appcfg" : (cfg ? pn : pn+".appcfg")),JSON.stringify(ncfg),(ok)=>{
	    if(ok) {
		if(nodisk)
		    sendCmd("getconfig",(rsp)=>localStorage.setItem("xedge", rsp.config));
		createTree();
		if(!cfg || (cfg && cfg.name != ncfg.name)) {
		    closeEditor(editorId);
		    log("Reopen config file via new app name.\n");
		}
	    }
	});
    };
    elems.AppCfgSave.onclick=saveCfg;
    if(cfg)
	elems.AppCfgRunning.onclick=saveCfg;
};



/**************	  EDITOR ***************/

let ios={};// Populated with all BAS IOs i.e. all real root nodes.
let monacoEnabled=false; // Set if we can load Monaco from CDN

/* editors[editorId] = undefined/false/true, where undefined=not set,
   false=content not changed, true=editor content changed
*/
let editors={};
let editorClose={};
let editorRename={};

let lastEditorId=false; // the last selected editor tab

const ext2Lang={ // File extension to source code langauge
  xlua:"lua",
  preload:"lua",
  config:"lua",
  lsp:"lsp",
  html:"html",
  htm:"html",
  js:"javascript",
  json:"javascript"
};


/* Determines Monaco editor's source code language from file extension
*/
function getLanguage(fn) {
    let ext=getFileExt(fn)
    if (ext) {
	return ext2Lang[ext] ? ext2Lang[ext] : ext;
    }
    return "text"
};


/* Removes tabheader and editor from 'editors' pane
*/
function eid(pn) {
    return 'editor-'+pn.replace(/[^a-z0-9]/gi,'-').toLowerCase();
}
function closeEditor(editorId) {
    let f=editorClose[editorId];
    delete editorClose[editorId];
    delete editorRename[editorId];
    f?.();
    q(`[data-target='${editorId}']`,q('#tabheader'))?.remove();
    q(`#${editorId}`)?.remove();
    q(`#${editorId}-buttonsdiv`)?.remove();
    delete editors[editorId];
    if(lastEditorId == editorId) lastEditorId=false;
};

// Set editor was changed: add class to tab to indicate it was changed.
function setMod(editorId,mod=true) {
    editors[editorId]=mod;
    q(`[data-target="${editorId}"]`)?.classList.toggle('modified',mod);
}
 


/* Inserts a new tab and file in the 'editors' pane.
   pn: [path+]name
   value: The text value (file content) to put in the editor. Set to null if newElem set.
   savecb: Optional save callback(data,cb), where data is what to save
	   and cb is a callback that must be called when file is saved
	   with the value cb(true) ok, or cb(false) failed.
   newElem: Set if 'value' is null. This must be a DOM element. Used when
	   building form data in an editor frame. See function
	   appCfg() for how this can be used.
   closecb: Optional cleanup callback invoked when the editor closes.
*/
function createEditor(pn,value,savecb,newElem,closecb) {
    diaHide();
    function save(data) {savecb(data,ok=>setMod(editorId,!ok?.ok));};
    let saveData;
    let editorId=eid(pn);
    if(undefined!=editors[editorId]) {
	if(true==editors[editorId])
	    return;
	closeEditor(editorId);
    }
    else if(false==editors[lastEditorId]) closeEditor(lastEditorId);
    lastEditorId=editorId;
    let tabBtn=el('button',{class:'tabbtn','data-target':editorId,text:pn.match(/[^/]+$/)[0]});
    tabBtn.onclick=()=>{
	if(lastEditorId==editorId) lastEditorId=false; 
	tabBtn.classList.add('pined');
	setActiveEditor(editorId);
	};
    let closeBtn=el('span',{class:'closebtn',text:'X'});
    tabBtn.append(closeBtn);
    closeBtn.onclick=e=>{
	e.stopPropagation();
	if(editors[editorId]) {
	    if(!confirm('The file has unsaved changes. Are you sure you want to close the tab?')) return;
	}
	closeEditor(editorId);
	};
    let editorContainer=el('div',{class:'editorcontainer',id:editorId});
    let editorButtons=el('div',{class:'editor-buttons',id:editorId+'-buttonsdiv'});
    function rename(to) {
	let old=editorId;
	editorId=eid(to);
	tabBtn.dataset.target=editorId;
	tabBtn.firstChild.data=to.match(/[^/]+$/)[0];
	editorContainer.id=editorId;
	editorButtons.id=editorId+'-buttonsdiv';
	editors[editorId]=editors[old];
	delete editors[old];
	if(editorClose[old]) editorClose[editorId]=editorClose[old],delete editorClose[old];
	delete editorRename[old];
	editorRename[editorId]=rename;
	rename.pn=to;
	if(lastEditorId==old) lastEditorId=editorId;
    }
    rename.pn=pn;
    editorRename[editorId]=rename;
    const button=(text,cb)=>{let b=el('button',{text,type:'submit'});b.onclick=cb;return b};
    if(null != value) {
	sendCmd("pn2info", (rsp) => {
	    let addSaveBut=true;
	    if(rsp.running) {
		const ext=getFileExt(pn);
		if('xlua' == ext) {
		    addSaveBut=false;
		    editorButtons.append(button('Save & Run',()=>saveData()));
		}
		else if(('lsp' == ext || 'htm' == ext || 'html' == ext) && rsp.lsp) {
		    editorButtons.append(button('Open',()=>{
			sendCmd("pn2url", (rsp) => {if(rsp.ok) window.open(rsp.url,'lsp');}, {fn:pn});
		    }));
		}
	    }
	    if(addSaveBut)
		editorButtons.append(button('Save',()=>saveData()));
	}, {fn:pn});
    }
    else if(savecb)
	editorButtons.append(button('Run',()=>saveData()));
    q('#tabheader').append(tabBtn);
    q('#editors').append(editorContainer,editorButtons);
    if(newElem) {
	if('string'==typeof newElem) editorContainer.innerHTML=newElem;
	else editorContainer.replaceChildren(newElem);
    }
    else if(monacoEnabled) {
	setTimeout(()=>{
	require(['vs/editor/editor.main'],()=>{
	    let editor = monaco.editor.create(editorContainer,{value:value??"",language:getLanguage(pn),theme:'vs-dark',automaticLayout:true});
	    editor.onDidChangeModelContent(()=>setMod(editorId));
	    editor.addAction({id:'save-content',label:'Save',
		keybindings:[monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS],
		run:ed=>save(ed.getValue())
	    });
	saveData=function() {save(editor.getValue())};
	});
	},10);
    }
    else {
	let ta=el('textarea',{value:value??""});
	ta.onkeydown=ev=>{
	    if(ev.ctrlKey && ev.key === 's') {
		ev.preventDefault();
		save(ta.value);
	    }
	    else if(!ev.ctrlKey)
		setMod(editorId)
	};
	editorContainer.append(ta);
	saveData=()=>save(ta.value);
    }
		
    setMod(editorId, false);
    if(closecb) editorClose[editorId]=closecb;
    setActiveEditor(editorId);
    return editorId;
};

/*  Activate editor tab; invoked by createEditor() event handlers.
*/
function setActiveEditor(editorId) {
  qa('.tabbtn').forEach(e=>e.classList.remove('active'));
  qa('.editor-buttons,.editorcontainer').forEach(e=>e.hidden=true);
  q(`[data-target="${editorId}"]`).classList.add('active');
  q(`#${editorId}`).hidden=false;
  q(`#${editorId}-buttonsdiv`).hidden=false;
};


// Create a two-pane splitter. v selects vertical mode and d is the default percentage.
function split(a,b,v,k,d) {
    a=q(a);b=q(b);
    let p=a.parentNode,z="client"+(v?"Height":"Width"),c="client"+(v?"Y":"X"),n;
    let g=el("div",{class:"gutter gutter-"+(v?"vertical":"horizontal")});
    a.after(g);b.style.flex="1";
    function set(x) {
	let s=p[z];
	x=Math.max(100,Math.min(s-105,x));
	n=100*x/s;
	a.style.flex=`0 0 ${n}%`;
    }
    let x=+localStorage.getItem(k);
    set(x ? (x>=100 ? x : x*p[z]/100) : p[z]*d/100);
    g.onpointerdown=e=>{
	g.setPointerCapture(e.pointerId);
	let r=p.getBoundingClientRect(),o=v?r.top:r.left;
	g.onpointermove=e=>set(e[c]-o);
	g.onpointerup=g.onpointercancel=()=>{
	    g.onpointermove=null;
	    localStorage.setItem(k,n);
	};
    };
}

/* At startup, initialize split panes & preload Monaco; fallback to textarea if failed.
*/
function initEditor() {
    split('#left-pane','#right-pane',false,'left-pane',100/6);
    split('#editorpane','#logpane',true,'editorpane',75);
    let loaderScript = document.createElement('script');
    let monacoBase='https://cdn.jsdelivr.net/npm/monaco-editor@0.56.0/min/vs';
    loaderScript.src = monacoBase+'/loader.min.js';
    loaderScript.onload = function() {
	monacoEnabled=true;
	require.config({
	    paths: {vs:monacoBase}
	});
	require(['vs/editor/editor.main'],()=>{
	    monaco.languages.register({ id: 'lsp' });
	    // Load HTML and Lua languages
	    Promise.all([
		monaco.languages.getLanguages().find((lang) => lang.id === 'html').loader(),
		monaco.languages.getLanguages().find((lang) => lang.id === 'lua').loader(),
	    ]).then(([htmlLang, luaLang]) => {
		var luaRoot = [
		    [/<\?((lsp|lua)|=)?/, { token: '@rematch', switchTo: '@luaInSimpleState.root' }],
		    ...htmlLang.language.tokenizer.root,
		]
		monaco.languages.setMonarchTokensProvider('lsp', {
		    // Inherit the HTML language syntax highlighting
		    ...htmlLang.language,
		    // Merge the HTML and Lua tokenizers
		    tokenizer: {
			...htmlLang.language.tokenizer,
			...luaLang.language.tokenizer,
			// Combine the root rules from both HTML and Lua
			root: luaRoot,
			luaInSimpleState: [
			    [/<\?((lsp|lua)|=)?/, 'metatag.lua'],
			    [/\?>/, { token: 'metatag.lua', switchTo: '@$S2.$S3' }],
			    { include: 'lspRoot' }
			],
			luaInEmbeddedState: [
			    [/<\?((lsp|lua)|=)?/, 'metatag.lua'],
			    [/\?>/, { token: 'metatag.lua', switchTo: '@$S2.$S3', nextEmbedded: '$S3' }],
			    { include: 'lspRoot' }
			],
			// Define the Lua context
			lspRoot: [
			    ...luaLang.language.tokenizer.root,
			    // Add a rule to detect the closing ?> tag and switch back to the root context
			    [/\?>/, { token: 'tag', next: '@pop' }],
			],
		    },
		    // Include the '@keywords', '@symbols',
		    // '@operators', and '@escapes' match targets from
		    // the Lua language
		    keywords: [
			...luaLang.language.keywords,

		    ],
		    symbols: luaLang.language.symbols,
		    operators: luaLang.language.operators,
		    escapes: luaLang.language.escapes,
		});
	    });
	});

    }; // loaderScript
    document.head.appendChild(loaderScript);
};


/**************	  FILE TREE ***************
* Left pane tree interface code for: https://github.com/lunu-bounir/tree.js
*/


let createTree // Function
let selpn; // the currently selected pn (path+name)
let tree; // the one and only tree instance

// The base added to pn to build a URL that can be used by the Web File Server at /rtl/apps/
const fsBase="/rtl/apps/";

// file extentions known to be text files
const okFileExt={
  appcfg:true,
  conf:true,
  config:true,
  preload:true,
  xlua:true,
  lua:true,
  lsp:true,
  htm:true,
  html:true,
  json:true,
  js:true,
  xml:true
};
let opening=new Set;

// Check if known text file
function ok2open(pn) {
    return okFileExt[getFileExt(pn)];
};

// Upload file to the Web File Manager
function savefile(fn,data,cb) {
    log("Uploading ",fn,"\n");
    jsonReq({url:fn,data:data,contentType:false,processData:false,type:'PUT'},cb,"Cannot save "+fn+"\n");
};


/* Sends a ?cmd=lj Web File Manager command to the selected directory 'path'.
   Web File Manager intro: https://tutorial.realtimelogic.com/wfs.lsp 
*/
function getDirList(path,cb) {
    jsonReq({url:fsBase+path,data:{cmd:"lj"}},(data)=>{
	if(false != data) {
	    let list=[];
	    for(const [ix, st] of Object.entries(data)) {
		list[ix]={name:st.n,dir:st.s<0}
	    }
	    cb(list);
	}
	else
	    cb([]);
	loader.remove();
    });
};


/* Sends a Web File Manager compatible command.
*/
function wfsReq(method,url,data,cb,msg) {
    jsonReq({type:method,url:url,data:data}, (rsp)=> {
	if(false != rsp) cb(rsp);
    },msg);
};


/* Displays a simple dialog featuring one input element and its associated label.
   e: event
   text: for label
   val: input element value
   cb: callback(input value) called when Enter key is pressed
*/
function inputDia(e,text,val,cb) {
    const i=el('input',{type:'text',id:'TreeDiaIn',value:val});
    i.onkeydown=e=>{if(e.key==='Enter')cb(i.value.trim())};
    diaShow(e).replaceChildren(el('label',{text,htmlFor:'TreeDiaIn'}),i);
    setTimeout(()=>i.focus(),2);
};
	     
/* Display the file tree context menu.
   e: event
   node: file tree node clicked.
   Activated on right click or long click.
*/
function treeCtxMenu(e,node) {
    if(!node) return;
    let pn=tree.path(node);
    if(!pn) return;
    let ion = strMatch(pn,/^([^\/]+)/);
    let isApp = ios[ion] ? false : true;

    // "New File" or "New Folder" clicked
    function newRes(isFolder) {
	let ready=tree.open(node);
	inputDia(e,isFolder?"New Folder":"New File","",v=>{
	    if(v.length == 0) return;
	    let fn = fsBase+pn+v;
	    const create=()=>{
		   if(isFolder) {
		       wfsReq("POST",fsBase+pn,{cmd:'mkdirt',dir:v},()=>{
			   ready.then(()=>tree.add({name:v,dir:true},node));
		       },`Cannot create folder ${v}.`);
		   }
		   else { // Create new file
		       function rsp(data) {
			   savefile(fn, data, (ok)=> {
			       if(ok) {
				   ready.then(()=>tree.add({name:v},node));
			       }
			   });
		       }
		       let ext=getFileExt(v);
		       if(ext)
			   sendCmd("gettemplate",(r)=>rsp(r.data),{ext:ext});
		       else
			   rsp("\n");
		   }
		   diaHide();
	    };
	    request(fn,{type:"HEAD"}).then(r=>r.ok ?
		alertErr(`Resource ${fn} already exists`) : create()).catch(create);
	});
    };

    //Return parent directory
    function pd(){
	return node.p ? tree.path(node.p) : '';
    };

    function rename() {
	inputDia(e,"Rename",node.name,v=>{
	    const d=pd();
	    if(v.length == 0 || v == node.name || !d) return;
	    wfsReq("GET",fsBase+d,{cmd:'mv',from:node.name, to:fsBase+d+v},()=>{
		let to=d+v+(node.dir?'/':'');
		Object.values(editorRename).forEach(f=>{
		    if(f.pn==pn || node.dir && f.pn.startsWith(pn)) f(to+f.pn.slice(pn.length));
		});
		tree.rename(node,v)},`Cannot rename ${node.name}.`);
	    diaHide();
	});
    };

    function rm() {
	if(confirm(`Are you sure you want to delete ${node.name}?`)) {
	    wfsReq("POST",fsBase+pd(),{cmd:'rmt',file:node.name},()=>{
		if(".appcfg" == node.name)
		    createTree();
		else tree.remove(node);
	    },`Cannot delete ${node.name}.`);
	    diaHide();
	}
    };

    function confApp() {
	const n=pn+".appcfg";
	request(fsBase+n).then(r=>r.text()).then(data=>appCfg(n,JSON.parse(data)));
    };

    function newApp() {
	diaHide();
	if("net" == ion) {
	    sendCmd("gethost",(rsp)=>appCfg(`http://${rsp.ip}/fs/`,null,true));
	}
	else
	    appCfg(pn);
    };
	let list = node.p ? [["Rename",rename],["Delete",rm]] :
	(isApp ? [["Configure App",confApp]] : []);
    function render() {
	if(node.dir) {
	    if(node.p || "net" != node.name) {
		list.push(["New File",()=>newRes(false)]);
		list.push(["New Folder",()=>newRes(true)]);
	    }
	}
	if((((!isApp && node.dir) || "zip" == getFileExt(pn)) && pd()) || "net" == ion) list.push(["New App",newApp]);
	const mlist=el('ul');
	list.forEach(x=>mlist.append(el('li',{text:x[0],onclick:x[1]})));
	diaShow(e).replaceChildren(mlist);
    };

    if(!node.dir && ['lsp','xlua'].includes(getFileExt(node.name))) {
	sendCmd("pn2info", (rsp) => {
	    if(rsp.running) {
		list.unshift(['Run', ()=>{
		    diaHide();
		    if(rsp.url)
			window.open(rsp.url,'lsp');
		    else
			sendCmd("run", (rsp) => {},{fn:pn});
		}]);
	    }
	    render();
	},{fn:pn});
    }
    else
       render();
};


/* Called when a non-directory node is clicked. Sends a HEAD request
   to the Web File Manager to obtain file information. If the
   information is acceptable, sends a GET request to load file
   content. The file content is then passed to the createEditor()
   function.
*/
function openSelFile(node) {
    const pn=tree.path(node),fn=fsBase+pn;
    const ext=getFileExt(pn);
    let id=eid(pn),b=q(`[data-target="${id}"]`);
    if(b) {
	setActiveEditor(id);
	lastEditorId=b.classList.contains('pined')?false:id;
	return;
    }
    if(opening.has(pn)) return;
    opening.add(pn);
    function err(e){
	if(401 == e.status)
	    loader.login(()=>openSelFile(node));
	else
	    alertErr('Request failed: '+(e.statusText || e.message || e));
    };
	request(fn,{type:"HEAD"}).then(xhr=>{
	    if(!xhr.ok) throw xhr;
	    const mt = xhr.headers.get('Content-Type');
	    const cl = xhr.headers.get('Content-Length');
	    if(parseInt(cl) < 100000) {
		if( !(mt && /^text\//.test(mt) || ok2open(pn)) ) {
		    if(!confirm("You can only open text files. Are you sure you want to open this file?"))
			return;
		    okFileExt[ext]=true;
		}
		return request(fn).then(r=>{
		    if(!r.ok) throw r;
		    return r.text();
		}).then((data)=>{
		    if(pn.match(/\/\.appcfg$/))
		       appCfg(pn,JSON.parse(data));
		    else
		       createEditor(pn,data,(ndata,cb)=>savefile(fsBase+tree.path(node),ndata,cb));
		});
	    }
	    else
		alertErr("File too big");
	}).catch(err).finally(()=>opening.delete(pn));
};

/* At startup, initialize left pane tree.
*/
function inittree() {
  let timer;
  let longClick=false;

  document.body.addEventListener('click',e=>{
    if(q('#TreeDia').contains(e.target)) return;
    if(longClick) longClick=false;
    else diaHide();
  });

  function ct() {
    selpn=undefined;
    let selected,apps={},root=el('div',{class:'xtree'});
    q('#TreeCont').replaceChildren(root);

    function path(n) {
      let dir=n.dir,a=[];
      for(;n;n=n.p) a.unshift(n.name);
      return a.join('/')+(dir?'/':'');
    }
    function visible() {
      return [...root.querySelectorAll('summary,a')].filter(e=>e.getClientRects().length);
    }
    function select(n,act=true) {
      selected?.e.classList.remove('selected');
      selected=n;
      n.e.classList.add('selected');
      n.e.focus();
      selpn=path(n);
      if(!n.dir && act) openSelFile(n);
    }
    function add(o,p) {
      let n={name:o.name,dir:!!o.dir,p},box=p?p.d:root;
      if(p) p.loaded=true;
      if(n.dir) {
	n.d=el('details');
	n.e=el('summary',{text:n.name});
	n.d.append(n.e);
	n.d.ontoggle=()=>{if(n.d.open)load(n)};
	box.append(n.d);
      }
      else {
	n.e=el('a',{text:n.name,href:'#'});
	n.e.dataset.ext=getFileExt(n.name);
	box.append(n.e);
      }
      n.e.n=n;
      if(!p && !ios[n.name]) {
	n.d?.classList.add('application');
	n.e.classList.add('appnode');
	apps[n.name]=n;
      }
      return n;
    }
    function load(n) {
      n.d.open=true;
      if(n.loaded) return Promise.resolve(n);
      if(n.loading) return n.loading;
      n.d.classList.add('loading');
      return n.loading=new Promise(resolve=>{
	function done(list=[]) {
	  list.forEach(o=>add(o,n));
	  n.loaded=!!list.length;
	  n.d.classList.remove('loading');
	  delete n.loading;
	  resolve(n);
	}
	if(path(n)=='net/') {
	  logErr("Cannot open the uninitialized NET IO.\n");
	  log("However, you may right click 'net' and create a network app. See the <a target='_blank' href='https://realtimelogic.com/articles/Using-the-NetIO-Network-File-System-Client-on-an-Embedded-Device'>NetIo Tutorial</a> for details.\n");
	  done();
	}
	else getDirList(path(n),done);
      });
    }
    function move(n,back) {
      let a=visible(),i=a.indexOf(n.e),e=a[i+(back?-1:1)];
      if(e) select(e.n);
    }
    function remove(n) {
      let a=visible(),i=a.indexOf(n.e),next=(a[i-1]||a[i+1])?.n;
      (n.d||n.e).remove();
      if(selected==n) {
	selected=undefined;
	if(next) select(next,false); else selpn=undefined;
      }
    }
    function rename(n,name) {
      n.name=name;
      n.e.textContent=name;
      if(!n.dir) n.e.dataset.ext=getFileExt(name);
      if(selected==n) selpn=path(n);
    }
    tree={path,add,open:load,remove,rename,select,active:()=>selected?.e};

    root.onclick=e=>{
      if(longClick) return e.preventDefault();
      let a=e.target.closest('summary,a');
      if(!a || !root.contains(a)) return;
      if(!a.n.dir) e.preventDefault();
      select(a.n);
    };
    root.oncontextmenu=e=>{
      let a=e.target.closest('summary,a');
      if(!a || !root.contains(a)) return;
      e.preventDefault();
      select(a.n,false);
      treeCtxMenu(e,a.n);
    };
    root.ondblclick=e=>{
      let n=e.target.n;
      if(n && !n.dir) {
	let id=eid(path(n));
	q(`[data-target="${id}"]`)?.classList.add('pined');
	if(lastEditorId==id) lastEditorId=false;
      }
    };
    root.onpointerdown=e=>{
      if(e.pointerType=='mouse') return;
      let n=e.target.n;
      if(n) timer=setTimeout(()=>{
	select(n,false);
	treeCtxMenu(e,n);
	longClick=true;
	timer=undefined;
      },700);
    };
    root.onpointerup=root.onpointercancel=root.onpointermove=()=>{
      if(timer) clearTimeout(timer),timer=undefined;
    };
    root.onkeydown=e=>{
      let n=e.target.n;
      if(!n) return;
      if(e.key=='ArrowUp' || e.key=='ArrowDown') move(n,e.key=='ArrowUp');
      else if(e.key=='ArrowRight' && n.dir) load(n);
      else if(e.key=='ArrowLeft') {
	if(n.dir && n.d.open) n.d.open=false;
	else if(n.p) select(n.p,false);
	else return;
      }
      else if(e.key=='Enter') n.dir ? n.d.open=!n.d.open : openSelFile(n);
      else if(e.key=='ContextMenu' || e.shiftKey && e.key=='F10') select(n,false),treeCtxMenu(e,n);
      else return;
      e.preventDefault();
    };

    // Fetch all root directories, including any loaded apps.
    setTimeout(()=>{
      getDirList("",(list)=>{
	list.forEach(o=>add(o));
	sendCmd("getappsstat",(rsp)=>{
	  for(const [name, running] of Object.entries(rsp.apps)) {
	    apps[name]?.e.classList.toggle('apprunning',!!running);
	  }
	});
	if(Object.keys(apps).length === 0) {
	  sendCmd("getintro",(rsp)=>{
	    createEditor("Welcome",null,null,rsp.intro);
	  });
	}
      });
    },10);
  };
  createTree=ct;
  createTree();
};

/************** END OF FILE TREE ****************/

const authenticationFormObj = [
    {
	el:"h2",
	html:"Authentication Settings"
    },
    {
	el: "fieldset",
	html: "",
	children:[
	    {
		el: "legend",
		html: "Add/Remove Local User"
	    },
	    {
		el: "input",
		type: "text",
		label: "AuthName",
		name: "Username",
		description: "Set a username and protect your Xedge IDE",
		placeholder: "Enter a username",
	    },
	    {
		el: "input",
		type: "password",
		label: "AuthPassword",
		name: "Password",
		description: "Add user by providing a password, remove user by setting password blank. Note that there is no password recovery, so it is essential to remember the password",
		placeholder: "Enter a password",
	    },
	    {
		id: "AuthSave",
		el: "input",
		type: "button",
		value: "Save"
	    }
	]
    },
    {el:"p",html:"<br>"},
    {
	el: "fieldset",
	html: "",
	children:[
	    {
		el: "legend",
		html: "Single Sign On"
	    },
	    {
		el: "input",
		type: "text",
		label: "OpenidTenantId",
		name: "Tenant ID",
		description: "A unique identifier for your Azure AD instance, representing your organization and used to ensure correct authentication requests.",
		placeholder: "Enter Tenant ID",
	    },
	    {
		el: "input",
		type: "text",
		label: "OpenidClientId",
		name: "Client id",
		description: "A unique identifier for your registered application, used by Azure AD to issue access tokens for authentication.",
		placeholder: "Enter Client ID",
	    },
	    {
		el: "input",
		type: "password",
		label: "OpenidClientSecret",
		name: "Client Secret",
		description: "A confidential key/password for your application to authenticate with Azure AD, used to request access tokens securely. Clear all three fields and save to disable SSO.",
		placeholder: "Enter Client Secret",
	    },
	    {
		el: "input",
		type: "date",
		label: "OpenidClientSecretExpires",
		name: "Expiration date",
		description: "The expiration date shown for this client secret in Microsoft Entra ID.",
	    },
	    {
		id: "OpenidSave",
		el: "input",
		type: "button",
		value: "Save"
	    }
	]
    }



];

const certificateFormObj = [
    {
	el:"h2",
	html:"Auto Certificate Management <a href='https://youtu.be/COOSMDw07bo' target='_blank'><div class='tooltip'>?<span>Video Tutorial: Automatically Manage Trusted Certificates using BAS and SharktrustX</span></div></a>"
    },
    {
	el:"div",
	id:"SetCertConnection",
	class:"connection-status",
	html:"",
	children:[
	    {el:"span",id:"SetCertConnectionLed",class:"connection-led red",html:""},
	    {el:"span",id:"SetCertConnectionText",html:"Disconnected"}
	]
    },
    {
	el:"p",
	id:"SetCertStatus",
	html:""
    },
    {
	el:"input",
	type: "checkbox",
	class: "switch",
	label: "SetCertManualIdentity",
	name: "Custom Portal Credentials",
	description: "Advanced: override the compiled tokengen identity. The portal URL, zone key, and secret are saved in Xedge's encrypted configuration."
    },
    {
	el: "input",
	type: "text",
	readonly: "true",
	label: "SetCertIp",
	name: "Local IP Address",
	description: "The local IP address identifies your device on your local network"
    },
    {
	el: "input",
	type: "text",
	readonly: "true",
	label: "SetCertWan",
	name: "Public IP Address",
	description: "The public (WAN) IP address identifies your network on the public Internet"
    },
    {
	el: "input",
	type: "text",
	readonly: "true",
	label: "SetCertPortal",
	name: "SharkTrustX Portal",
	description: "The online SharkTrustX portal manages proof of ownership for Let's Encrypt, and controls remote access via the Reverse Connection if enabled."
    },
    {
	el: "input",
	type: "text",
	label: "SetCertZoneKey",
	name: "Zone Key",
	description: "Required when this device does not include a generated tokengen security module",
	placeholder: "Enter the 64-character zone key"
    },
    {
	el: "input",
	type: "password",
	label: "SetCertSecret",
	name: "Zone Secret",
	description: "Required when this device does not include a generated tokengen security module",
	placeholder: "Enter the 64-character zone secret"
    },
    {
	el: "input",
	type: "email",
	label: "SetCertEmail",
	name: "Email",
	description: "The Let's Encrypt CA service requires a valid email address",
	placeholder: "Enter your email address",
    },
    {
	el:"input",
	type: "checkbox",
	class: "switch",
	label: "SetCertStaging",
	name: "Let's Encrypt Staging",
	description: "Use the staging ACME service for development and testing. Staging certificates are not publicly trusted."
    },
    {
	el: "input",
	type: "text",
	label: "SetCertName",
	name: "Name",
	description: "Set a server name. The fully qualified name will be name.portal-domain-name",
	placeholder: "Enter the name you wish to use for your server",
    },
    {
	el:"input",
	type: "checkbox",
	class:"switch",
	label: "SetCertRevcon",
	name: "Reverse Connection",
	description: "Activate remote access via the portal; Please ensure that you set a password before enabling this service",
    },
    {
	id: "SetCertSave",
	el: "input",
	type: "button",
	value: "Save"
    }
];


const emailFormObj = [
    {
	el:"h2",
	html:"SMTP Server"
    },
    {
	el: "fieldset",
	html: "",
	children:[
	    {
		el: "legend",
		html: "Settings"
	    },
	    {
		el: "input",
		type: "email",
		label: "EmailEmail",
		name: "Email Address",
		description: "Your email address",
		placeholder: "Enter your email address",
	    },
	    {
		el: "input",
		type: "text",
		label: "EmailServer",
		name: "Server Name",
		description: "The email server's address",
		placeholder: "Enter the email server's address",
	    },
	    {
		el: "input",
		type: "text",
		label: "EmailServerPort",
		name: "Port",
		description: "The email server's port number",
		placeholder: "Enter email server's port number",
	    },
	]
    },
    {
	el: "fieldset",
	html: "",
	children:[
	    {
		el: "legend",
		html: "Security and Authentication"
	    },

	    {
		el: "input",
		type: "text",
		label: "EmailUsername",
		name: "Username",
		description: "Set the username if the SMTP server requires authentication",
		placeholder: "Enter your username",
	    },
	    {
		el: "input",
		type: "password",
		label: "EmailPassword",
		name: "Password",
		description: "Must be set if you set a username",
		placeholder: "Enter your password"
	    },
	    {
		el: "fieldset",
		html: "",
		children:[
		    {
			el: "legend",
			html: "Connection Security"
		    },
		    {
			el: "input",
			type: "radio",
			label: "EmailNone",
			rname:"None",
			name:"EmailConnsec",
			value: "none"
		    },
		    {
			el: "input",
			type: "radio",
			label: "EmailTLS",
			rname:"TLS",
			checked:"true",
			name: "EmailConnsec",
			value: "tls"
		    },
		    {
			el: "input",
			type: "radio",
			label: "EmailSTARTTLS",
			rname:"STARTTLS",
			name: "EmailConnsec",
			value: "starttls"
		    }
		]
	    }
	]
    },
    {
	id: "EmailSave",
	el: "input",
	type: "button",
	value: "Save"
    },
    {
	el: "fieldset",
	html: "",
	children:[
	    {
		el: "legend",
		html: "Email Log"
	    },
	    {
		el: "input",
		type: "text",
		label: "EmailSubject",
		name: "Subject",
		description: "The default email subject",
		placeholder: "Enter the default email subject",
	    },
	    {
		el: "input",
		type: "number",
		label: "EmailMaxBuf",
		name: "Max buffer",
		description: "The maximum number of bytes to buffer before sending email",
		placeholder: "Max bytes to buffer"
	    },
	    {
		el: "input",
		type: "number",
		label: "EmailMaxTime",
		name: "Max time",
		description: "The maximum time in hours to wait before sending email",
		placeholder: "Max time in hours"
	    },

	    {
		el:"input",
		type: "checkbox",
		class:"switch",
		label: "EmailEnableLog",
		name: "Enable",
		description: "Enable sending logs by email",
	    },
	]
    }
]




/* Builds and displays the configuration option's context menu when the
   user clicks on the 3-dot icon.
*/
let ideCfgCB=[]; //CB added by plugins
function ideCfg(e) {
    const m=el('ul'),add=(s,f)=>m.append(el('li',{text:s,onclick:f}));
    add("Lua Shell",()=>{
	diaHide();
	createEditor("LuaShell",null,(data,cb)=>sendCmd("execLua", cb, {code:data}));
    });
    if( ! nodisk ) {
	add("Authentication",()=>{
	    diaHide();
	    sendCmd("credentials",(rsp)=>{
		if(!rsp) return;
		let cfg=rsp.data;
		sendCmd("openid",(rsp)=>{
		    if(!rsp) return;
		    let oid=rsp.data;
		    let elems={};
		    let editorId=createEditor(" Authentication",null,null,mkForm(authenticationFormObj,elems));
		    if(cfg.name)
			elems.AuthName.value=cfg.name;
		    if(oid.tenant)
			elems.OpenidTenantId.value=oid.tenant;
		    if(oid.client_id)
			elems.OpenidClientId.value=oid.client_id;
		    if(oid.client_secret)
			elems.OpenidClientSecret.value=oid.client_secret;
		    elems.OpenidClientSecretExpires.value=oid.client_secret_expires || new Date().toISOString().slice(0,10);
		    elems.AuthSave.onclick=()=>{
			let data={
			    name:elems.AuthName.value.trim(),
			    pwd:elems.AuthPassword.value.trim(),
			};
			sendCmd("credentials",(rsp)=>{
			    if(rsp) {
				closeEditor(editorId);
				if(!cfg.name && data.pwd) loader.login();
			    }
			}, data);
		    };
		    elems.OpenidSave.onclick=()=>{
			let data={ // Matches format used by Lua module "ms-sso"
			    tenant:elems.OpenidTenantId.value.trim(),
			    client_id:elems.OpenidClientId.value.trim(),
			    client_secret:elems.OpenidClientSecret.value.trim(),
			    client_secret_expires:elems.OpenidClientSecretExpires.value,
			};
			sendCmd("openid",(rsp)=>{
			    if(rsp) closeEditor(editorId);
			}, data);
		    };
		});
	    });
	});
	add("TLS Certificate",()=>{
	    diaShow(e).replaceChildren(el('p',{text:"Waiting for online server..."}));
	    sendAcmeCmd("isreg",(rsp)=>{
		diaHide();
		if(!rsp) return;
		if(undefined == rsp.isreg) {
		    alert(`Cannot connect to SharkTrustX portal ${rsp.portal}`);
		    return;
		}
	let elems={},statusTimer,autoPending=false,formBusy=false;
	let editorId=createEditor(" Certificate",null,null,mkForm(certificateFormObj,elems),
	    ()=>clearInterval(statusTimer));
	elems.SetCertStatus.setAttribute("role","status");
	elems.SetCertStatus.setAttribute("aria-live","polite");
	let connectionError=rsp.connectionError ?
	    `Cannot connect to ${rsp.portal}: ${rsp.connectionError}` : "";
	function working(active,message) {
	    formBusy=active;
	    elems.SetCertSave.disabled=active;
	    elems.SetCertSave.value=active ? "Working..." : "Save";
	    elems.SetCertStatus.textContent=message || connectionError;
	    elems.SetCertStatus.hidden=!(message || connectionError);
	    elems.SetCertStatus.classList.toggle("certificate-working",active);
	}
	function connectionStatus(value) {
	    let reverse=value.reverseStatus || {},state,text;
	    if(value.connectionError || undefined == value.isreg)
		state="red",text="Disconnected";
	    else if(reverse.enabled)
		state=reverse.connected ? "green" : "red",
		text=reverse.connected ? "Reverse connection connected" : "Reverse connection disconnected";
	    else state="yellow",text="Portal connected; reverse connection disabled";
	    elems.SetCertConnectionLed.className=`connection-led ${state}`;
	    elems.SetCertConnectionText.textContent=text;
	}
	connectionStatus(rsp);
	statusTimer=setInterval(()=>sendAcmeCmd("isreg",value=>{
	    if(!value || !elems.SetCertConnection.isConnected) return;
	    connectionStatus(value);
	    connectionError=value.connectionError ?
		`Cannot connect to ${value.portal}: ${value.connectionError}` : "";
	    if(autoPending) {
		if(value.certificateReady) closeEditor(editorId);
		else if(value.certificateWorking)
		    working(true,value.certificateRetrying ?
			"A temporary network problem occurred. Certificate management is retrying in the background..." :
			"Certificate management is working in the background. This can take a few minutes...");
		else {
		    autoPending=false;
		    if(!connectionError) connectionError="Certificate management stopped. See the trace console for details.";
		    working(false);
		}
	    }
	    else if(!formBusy) working(false);
	}),10000);
	working(false);
		if(!rsp.name) {
		    sendCmd("getmac",(rsp)=>{
			if(rsp.ok) {
			    elems.SetCertName.value=rsp.mac.slice(-6)
			}
		    });
		}
		elems.SetCertIp.value=rsp.sockname || "";
		elems.SetCertWan.value=rsp.wan || "";
		let compiled=!!rsp.compiledIdentity;
		elems.SetCertManualIdentity.parentElement.hidden=!compiled;
		elems.SetCertManualIdentity.checked=!!rsp.manualIdentity || !compiled;
		function identityMode() {
		    let manual=elems.SetCertManualIdentity.checked || !compiled;
		    let display=manual ? "" : "none";
		    for(let e of [elems.SetCertPortal,elems.SetCertZoneKey,elems.SetCertSecret])
			e.style.display=e.previousElementSibling.style.display=display;
		    elems.SetCertPortal.readOnly=!manual;
		    if(!manual) elems.SetCertPortal.value=rsp.compiledPortal || rsp.portal || "";
		    else if(rsp.manualIdentity) elems.SetCertPortal.value=rsp.portal || "";
		};
		elems.SetCertManualIdentity.onchange=identityMode;
		elems.SetCertPortal.value=rsp.portal || "";
		identityMode();
		if(rsp.name)
		    elems.SetCertName.value=rsp.name;
		elems.SetCertRevcon.checked=rsp.revcon;
		elems.SetCertStaging.checked=!!rsp.staging;
		let email;
		let name;
		function portalUrl() {
		    let url=elems.SetCertPortal.value.trim();
		    if(url && !/^[a-z]+:\/\//i.test(url)) url="https://"+url;
		    return url;
		};
		function validate() {
		    email=elems.SetCertEmail.value.trim();
		    name=elems.SetCertName.value.trim();
		    let manual=elems.SetCertManualIdentity.checked || !compiled;
		    let key=elems.SetCertZoneKey.value.trim(),secret=elems.SetCertSecret.value.trim();
		    let credentials=rsp.manualIdentity && elems.SetCertPortal.value.trim()==rsp.portal && !key && !secret ||
			(/^[0-9a-f]{64}$/i.test(key) && /^[0-9a-f]{64}$/i.test(secret));
		    if(/^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/.test(email) &&
		       name.length > 2 && /^[a-zA-Z0-9]+$/.test(name) && (!manual ||
		       (/^https:\/\//i.test(portalUrl()) && credentials)))
			return true;
		    alert("Invalid settings");
		    return false;
		};
		function settings() {
		  let manual=elems.SetCertManualIdentity.checked || !compiled;
		  return {email:email,name:name,revcon:elems.SetCertRevcon.checked,
		      staging:elems.SetCertStaging.checked,manualIdentity:manual,
		      portalUrl:manual ? portalUrl() : undefined,
		      zoneKey:manual ? elems.SetCertZoneKey.value.trim() : undefined,
		      secret:manual ? elems.SetCertSecret.value.trim() : undefined};
		};
		function sendAuto(d) {
		  autoPending=true;
		  working(true,"Applying settings and requesting a certificate. This can take a few minutes. The dialog will close when finished.");
		  sendAcmeCmd("auto",(rsp)=>{
		      if(rsp && !rsp.pending) closeEditor(editorId);
		      else if(!rsp) autoPending=false,working(false);
		  },d);
		};
		if(rsp.isreg) {
		    elems.SetCertName.readOnly=true;
		    if(rsp.email)
			elems.SetCertEmail.value=rsp.email,elems.SetCertEmail.readOnly=true;
		    elems.SetCertSave.onclick=()=>{if(validate()) sendAuto(settings());};
		}
		else
		{
		    elems.SetCertSave.onclick=()=>{
			if(validate()) {
			    let d=settings();
			    working(true,"Checking whether the device name is available...");
			    sendAcmeCmd("available",(rsp)=>{
				if(!rsp) return working(false);
				if(rsp.available) sendAuto(d);
				else {
				    working(false);
				    alert(`${name} is in use. Please select another name.`);
				}
			    },d);
			}
		    };
		}
	    });
	});
	add("SMTP Server",()=>{
	    let elems={};
	    let editorId=createEditor(" SMTP Server",null,null,mkForm(emailFormObj,elems));
	    sendCmd("smtp",(rsp)=>{
		if(!rsp) return;
		let x=s=>s??"";
		elems.EmailEmail.value=x(rsp.email);
		elems.EmailServer.value=x(rsp.server);
		elems.EmailServerPort.value=x(rsp.port);
		elems.EmailUsername.value=x(rsp.user);
		elems.EmailPassword.value=x(rsp.password);
		if(rsp.connsec)
		    document.querySelector(`input[name="EmailConnsec"][value="${rsp.connsec}"]`).checked=true;
		elems.EmailSubject.value=x(rsp.subject);
		elems.EmailMaxBuf.value=x(rsp.maxbuf);
		elems.EmailMaxTime.value=x(rsp.maxtime);
		elems.EmailEnableLog.checked=rsp.enablelog;
	    });
	    elems.EmailSave.onclick=()=>{
		let d={
		    email:elems.EmailEmail.value.trim(),
		    server:elems.EmailServer.value.trim(),
		    port:elems.EmailServerPort.value.trim(),
		    user:elems.EmailUsername.value.trim(),
		    password:elems.EmailPassword.value.trim(),
		    connsec:document.querySelector('input[name="EmailConnsec"]:checked').value
		};
		sendCmd("smtp",(rsp)=>{if(rsp) closeEditor(editorId);},d);
	    };
	    elems.EmailEnableLog.onclick=()=>{
		let d={
		    enablelog:elems.EmailEnableLog.checked,
		    subject:elems.EmailSubject.value,
		    maxbuf:elems.EmailMaxBuf.value,
		    maxtime:elems.EmailMaxTime.value
		}
		sendCmd("elog",()=>{}, d);
	    };
	});
    }
    add("Xedge Documentation",()=>{
	diaHide();
	window.open('https://realtimelogic.com/ba/doc/?url=Xedge.html', '_blank')
    });
    ideCfgCB.forEach(cb=>cb(m,nodisk));
    diaShow(e).replaceChildren(m);
};

/************** Init ***************/
addEventListener("load",()=> {
    let iframe=q("#tracelogger");
    let cw=iframe.contentWindow;
    trLog = cw.log ? cw.log : (msg)=>console.log(msg);
    trLogErr = cw.logErr ? cw.logErr : (msg)=>console.log(msg);
    let startTL = cw.startTL ? cw.startTL : ()=>{};
    initEditor();

    loader=(function() {
	let cb;
	let hasLoader=true;
	let l=q('#loader');
	let spinner=l.innerHTML; // Save
	function show(){l.style.cssText='z-index:1000;display:flex';hasLoader=true}
	let o={
	    remove:()=>{
		if(hasLoader) {
		    hasLoader=false;
		    l.style.display='none';
		}
	    },
	    login:(callback)=>{
		cb=callback;
		l.innerHTML='<iframe src="login/" width="500" height="700"></iframe>';
		show();
	    },
	    spinner:()=>{
		l.innerHTML=spinner;
		show();
	    },
	    isActive:()=> hasLoader
	};
	afterLogin=()=>{
	    o.remove();
	    if(cb) {
		cb();
		cb=null;
	    }
	    else startTL();
	};
	return o;
    })();

    // Get list of all known IOs. This call also activates login if an
    // authenticator is installed.
    let data={xedgeconfig:localStorage.getItem("xedge") || ""};
    sendCmd("getionames",(rsp)=>{
	loader.spinner();
	nodisk=rsp.nodisk;
	// Populate the 'ios' variable with all known IOs
	rsp.ios.forEach((name)=>ios[name]=true);
	//Continue initialization after possible login.
	if(!tree) inittree();
	startTL(); // tracelogger can now establish websocket connection.
	Object.assign(window,{el,ideCfgCB,log,logR,mkForm,createEditor,alertErr,sendCmd,closeEditor,createTree});
	sendCmd("lsPlugins",async rsp=>{
	    for(const name of rsp)
		await loadScript("private/command.lsp?cmd=getPlugin&name="+encodeURIComponent(name));
	});
	q("#IdeCfg").onclick=ideCfg;
    }, data);
	addEventListener("beforeunload",e=>{
	for(const [file,changed] of Object.entries(editors)) {
	    if(changed) {
		e.returnValue = 'You have unfinished changes!';
		e.preventDefault();
		return false;
	    }
	}
	});
});

function onreconnect() { //Called by TraceLogger
    sendCmd("getionames",(rsp)=>{
	ios={}
	rsp.ios.forEach((name)=>ios[name]=true);
	if(!tree) inittree();
    });
};
