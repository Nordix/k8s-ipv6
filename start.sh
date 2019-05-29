#!/usr/bin/env bash

dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source "${dir}/helpers.sh"
source "${dir}/cni_conf.sh"

# Internal variables used in the Vagrantfile
export 'EARVWAN_SCRIPT'=true
# Sets the directory where the temporary setup scripts are created
export 'EARVWAN_TEMP'="${dir}"

# export 'K8S'="1"
# export 'NWORKERS'=1

export 'VM_MEMORY'=${MEMORY:-3072}
# Number of CPUs
export 'VM_CPUS'=${CPUS:-2}

# VM_BASENAME tag is only set if K8S option is active
export 'VM_BASENAME'="k8s"

# Set VAGRANT_DEFAULT_PROVIDER to virtualbox
export 'VAGRANT_DEFAULT_PROVIDER'=${VAGRANT_DEFAULT_PROVIDER:-"virtualbox"}
# Sets the default cilium TUNNEL_MODE to "vxlan"

# Master's IPv4 address. Workers' IPv4 address will have their IP incremented by
# 1. The netmask used will be /24
export 'MASTER_IPV4'=${MASTER_IPV4:-"192.168.33.8"}
# NFS address is only set if NFS option is active. This will create a new
# network interface for each VM with starting on this IP. This IP will be
# available to reach from the host.
export 'MASTER_IPV4_NFS'=${MASTER_IPV4_NFS:-"192.168.34.8"}
# Enable IPv4 mode.
export 'IPV4'=${IPV4:-1}

# Exposed IPv6 node CIDR, only set if IPV4 is disabled. Each node will be setup
# with a IPv6 network available from the host with $IPV6_PUBLIC_CIDR +
# 6to4($MASTER_IPV4). For IPv4 "192.168.33.8" we will have for example:
#   master  : FD00::B/16
#   worker 1: FD00::C/16
# The netmask used will be /16
export 'IPV6_PUBLIC_CIDR'=${IPV4+"FD00::"}

# Internal IPv6 node CIDR, always set up by default. Each node will be setup
# with a IPv6 network available from the host with IPV6_INTERNAL_CIDR +
# 6to4($MASTER_IPV4). For IPv4 "192.168.33.8" we will have for example:
#   master  : FD01::B/16
#   worker 1: FD01::C/16
# The netmask used will be /16
# ~EARVWAN~ This is the InternalIP for each node in k8. Try:  kubectl get nodes -o json | grep -i -C 10 InternalIP
export 'IPV6_INTERNAL_CIDR'=${IPV4+"FD01::"}

# Cilium IPv6 node CIDR. Each node will be setup with IPv6 network of
# $CILIUM_IPV6_NODE_CIDR + 6to4($MASTER_IPV4). For IPv4 "192.168.33.8" we will
# have for example:
#   master  : FD02::C0A8:2108:0:0/96
#   worker 1: FD02::C0A8:2109:0:0/96
# ~EARVWAN~ This is the PodCIDR. Try: kubectl get nodes -o json | grep -i -C 10 podCIDR 
# NOTE: I'm not sure embedding the ipv4 address in the podCIDR is all that useful, but I'll leave it for now.
# It may be better in the future to just do #   master  : FD02::0:0:0/96   worker 1: FD02::1:0:0/96
export 'CILIUM_IPV6_NODE_CIDR'=${CILIUM_IPV6_NODE_CIDR:-"FD02::"}

split_ipv4 ipv4_array "${MASTER_IPV4}"
export 'MASTER_IPV6'="${IPV6_INTERNAL_CIDR}$(printf '%02X' ${ipv4_array[3]})"
export 'MASTER_IPV6_PUBLIC'="${IPV6_PUBLIC_CIDR}$(printf '%02X' ${ipv4_array[3]})"

# CNI defaults
export 'CNI'="${CNI:-"kube-router"}"
export 'CNI_INSTALL_TYPE'="${CNI_INSTALL_TYPE:-"systemd"}"
export 'DEFAULT_CNI_ARGS_SYSTEMD'="--v=3 --kubeconfig=/home/vagrant/.kube/config --run-firewall=false --run-service-proxy=false --run-router=true  --advertise-cluster-ip=true --routes-sync-period=10s"
export 'DEFAULT_KUBEROUTER_MANIFEST'="examples/kube-router/ipv4-router-only-kube-router.yaml"

