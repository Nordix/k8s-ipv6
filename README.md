# k8s-ipv6: Vagrant Based Kubernetes IPv6 Cluster

This project serves two primary purposes: (i) study and validate ipv6 support in kubernetes and associated plugins (ii) provide a dev environment for implementing and testing additional functionality (e.g.dual-stack)

## Getting Started

You will need to have virtualbox and vagrant installed. 

    mkdir -p ~/go/src/github.com/Nordix
    cd ~/go/src/github.com/Nordix
    git clone https://github.com/Nordix/k8s-ipv6.git
    cd k8s-ipv6

## Creating a K8s Cluster

There are two ways to setup the cluster -- start individual components manaully (cilium approach) or use kubeadm. Kubeadm is the default option; however, you can set env var ENABLE_KUBEKDM == "false" to disable it. The current focus of this project is on IPv6 support for calico, kube-router and the CNCF cni plugins -- bridge and host-local. 

## Calico

Calico can be installed via systemd (default) or as a privileged pod. The current release is set to v3.7.1 but this can be changed. Additionally, since this is meant as a dev environment, it is assumed that the following calico repos have been cloned locally and the binaries/docker-images pre-built:
    
    1. CNI-Plugin
    2. Calico/Node 
    3. Calico-kube-controllers
    4. Calicoctl

The current approach sets up a local etcd cluster on master (k8s1) instead of using the kubernetes etcd cluster.
For the IPAM, the calico-ipam is utilized. However, switching to host-local is also possible. 

### IPv6 Cluster Using Calico
    
As with the kube-router IPv6 approach (discussed below), you will first need to provision a DNS64/NAT64 VM; followed by the k8s cluster:

    DNS64NAT64=1 vagrant up
    CNI=calico NWORKERS=2 IPV4=0 GOBGP=1 DNS64_IPV6=CC00::2 INSTALL_LOCAL_BUILD=1 K8S_VERSION=v1.13.0 K8S=1 ./start.sh

### IPv4 Cluster Using Calico

    CNI=calico NWORKERS=2 IPV4=1 GOBGP=1 INSTALL_LOCAL_BUILD=1 K8S_VERSION=v1.13.0 K8S=1 ./start.sh

### Calico Dual-Stack (work in progress)

Calico dual-stack is possible eventhough k8s itself will only see one of the addresses. The current setup assumes a dual-stack host/VM and uses the calico-ipam to assign both ipv4 and ipv6 addresses to pods. To choose between IPv4 and IPv6, calico supports annotations on pods to pick which pool the address should come from.

To try out dual stack, you will have to edit the func write_cni_calico_cfg in start.sh with the following:
        "assign_ipv4": "true",
        "assign_ipv6": "true"

After bringing up the cluster, create a busybox pod and after doing so, you should see that both an IPv4 and an IPv6 address have been assigned:

    kubectl run -i --tty bb1 --image=busybox -- sh
    # ifconfig 
    eth0  
          inet addr:192.168.219.0  Bcast:0.0.0.0  Mask:255.255.255.255
          inet6 addr: fd02::c0a8:2108:7fc:db00/128 Scope:Global

## Kube-Router

### IPv6 Cluster Using Kube-Router

By default, start.sh will look for the kube-router binary in this location. You will need to ensure the kube-router binary exists here or modify this path to the correct location. 

    /home/vagrant/go/src/github.com/cloudnativelabs/kube-router/cmd/kube-router/
    
Additionally, you'll have to create a NAT64/DNS64 VM (vm-01) external to the cluster before actually creating the k8 cluster:
    
    cd client-vm/
    DNS64NAT64=1 vagrant up

We can create our cluster with the following command:

     GOBGP=1 DNS64_IPV6=CC00::2 INSTALL_LOCAL_BUILD=1 K8S_VERSION=v1.13.0 IPV4=0 K8S=1 NWORKERS=1 ./start.sh

Note that we specify the address of the DNS translation server above with DNS64_IPV6=CC00::2. 

