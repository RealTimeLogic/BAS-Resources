// SHA1 digest login. See BA doc for more information.

$(function() {
    $("#ba_loginbut").click(function() {
        var s=$('form input[name="ba_seed"]');
        var p=$('form input[name="ba_password"]');
        var p2=$('#ba_password2');
        if(!p2.length) p2=p;
        var f=s.parent();
        while(!f.is("form")&&f.length) f=f.parent();
        if(f.length && s.length && p.length)
        {
            var realm=$('form input[name="ba_realm"]').val();
            var hash;
            if(realm) { // Calc HA1: https://realtimelogic.com/ba/doc/en/lua/auth.html
                var spark = new SparkMD5();
                spark.append(utf8Encode($('form input[name="ba_username"]').val()));
                spark.append(':');
                spark.append(utf8Encode(realm));
                spark.append(':');
                spark.append(utf8Encode(p2.val()));
                hash = SHA1.hash(spark.end()+s.val());
            }
            else {
                hash = SHA1.hash(utf8Encode(p2.val())+s.val());
            }
            p.val('').remove();
            s.after('<input type="hidden" name="ba_password" value="'+hash+'">');
            f.submit();
        }
        else
            alert("Invalid form");
        return false;
    });
});

function utf8Encode(s){var cc=String.fromCharCode;s=s.replace(/\r\n/g,"\n");var u="";for(var n=0;n<s.length;n++){var c=s.charCodeAt(n);if(c<128)u+=cc(c);else if((c>127)&&(c<2048)){u+=cc((c>>6)|192);u+=cc((c&63)|128);}else{u+=cc((c>>12)|224);u+=cc(((c>>6)&63)|128);u+=cc((c&63)|128);}}return u;};

SHA1=function(){var C=function(E,D,G,F){switch(E){case 0:return(D&G)^(~D&F);case 1:return D^G^F;case 2:return(D&G)^(D&F)^(G&F);case 3:return D^G^F}},B=function(D,E){return(D<<E)|(D>>>(32-E))},A=function(G){var F="",D,E;for(E=7;E>=0;E--){D=(G>>>(E*4))&15;F+=D.toString(16)}return F};return{hash:function(F){F+=String.fromCharCode(128);var I=[1518500249,1859775393,2400959708,3395469782],U=Math.ceil(F.length/4)+2,G=Math.ceil(U/16),H=new Array(G),X=0,Q=1732584193,P=4023233417,O=2562383102,L=271733878,J=3285377520,D=new Array(80),h,g,f,Z,Y,R,V;for(;X<G;X++){H[X]=new Array(16);for(V=0;V<16;V++){H[X][V]=(F.charCodeAt(X*64+V*4)<<24)|(F.charCodeAt(X*64+V*4+1)<<16)|(F.charCodeAt(X*64+V*4+2)<<8)|(F.charCodeAt(X*64+V*4+3))}}H[G-1][14]=((F.length-1)*8)/Math.pow(2,32);H[G-1][14]=Math.floor(H[G-1][14]);H[G-1][15]=((F.length-1)*8)&4294967295;for(X=0;X<G;X++){for(R=0;R<16;R++){D[R]=H[X][R]}for(R=16;R<80;R++){D[R]=B(D[R-3]^D[R-8]^D[R-14]^D[R-16],1)}h=Q;g=P;f=O;Z=L;Y=J;for(R=0;R<80;R++){var S=Math.floor(R/20),E=(B(h,5)+C(S,g,f,Z)+Y+I[S]+D[R])&4294967295;Y=Z;Z=f;f=B(g,30);g=h;h=E}Q=(Q+h)&4294967295;P=(P+g)&4294967295;O=(O+f)&4294967295;L=(L+Z)&4294967295;J=(J+Y)&4294967295}return A(Q)+A(P)+A(O)+A(L)+A(J)}}}();