# kubeadm is used by default
# alternative is to manually launch each component (cilium approach)
export 'ENABLE_KUBEKDM'="${ENABLE_KUBEKDM:-"true"}"

if [ "${CNI}" == "bridge" ]; then
    echo "Using bridge as the CNI plugin"
elif [ "${CNI}" == "calico" ]; then
    echo "Using calico as the CNI plugin"
    export CALICO_ETCD_EP_V4=http://"${MASTER_IPV4}":6666
    export CALICO_ETCD_EP_V6="http://[${MASTER_IPV6}]:6666"
    export CALICO_PRELOAD_LOCAL_IMAGES="true" 
    # calico-node-latest.tar should be in this directory:
    calico_vagrant_base_dir="/home/vagrant/go/src/github.com/projectcalico/"
    export 'CALICO_VAGRANT_BASE_DIR'=${calico_vagrant_base_dir}
else # default: kube-router
    if [ "${CNI_INSTALL_TYPE}" == "daemonset" ]; then
        if [ -n "${CNI_ARGS}" ]; then
            export 'CNI_ARGS'="${CNI_ARGS}"
        else
            export 'CNI_ARGS'="${DEFAULT_KUBEROUTER_MANIFEST}"
            echo "Using default yaml file: ${CNI_ARGS}. If desired, you can override this via CNI_ARGS"
        fi
    else # default is "systemd"
        kuberouter_vagrant_bin_dir="/home/vagrant/go/src/github.com/cloudnativelabs/kube-router/cmd/kube-router/"
        export 'KUBEROUTER_VAGRANT_BIN_DIR'=${kuberouter_vagrant_bin_dir}
        if [ -n "${CNI_ARGS}" ]; then
            export 'CNI_ARGS'="${CNI_ARGS}"
        else
            export 'CNI_ARGS'="${DEFAULT_CNI_ARGS_SYSTEMD}"
            echo "using default kube-router args"
        fi
        echo "Installing kube-router via systemd using kube-router args: ${CNI_ARGS}"
    fi
fi


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#
#			Create Master & Node Config files (node-1.sh, ...) 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#

function create_master(){
	local ipv4_array_l
    split_ipv4 ipv4_array_l "${MASTER_IPV4}"
    get_cilium_node_addr master_cilium_ipv6 "${MASTER_IPV4}"
    get_cilium_node_gw_addr ipv6_gw_addr "${MASTER_IPV4}"
    output_file="${dir}/node-1.sh"
    
    if [[ "${IPV4}" -ne "1" ]]; then
        write_ipv6_netcfg_header "${MASTER_IPV6}" "${MASTER_IPV6}" "${output_file}"
        if [ -n "${NWORKERS}" ]; then
            write_ipv6_nodes_routes 1 "${MASTER_IPV4}" "${output_file}"
        fi
        if [ "${CNI}" == "bridge" ]; then           # for bridge we need manual routes
    	   add_ipv6_podCIDR_routes_on_master "${output_file}"
        fi
        if [ -n "${DNS64_IPV6}" ]; then
            write_dns64_resolv_conf "${DNS64_IPV6}" "${output_file}"
        fi
        write_ipv6_cni_cfg 1 "${ipv4_array_l[3]}" "${master_cilium_ipv6}" 96 "${ipv6_gw_addr}" "${output_file}"
    else
        # IPv4
        write_ipv4_netcfg_header "" "${MASTER_IPV4}" "${output_file}"
        write_ipv4_nodes_routes 1 "${MASTER_IPV4}" "${output_file}"
        if [ "${CNI}" == "bridge" ]; then           # for bridge we need manual routes
           echo "cni bridge: adding ipv4 manual routes on master"
           add_ipv4_podCIDR_routes_on_master "${output_file}"
        fi
        write_ipv4_cni_cfg 1 "" "10.128.0.0" 24 "" "${output_file}"
    fi
}

