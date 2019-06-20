#!/usr/bin/env bash

set -e

dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

source "${dir}/helpers.sh"
source "${dir}/get-k8s-packages.sh"

mkdir -p /home/vagrant/config/

cat <<EOF > /home/vagrant/config/kubeadm-config.yaml
kind: InitConfiguration
apiVersion: kubeadm.k8s.io/v1beta2
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: ${KUBEADM_TOKEN}
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
localAPIEndpoint:
  advertiseAddress: ${controllers_ips[1]}
  bindPort: 6443
nodeRegistration:
  criSocket: /var/run/dockershim.sock
  name: ${VM_BASENAME}1
  taints:
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
EOF
if [ -n "${DUAL_STACK}" ]; then
cat <<EOF >> /home/vagrant/config/kubeadm-config.yaml
  kubeletExtraArgs:
    feature-gates: ${FEATURE_GATES_DS_KEY}=${FEATURE_GATES_DS_VAL}
EOF
fi
cat <<EOF >> /home/vagrant/config/kubeadm-config.yaml
---
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta2
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: /var/lib/etcd
kubernetesVersion: ${k8s_version}
networking:
  dnsDomain: cluster.local
  podSubnet: ${k8s_cluster_cidr}
  serviceSubnet: ${k8s_service_cluster_ip_range}
apiServer:
  timeoutForControlPlane: 4m0s
  extraArgs:
    authorization-mode: Node,RBAC
EOF
if [ -n "${DUAL_STACK}" ]; then
	cat <<EOF >> /home/vagrant/config/kubeadm-config.yaml
    feature-gates: ${FEATURE_GATES_DS_KEY}=${FEATURE_GATES_DS_VAL}
controllerManager:
  extraArgs:
    feature-gates: ${FEATURE_GATES_DS_KEY}=${FEATURE_GATES_DS_VAL}
scheduler:
  extraArgs:
    feature-gates: ${FEATURE_GATES_DS_KEY}=${FEATURE_GATES_DS_VAL}
---
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
featureGates:
  ${FEATURE_GATES_DS_KEY}: ${FEATURE_GATES_DS_VAL}
EOF
else
cat <<EOF >> /home/vagrant/config/kubeadm-config.yaml
controllerManager: {}
scheduler: {}
EOF
fi

# featureGates:
#   IPv6DualStack: true


if [ ! -f "/home/home/vagrant/config/kubadm-init-done" ]; then
  echo "Initiate kubeadm using token $KUBEADM_TOKEN"
  sudo kubeadm init --ignore-preflight-errors=ImagePull --config="/home/vagrant/config/kubeadm-config.yaml" | tee /home/vagrant/config/init.out
  touch "/home/vagrant/config/kubadm-init-done"
fi

# if [ ! -f "/home/home/vagrant/config/kubadm-init-done" ]; then
#   echo "Initiate kubeadm using token $KUBEADM_TOKEN"
#   sudo kubeadm init \
# --kubernetes-version "${k8s_version}" \
# --apiserver-advertise-address="${controllers_ips[1]}" \
# --pod-network-cidr="${k8s_cluster_cidr}" \
# --service-cidr="${k8s_service_cluster_ip_range}" \
# --node-name="${VM_BASENAME}1" \
# --token="${KUBEADM_TOKEN}" | tee /home/vagrant/config/init.out
#   touch "/home/vagrant/config/kubadm-init-done"
# fi
# --feature-gates="${FEATURE_GATES_DS_KEY}=${FEATURE_GATES_DS_VAL}" \

mkdir -p /home/vagrant/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

# by default, master does not schedule pods. we remove this limit:
# https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/#control-plane-node-isolation
# kubectl taint nodes --all node-role.kubernetes.io/master-
