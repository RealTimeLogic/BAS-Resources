<?lsp
local hasUserDb,sso=xedge.hasUserDb()

------------------------------------------------------------
local function doIdErr(secretErr)
?>
<div class="center">
   <div class="alert"><p>Login failed: <?lsp=secretErr?></p></div>
   <form method="post" class="form" style="width:100%;">
     <div class="frow">
      <input name="secret" type="text" placeholder="Enter new client secret value" />
     </div>
     <div class="frow"><input type="submit" value="Save"/></div>
   </form>
</div>
<?lsp
end

------------------------------------------------------------
local function emitLogin(err,ssoErrCodes)
   local secretErr
   if ssoErrCodes then
      -- https://learn.microsoft.com/en-us/entra/identity-platform/reference-error-codes
      local idErrs={
	 [7000215]="The client secret key is invalid/unknown",
	 [7000222]="The client secret key has expired"
      }
      for _,code in ipairs(ssoErrCodes) do
	 secretErr=idErrs[code]
	 if secretErr then doIdErr(secretErr) return end
      end
   end
?>
<div class="center">
  <?lsp if err then ?>
   <div class="alert"><p>Login failed: <?lsp=err?></p></div>
  <?lsp end if hasUserDb and not ssoErrCodes then ?>
   <form method="post" class="form" style="width:100%;">
     <input type="hidden" name="locallogin"/>
     <div class="frow">
      <input name="username" type="text" placeholder="Enter your username" />
     </div>
     <div class="frow">
      <input id="password" name="password" type="password" placeholder="Enter your password"/>
     </div>
     <div class="frow"><input type="submit" value="Sign in"/></div>
   </form>
  <?lsp
  end
  if hasUserDb and sso and not ssoErrCodes then response:write'<div class="or">- OR -</div>' end
  if sso then
  ?>
<button id="sso" type="submit">
   <div class="frow">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 23 23"><path fill="#252526" d="M0 0h23v23H0z"/><path fill="#f35325" d="M1 1h10v10H1z"/><path fill="#81bc06" d="M12 1h10v10H12z"/><path fill="#05a6f0" d="M1 12h10v10H1z"/><path fill="#ffba08" d="M12 12h10v10H12z"/></svg>
<span>Sign in with Microsoft</span>
   </div>
</button>
  <?lsp end ?>
</div>
<?lsp
end


------------------------------------------------------------
local function emitOK()
   response:write'<script>authenticated();</script>'
end

------------------------------------------------------------

if not xedge.authenticator then
   emitOK()
   return
end

local data=request:data()
local trim=xedge.trim
for k,v in pairs(data) do data[k]=trim(v) end

local action
if request:method() == "POST" then
   local function tooMany() emitLogin("Too many authenticated users") end
   if data.secret then
      if xedge.ssoSetSecret(data.secret) then
	 action=function() emitLogin(nil,{}) end
      else
	 action=function() doIdErr("Invalid secret") end
      end
   elseif data.locallogin then
      if hasUserDb then
	 local uname,pwd=data.username,data.password
	 local ha1,maxusers,recycle=xedge.authuser:getpwd(uname)
	 if ha1 and ha1 == xedge.ha1(uname,pwd) then
	    if request:login(uname,maxusers,recycle) then
	       request:session().xadmin=true
	       action=emitOK
	    else
	       action = tooMany
	    end
	 else
	    action = function() emitLogin"Invalid credentials" end
	 end
      else
	 action=emitOK -- fail
      end
   elseif sso then -- SSO resp and we have sso
      local header,payload,ecodes = sso.login(request)
      if header then
	 if request:login(payload.preferred_username,2,false) then
	    request:session().xadmin=true
	    action = function() emitOK(payload) end
	 else
	    action = tooMany
	 end
      else
	 action = function() emitLogin(payload,ecodes or {}) end -- Payload is now 'err'
      end
   else
      action=emitOK -- fail
   end
else
   if request:user() then
      action=(hasUserDb or sso) and not request:session().xadmin and emitLogin or emitOK
   elseif data.sso and sso then
      sso.sendredirect(request)
   elseif hasUserDb or sso then
      action=emitLogin
   else
      action=emitOK -- fail
   end
end
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <title>Xedge</title>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <link rel="stylesheet" href="../assets/xedge.css"/>
<style>
.login-frame h2 {font: normal bold 20px/30px sans-serif; text-align: center; padding: 10px; color: #FFF; }
.center {display: flex;justify-content: center;align-items: center;flex-direction:column-reverse;height: calc(100vh - 30px - 20px);grid-gap:10px;}
#sso {width:220px;padding:10px 12px;box-shadow: 0px 0px 7px;background: #000;font-size: 15px;line-height: 23px;}
#sso:hover {background: #2F2F2F;}
#sso .frow{gap: 12px; margin: 0;}
#sso svg {max-height:20px}
</style>
<script src="../jquery.js"></script>
<script>
function authenticated() {
  if(window.opener) {
    if(window.opener.authenticated) {
      try {window.opener.authenticated();}
      catch(e) {}
    }
    window.close();
  }
  else if(window.top && window.top.login)
    window.top.login();
  else
    location.href="../";
};
$(function(){
  let w=null;
  $("#sso").click(function() {
    if(w) return;
    let width = 500;
    let height = 600;
    let left = (screen.width / 2) - (width / 2);
    let top = (screen.height / 2) - (height / 2);
    let options = 'toolbar=no, location=no, directories=no, status=no, menubar=no, scrollbars=yes, resizable=yes, copyhistory=no, ' +
      'width=' + width + ', height=' + height + ', top=' + top + ', left=' + left;
    w=window.open("./?sso=", 'Sign in with Microsoft', options);
    let i = setInterval(function() {
      if(w.closed) {
	clearInterval(i);
	w=null;
	window.top.location.reload();
      }
    },1000);
  });
});
</script>
</head>
<body class="login-frame">
<h2>Login</h2>
<?lsp action() ?>
</body>
</html>