function create_workers(){
	local ipv4_array_l
    split_ipv4 ipv4_array_l "${MASTER_IPV4}"
    master_prefix_ip="${ipv4_array_l[3]}"
    get_cilium_node_addr master_cilium_ipv6 "${MASTER_IPV4}"
  
    base_workers_ip=$(printf "%d.%d.%d." "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}")
    if [ -n "${NWORKERS}" ]; then
        for i in `seq 2 1 $(( NWORKERS + 1 ))`; do
            output_file="${dir}/node-${i}.sh"
            worker_ip_suffix=$(( ipv4_array_l[3] + i - 1 ))
            worker_ipv6=${IPV6_INTERNAL_CIDR}$(printf '%02X' ${worker_ip_suffix})
            worker_host_ipv6=${IPV6_PUBLIC_CIDR}$(printf '%02X' ${worker_ip_suffix})

            if [[ "${IPV4}" -ne "1" ]]; then
                write_ipv6_netcfg_header "${worker_ipv6}" "${MASTER_IPV6}" "${output_file}"
                # TODO: I don't believe write_master_route does anything useful...
                # write_master_route "${master_prefix_ip}" "${master_cilium_ipv6}" \
                    # "${MASTER_IPV6}" "${i}" "${worker_ipv6}" "${output_file}"
                write_ipv6_nodes_routes "${i}" "${MASTER_IPV4}" "${output_file}"

                worker_cilium_ipv4="${base_workers_ip}${worker_ip_suffix}"
                get_cilium_node_addr worker_cilium_ipv6 "${worker_cilium_ipv4}"
                get_cilium_node_gw_addr ipv6_gw_addr "${worker_cilium_ipv4}"
                if [ "${CNI}" == "bridge" ]; then
                    add_ipv6_podCIDR_routes_on_workers "${i}" "${output_file}"
                fi        
                if [ -n "${DNS64_IPV6}" ]; then
                    write_dns64_resolv_conf "${DNS64_IPV6}" "${output_file}"
                fi
    			write_ipv6_cni_cfg "${i}" "${worker_ip_suffix}" "${worker_cilium_ipv6}" 96 "${ipv6_gw_addr}" "${output_file}"
            else
                # IPv4
                let "id = $i - 1"
                worker_ipv4=$(printf "10.128.%d.0" "${id}")
                write_ipv4_netcfg_header "" "${MASTER_IPV4}" "${output_file}"
                # write_master_route "" "" "" "${i}" "${worker_ipv4}" "${output_file}"
                write_ipv4_nodes_routes "${i}" "${MASTER_IPV4}" "${output_file}"
                if [ "${CNI}" == "bridge" ]; then
                    echo "cni bridge: adding ipv4 manual routes on worker ${i}"
                    add_ipv4_podCIDR_routes_on_workers "${i}" "${output_file}"
                fi        
                write_ipv4_cni_cfg "${i}" "" "${worker_ipv4}" 24 "" "${output_file}"
            fi
        done
    fi
}

