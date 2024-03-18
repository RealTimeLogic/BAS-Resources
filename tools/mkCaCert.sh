

# Creates rtl/.certificate/cacert.shark from curl's cacert.pem

wget https://curl.se/ca/cacert.pem

linux/SharkSSLParseCAList -b ../src/core/.certificate/cacert.shark cacert.pem
rm -f cacert.pem
