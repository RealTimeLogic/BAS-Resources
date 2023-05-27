<?lsp

local sso=xedge.sso
local hasUserDb=xedge.hasUserDb()

------------------------------------------------------------
local function emitLogin(err)
?>
<div class="center">
  <?lsp if err then ?>
   <div class="alert"><p>Login failed: <?lsp=err?></p></div>
  <?lsp end if hasUserDb then ?>
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
  if hasUserDb and sso then response:write'<div class="or">- OR -</div>' end
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

local action
if request:method() == "POST" then
   local function tooMany() emitLogin("Too many authenticated users") end
   if data.locallogin then
      if hasUserDb then
	 local username=xedge.trim(data.username)
	 local ha1,maxusers,recycle=xedge.authuser:getpwd(username)
	 if ha1 and ha1 == xedge.ha1(username,xedge.trim(data.password)) then
	    if request:login(username,maxusers,recycle) then
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
      local header,payload = sso.login(request)
      if header then
	 if request:login(payload.preferred_username,2,false) then
            action = function() emitOK(payload) end
         else
            action = tooMany
         end
      else
	 action = function() emitLogin(payload) end -- Payload is now 'err'
      end
   else
      action=emitOK -- fail
   end
else
   if request:user() then
      action=emitOK
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
	if(window.opener.authenticated)
	    window.opener.authenticated();
	window.close();
    }
    else if(window.top && window.top.login)
	window.top.login();
    else
	location.href="../";
};
$(function(){
   $("#sso").click(function() {
	let width = 500;
	let height = 600;
	let left = (screen.width / 2) - (width / 2);
	let top = (screen.height / 2) - (height / 2);
	let options = 'toolbar=no, location=no, directories=no, status=no, menubar=no, scrollbars=yes, resizable=yes, copyhistory=no, ' +
	    'width=' + width + ', height=' + height + ', top=' + top + ', left=' + left;
	window.open("./?sso=", 'Sign in with Microsoft', options);
   });
});
</script>
</head>
<body class="login-frame">
<h2>Login</h2>
<?lsp action() ?>
</body>
</html>
