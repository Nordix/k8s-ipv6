#!/usr/bin/env bash

set -e

GOLANG_TAR_FILE=/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/packages/go1.12.5.linux-amd64.tar.gz
if test -f "$GOLANG_TAR_FILE"; then
    echo "$GOLANG_TAR_FILE exists and will be be installed..."
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf $GOLANG_TAR_FILE
fi

# https://docs.bazel.build/versions/master/install-ubuntu.html
BAZEL_INSTALL_SCRIPT=/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/packages/bazel-0.23.0-installer-linux-x86_64.sh
if test -f "$BAZEL_INSTALL_SCRIPT"; then
    echo "$BAZEL_INSTALL_SCRIPT exists and will be be executed..."
	sudo $BAZEL_INSTALL_SCRIPT
fi

if [[ -f "/var/lib/apt/lists/lock" ]]; then
    sudo rm /var/lib/apt/lists/lock
fi
sudo apt-get update
sudo apt-get -y install ipset ipvsadm sshpass

wget https://raw.githubusercontent.com/johanhaleby/kubetail/master/kubetail
sudo cp kubetail /usr/local/bin
sudo chmod +x /usr/local/bin/kubetail