#!/usr/bin/env bash

set -e

dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

source "${dir}/helpers.sh"
source "${dir}/get-k8s-packages.sh"

mkdir -p /vagrant/config/

if [[ -n "${IPV6_EXT}" ]]; then
	if [ ! -f "/vagrant/config/kubadm-join-${self_name}-done" ]; then
		echo "Running kubeadm join (IPv6 addressing)"
		sudo kubeadm join "[${master_ip}]":6443 --token "${KUBEADM_TOKEN}" --discovery-token-unsafe-skip-ca-verification
		touch "/vagrant/config/kubadm-join-${self_name}-done"
	fi
else
	if [ ! -f "/vagrant/config/kubadm-join-${self_name}-done" ]; then
		echo "Running kubeadm join (IPv4 addressing)"
		sudo kubeadm join "${master_ip}":6443 --token "${KUBEADM_TOKEN}" --discovery-token-unsafe-skip-ca-verification
		touch "/vagrant/config/kubadm-join-${self_name}-done"
	fi
fi

# since we have multiple interfaces, we need to tell kubelet to use the correct one
# https://github.com/kubernetes/kubeadm/issues/203
echo "KUBELET_EXTRA_ARGS=--node-ip=${node_ip}" > /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# arvinder: kubeconfig is needed by kube-router and kubectl 
mkdir -p /home/vagrant/.kube
sshpass -p "vagrant" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no vagrant@k8s1:~/.kube/config /home/vagrant/.kube
sudo chown vagrant:vagrant /home/vagrant/.kube/config
