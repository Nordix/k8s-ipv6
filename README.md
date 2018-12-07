# k8-ipv6

This project serves two primary purposes: (i) study and validate ipv6 support in kubernetes and associated plugins (namely: metallb and kube-router) (ii) provide a dev environment for implementing and testing additional functionality (e.g.dual-stack)

-----------------
Getting Started
-----------------
    mkdir -p ~/go/src/github.com/Arvinderpal
    cd ~/go/src/github.com/Arvinderpal
    git clone https://github.com/Arvinderpal/k8-ipv6.git
    cd k8-ipv6
    IPV4=0 K8S=1 NWORKERS=1 ./start.sh

-------------------------
Using Local Builds of k8
-------------------------
We need a means to bring in recent patches that may not be part of any official k8 release. Additionally, we may make changes of our own. 
Clone the stock k8 repo, and build all the components: 
    
    build/run.sh make 

Binary will be available in here but must be copied over to the k8-ipv6 dir: 
    
    cd _output/dockerized/bin/linux/amd64 
    cp * /home/earvwan/go/src/github.com/Arvinderpal/k8-ipv6/hack/local_builds/k8s/v1.11.3 

Now, when we deploy our cluster, we can specify INSTALL_LOCAL_BUILD=1. Binaries will be copied from hack/local_builds/ instead of being downloaded:

    INSTALL_LOCAL_BUILD=1 IPV4=0 K8S=1 NWORKERS=1 ./start.sh 

Initially we have to build all components (as we did above) and copy them over; however, later we can only build the components we modify. For example, we build kubelet here and copy it over to the k8-ipv6 local_builds dir: 

    build/run.sh make kubelet KUBE_BUILD_PLATFORMS=linux/amd6 
    cd _output/dockerized/bin/linux/amd64 
    cp kubelet /home/earvwan/go/src/github.com/Arvinderpal/k8-ipv6/hack/local_builds/k8s/v1.11.3