function init_global_worker_addrs(){
	local ipv4_array_l
    split_ipv4 ipv4_array_l "${MASTER_IPV4}" 
  
    base_workers_ip=$(printf "%d.%d.%d." "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}")
    if [ -n "${NWORKERS}" ]; then
        for i in `seq 2 1 $(( NWORKERS + 1 ))`; do
            output_file="${dir}/node-${i}.sh"
            worker_ip_suffix=$(( ipv4_array_l[3] + i - 1 ))
            
            # IPv4 and IPv6 of cluster interfaces on the hosts. (e.g "192.168.33.8")
            worker_cilium_ipv4="${base_workers_ip}${worker_ip_suffix}"
            ipv4_internal_workers_addrs+=(${worker_cilium_ipv4})
            worker_ipv6=${IPV6_INTERNAL_CIDR}$(printf '%02X' ${worker_ip_suffix})
            ipv6_internal_workers_addrs+=(${worker_ipv6})
            
            # IPV6 public interface 
            # TODO: add for IPv4 as well
            worker_host_ipv6=${IPV6_PUBLIC_CIDR}$(printf '%02X' ${worker_ip_suffix})
            ipv6_public_workers_addrs+=(${worker_host_ipv6})

            # pod CIDRs for IPv4 and IPv6
            let "id = $i - 1"
            worker_podCIDR_ipv4=$(printf "10.128.%d.0" "${id}")
            ipv4_podCIDR_workers_addrs+=(${worker_podCIDR_ipv4})            
            get_cilium_node_addr worker_cilium_ipv6 "${worker_cilium_ipv4}"
            ipv6_podCIDR_workers_addrs+=(${worker_cilium_ipv6})
        done
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#
# 						K8 Install 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#


# write_k8s_header create the file in ${2} and writes the k8s configuration.
# Sets up the k8s temporary directory inside the VM with ${1}.
function write_k8s_header(){
    k8s_dir="${1}"
    filename="${2}"
    cat <<EOF > "${filename}"
#!/usr/bin/env bash

set -e

# K8s installation
sudo apt-get -y install curl
mkdir -p "${k8s_dir}"
cd "${k8s_dir}"

EOF
}

# write_k8s_install writes the k8s installation first half in ${2} and the
# second half in ${3}. Changes the k8s temporary directory inside the VM,
# defined in ${1}, owner and group to vagrant.
function write_k8s_install() {
    k8s_dir="${1}"
    filename="${2}"
    filename_2nd_half="${3}"
    if [[ -n "${IPV6_EXT}" ]]; then
        # The k8s cluster cidr will be /80
        # it can be any value as long it's lower than /96
        # k8s will assign each node a cidr for example:
        #   master  : FD02::C0A8:2108:0:0/96
        #   worker 1: FD02::C0A8:2109:0:0/96
        # The kube-controller-manager is responsible for incrementing 8, 9, A, ...
        k8s_cluster_cidr+="FD02::C0A8:2108:0:0/93"
        k8s_node_cidr_mask_size="96"
        k8s_service_cluster_ip_range="FD03::/112"
        k8s_cluster_api_server_ip="FD03::1"
        k8s_cluster_dns_ip="FD03::A"
    fi
    k8s_cluster_cidr=${k8s_cluster_cidr:-"10.128.0.0/18"}
    k8s_node_cidr_mask_size=${k8s_node_cidr_mask_size:-"24"}
    k8s_service_cluster_ip_range=${k8s_service_cluster_ip_range:-"172.20.0.0/24"}
    k8s_cluster_api_server_ip=${k8s_cluster_api_server_ip:-"172.20.0.1"}
    k8s_cluster_dns_ip=${k8s_cluster_dns_ip:-"172.20.0.10"}

    cat <<EOF >> "${filename}"
# K8s
k8s_path="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/examples/kubernetes-ingress/scripts"
kubeadm_path="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/examples/kubeadm"
export IPV6_EXT="${IPV6_EXT}"
export K8S_VERSION="${K8S_VERSION}"
export VM_BASENAME="k8s"
export MASTER_IPV6="${MASTER_IPV6}"
export MASTER_IPV6_PUBLIC="${MASTER_IPV6_PUBLIC}"
export K8S_CLUSTER_CIDR="${k8s_cluster_cidr}"
export K8S_NODE_CIDR_MASK_SIZE="${k8s_node_cidr_mask_size}"
export K8S_SERVICE_CLUSTER_IP_RANGE="${k8s_service_cluster_ip_range}"
export K8S_CLUSTER_API_SERVER_IP="${k8s_cluster_api_server_ip}"
export K8S_CLUSTER_DNS_IP="${k8s_cluster_dns_ip}"
export RUNTIME="${RUNTIME}"
# Only do installation if RELOAD is not set
if [ -z "${RELOAD}" ]; then
    export INSTALL="1"
fi
# Use local binaries if desired
if [ -n "${INSTALL_LOCAL_BUILD}" ]; then
    export INSTALL_LOCAL_BUILD="1"
fi
export ETCD_CLEAN="${ETCD_CLEAN}"

EOF

    if [ "${ENABLE_KUBEKDM}" == "true" ]; then
    cat <<EOF >> "${filename}"
if [[ "\$(hostname)" == "${VM_BASENAME}1" ]]; then
    echo "\$(hostname)"
    "\${kubeadm_path}/install-packages.sh"
    "\${kubeadm_path}/init-control-plane.sh"
else
    echo "\$(hostname)"
    "\${kubeadm_path}/install-packages.sh"
    "\${kubeadm_path}/join-worker.sh"
fi

EOF

    else
    cat <<EOF >> "${filename}"
if [[ "\$(hostname)" == "${VM_BASENAME}1" ]]; then
    echo "\$(hostname)"
    "\${k8s_path}/00-create-certs.sh"
    "\${k8s_path}/01-install-etcd.sh"
    "\${k8s_path}/02-install-kubernetes-master.sh"
fi
# All nodes are a kubernetes worker
"\${k8s_path}/03-install-kubernetes-worker.sh"
"\${k8s_path}/04-install-kubectl.sh"
chown vagrant.vagrant -R "${k8s_dir}"

EOF

    fi

    cat <<EOF > "${filename_2nd_half}"
#!/usr/bin/env bash
# K8s installation 2nd half
k8s_path="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/examples/kubernetes-ingress/scripts"
export IPV6_EXT="${IPV6_EXT}"
export K8S_VERSION="${K8S_VERSION}"
export VM_BASENAME="k8s"
export MASTER_IPV4="${MASTER_IPV4}"
export MASTER_IPV6="${MASTER_IPV6}"
export MASTER_IPV6_PUBLIC="${MASTER_IPV6_PUBLIC}"
export K8S_CLUSTER_CIDR="${k8s_cluster_cidr}"
export K8S_NODE_CIDR_MASK_SIZE="${k8s_node_cidr_mask_size}"
export K8S_SERVICE_CLUSTER_IP_RANGE="${k8s_service_cluster_ip_range}"
export K8S_CLUSTER_API_SERVER_IP="${k8s_cluster_api_server_ip}"
export K8S_CLUSTER_DNS_IP="${k8s_cluster_dns_ip}"
export RUNTIME="${RUNTIME}"
export K8STAG="${VM_BASENAME}"
export NWORKERS="${NWORKERS}"
# Only do installation if RELOAD is not set
if [ -z "${RELOAD}" ]; then
    export INSTALL="1"
fi
# Use local binaries if desired
if [ -n "${INSTALL_LOCAL_BUILD}" ]; then
    export INSTALL_LOCAL_BUILD="1"
fi
export ETCD_CLEAN="${ETCD_CLEAN}"

cd "${k8s_dir}"

EOF
    if [ "${ENABLE_KUBEKDM}" == "true" ]; then
    cat <<EOF >> "${filename_2nd_half}"
# using kubeadm...nothing to do here. 
EOF
    else
    cat <<EOF >> "${filename_2nd_half}"

if [[ "\$(hostname)" == "${VM_BASENAME}1" ]]; then
    "\${k8s_path}/06-install-kubedns.sh"
else
    "\${k8s_path}/04-install-kubectl.sh"
fi
EOF

    fi
}

# create_k8s_config creates k8s config
function create_k8s_config(){
    if [ -n "${K8S}" ]; then
        k8s_temp_dir="/home/vagrant/k8s"
        output_file="${dir}/k8s-install-1st-part.sh"
        output_2nd_file="${dir}/k8s-install-2nd-part.sh"
        write_k8s_header "${k8s_temp_dir}" "${output_file}"
        write_k8s_install "${k8s_temp_dir}" "${output_file}" "${output_2nd_file}"
    fi
}

# create_cni_config creates cni config 
function create_cni_config(){
    if [ -n "${K8S}" ]; then
        k8s_temp_dir="/home/vagrant/k8s"
        output_file="${dir}/k8s-install-cni.sh"
        write_cni_install_file "${k8s_temp_dir}" "${output_file}"
    fi
}

if [[ "${VAGRANT_DEFAULT_PROVIDER}" -eq "virtualbox" ]]; then
     vboxnet_addr_finder
fi

ipv4_internal_workers_addrs=() 
ipv4_podCIDR_workers_addrs=()
ipv4_public_workers_addrs=()

ipv6_internal_workers_addrs=() 
ipv6_podCIDR_workers_addrs=()
ipv6_public_workers_addrs=()

set_reload_if_vm_exists

init_global_worker_addrs # populates above arrays

create_master
create_workers
set_vagrant_env
create_k8s_config	
create_cni_config						

# cd "${dir}/../.."

if [ -n "${RELOAD}" ]; then
    vagrant reload
elif [ -n "${NO_PROVISION}" ]; then
    vagrant up --no-provision
elif [ -n "${PROVISION}" ]; then
    vagrant provision
else
    vagrant up
    if [ -n "${K8S}" ]; then
    	echo "copying k8 config file from k8s1 to host under the name vagrant.kubeconfig"
		vagrant ssh k8s1 -- cat /home/vagrant/.kube/config | sed 's;server:.*:6443;server: https://k8s1:7443;g' > vagrant.kubeconfig
        echo "copying vagrant.kubeconfig to host ~/.kube/config to use with kubectl"
        cp vagrant.kubeconfig ~/.kube/config
	fi
	echo "Add '127.0.0.1 k8s1' to your /etc/hosts to use ~/.kube/config file for kubectl"
fi


