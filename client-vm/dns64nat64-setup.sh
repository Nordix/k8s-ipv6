#!/usr/bin/env bash
set -e

# Jool (NAT64)
# Install Kernel Modules:
# Reference: https://www.jool.mx/en/install-mod.html
git clone https://github.com/NICMx/Jool.git
dkms install Jool
# Install User Modules:
apt install -y gcc make pkg-config libnl-genl-3-dev autoconf
cd Jool/usr
./autogen.sh
./configure
make
make install
# leaving NAT64 translation disabled while configuring Jool:
/sbin/modprobe jool pool6=64:ff9b::/96 disabled
# Set the pool4 range to use 10.0.2.15 7000-8000:
# NOTE: Don't use 5000-6000 on VirtualBox setup
jool -4 --add 10.0.2.15 7000-8000
# Check pools
jool -4 -d
jool -6 -d
# enable jool translation:
jool --enable
# Check status
jool -d

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
        listen-on-v6 { any; };
        allow-query { any; };

        // Add prefix for Jool's pool6
        dns64 64:ff9b::/96 {
        	exclude { any; };
        };
};
EOF
service bind9 restart
systemctl status bind9
