#!/usr/bin/env bash
set -e
mkdir gobgp_v1.33
cd gobgp_v1.33
wget https://github.com/osrg/gobgp/releases/download/v1.33/gobgp_1.33_linux_amd64.tar.gz
tar xvf gobgp_1.33_linux_amd64.tar.gz
cp gobgp /usr/local/bin
cp gobgpd /usr/local/bin
