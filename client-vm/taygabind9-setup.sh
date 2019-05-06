ipv6_addr=$(echo "${1}" | awk -F'/' '{print $1}') # remove netmask if present
containerize=${2}

# Instructions: http://www.litech.org/tayga/README-0.9.2
wget http://www.litech.org/tayga/tayga-0.9.2.tar.bz2
tar xvf tayga-0.9.2.tar.bz2 
cd tayga-0.9.2/
./configure && make && make install
mkdir -p /var/db/tayga

sudo tee /usr/local/etc/tayga.conf <<EOF
tun-device nat64
#
# TAYGA's IPv4 address.  This is NOT your router's IPv4 address!  TAYGA
# requires its own address because it acts as an IPv4 and IPv6 router, and
# needs to be able to send ICMP messages.  TAYGA will also respond to ICMP
# echo requests (ping) at this address.
#
# This address can safely be located inside the dynamic-pool prefix.
#
# Mandatory.
#
#ipv4-addr 192.168.255.1
#ipv4-addr 10.0.2.200
ipv4-addr 172.29.7.240

#
# TAYGA's IPv6 address.  This is NOT your router's IPv6 address!  TAYGA
# requires its own address because it acts as an IPv4 and IPv6 router, and
# needs to be able to send ICMP messages.  TAYGA will also respond to ICMP
# echo requests (ping6) at this address.
#
# You can leave ipv6-addr unspecified and TAYGA will construct its IPv6
# address using ipv4-addr and the NAT64 prefix.
#
# Optional if the NAT64 prefix is specified, otherwise mandatory.  It is also
# mandatory if the NAT64 prefix is 64:ff9b::/96 and ipv4-addr is a private
# (RFC1918) address.
# 
#ipv6-addr 2001:db8:1::2
#ipv6-addr ${ipv6_addr}
ipv6-addr cc00::3

#
# The NAT64 prefix.  The IPv4 address space is mapped into the IPv6 address
# space by prepending this prefix to the IPv4 address.  Using a /96 prefix is
# recommended in most situations, but all lengths specified in RFC 6052 are
# supported.
#
# This must be a prefix selected from your organization's IPv6 address space
# or the Well-Known Prefix 64:ff9b::/96.  Note that using the Well-Known
# Prefix will prohibit IPv6 hosts from contacting IPv4 hosts that have private
# (RFC1918) addresses, per RFC 6052.
#
# The NAT64 prefix need not be specified if all required address mappings are
# listed in map directives.  (See below.)
#
# Optional.
#
#prefix 2001:db8:1:ffff::/96
prefix 64:ff9b::/96

#
# Dynamic pool prefix.  IPv6 hosts which send traffic through TAYGA (and do
# not correspond to a static map or an IPv4-translatable address in the NAT64
# prefix) will be assigned an IPv4 address from the dynamic pool.  Dynamic
# maps are valid for 124 minutes after the last matching packet is seen.
#
# If no unassigned addresses remain in the dynamic pool (or no dynamic pool is
# configured), packets from unknown IPv6 hosts will be rejected with an ICMP
# unreachable error.
#
# Optional.
#
#dynamic-pool 192.168.255.0/24
#dynamic-pool 10.0.2.0/24
dynamic-pool 172.29.7.0/24

#
# Persistent data storage directory.  The dynamic.map file, which saves the
# dynamic maps that are created from dynamic-pool, is stored in this 
# directory.  Omit if you do not need these maps to be persistent between
# instances of TAYGA.
#
# Optional.
#
data-dir /var/db/tayga

#
# Establishes a single-host map.  If an IPv6 host should be consistently
# reachable at a specific IPv4 address, the mapping can be specified in a
# map directive.  (IPv6 hosts numbered with an IPv4-translatable address do
# not need map directives.)
#
# IPv4 addresses specified in the map directive can safely be located inside
# the dynamic-pool prefix.
#
# Optional.
#
#map 192.168.5.42 2001:db8:1:4444::1
#map 192.168.5.43 2001:db8:1:4444::2
#map 192.168.255.2 2001:db8:1:569::143

EOF

tayga --mktun

ip link set nat64 up

ip addr add cc00::2 dev nat64  # replace with your router's address
ip addr add 2600:1700:d610:1cf0::/64  dev nat64


ip addr add 10.0.2.15 dev nat64    # replace with your router's address
	ip addr del 10.0.2.15 dev nat64

ip route add 64:ff9b::/96 dev nat64
	ip route del 64:ff9b::/96 dev nat64 

ip route add 10.0.2.0/24 dev nat64 
	ip route del 10.0.2.0/24 dev nat64 

ip route add 192.168.255.0/24 dev nat64 
	ip route del 192.168.255.0/24 dev nat64 

ip addr add 192.168.255.1 dev nat64
	ip addr del 192.168.255.1 dev nat64


# vm-01
ip addr add 2600:1700:d610:1cf0:ffff:ffff::2 dev enp0s9
ip r a 2600:1700:d610:1cf0:ffff:ffff::/96 dev enp0s9 
ip r a default via 2600:1700:d610:1cf0:ffff:ffff::1 dev enp0s9
# host
ip route add 2600:1700:d610:1cf0:ffff:ffff::/96 dev vboxnet0
ip addr add 2600:1700:d610:1cf0:ffff:ffff::1 dev vboxnet0

ip addr add 2600:1700:d610:1cf0:ffff:ffff:0:1 dev wlp59s0


tayga -d




# BIND9 for DNS64
apt install -y bind9
# Config setup:
mv /etc/bind/named.conf.options /etc/bind/named.conf.options.ORIG
cat <<EOF > "/etc/bind/named.conf.options"
options {
        directory "/var/cache/bind";

        // If there is a firewall between you and nameservers you want
        // to talk to, you may need to fix the firewall to allow multiple
        // ports to talk.  See http://www.kb.cert.org/vuls/id/800113

        // If your ISP provided one or more IP addresses for stable
        // nameservers, you probably want to use them as forwarders.
        // Uncomment the following block, and insert the addresses replacing
        // the all-0's placeholder.
        forwarders {
        	8.8.8.8;
        };

        //=
        // If BIND logs error messages about the root key being expired,
        // you will need to update your keys.  See https://www.isc.org/bind-keys
        //=
        //dnssec-validation auto;

        auth-nxdomain no;    # conform to RFC1035
        listen-on { any; };
        listen-on-v6 { any; };
        allow-query { any; };

        // Add prefix for Jool's pool6
        dns64 64:ff9b::/96 {
        	clients { any; };
        	exclude { any; };
        };
};
EOF
service bind9 restart
systemctl status bind9