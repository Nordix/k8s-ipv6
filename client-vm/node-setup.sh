#!/usr/bin/env bash
set -e
export 'IPV6_GATEWAY'="CC00::1"

ip -6 r a default via "${IPV6_GATEWAY}" dev enp0s9 || true

sysctl -w net.ipv6.conf.all.forwarding=1

apt update
apt install -y build-essential linux-headers-$(uname -r) dkms

# Install misc packages
apt install -y conntrack # required by kube-proxy
apt install -y ipset
apt install -y bridge-utils