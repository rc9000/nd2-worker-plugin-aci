#!/bin/bash

docker run --rm -it \
    -e "PERLLIB=/nd2-worker-plugin-aci/lib:/home/netdisco/perl5/lib/perl5" \
    -e "JDIR=/nd2-worker-plugin-aci/t/testdata" \
    -e "CPANM=/home/netdisco/perl5/bin/cpanm" \
    --mount type=bind,source="$PWD/..",target=/nd2-worker-plugin-aci -u root \
    --entrypoint /nd2-worker-plugin-aci/t/entrypoint.sh  \
    netdisco/netdisco:latest-backend 

