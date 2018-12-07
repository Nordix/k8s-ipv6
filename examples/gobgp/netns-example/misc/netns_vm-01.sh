 #!/bin/sh

# create a bridge 
brctl addbr bgp0_br

# add the namespace
ip netns add ns0

# create a port pair
ip link add veth0 type veth peer name br-veth0

# attach one side to bridge
brctl addif bgp0_br br-veth0 

# attach the other side to namespace
ip link set veth0 netns ns0

# set the ports to up
ip link set dev br-veth0 up
ip netns exec ns0 ip link set dev veth0 up
ip netns exec ns0 ip link set lo up
ip netns exec ns0 ethtool -K  veth0 rx off tx off

# assign IP address & defult route
ip netns exec ns0 ip addr add 10.0.10.2/24 dev veth0
ip netns exec ns0 ip route add default via 10.0.10.1


# bridge gw
ifconfig bgp0_br 10.0.10.1 netmask 255.255.255.0 up

