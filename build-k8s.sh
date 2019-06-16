#!/usr/bin/env bash

export LOCAL_K8S_REPO=${LOCAL_K8S_REPO:-"/home/awander/go/src/github.com/khenidak/kubernetes/"}

# Build everything
if [ -z "${SKIP_BUILD}" ]; then
	cwd=$(pwd)
	cd $LOCAL_K8S_REPO
	make kubeadm kubectl kubelet
	make quick-release-images
	cd $cwd
fi

# Extract the k8s version:
export K8S_VERSION=$("${LOCAL_K8S_REPO}_output/bin/kubeadm" version | sed -n -e 's/^.*GitVersion://p' | sed 's/[^"]*"\([^"]*\)".*/\1/')
echo "Using local K8s verion: "$K8S_VERSION

# Create directory in vagrant repo and copy binaries/images:
vagrant_bin_path="/home/awander/go/src/github.com/Nordix/k8s-ipv6/hack/local_builds/k8s/${K8S_VERSION}"
rm -rf $vagrant_bin_path
mkdir $vagrant_bin_path
cp -r "${LOCAL_K8S_REPO}_output" $vagrant_bin_path 