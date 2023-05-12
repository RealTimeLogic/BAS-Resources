var ctxmenuactive;
var wl=window.location;

function hidectxmenu(){};

function diaOnShow(h){
   scroll(0,0);
   var urlT={WebDAVB:'/davdia.txt',SearchB:'/searchdia.txt'};
   var url = h.url ? h.url : urlT[$(h.t).attr("id")];
   if(!url) url='/clipboarddia.txt';
   $.get('/rtl/wfm'+url, function(data) {
      var dw = $(h.t).attr("id") == "SearchB" ? 800 : 600;
      var w=$(document).width();
      var left;
      if(w < dw) {left=0;dw="100%";}
      else left = (w-dw)/2;
      h.w.html(data).css('width',dw).css('left',left).css('top',100);
      var onClose=initDialog(h);
      h.w.fadeIn();
     $('span', h.w).click(function(){
        if(onClose) onClose();
        h.w.jqmHide();
     });
   })
};


function getscript(name,func,absurl,data) {
   $.ajax({
     url: absurl ? name : "/rtl/wfm"+name+".js",
     dataType: 'script',
     data:data,
     success:function(){try { func(); } catch(e) {alert('Error:\n'+e);}},
     error:function(s,e) {if(e) alert('Error: '+s+' : '+e); else alert("Err status: "+s); }
   });
};

