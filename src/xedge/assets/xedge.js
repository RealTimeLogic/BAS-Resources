let trLog;
let trLogErr;
let nodisk;

function play(id) {
    try{$(id)[0].play();}catch(e){}
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

//Simple $.ajax JSON wrapper
function jsonReq(settings,cb,emsg) {
    if(!emsg) emsg='Request failed: ';
    settings.dataType="json";
    settings.success = (rsp)=>{
	if(!rsp.err && !rsp.emsg) {cb(rsp);return;}
	alertErr(emsg+(rsp.emsg ? rsp.emsg : rsp.err));
	cb(false);
    };
    settings.error=(x,s,err)=>{
	let r=x.responseText;
	if("Unauthorized"==err) {
	    loader.login(()=>jsonReq(settings,cb,emsg));
	}
	else if(loader.isActive()) {
	    //Just reload everything if it fails at startup (TCP glitch)
	    location.reload();
	}
	else {
	    emsg=emsg+(r ? r : err);
	    alertErr(emsg);
	    logErr(emsg);
	    cb(false);
	    loader.remove();
	}
    }
    $.ajax(settings);
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
    const t=$("#TreeDia");
    const css = {left: 'auto', right: 'auto', top: e.pageY > 15 ? e.pageY-8 : 15, display: 'flex'};
    $(window).width()-e.pageX > 200 ? css.left = e.pageX+10 + 'px' : css.right = '10px';
    setTimeout(()=>t.css(css),1);
    return t;
};

function diaHide() {
    $("#TreeDia").hide();
};


/* DOM form builder.
   list: build DOM based on data in list.
   olist: output list, where key is element ID and value is the element
   pe: Optional parent element
*/
function mkForm(list,olist,pe,insrt) {
    if(!pe) pe=$("<div>",{class:"form"});
    list.forEach(o => {
	if(undefined != o.html) { // Non form element
	    let el=$(`<${o.el}>`, o.class ? {class:o.class} :{})
	    if(o.children)
		mkForm(o.children,olist,el);
	    else
		el.html(o.html);
	    pe.append(el);
	    if(insrt) olist[o.id]=el;
	    return;
	}
	if("radio" == o.type) {
	    pe.append($('<label>',{text:o.rname,for:o.label}));
	    let p={};
	    for(let k in o)  p["label" == k ? "id" : k]=o[k];
	    pe.append($('<input>',p));
	    return;
	}
	let l=o.label ? $('<label>',{text:o.name,for:o.label}) : $('<span>');
	const tt=o.description ? $("<div>",{class:"tooltip"}).text("?").append($('<span>').text(o.description)) : $("<span>");
	if(o.label)
	    o.id=o.label;
	let el=$(`<${o.el}>`,o);
	if("switch"==o.class)
	    pe.append($("<div>",{class:"frow"}).append($("<div>",{class:"switch"}).append(el).append(l))
		      .append($("<div>").text(o.name)).append(tt));
	else if("checkbox"==o.type)
	    pe.append($("<div>",{class:"frow"}).append(el).append(l).append(tt));
	else if(o.label)
	    pe.append($("<div>",{class:"frow"}).append(l).append(tt)).append(el);
	else {
	    if(o.children) {
		let oc={...o};
		delete oc.children;
		let c=$("<div>",oc);
		mkForm(o.children,olist,c);
		pe.append(c);
	    }
	    else
		pe.append($("<div>").append(el));
	}
	olist[o.id]=el;
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
		description: "The LSP app's base URL",
		placeholder: "Enter the app's base URL or leave blank if root app",
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
	elems.AppCfgRunning.prop("checked", cfg.running);
	elems.AppCfgAutostart.prop("checked", cfg.autostart);
	elems.AppCfgName.val(cfg.name);
	elems.AppCfgURL.val(cfg.url);
	if(undefined !== cfg.dirname) {
	    elems.AppCfgLspApp.prop("checked", true);
	    elems.AppCfgDirName.val(cfg.dirname);
	    elems.AppCfgPriority.val(cfg.priority);
	    $("#AppCfgLspAppDetails").show();
	}
    }
    else { //Configure new app
	let n=strMatch(pn,/\/([^/]+)\/$/)
	if(n) {
	    elems.AppCfgName.val(n);
	    elems.AppCfgDirName.val(n);
	}
	elems.AppCfgURL.val(pn);
    }
    elems.AppCfgLspApp.click(function() {
	$("#AppCfgLspAppDetails")[$(this).prop("checked") ? "show" : "hide"]();
    });
    function saveCfg() {
	function err() {alertErr("Invalid settings");return false;};
	let ncfg={
	    name:elems.AppCfgName.val().trim(),
	    url:elems.AppCfgURL.val().trim(),
	    running:elems.AppCfgRunning.prop("checked"),
	    autostart:elems.AppCfgAutostart.prop("checked")
	};
	if(elems.AppCfgLspApp.prop("checked")) {
	    ncfg.dirname=elems.AppCfgDirName.val().trim();
	    ncfg.priority=elems.AppCfgPriority.val().trim();
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
    elems.AppCfgSave.click(saveCfg);
    if(cfg)
	elems.AppCfgRunning.click(saveCfg);
};



/**************	  EDITOR ***************/

let ios={};// Populated with all BAS IOs i.e. all real root nodes.
let monacoEnabled=false; // Set if we can load Monaco from CDN

/* editors[editorId] = undefined/false/true, where undefined=not set,
   false=content not changed, true=editor content changed
*/
let editors={};

let lastEditorId=false; // the last selected editor tab

const ext2Lang={ // File extension to source code langauge
    xlua: "lua",
    preload: "lua",
    config: "lua",
    lsp: "lsp",
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
function closeEditor(editorId) {
    $('#tabheader').find(`[data-target='${editorId}']`).remove();
    $(`#${editorId}`).remove();
    $(`#${editorId}-buttonsdiv`).remove();
    delete editors[editorId];
    if(lastEditorId == editorId) lastEditorId=false;
};

// Set editor was changed: add class to tab to indicate it was changed.
function setMod(editorId,mod=true) {
    editors[editorId]=mod;
    if (mod) $(`[data-target="${editorId}"]`).addClass('modified'); else $(`[data-target="${editorId}"]`).removeClass('modified');
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
*/
function createEditor(pn,value,savecb,newElem) {
    diaHide();
    function save(data) {savecb(data, ok => setMod(editorId, !ok.ok));};
    let saveData;
    let editorId = 'editor-' + pn.replace(/[^a-z0-9]/gi, '-').toLowerCase();
    if(undefined!=editors[editorId]) {
	if(true==editors[editorId])
	    return;
	closeEditor(editorId);
    }
    else if(false==editors[lastEditorId]) closeEditor(lastEditorId);
    lastEditorId=editorId;
    let tabBtn = $('<button>', {class: 'tabbtn','data-target': editorId,text: pn.match(/[^/]+$/)[0]});
    tabBtn.click((e)=>{
	if(lastEditorId==editorId) lastEditorId=false; 
	$(e.target).addClass('pined'); 
	setActiveEditor(editorId);
    });
    let closeBtn=$('<span>',{class:'closebtn',text:'X'}).appendTo(tabBtn);
    closeBtn.click(()=>{
	if(editors[editorId]) {
	    var shouldClose = confirm('The file has unsaved changes. Are you sure you want to close the tab?');
	    if (!shouldClose) return;
	}
	closeEditor(editorId);
    });
    let editorContainer = $('<div>', {class: 'editorcontainer',id: editorId});
    let editorButtons = $('<div>', {class:'editor-buttons', id: editorId+'-buttonsdiv'});
    if(value) {
	sendCmd("pn2info", (rsp) => {
	    let addSaveBut=true;
	    if(rsp.running) {
		if('xlua' == getFileExt(pn)) {
		    addSaveBut=false;
		    editorButtons.append($('<button>', { html: 'Save &amp; Run', type: 'submit'}).click(()=>saveData()));
		}
		else if('lsp' == getFileExt(pn)) {
		    editorButtons.append($('<button>', { html: 'Open', type: 'submit'}).click( () => {
			sendCmd("pn2url", (rsp) => {if(rsp.ok) window.open(rsp.url,'lsp');}, {fn:pn});
		    }));
		}
	    }
	    if(addSaveBut)
		editorButtons.append($('<button>', { html: 'Save', type: 'submit'}).click(()=>saveData()));
	}, {fn:pn});
    }
    else if(savecb)
	editorButtons.append($('<button>', { html: 'Run', type: 'submit'}).click(()=>saveData()));
    $('#tabheader').append(tabBtn);
    $('#editors').append(editorContainer).append(editorButtons)
    if(newElem) editorContainer.html(newElem);
    else if(monacoEnabled) {
	setTimeout(()=>{
	require(['vs/editor/editor.main'],()=>{
	    let editor = monaco.editor.create(editorContainer.get(0), {value:value,language:getLanguage(pn),theme:'vs-dark',automaticLayout:true});
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
	let ta=$('<textarea>').val(value).on('keydown',function(ev){
	    if(ev.ctrlKey && ev.key === 's') {
		ev.preventDefault();
		save($(this).val());
	    }
	    else if(!ev.ctrlKey)
		setMod(editorId)
	});
	editorContainer.html(ta);
	saveData=function() {save(ta.val());};
    }
		
    setMod(editorId, false);
    setActiveEditor(editorId);
    return editorId;
};

/*  Activate editor tab; invoked by createEditor() event handlers.
*/
function setActiveEditor(editorId) {
  $('.tabbtn').removeClass('active');
  $('.editor-buttons').hide();
  $('.editorcontainer').hide();
  $(`[data-target="${editorId}"]`).addClass('active');
  $(`#${editorId}`).show();
  $(`#${editorId}-buttonsdiv`).show();
};


/* At startup, initialize split panes & preload Monaco; fallback to textarea if failed.
*/ 
function initEditor() {
    try{
	Split(['#left-pane', '#right-pane'], {
	    sizes: [15, 75],
	    minSize: 100,
	    direction: 'horizontal',
	    gutterSize: 5,
	});
	Split(['#editorpane', '#logpane'], {
	    sizes: [75, 25],
	    minSize: 100,
	    direction: 'vertical',
	    gutterSize: 5,
	});
    }
    catch(e){
	log("Cannot load resources from CDN\n");
    }
    let loaderScript = document.createElement('script');
    loaderScript.src = 'https://unpkg.com/monaco-editor@0.36.1/min/vs/loader.js';
    loaderScript.onload = function() {
	monacoEnabled=true;
	require.config({
	    paths: {'vs': 'https://unpkg.com/monaco-editor@0.36.1/min/vs'}
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
    lsp:true
};
let notOkFileExt={};

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
		if(st.s < 0) list[ix]={asynced: true, type: Tree.FOLDER, name:st.n}
		else list[ix]={name:st.n}
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
function wfsReq(method,url,data,cb) {
    jsonReq({type:method,url:url,data:data}, (rsp)=> {
	if(false != rsp) cb(rsp);
    });
};


/* Displays a simple dialog featuring one input element and its associated label.
   e: event
   text: for label
   val: input element value
   cb: callback(input-data, element) called when Enter key is pressed
*/
function inputDia(e,text,val,cb) {
    const d=diaShow(e);
    d.html($('<label>',{text:text,for:"TreeDiaIn"})).
	append($('<input>', {type:'text',id:"TreeDiaIn",value:val}).
	       on('keydown',function(e) { if (e.key === 'Enter') cb(d,$(this)); }));
};
	     
/* Display the file tree context menu.
   e: event
   node: file tree node clicked.
   Activated on right click or long click.
*/
function treeCtxMenu(e,node) {
    let pn=selpn
    if(!node ||!pn) return;
    let h = tree.hierarchy(node.e);
    let ion = strMatch(pn,/^([^\/]+)/);
    let isApp = ios[ion] ? false : true;

    // "New File" or "New Folder" clicked
    function newRes(isFolder) {
	//We need to expand tree node if not opened or tree will fail to work.
	if( !node.opn ) {
	    let f=tree.active();
	    getDirList(pn,(list)=>{if(list)tree.json(list,f);f.resolve();});
	}
	inputDia(e,isFolder?"New Folder":"New File","",(diaE,inpE)=>{
	    let v=inpE.val().trim();
	    if(v.length == 0) return;
	    let fn = fsBase+pn+v;
	    $.ajax({type:"HEAD",url:fn,
	       success:()=> alertErr(`Resource ${fn} already exists`),
	       error:()=> {
		   if(isFolder) {
		       wfsReq("POST",fsBase+pn,{cmd:'mkdirt',dir:v},()=>{
			   tree.folder({name:v,type:"folder"}, node.e);
			   node.e.resolve();
		       });
		   }
		   else { // Create new file
		       function rsp(data) {
			   savefile(fn, data, (ok)=> {
			       if(ok) {
				   tree.file({name:v,asynced:true}, node.e);
				   node.e.resolve();
			       }
			   });
		       }
		       let ext=getFileExt(v);
		       if(ext)
			   sendCmd("gettemplate",(r)=>rsp(r.data),{ext:ext});
		       else
			   rsp("\n");
		   }
		   diaE.hide();
	       }
	    })
	});
    };

    //Return parent directory
    function pd(){
	return strMatch(pn,node.type ? /^(.*\/)[^/]+\/$/ : /^(.*\/)[^/]+$/);
    };

    function rename() {
	inputDia(e,"Rename",node.name, (diaE,inpE)=> {
	    let v=inpE.val().trim();
	    const d=pd();
	    if(v.length == 0 || v == node.name || !d) return;
	    wfsReq("GET",fsBase+d,{cmd:'mv',from:node.name, to:fsBase+d+v},()=>{
		tree.active().textContent=v; node.name=v;});
	    diaE.hide();
	});
    };

    function rm() {
	if(confirm(`Are you sure you wan to delete ${node.name} ?`)) {
	    wfsReq("POST",fsBase+pd(),{cmd:'rmt',file:node.name},()=>{
		if(".appcfg" == node.name)
		    createTree();
		else {
		    node=tree.active();
		    tree.navigate('backward');
		    tree.remove(node);
		}
	    });
	    diaHide();
	}
    };

    function confApp() {
	const n=pn+".appcfg";
	$.get(fsBase+n).done((data)=>appCfg(n,JSON.parse(data)));
    };

    function newApp() {
	diaHide();
	if("net" == ion) {
	    sendCmd("gethost",(rsp)=>appCfg(`http://${rsp.ip}/fs/`,null,true));
	}
	else
	    appCfg(pn);
    };
    let list = h.length > 1 ? [["Rename",rename],["Delete",rm]] :
	(isApp ? [["Configure App",confApp]] : []);
    function render() {
	if(node.type) {
	    if(h.length > 1 || "net" != node.name) {
		list.push(["New File",()=>newRes(false)]);
		list.push(["New Folder",()=>newRes(true)]);
	    }
	}
	if((((!isApp && node.type) || "zip" == getFileExt(pn)) && pd()) || "net" == ion) list.push(["New App",newApp]);
	const mlist = $('<ul>');
	list.forEach(x => mlist.append($('<li>').text(x[0]).on('click', x[1])));
	diaShow(e).html(mlist);
    };

    if(node.e.getAttribute('data-type') === 'file' && ['lsp', 'xlua'].includes(node.e.getAttribute('data-ext'))) {
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
function openSelFile() {
    const fn=fsBase+selpn;
    const ext=getFileExt(selpn);
    if(notOkFileExt[ext]) return;
    notOkFileExt[ext]=true;
    function err(xhr, stat, e){
	if("Unauthorized"==e)
	    loader.login(openSelFile);
	else
	    alertErr('Request failed: '+e+ " : "+stat);
    };
    $.ajax({type:"HEAD",url:fn,
	success: function(data, s, xhr) {
	    const mt = xhr.getResponseHeader('Content-Type');
	    const cl = xhr.getResponseHeader('Content-Length');
	    if(parseInt(cl) < 100000) {
		if( !(mt && /^text\//.test(mt) || ok2open(selpn)) ) {
		    if(!confirm("You can only open text files. Are you sure you want to open this file?"))
			return;
		    okFileExt[ext]=true;
		}
		$.get(fsBase+selpn).done((data)=>{
		    if(selpn.match(/\/\.appcfg$/))
		       appCfg(selpn,JSON.parse(data));
		    else
		       createEditor(selpn,data,(ndata,cb)=>savefile(fn,ndata,cb));
		}).fail(err);
	    }
	    else
		alertErr("File too big");
	    notOkFileExt[ext]=undefined;
	},
	error: err
    });
};

/* At startup, initialize left pane tree.
*/
function inittree() {
    let timer;
    let curNode;
    let rightClick=false;
    let longClick=false;

    /* Hides tree dialog if event is outside an element in the
       dialog. Also resets long press logic.
    */
    $("body").click(function (e) {
	let el = e.target;
	while(el.parentElement) {
	    if("TreeDia" == el.id)
		return;
	    el=el.parentElement;
	}
	if(longClick)
	    longClick=false;
	else
	    diaHide();
    });

    // Right click: activate context menu
    $("#tree").contextmenu(ev=>{
	treeCtxMenu(ev,curNode);
	return false;
    }).
		// Double click = pin editor
		on('dblclick', () => { $(`[data-target="${lastEditorId}"]`).addClass('pined'); lastEditorId = false;}).
    // Start long click timer; call treeCtxMenu() upon timer completion.
    on('mousedown touchstart',ev=>{
	rightClick = 3 === ev.which;
	timer=setTimeout(()=> {
	    treeCtxMenu(ev,curNode);
	    longClick=true;
	    timer=null;
	},1000);
    }).
    // Cancel long click timer
    on('mouseup touchend', ()=>{
	if(timer) {
	    clearTimeout(timer);
	    timer=null;
	}
    });

    /* Inner createTree() function; called at startup & for new tree
       rendering. See createTree=ct below.
    */
    function ct() {
	selpn=undefined;
	let appsEl={};
	$('#tree').empty();
	tree = new Tree(document.getElementById('tree'),{navigate: true});
	// Fetch all root directories, inclding any loaded apps.
	setTimeout(()=>{
	    getDirList("",(list)=>{
		tree.json(list);//Display root list; triggers 'created' event for each node.
		sendCmd("getappsstat",(rsp)=>{
		    for(const [name, running] of Object.entries(rsp.apps)) {
			appsEl[name].addClass(running ? "apprunning" : "appstopped");
		    }
		});
		// The 'created' event has now populated 'appsEl'
		if(Object.keys(appsEl).length === 0) {// if no apps
		    sendCmd("getintro",(rsp)=>{
			// Show introductory information if we have no apps.
			createEditor("Welcome",null,null,rsp.intro);
		    });
		}
	    });
	},10);
	// Called for each inserted node.
	tree.on('created',(e,node)=>{
	    if(!selpn) { //If loading root dirs
		if(!ios[node.name]) { // if an app
		    appsEl[node.name] = $(e).addClass("appnode");
		    $(e).parent().addClass('application')
		}
	    }
	    //Code below based on: https://github.com/lunu-bounir/tree.js/issues/5
	    e.node=node;
	    node.e=e;
	});

	// On expand tree. 'opn' used by treeCtxMenu() -> newRes()
	tree.on('open', e => e.node.opn=true);

	// When tree node selected (clicked). Build 'selpn' based on
	// data set in on 'created'
	tree.on('select',e=>{
	    if(!e.node) return;
	    curNode=e.node;
	    selpn=tree.hierarchy(e).map(e=>[e, e.node]).
		reduce((n, obj)=>{return obj[1].name + '/' + n;}, '');
	    if(!e.node.type) {//if file
		selpn=selpn.slice(0, -1); // Remove '/' in file.ext/
		if(timer) { // Cancel long press
		    clearTimeout(timer);
		    timer=null;
		}
		if(!rightClick) //Open file in editor if left click.
		    openSelFile();
	    }
	});

	// When tree node clicked.
	tree.on('fetch', folder=>{
	    if("net/" == selpn) {
		folder.resolve();
		logErr("Cannot open the uninitialized NET IO.\n");
		log("However, you may right click 'net' and create a network app.\n");
	    }
	    else {
		getDirList(selpn, (list)=>{
		    if(list) tree.json(list,folder);
		    folder.resolve();
		});
	    }
	});
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
		description: "A confidential key/password for your application to authenticate with Azure AD, used to request access tokens securely.",
		placeholder: "Enter Client Secret",
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
	type: "email",
	label: "SetCertEmail",
	name: "Email",
	description: "The Let's Encrypt CA service requires a valid email address",
	placeholder: "Enter your email address",
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
		type: "subject",
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
    const mlist = $('<ul>');
    mlist.append($('<li>').text("Lua Shell").on("click",()=>{
	diaHide();
	createEditor("LuaShell","",(data,cb)=>sendCmd("execLua", cb, {code:data}));
    }));
    if( ! nodisk ) {
	mlist.append($('<li>').text("Authentication").on("click",()=>{
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
			elems.AuthName.val(cfg.name);
		    if(oid.tenant)
			elems.OpenidTenantId.val(oid.tenant);
		    if(oid.client_id)
			elems.OpenidClientId.val(oid.client_id);
		    if(oid.client_secret)
			elems.OpenidClientSecret.val(oid.client_secret);
		    elems.AuthSave.click(()=>{
			let data={
			    name:elems.AuthName.val().trim(),
			    pwd:elems.AuthPassword.val().trim(),
			};
			sendCmd("credentials",(rsp)=>{
			    if(rsp) closeEditor(editorId);
			}, data);
		    });
		    elems.OpenidSave.click(()=>{
			let data={ // Matches format used by Lua module "ms-sso"
			    tenant:elems.OpenidTenantId.val().trim(),
			    client_id:elems.OpenidClientId.val().trim(),
			    client_secret:elems.OpenidClientSecret.val().trim(),
			};
			sendCmd("openid",(rsp)=>{
			    if(rsp) closeEditor(editorId);
			}, data);
		    });
		});
	    });
	}));
	mlist.append($('<li>').text("TLS Certificate").on("click",()=>{
	    diaShow(e).html("<p>Waiting for online server...</p>");
	    sendAcmeCmd("isreg",(rsp)=>{
		diaHide();
		if(undefined == rsp.isreg) {
		    closeEditor(editorId);
		    alertErr(`Cannot connect to SharkTrustX portal ${rsp.portal}`);
		    return;
		}
		let elems={};
		let editorId=createEditor(" Certificate",null,null,mkForm(certificateFormObj,elems));
		if(! rsp.isreg ) {
		    sendCmd("getmac",(rsp)=>{
			if(rsp.ok) {
			    elems.SetCertName.val(rsp.mac.slice(-6))
			}
		    });
		}
		elems.SetCertIp.val(rsp.sockname);
		elems.SetCertWan.val(rsp.wan);
		elems.SetCertPortal.val(rsp.portal);
		if(rsp.name)
		    elems.SetCertName.val(rsp.name);
		elems.SetCertRevcon.prop("checked", rsp.revcon);
		let email;
		let name;
		function validate() {
		    email=elems.SetCertEmail.val().trim();
		    name=elems.SetCertName.val().trim();
		    if(/^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/.test(email) &&
		       name.length > 2 && /^[a-zA-Z0-9]+$/.test(name))
			return true;
		    alertErr("Invalid settings");
		    return false;
		};
		function sendAuto() {
		    let d={revcon:elems.SetCertRevcon.prop("checked")};
		    if(!rsp.email) {
			d.email=email;
			d.name=name;
		    }
		    sendAcmeCmd("auto",(rsp)=>closeEditor(editorId),d);
		};
		if(rsp.isreg) {
		    elems.SetCertName.attr("readonly",true);
		    if(rsp.email)
			elems.SetCertEmail.val(rsp.email).attr("readonly",true);
		    elems.SetCertSave.click(() => {if(validate()) sendAuto();});
		}
		else
		{
		    elems.SetCertSave.click(()=>{
			if(validate()) {
			    sendAcmeCmd("available",(rsp)=>{
				if(rsp.available) 
				    sendAuto();
				else
				    alertErr(`${name} is in use. Please select another name.`);
			    },{name:name});
			}
		    });
		}
	    });
	}));
	mlist.append($('<li>').text("SMTP Server").on("click",()=>{
	    let elems={};
	    let editorId=createEditor(" SMTP Server",null,null,mkForm(emailFormObj,elems));
	    sendCmd("smtp",(rsp)=>{
		function x(s,v) {return s ? s : ""};
		elems.EmailEmail.val(x(rsp.email));
		elems.EmailServer.val(x(rsp.server));
		elems.EmailServerPort.val(x(rsp.port));
		elems.EmailUsername.val(x(rsp.user));
		elems.EmailPassword.val(x(rsp.password));
		if(rsp.connsec)
		    $(`input[name="EmailConnsec"][value="${rsp.connsec}"]`).prop('checked', true);
		elems.EmailSubject.val(x(rsp.subject));
		elems.EmailMaxBuf.val(x(rsp.maxbuf));
		elems.EmailMaxTime.val(x(rsp.maxtime));
		elems.EmailEnableLog.prop("checked", rsp.enablelog);
	    });
	    elems.EmailSave.click(()=>{
		let d={
		    email:elems.EmailEmail.val().trim(),
		    server:elems.EmailServer.val().trim(),
		    port:elems.EmailServerPort.val().trim(),
		    user:elems.EmailUsername.val().trim(),
		    password:elems.EmailPassword.val().trim(),
		    connsec:$('input[name="EmailConnsec"]:checked').val()
		};
		sendCmd("smtp",(rsp)=>{if(rsp) closeEditor(editorId);},d);
	    });
	    elems.EmailEnableLog.click(()=>{
		let d={
		    enablelog:elems.EmailEnableLog.prop("checked"),
		    subject:elems.EmailSubject.val(),
		    maxbuf:elems.EmailMaxBuf.val(),
		    maxtime:elems.EmailMaxTime.val()
		}
		sendCmd("elog",()=>{}, d);
	    });
	}));
    }
    mlist.append($('<li>').text("Xedge Documentation").on("click",()=>{
	diaHide();
	window.open('https://realtimelogic.com/ba/doc/?url=Xedge.html', '_blank')
    }));
    ideCfgCB.forEach((cb) => cb(mlist,nodisk));
    diaShow(e).html(mlist);
};

/************** Init ***************/
$( window ).on( "load",()=> {
    let iframe=$("#tracelogger")[0];
    let cw=iframe.contentWindow;
    trLog = cw.log ? cw.log : (msg)=>console.log(msg);
    trLogErr = cw.logErr ? cw.logErr : (msg)=>console.log(msg);
    let startTL = cw.startTL ? cw.startTL : ()=>{};
    initEditor();

    loader=(function() {
	let cb;
	let hasLoader=true;
	let l=$('#loader');
	let spinner=l.html(); // Save
	function show() { l.css('z-index',1000).show();hasLoader=true; };
	let o={
	    remove:()=>{
		if(hasLoader) {
		    hasLoader=false;
		    l.hide().css('z-index', -1);
		}
	    },
	    login:(callback)=>{
		cb=callback;
		l.html('<iframe src="login/" width="500" height="700"></iframe>');
		show();
	    },
	    spinner:()=>{
		l.html(spinner);
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
	    startTL();
	};
	return o;
    })();

    // Get list of all known IOs. This call also activates login if an
    // authenticator is installed.
    let data={xedgeconfig:localStorage.getItem("xedge")};
    sendCmd("getionames",(rsp)=>{
	loader.spinner();
	nodisk=rsp.nodisk;
	// Populate the 'ios' variable with all known IOs
	rsp.ios.forEach((name)=>ios[name]=true);
	//Continue initialization after possible login.
	inittree();
	startTL(); // tracelogger can now establish websocket connection.
	sendCmd("lsPlugins",(rsp)=>{
	    for(let i = 0; i < rsp.length; i++)
		$.getScript("private/command.lsp?cmd=getPlugin&name="+encodeURIComponent(rsp[i]));
	});
	$("#IdeCfg").click(ideCfg);
    }, data);
    $( window ).on("beforeunload",function(e) {
	window.localStorage.setItem('left-pane', $('#left-pane').width());
	window.localStorage.setItem('editorpane', $('#editorpane').height());
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
	inittree();
    });
};
