# Cygwin Shell script for fetching the latest jquery, tablesorter, and cookie
# plugin. These 3 files are compressed, concatenated together and put
# in src/core/jquery.js

# Designed for Cygwin.
# Requires wget and JSCompressCL

#Path to: http://www.codeproject.com/csharp/JSCompress.asp
export JSCOMPDIR="c:/tools"

export JQVER=3.7.1

function abort() {
    echo "Aborting installation..."
    sleep 5
    exit 1
}

mkdir tmp
cd tmp
wget https://code.jquery.com/jquery-$JQVER.min.js || abort
wget https://mottie.github.io/tablesorter/dist/js/jquery.tablesorter.min.js || abort
wget --no-check-certificate https://raw.githubusercontent.com/carhartl/jquery-cookie/master/src/jquery.cookie.js || abort
wget https://raw.githubusercontent.com/briceburg/jqModal/master/jqModal.js || abort
wget https://raw.githubusercontent.com/gaarf/jqDnR-touch/master/jqdnr.js || abort
mkdir out
echo "//cat: jquery + jquery.cookie + jquery.tablesorter + jqModal" >a.js
cat a.js >x.js
cat jquery-$JQVER.min.js >> x.js
echo "" >> x.js
cat jquery.cookie.js >> x.js
echo "" >> x.js
cat jquery.tablesorter.min.js >> x.js
echo "" >> x.js
cat jqModal.js >> x.js
echo "" >> x.js
cat jqdnr.js >> x.js

cp x.js ../../src/core/jquery.js
rm *.js
cd ..
rm -rf tmp