function cleanHref(href) {
   var x =/(.+)(\?|#).*/.exec(href);
   if(x) return x[1];
   return href;
};


function reload() {
   setTimeout('window.location.reload();', 10); 
};


function showWait(ev) {
   $('<div id="waiticon"></div>').appendTo('body');
   var sw=function(ev) {
      if(ev && ev.pageX) {
         $("#waiticon").css("left", ev.pageX+10).css("top", ev.pageY-48).show();
      }
   };
   showWait=sw;
   sw(ev);
};

function hideWait(){
   $("#waiticon").hide();
}

function ctxmenu(tr,e) {
   if(window.enableCtxMenu)
      getscript(cleanHref(wl.href),function(){ctxmenu(tr,e);},true,{cmd:"ctxmenu"});
};


var hasAlbum;
$(function(){
   if(!$.cookie('tzone'))
      $.cookie('tzone', '-'+(new Date()).getTimezoneOffset(),{expires:180});
   $("#NewFolderB").click(function(e){mkDir(); e.preventDefault(); });
   $("#UploadB").click(function(e){upload(); e.preventDefault(); });
   $("#NewWindowB").click(function(e){newWindow(); e.preventDefault(); });
   $('<div class="rtlm"></div>').appendTo('body').jqm({
     trigger: '#WebDAVB,#SearchB',
     modal:true,
     onShow:diaOnShow,
     overlay: 80,
     onHide:function(h){h.w.fadeOut(function(){if(h.o) h.o.remove();});}
   });
   $("#fstab tbody tr").click(function(e){ctxmenu(this,e);}).bind("contextmenu",function(e){e.preventDefault();ctxmenu(this,e);});

   function trbg(ae, color) {
      $(ae).parent().parent().css("background",color);
   };

   var qvBusyId;
   var savedEv;
   function hideInfo(rem) {
      var x=$('#qview');
      if(rem) x.remove();
      else x.hide();
   };
   function checkSavedEv() {
      if(qvBusyId) {
         clearTimeout(qvBusyId);
         qvBusyId=null;
      }
      if(savedEv) {
         var e=savedEv;
         savedEv=null;
         showInfo(e);
      }
   };
   function showInfo(e) {
      if(!window.enableCtxMenu) return;
      function _showInfo(e) {
         var showLock=$(e.target).hasClass("lock");
         var t=showLock?$(e.target).next():$(e.target);
         var href=unescape(t.attr("href"));
         var x = /\.(jpg|jpeg|mp3)/i.exec(href.toLowerCase());
         if(x || showLock) {
            hideInfo(true);
            if(qvBusyId) {
               savedEv=e;
               clearTimeout(qvBusyId);
               qvBusyId=setTimeout(checkSavedEv, 500);
               return;
            }
            qvBusyId=setTimeout(checkSavedEv, 500);
            var html='<div style="position:absolute;z-index:100" id="qview">';
            function ins(html) {
               var y=e.pageY-130;
               if(y < 50) y=50;
               else if((y + 300) > $(document).height()) y = $(document).height() - 300;
               html.appendTo('body').css('left',e.pageX+50).css('top',y);
            }
            if(showLock) {
               $.getJSON(cleanHref(wl.href), {cmd:"getlock",name:href}, function(resp) {
                  if(savedEv) checkSavedEv();
                  else {
                     clearTimeout(qvBusyId);
                     qvBusyId=null;
                     if(resp.owner) {
                        var t=(new Date(resp.time*1000)).toString("yyyy MMMM dd, dddd,  h:mm:ss tt");
                        ins($(html+'<p>Locked by '+resp.owner+'. Expires '+t+'</p></div>'));
                     }
                     else
                        reload();
                  }
               });
            }
            else if(x[1] == "mp3") {
               $.getJSON(cleanHref(wl.href), {cmd:"id3tag",name:href}, function(resp) {
                  if(savedEv) checkSavedEv();
                  else {
                     clearTimeout(qvBusyId);
                     qvBusyId=null;
                     var x='<table>';
                     function tr(name) {
                        if(resp[name]) x+='<tr><td>'+(name.charAt(0).toUpperCase() + name.slice(1))+
                                          ': </td><td>'+resp[name]+'</td></tr>';
                     };
                     tr('title');tr('artist');tr('album');tr('year');tr('comment');
                     x+='</table>';
                     html=$(html+x+'</div>');
                     ins(html);
                  }
               });
            }
            else {
                  html=$(html+'<img src="'+cleanHref(wl.href)+'?cmd=qview&name='+href+'"/></div>');
                  ins(html);
                  $('#qview img').load(function() {
                     if($(this).width() == 1) hideInfo(true); // err
                     else if(savedEv) checkSavedEv();
                     else {
                        clearTimeout(qvBusyId);
                        qvBusyId=null;
                     }
                  });
            }
         }
      };
      $.ajax({
	 type: "POST",
	 url: cleanHref(wl.href),
	 data: {cmd:"qview"},
	 error: function(){showInfo=function(){};},
         success: function(data){showInfo=_showInfo;showInfo(e);}
      });
   };
   $("#fstab tr a").click(function(e){
      e.stopImmediatePropagation();}
      ).mouseover(function(e) {
         e.stopImmediatePropagation();
         hidectxmenu();
         showInfo(e);
         trbg(this,"#B6D7EB");
      }).mouseout(function(e) {
         hideInfo();
         e.stopImmediatePropagation();
         trbg(this,"");
      });
   $("#fstab").mouseout(hideInfo);
   $("#fstab tr").mouseover(function(e) {
      if(!ctxmenuactive) $(this).css("background","#FFFF66");
   }).mouseout(function() {
      if(!ctxmenuactive) $(this).css("background","");
   });
   $("#fstab .lock").mouseover(function(e) {
         hidectxmenu();
         showInfo(e);
      }).mouseout(function(e) {
         hideInfo();
      });
   var dropQ;
   var initDrop=function(e) {
      if(!dropQ) {
         dropQ=[];
         $('<div></div>').appendTo('body').load("/rtl/wfm/dragdrop.txt",function(){startDragDrop(dropQ);});
      }
      e.preventDefault();
   };
   var dropstarted=false;
   $('body').bind('dragover',initDrop).bind('drop',function(e) {
      if(dropstarted) return true;
      dropstarted=true;
      var f=e.originalEvent.dataTransfer.files;
      for(k in f) dropQ.push(f[k]);
      e.preventDefault();
   });
   try {
      var ua=window.navigator.userAgent;
      var txt = ua.search(/windows/i) > 0 ? "Map windows drive letter to current directory using a session URL" : "Mount current directory using a WebDAV session URL";
      $("#WebDAVB").attr("title",txt);
   }
   catch(e){}
   try { // fails if empty
      $("table").tablesorter(
      {
	sortList: window.sortList ? window.sortList : [[0,0]],
	widgets: ['zebra'],
	textExtraction: function(node) {  
	   var t;
	   var cn0=node.childNodes[0];
	   if(cn0 && cn0.hasChildNodes()) {
	      t = cn0.innerHTML;
	   }
	   else {
	      if(cn0 && cn0.nodeName == "IMG") t="-1";
	      else t = node.innerHTML;
	   }
	   return t;
	} 
      }).addClass("ctxmcur");
      var doAlbum = function() {
	 if(!hasAlbum) {
            $.ajax({
              url:'/rtl/wfm-album/loading.gif',
              type:'HEAD',
              success: function() {
                 $("<a id='AlbumB' href='#' target='album' title='Photo Album'></a>").appendTo("#menulinks");
                 $("#AlbumB").click(function(e) {
                    window.open('/rtl/wfm-album/?href='+cleanHref(wl.href), "album");
                    $(this).blur();
                    e.preventDefault();
                 });
              }
            });
	 }
	 hasAlbum=true;
      };

      var mp3Elems;
      var mp3=function(el) {
         if(mp3Elems) mp3Elems[mp3Elems.length]=el;
         else {
            mp3Elems=[el];
            getscript('-mp3/insertplayer',function() {
               insertPlayer(mp3Elems);
               mp3Elems=null;
            });
         }
      };

      var action={
	 jpg:doAlbum,
	 jpeg:doAlbum,
	 gif:doAlbum,
	 png:doAlbum,
	 mp3: mp3
      };
      $("tbody a").each(
	 function() {
	 var href=$(this).attr("href");
	 var x = /\.(jpg|jpeg|gif|png|mp3)/i.exec(href);
	 if(x) action[x[1].toLowerCase()](this);
      });
   }
   catch(e) {}
});

function mkDir() {
   var name=prompt('Folder Name:','New Folder');
   if(name) {
      $.ajax({
	 type: "POST",
	 url: cleanHref(wl.href),
	 data: {cmd:"mkdirt",dir:unescape(name)},
	 error: showError,
         success: function(r) {ajaxRsp(r);}
	 });
   }
};

function ajaxRsp(x, ret) {
   if(x && x.err) showError(x);
   else if(!ret) reload();
   return x && x.err;
}

function showError(x) {
   var msg="error";
   hideWait();
   try {
      if(x.err) {
         if(x.emsg) msg=x.emsg;
         else msg=x.err;
      }
      else if(x.status == 403) msg="Permission denied.";
      else msg = "Status: "+x.status + "\n"+x.responseText;
   }
   catch(e) {}
   alert(msg);
   reload();
};


function newWindow() {
   var d = new Date();
   var w = window.open(
      cleanHref(wl.href),
      d.getMilliseconds(),
      "scrollbars=1,toolbar=0,status=0,resizable=1,width=800,height=640");
   if(!w) alert('Your browser is blocking the pop-up window');
};

var uploadF=false;
function upload() {
   var i = "File: <input class='uploadfn' type='file' size='40' name='file' multiple='true'/>"
   var x;
   if(uploadF) {
      var f = "<br/>"+i;
      $(f).insertBefore("#SubmUpload");
   }
   else {
      var extra="";
      try {
         var xhr = new XMLHttpRequest();
         xhr.upload.addEventListener("progress", function(){},false);
         extra="<span style='color:yellow'><b>Note:</b> Drag and drop upload is supported by this browser! Drop your file(s) into the box.</span>";
         $('<img id="dropbox" src="/rtl/wfm/dropbox.png"/>').appendTo('body');
         $('#dropbox').show();
         $('#resources').fadeTo(400,0.1);
      }
      catch(e) {}

      var f = "<div><form method='post' enctype='multipart/form-data'>"+i+
	 "<input id = 'SubmUpload' type='Submit' value='Upload file'/></form>"+
         extra+"</div>";
      $(f).insertAfter("#curdir");
      function checkUpFrm() {
         var ret=true;
         $(".uploadfn").each(function(i){
            if( ! $(this).val() ) {
               reload();
               ret=false;
               return false;
            }
         });
         return ret;
      };
      $("#SubmUpload").click(checkUpFrm);
      uploadF=true;
   }
};
