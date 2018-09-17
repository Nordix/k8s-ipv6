#!/usr/bin/env bash

# Use of IPv6 'documentation block' to provide example
# ip -6 a a FD01::0B/16 dev enp0s8

sysctl -w net.ipv6.conf.all.forwarding=1