Custom kube-router configurations can be passed via CNI_ARGS. In the example below, we are only using kube-router for pod-to-pod connectivity (--run-router=true). 

    CNI_ARGS="--v=3 --kubeconfig=/home/vagrant/.kube/config --run-firewall=false --run-service-proxy=false --run-router=true  --advertise-cluster-ip=true --routes-sync-period=10s" CNI=kube-router GOBGP=1 DNS64_IPV6=CC00::2 INSTALL_LOCAL_BUILD=1 K8S_VERSION=v1.13.0 IPV4=0 K8S=1 NWORKERS=1 ./start.sh

Provisioning is a lot faster if you precompile the k8s binaries (INSTALL_LOCAL_BUILD=1). See the section below on how to do build k8 localy. If we leave out INSTALL_LOCAL_BUILD binaies will be downloaded from the appropriate k8 release location.

The following routes will be required on the host/laptop. Note that the assumption is that vm-01 is on vboxnet0 and k8s VMs are on vboxnet1. Addtionally, vm-01 is on the cc00:: subnet:

    sudo ip r a cc00::/16 dev vboxnet0
    sudo ip a a cc00::1 dev vboxnet0
    sudo ip a a fd00::1 dev vboxnet1
    sudo ip r a fd00::/16 dev vboxnet1
    sudo ip r a 64:ff9b::/96 via cc00:: dev vboxnet0

We can also add routes to access the pods directly. This is optional: 

    sudo ip r a fd02::c0a8:2108:0:0/96 via fd00:: dev vboxnet1 
    sudo ip r a fd02::c0a8:2109:0:0/96 via fd00:: dev vboxnet1

### IPv6 Cluster Using Bridge and Manual Routing
    
    GOBGP=1 DNS64_IPV6=CC00::2 K8S_VERSION=v1.13.0 IPV4=0 K8S=1 NWORKERS=1 ./start.sh

### IPv4 Cluster Using Kube-Router

    INSTALL_LOCAL_BUILD=1 K8S_VERSION=v1.13.0 IPV4=1 K8S=1 NWORKERS=1 ./start.sh

Note that IPV4=1 enables IPv4 addressing.

As above, we can use CNI_ARGS to pass custom kube-router configs. Here we create an IPv4 based cluster with kube-router based pod-to-pod and services handling enabled: 

    CNI_ARGS="--v=3 --kubeconfig=/home/vagrant/.kube/config --run-firewall=false --run-service-proxy=true --run-router=true  --advertise-cluster-ip=true --routes-sync-period=10s" CNI=kube-router GOBGP=1 INSTALL_LOCAL_BUILD=1 K8S_VERSION=v1.13.0 IPV4=1 K8S=1 NWORKERS=1 ./start.sh

## Using Local Builds of k8

We need a means to bring in recent patches that may not be part of any official k8 release. Additionally, we may make changes of our own. 
Clone the stock k8 repo, and build all the components: 
    
    build/run.sh make 

Binary will be available in here but must be copied over to the k8s-ipv6 dir: 
    
    cd _output/dockerized/bin/linux/amd64 
    cp * ~/go/src/github.com/Nordix/k8s-ipv6/hack/local_builds/k8s/v1.13.0/

Now, when we deploy our cluster, we can specify INSTALL_LOCAL_BUILD=1. Binaries will be copied from hack/local_builds/ instead of being downloaded:

    CNI=kube-router GOBGP=1 DNS64_IPV6=CC00::2 K8S_VERSION=v1.13.0 IPV4=0 K8S=1 NWORKERS=1 ./start.sh

Initially we have to build all components (as we did above) and copy them over; however, later we can only build the components we modify. For example, we build kubelet here and copy it over to the k8s-ipv6 local_builds dir: 

    build/run.sh make kubelet KUBE_BUILD_PLATFORMS=linux/amd6 
    cd _output/dockerized/bin/linux/amd64 
    cp kubelet ~/go/src/github.com/Nordix/k8s-ipv6/hack/local_builds/k8s/v1.13.0/
