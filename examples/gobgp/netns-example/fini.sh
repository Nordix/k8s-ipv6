#!/bin/sh

misc/netns_clean.sh
rm -f /var/run/quagga/*
pkill zebra
pkill gobgpd
