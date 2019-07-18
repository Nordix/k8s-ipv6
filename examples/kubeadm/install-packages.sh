#!/usr/bin/env bash

set -e

# (TODO:arvinder) install k8s deb packages
# https://github.com/kubernetes/kubeadm/blob/master/testing-pre-releases.md#creating-the-kubernetes-cluster-with-kubeadm
# sudo apt install path/to/kubectl.deb path/to/kubeadm.deb path/to/kubelet.deb path/to/kubernetes-cni.deb

if [ "${CGROUP_DRIVER}" == "systemd" ]; then
	echo "using docker cgroup driver: systemd"
	# TODO: modify docker service: https://github.com/openshift/origin/issues/18776
	# Also see corresponding change in kubelet: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#configure-cgroup-driver-used-by-kubelet-on-master-node
fi 