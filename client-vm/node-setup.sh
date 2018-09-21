#!/usr/bin/env bash
set -e
export 'IPV6_GATEWAY'="CC00::1"

ip -6 r a default via "${IPV6_GATEWAY}" dev enp0s9 || true

sysctl -w net.ipv6.conf.all.forwarding=1


# Install packages
apt install conntrack # required by kube-proxy