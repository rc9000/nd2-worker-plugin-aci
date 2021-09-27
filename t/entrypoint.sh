#!/bin/ash

apk update
apk upgrade
apk add apk-tools 
apk add wget 
apk add make 
apk add perl-json-xs 
apk add perl-lwp-protocol-https
apk add perl-file-slurp
apk add perl-test-harness
apk add perl-regexp-common
apk add perl-test-harness
apk add perl-utils

curl -L https://cpanmin.us | perl - App::cpanminus

$CPANM -n JSON URL::Encode App::Prove REST::Client

echo PERLLIB=$PERLLIB

echo "------ prove------"
echo 
echo 

cd /nd2-worker-plugin-aci/ 
prove -v t/[0-9]*


echo
echo
echo "here's a shell in the testing container if you want to rerun stuff:"
echo
ash


