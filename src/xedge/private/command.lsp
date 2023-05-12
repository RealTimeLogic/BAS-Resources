<?lsp
if not request:header"x-requested-with" then response:senderror(404) return end
xedge.command(request)
?>
