<!DOCTYPE html>
<html lang="en">
<head>
  <title>Xedge</title>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <link rel="icon" type="image/x-icon" href="assets/favicon.ico"/>
  <link rel="stylesheet" href="assets/tree.css">
  <link rel="stylesheet" href="assets/xedge.css"/>
  <script src="jquery.js"></script>
  <script src="assets/tree.js"></script> 
  <script src="https://cdnjs.cloudflare.com/ajax/libs/split.js/1.6.0/split.min.js"></script>
  <script src="assets/xedge.js"></script>
</head>
<body>
<?lsp response:include"assets/loader.html" ?>
  <div id="container">
    <div id="TreeDia"></div>
    <div id="left-pane">
      <div id="TreeCont"></div>
    </div>
    <div id="right-pane">
      <div id="editorpane">
	<div id="tabheader"><div id="IdeCfg" class="menuicon"></div></div>
	<div id="editors"></div>
      </div>
      <div id="logpane">
	<iframe id="tracelogger" src="tracelogger/?embedded="></iframe>
      </div>
    </div>
  </div>
  <audio id="sound-error"><source src="https://simplemq.com/WeatherApp/sound/error.mp3" type="audio/mp3" /></audio>
</body>
</html>
