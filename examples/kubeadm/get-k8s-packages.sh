#!/usr/bin/env bash

set -e

# https://github.com/kubernetes/kubeadm/blob/master/testing-pre-releases.md#creating-the-kubernetes-cluster-with-kubeadm

apt-get update && apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

if [ -n "${INSTALL}" ]; then
    if [ -n "${INSTALL_LOCAL_BUILD}" ]; then
		log "Using local binaries"
		local_kubeadm_build_dir="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/hack/local_builds/k8s/${k8s_version}/_output/local/bin/linux/amd64"
		local_docker_build_dir="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/hack/local_builds/k8s/${k8s_version}/_output/release-images/amd64"

		# copy local binaries and docker images 
		cp $local_kubeadm_build_dir/kubeadm /usr/bin/kubeadm
		cp $local_kubeadm_build_dir/kubelet /usr/bin/kubelet
		cp $local_kubeadm_build_dir/kubectl /usr/bin/kubectl

		array=(kube-apiserver kube-controller-manager kube-scheduler kube-proxy)
		for i in "${array[@]}"; do 
		  sudo docker load -i $local_docker_build_dir/$i.tar
		done
		
		# the base cni binaries are installed as part of the kubelet install. however, these are very old and need to be updated
		# TODO(arvinder): make cni version configurable and support local builds
		download_to "${cache_dir}/cni" "cni-plugins-amd64-v0.7.1.tgz" \
		    "https://github.com/containernetworking/plugins/releases/download/v0.7.1/cni-plugins-amd64-v0.7.1.tgz"
		cp "${cache_dir}/cni/cni-plugins-amd64-v0.7.1.tgz" .
		sudo tar -xvf cni-plugins-amd64-v0.7.1.tgz -C /opt/cni/bin

	else
		# TODO(arvinder): need to test this works...
		for component in kubelet kubectl kube-apiserver kube-controller-manager kube-scheduler kubeadm; do
			download_to "${k8s_cache_dir}" "${component}" "https://dl.k8s.io/release/${k8s_version}/bin/linux/amd64/${component}"
			cp "${k8s_cache_dir}/${component}" .	
		done
	    chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl kubelet kubeadm
    	sudo cp kube-apiserver kube-controller-manager kube-scheduler kubectl kubelet kubeadm /usr/bin/
    fi
fi
