#!/usr/bin/env bash

set -e

dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

source "${dir}/helpers.sh"
source "${dir}/get-k8s-packages.sh"

mkdir -p /vagrant/config/

if [ ! -f "/vagrant/config/kubadm-init-done" ]; then
  echo "Initiate kubeadm using token $KUBEADM_TOKEN"
  sudo kubeadm init \
--apiserver-advertise-address="${controllers_ips[1]}" \
--pod-network-cidr="${k8s_cluster_cidr}" \
--service-cidr="${k8s_service_cluster_ip_range}" \
--node-name="${VM_BASENAME}1" \
--token="${KUBEADM_TOKEN}" | tee /vagrant/config/init.out
  touch "/vagrant/config/kubadm-init-done"
fi
# --kubernetes-version "${k8s_version}" \

mkdir -p /home/vagrant/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

# by default, master does not schedule pods. we remove this limit:
# https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/#control-plane-node-isolation
# kubectl taint nodes --all node-role.kubernetes.io/master-
