
function ctxmenu(tr,e) {
   function remove(keepSel) {
      $(document).unbind('click',remove);
      $("#ctxmenu").remove();
      ctxmenuactive=false;
      if(keepSel == true) return;
      $(".softblue").removeClass("softblue");
   };
   hidectxmenu=remove;

   function getName(tr) {return unescape($('a:first',tr).attr('href'));}

   function rm(e,sel) {
      var l=sel.length;
      var x= 'Do you want to delete ' + (l > 1 ? l+' files' : getName(sel.first())) +'?';
      x=confirm(x);
      if(x) {
         showWait(e);
         var i=0;
         var url=cleanHref(wl.href);
         function _rm() {
            $.ajax({
	       type: "POST",
               url: url,
               data: {cmd:"rmt",file:getName(sel[i])},
               error: showError,
               success: function(r) {if(!ajaxRsp(r,++i < l) && i < l) _rm();}
            });
         };
         _rm();
      }
   };

   var action={
      download: function(e,sel){window.location=cleanHref(wl.href)+getName(sel.first())+"?download=";},
      rm:rm
   };

   var lastSelTr;
   var tabrows;

   function _ctxmenu(tr,e) {
      remove(true);
      e.stopPropagation();
      e.preventDefault();
      if(e.shiftKey) {
         var last = tabrows.index(lastSelTr);
         var first = tabrows.index(tr);
         var start = Math.min(first, last);
         var end = Math.max(first, last);
         if(start >=0 && end >= 0)
            tabrows.slice(start,end+1).addClass("softblue");
         $(tr).css("background","");
      }
      else {
         tr=$(tr);
         if(!e.ctrlKey)
            tabrows.removeClass("softblue");
         (e.ctrlKey && tr.hasClass("softblue") ? 
           tr.removeClass("softblue") : tr.addClass("softblue")).css("background","");
      }
      lastSelTr=tr;
      $(document).bind('click',remove);
      var h='<div id="ctxmenu"><ul>';
      var sel=$(".softblue");
      var hasdir=false;
      sel.each(function() {
         if($('img[class|="dir"]',this).length!=0) {
            hasdir=true;
            return false;
         }
      });
      if(!hasdir) {
         if(sel.length == 1)
            h+='<li id="download"><img src="/rtl/wfm/download.gif" /> Download</li>'+
               '<li id="clipboard" href="'+getName(sel.first())+'"><img src="/rtl/wfm/clipboard.png" /> Copy URL</li>';
      }
      h+='<li id="rm"><img src="/rtl/wfm/delete.gif" /> Delete</li></ul></div>';
      $(h).appendTo('body').css('left',e.pageX+10).css('top',e.pageY).show();
      $("#ctxmenu li").click(function() {
         remove(true);
         var a=action[$(this).attr("id")];
         if(a) a(e,sel);
         tabrows.removeClass("softblue");
      });
      $(".rtlm").jqmAddTrigger("#clipboard");
      ctxmenuactive=true;
   };
   tabrows=$(tr).parent().children();
   tabrows.children('td').attr('unselectable', 'on');
   lastSelTr=tr;
   ctxmenu=_ctxmenu;
   _ctxmenu(tr,e);
};
