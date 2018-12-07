#!/usr/bin/env bash
set -e
apt-get -y install quagga quagga-doc
touch /etc/quagga/zebra.conf
chown quagga.quaggavty /etc/quagga/*.conf
chmod 640 /etc/quagga/*.conf
# sed -i s'/zebra=no/zebra=yes/' /etc/quagga/daemons
# /etc/init.d/quagga start
