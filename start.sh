#!/usr/bin/env bash

dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

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

# CNI defaults
export 'CNI'="${CNI:-"kube-router"}"
export 'CNI_INSTALL_TYPE'="${CNI_INSTALL_TYPE:-"systemd"}"
export 'DEFAULT_CNI_ARGS_SYSTEMD'="--v=3 --kubeconfig=/home/vagrant/.kube/config --run-firewall=false --run-service-proxy=false --run-router=true  --advertise-cluster-ip=true --routes-sync-period=10s"
export 'DEFAULT_KUBEROUTER_MANIFEST'="examples/kube-router/ipv4-router-only-kube-router.yaml"

if [ "${CNI}" == "bridge" ]; then
    echo "Using bridge as the CNI plugin"
elif [ "${CNI}" == "calico" ]; then
    echo "Using calico as the CNI plugin"
    export CALICO_ETCD_EP_V6="http://[::1]:6666"
    export CALICO_ETCD_EP_V4="http://127.0.0.1:6666"
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

# kubeadm is used by default
# alternative is to manually launch each component (cilium approach)
export 'ENABLE_KUBEKDM'="${ENABLE_KUBEKDM:-"true"}"


# split_ipv4 splits an IPv4 address into a bash array and assigns it to ${1}.
# Exits if ${2} is an invalid IPv4 address.
function split_ipv4(){
    IFS='.' read -r -a ipv4_array <<< "${2}"
    eval "${1}=( ${ipv4_array[@]} )"
    if [[ "${#ipv4_array[@]}" -ne 4 ]]; then
        echo "Invalid IPv4 address: ${2}"
        exit 1
    fi
}

# get_cilium_node_addr sets the cilium node address in ${1} for the IPv4 address
# in ${2}.
function get_cilium_node_addr(){
	local ipv4_array_l
    split_ipv4 ipv4_array_l "${2}"
    hexIPv4=$(printf "%02X%02X:%02X%02X" "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}" "${ipv4_array_l[3]}")
    eval "${1}=${CILIUM_IPV6_NODE_CIDR}${hexIPv4}:0:0"
}


function get_cilium_node_gw_addr(){
	local ipv4_array_l
    split_ipv4 ipv4_array_l "${2}"
    hexIPv4=$(printf "%02X%02X:%02X%02X" "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}" "${ipv4_array_l[3]}")
    eval "${1}=${CILIUM_IPV6_NODE_CIDR}${hexIPv4}:0:1"
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#
#               NAT64/DNS64 (written in node-1.sh, ...)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#
function write_dns64_resolv_conf(){
    dns64_ipv6="${1}"
    filename="${2}"
    cat <<EOF >> "${filename}"
# NOTE: /etc/resolv.conf may get overwritten if DHCP is set on enp0s3.
# TODO: Best to disable DHCP. 
sed -i 's/nameserver.*/nameserver ${dns64_ipv6}/' /etc/resolv.conf 
EOF
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#
# 				Network Configs (written in node-1.sh, ...)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#

# write_ipv6_netcfg_header creates the file in ${3} and writes the internal network
# configuration for the vm IP ${1}. Sets the master's hostname with IPv6 address
# in ${2}.
function write_ipv6_netcfg_header(){
    vm_ipv6="${1}"
    master_ipv6="${2}"
    filename="${3}"
    cat <<EOF > "${filename}"
#!/usr/bin/env bash

if [ -n "${K8S}" ]; then
    export K8S="1"
fi

# Use of IPv6 'documentation block' to provide example
ip -6 a a ${vm_ipv6}/16 dev enp0s8

echo '${master_ipv6} ${VM_BASENAME}1' >> /etc/hosts
sysctl -w net.ipv6.conf.all.forwarding=1

# For ipv6, default route will point to s9 interface
ip -6 r a default via ${IPV6_PUBLIC_CIDR}1 dev enp0s9

EOF
}

# write_ipv4_netcfg_header creates the file in ${3} and writes the internal network
# configuration for the vm IP ${1}. Sets the master's hostname with IPv4 address
# in ${2}.
function write_ipv4_netcfg_header(){
    vm_ipv4="${1}"
    master_ipv4="${2}"
    filename="${3}"
    cat <<EOF > "${filename}"
#!/usr/bin/env bash

if [ -n "${K8S}" ]; then
    export K8S="1"
fi

echo '${master_ipv4} ${VM_BASENAME}1' >> /etc/hosts
sysctl -w net.ipv4.conf.all.forwarding=1

EOF
}

function write_master_route(){
    master_ipv4_suffix="${1}"
    master_cilium_ipv6="${2}"
    master_ipv6="${3}"
    node_index="${4}"
    worker_ip="${5}"
    filename="${6}"

    cat <<EOF >> "${filename}"
echo "${worker_ip} ${VM_BASENAME}${node_index}" >> /etc/hosts

EOF
}

# write_ipv6_nodes_routes writes in file ${3} the routes for all nodes in the
# clusters except for node with index ${1}. All routes will be based on IPv4
# defined in ${2}.
function write_ipv6_nodes_routes(){
    node_index="${1}"
    base_ipv4_addr="${2}"
    filename="${3}"
    local ipv4_array_l
    cat <<EOF >> "${filename}"
# Node's routes
EOF
    split_ipv4 ipv4_array_l "${base_ipv4_addr}"
    local i
    local index=1
    for i in `seq $(( ipv4_array_l[3] + 1 )) $(( ipv4_array_l[3] + NWORKERS ))`; do
        index=$(( index + 1 ))
        hexIPv4=$(printf "%02X%02X:%02X%02X" "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}" "${i}")
        if [ "${node_index}" -eq "${index}" ]; then
            continue
        fi
        worker_internal_ipv6=${IPV6_INTERNAL_CIDR}$(printf "%02X" "${i}")

        cat <<EOF >> "${filename}"
echo "${worker_internal_ipv6} ${VM_BASENAME}${index}" >> /etc/hosts
EOF
    done

    cat <<EOF >> "${filename}"

EOF
}

# write_ipv4_nodes_routes writes in file ${3} the routes for all nodes in the
# clusters except for node with index ${1}.
function write_ipv4_nodes_routes(){
    node_index="${1}"
    base_ipv4_addr="${2}"
    filename="${3}"
    local ipv4_array_l
    cat <<EOF >> "${filename}"
# Node's routes
EOF
    split_ipv4 ipv4_array_l "${base_ipv4_addr}"
    local i
    local index=1
    for i in `seq $(( ipv4_array_l[3] + 1 )) $(( ipv4_array_l[3] + NWORKERS ))`; do
        index=$(( index + 1 ))
        if [ "${node_index}" -eq "${index}" ]; then
            continue
        fi
        ipv4_addr=$(printf "%d.%d.%d.%d" "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}" "${i}")

        cat <<EOF >> "${filename}"
echo "${ipv4_addr} ${VM_BASENAME}${index}" >> /etc/hosts
EOF
    done

    cat <<EOF >> "${filename}"

EOF
}

function write_ip_route_entry(){
    podcidr="${1}"
    node_ipv6="${2}"
    filename="${3}"
# sudo ip -6 r a fd02::c0a8:210c:0:0/96  via fd01::c 
cat <<EOF >> "${filename}"
ip -6 r a ${podcidr}/96 via ${node_ipv6}
EOF
}


# add_ipv6_podCIDR_routes_on_master adds routes for the podCIDR of all the workers
# on the master node.
function add_ipv6_podCIDR_routes_on_master(){
	filename="${1}"        	
cat <<EOF >> "${filename}"
# Manual routes for podCIDRs:  
EOF
    if [ -n "${NWORKERS}" ]; then
        for i in `seq 0 $(( NWORKERS - 1 ))`; do
			write_ip_route_entry "${ipv6_podCIDR_workers_addrs[i]}" "${ipv6_internal_workers_addrs[i]}" "${filename}"
        done
    fi

}

# add_ipv6_podCIDR_routes_on_workers adds routes for podCIDRs of each node. 
# This is required for the cni bridge plugin for multi-node communication. 
function add_ipv6_podCIDR_routes_on_workers(){
    node_index="${1}"
    filename="${2}"

	local ipv4_array_l
    split_ipv4 ipv4_array_l "${MASTER_IPV4}"
    master_ip_suffix="${ipv4_array_l[3]}"
    master_ipv6=${IPV6_INTERNAL_CIDR}$(printf '%02X' ${master_ip_suffix})

    get_cilium_node_addr master_cilium_ipv6 "${MASTER_IPV4}"

cat <<EOF >> "${filename}"
# Manual routes for podCIDRs:  
EOF

	# Add master podCIDR to worker
	write_ip_route_entry "${master_cilium_ipv6}" "${master_ipv6}" "${filename}"

	# Add entry of each worker, skipping self.
    for j in `seq 0 $(( NWORKERS - 1 ))`; do
        idx=$(expr $j + 2)
        if [ "${idx}" -eq "${node_index}" ]; then
            continue
        fi
		write_ip_route_entry "${ipv6_podCIDR_workers_addrs[j]}" "${ipv6_internal_workers_addrs[j]}" "${filename}"
    done
      
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#
# 							CNI Conf
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#
function write_ipv6_cni_cfg(){
    if [[ "${CNI}" == "kube-router" && "${CNI_INSTALL_TYPE}" == "systemd" ]]; then
        write_cni_kuberouter_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}"
    elif [[ "${CNI}" == "calico" ]]; then
        write_cni_calico_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}" "IPv6"
    elif [ -z "${CNI}" ]; then
        # if no cni is defined, we default to bridge
        write_cni_bridge_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}"
    fi
}

function write_ipv4_cni_cfg(){
    if [[ "${CNI}" == "kube-router" && "${CNI_INSTALL_TYPE}" == "systemd" ]]; then
        write_cni_kuberouter_cfg "${1}" "" "${3}" "${4}" "" "${6}"
    elif [[ "${CNI}" == "calico" ]]; then
        write_cni_calico_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}" "IPv4"
    elif [ -z "${CNI}" ]; then
        # if no cni is defined, we default to bridge
        write_cni_bridge_cfg "${1}" "" "${3}" "${4}" "" "${6}"
    fi
}

function write_cni_bridge_cfg(){
    node_index="${1}"
    master_ipv4_suffix="${2}"
    ip_addr="${3}"
    mask_size="${4}"
    ip_gw_addr="${5}"
    filename="${6}"

cat <<EOF >> "$filename"

cat <<EOF >> "/etc/cni/net.d/10-mynet.conf"
{
    "cniVersion": "0.3.0",
    "name": "my-bridge",
    "type": "bridge",
    "bridge": "cni0",
    "isDefaultGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "${ip_addr}/${mask_size}"
    }
}
EOF

cat <<EOF >> "${filename}"

EOF
}


function write_cni_calico_cfg(){
    node_index="${1}"
    master_ipv4_suffix="${2}"
    ip_addr="${3}"
    mask_size="${4}"
    ip_gw_addr="${5}"
    filename="${6}"
    addrFamily="${7}"

if [[ "${addrFamily}" == "IPv4" ]]; then

cat <<EOF >> "$filename"

cat <<EOF >> "/etc/cni/net.d/10-calico.conf"
{
    "name": "calico-k8s-network",
    "type": "calico",
    "etcd_endpoints": "${CALICO_ETCD_EP_V6}",
    "log_level": "DEBUG",
    "ipam": {
        "type": "calico-ipam",
        "assign_ipv4": "true",
        "ipv4_pools": ["${ip_addr}/${mask_size}"]
    },
    "kubernetes": {
        "kubeconfig": "/home/vagrant/.kube/config"
    }
}
EOF

cat <<EOF >> "${filename}"

EOF

else

cat <<EOF >> "$filename"

cat <<EOF >> "/etc/cni/net.d/10-calico.conf"
{
    "name": "calico-k8s-network",
    "type": "calico",
    "etcd_endpoints": "${CALICO_ETCD_EP_V6}",
    "log_level": "DEBUG",
    "ipam": {
        "type": "calico-ipam",
        "assign_ipv6": "true",
        "ipv6_pools": ["${ip_addr}/${mask_size}"]
    },
    "kubernetes": {
        "kubeconfig": "/home/vagrant/.kube/config"
    }
}
EOF

cat <<EOF >> "${filename}"

EOF

fi
}


function write_cni_kuberouter_cfg(){
    node_index="${1}"
    master_ipv4_suffix="${2}"
    ip_addr="${3}"
    mask_size="${4}"
    ip_gw_addr="${5}"
    filename="${6}"


cat <<EOF >> "$filename"

cat <<EOF >> "/etc/cni/net.d/10-kuberouter.conf"
{
    "cniVersion": "0.3.0",
    "name": "mynet",
    "type": "bridge",
    "bridge": "kube-bridge",
    "isDefaultGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "${ip_addr}/${mask_size}"
    }
}
EOF

cat <<EOF >> "${filename}"

EOF
}


function write_cni_lo_cfg(){
cat <<EOF >> "$filename"
cat <<EOF >> "/etc/cni/net.d/99-loopback.conf"
{
	"cniVersion": "0.3.0",
	"name": "lo",
	"type": "loopback"
}
EOF
cat <<EOF >> "${filename}"

EOF

}

function write_cni_install_file() {
    k8s_dir="${1}"
    filename="${2}"
    if [[ -n "${IPV6_EXT}" ]]; then
        # The k8s cluster cidr will be /80
        # it can be any value as long it's lower than /96
        # k8s will assign each node a cidr for example:
        #   master  : FD02::C0A8:2108:0:0/96
        #   worker 1: FD02::C0A8:2109:0:0/96
        # The kube-controller-manager is responsible for incrementing 8, 9, A, ...
        k8s_cluster_cidr="FD02::C0A8:2108:0:0/93"
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

    cat <<EOF > "${filename}"
#!/usr/bin/env bash

set -e

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
export CNI_INSTALL_TYPE="${CNI_INSTALL_TYPE}"
export CNI_ARGS="${CNI_ARGS}"
ROUTER_ID=\${1}

EOF

    if [ "${CNI}" == "bridge" ]; then
    cat <<EOF >> "${filename}"
# bridge cni. nothing to do here.
EOF

    elif [ "${CNI}" == "calico" ]; then
    cat <<EOF >> "${filename}"
export CALICO_PATH="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/examples/calico/"
export CALICO_VAGRANT_BASE_DIR="${CALICO_VAGRANT_BASE_DIR}"
export CALICO_ETCD_EP_V6="${CALICO_ETCD_EP_V6}"
export CALICO_ETCD_EP_V4="${CALICO_ETCD_EP_V4}"
export CALICO_PRELOAD_LOCAL_IMAGES="${CALICO_PRELOAD_LOCAL_IMAGES}"

"\${CALICO_PATH}/install-calico.sh"
EOF

    else # kube-router is default
    cat <<EOF >> "${filename}"
kuberouter_path="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/examples/kube-router"
export KUBEROUTER_VAGRANT_BIN_DIR="${KUBEROUTER_VAGRANT_BIN_DIR}"
"\${kuberouter_path}/install-kube-router.sh" "\${ROUTER_ID}"
EOF

    fi

}


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
        if [ -z "${CNI}" ]; then
            # we only add manual routes if no cni plugin is defined. 
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
                if [ -z "${CNI}" ]; then
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
            
            worker_ipv6=${IPV6_INTERNAL_CIDR}$(printf '%02X' ${worker_ip_suffix})
            ipv6_internal_workers_addrs+=(${worker_ipv6})
            
            worker_host_ipv6=${IPV6_PUBLIC_CIDR}$(printf '%02X' ${worker_ip_suffix})
            ipv6_public_workers_addrs+=(${worker_host_ipv6})

            worker_cilium_ipv4="${base_workers_ip}${worker_ip_suffix}"
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


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#
# 						Vagrant & Virtualbox Functions 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`#

# set_vagrant_env sets up Vagrantfile environment variables
function set_vagrant_env(){
	local ipv4_array_l
    split_ipv4 ipv4_array_l "${MASTER_IPV4}"
    export 'IPV4_BASE_ADDR'="$(printf "%d.%d.%d." "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}")"
    export 'FIRST_IP_SUFFIX'="${ipv4_array_l[3]}"

    split_ipv4 ipv4_array_nfs "${MASTER_IPV4_NFS}"
    export 'IPV4_BASE_ADDR_NFS'="$(printf "%d.%d.%d." "${ipv4_array_nfs[0]}" "${ipv4_array_nfs[1]}" "${ipv4_array_nfs[2]}")"
    export 'FIRST_IP_SUFFIX_NFS'="${ipv4_array[3]}"
    if [[ -n "${NFS}" ]]; then
        echo "# NFS enabled. don't forget to enable this ports on your host"
        echo "# before starting the VMs in order to have nfs working"
        echo "# iptables -I INPUT -p udp -s ${IPV4_BASE_ADDR_NFS}0/24 --dport 111 -j ACCEPT"
        echo "# iptables -I INPUT -p udp -s ${IPV4_BASE_ADDR_NFS}0/24 --dport 2049 -j ACCEPT"
        echo "# iptables -I INPUT -p udp -s ${IPV4_BASE_ADDR_NFS}0/24 --dport 20048 -j ACCEPT"
    fi

    temp=$(printf " %s" "${ipv6_public_workers_addrs[@]}")
    export 'IPV6_PUBLIC_WORKERS_ADDRS'="${temp:1}"
    # echo "IPV6_PUBLIC_WORKERS_ADDRS: ${IPV6_PUBLIC_WORKERS_ADDRS}"
    if [[ "${IPV4}" -ne "1" ]]; then
        export 'IPV6_EXT'=1
    fi
}


# vboxnet_create_new_interface creates a new host only network interface with
# VBoxManage utility. Returns the created interface name in ${1}.
function vboxnet_create_new_interface(){
    output=$(VBoxManage hostonlyif create)
    vboxnet_interface=$(echo "${output}" | grep -oE "'[a-zA-Z0-9]+'" | sed "s/'//g")
    if [ -z "${vboxnet_interface}" ]; then
        echo "Unable create VBox hostonly interface:"
        echo "${output}"
        return
    fi
    eval "${1}=${vboxnet_interface}"
}

# vboxnet_add_ipv6 adds the IPv6 in ${2} with the netmask length in ${3} in the
# hostonly network interface set in ${1}.
function vboxnet_add_ipv6(){
    vboxnetif="${1}"
    ipv6="${2}"
    ipv6_mask="${3}"
    VBoxManage hostonlyif ipconfig "${vboxnetif}" \
        --ipv6 "${ipv6}" --netmasklengthv6 "${ipv6_mask}"
}

# vboxnet_add_ipv4 adds the IPv4 in ${2} with the netmask in ${3} in the
# hostonly network interface set in ${1}.
function vboxnet_add_ipv4(){
    vboxnetif="${1}"
    ipv4="${2}"
    ipv4_mask="${3}"
    VBoxManage hostonlyif ipconfig "${vboxnetif}" \
        --ip "${ipv4}" --netmask "${ipv4_mask}"
}

# vboxnet_addr_finder checks if any vboxnet interface has the IPv6 public CIDR
function vboxnet_addr_finder(){
    if [ -z "${IPV6_EXT}" ] && [ -z "${NFS}" ]; then
        return
    fi

    all_vbox_interfaces=$(VBoxManage list hostonlyifs | grep -E "^Name|IPV6Address|IPV6NetworkMaskPrefixLength" | awk -F" " '{print $2}')
    # all_vbox_interfaces format example:
    # vboxnet0
    # fd00:0000:0000:0000:0000:0000:0000:0001
    # 64
    # vboxnet1
    # fd05:0000:0000:0000:0000:0000:0000:0001
    # 16
    if [[ -n "${RELOAD}" ]]; then
        all_ifaces=$(echo "${all_vbox_interfaces}" | awk 'NR % 3 == 1')
        if [[ -n "${all_ifaces}" ]]; then
            while read -r iface; do
                iface_addresses=$(ip addr show "$iface" | grep inet6 | sed 's/.*inet6 \([a-fA-F0-9:/]\+\).*/\1/g')
                # iface_addresses format example:
                # fd00::1/64
                # fe80::800:27ff:fe00:2/64
                if [[ -z "${iface_addresses}" ]]; then
                    # No inet6 addresses
                    continue
                fi
                while read -r ip; do
                    if [ ! -z $(echo "${ip}" | grep -i "${IPV6_PUBLIC_CIDR/::/:}") ]; then
                        found="1"
                        net_mask=$(echo "${ip}" | sed 's/.*\///')
                        vboxnetname="${iface}"
                        break
                    fi
                done <<< "${iface_addresses}"
                if [[ -n "${found}" ]]; then
                    break
                fi
            done <<< "${all_ifaces}"
        fi
    fi
    if [[ -z "${found}" ]]; then
        all_ipv6=$(echo "${all_vbox_interfaces}" | awk 'NR % 3 == 2')
        line_ip=0
        if [[ -n "${all_vbox_interfaces}" ]]; then
            while read -r ip; do
                line_ip=$(( $line_ip + 1 ))
                if [ ! -z $(echo "${ip}" | grep -i "${IPV6_PUBLIC_CIDR/::/:}") ]; then
                    found=${line_ip}
                    net_mask=$(echo "${all_vbox_interfaces}" | awk "NR == 3 * ${line_ip}")
                    vboxnetname=$(echo "${all_vbox_interfaces}" | awk "NR == 3 * ${line_ip} - 2")
                    break
                fi
            done <<< "${all_ipv6}"
        fi
    fi

    if [[ -z "${found}" ]]; then
        echo "WARN: VirtualBox interface with \"${IPV6_PUBLIC_CIDR}\" not found"
        if [ ${YES_TO_ALL} -eq "0" ]; then
            read -r -p "Create a new VBox hostonly network interface? [y/N] " response
        else
            response="Y"
        fi
        case "${response}" in
            [yY])
                echo "Creating VBox hostonly network..."
            ;;
            *)
                exit
            ;;
        esac
        vboxnet_create_new_interface vboxnetname
        if [ -z "${vboxnet_interface}" ]; then
            exit 1
        fi
    elif [[ "${net_mask}" -ne 64 ]]; then
        echo "WARN: VirtualBox interface with \"${IPV6_PUBLIC_CIDR}\" found in ${vboxnetname}"
        echo "but set wrong network mask (${net_mask} instead of 64)"
        if [ ${YES_TO_ALL} -eq "0" ]; then
            read -r -p "Change network mask of '${vboxnetname}' to 64? [y/N] " response
        else
            response="Y"
        fi
        case "${response}" in
            [yY])
                echo "Changing network mask to 64..."
            ;;
            *)
                exit
            ;;
        esac
    fi
    split_ipv4 ipv4_array_nfs "${MASTER_IPV4_NFS}"
    IPV4_BASE_ADDR_NFS="$(printf "%d.%d.%d.1" "${ipv4_array_nfs[0]}" "${ipv4_array_nfs[1]}" "${ipv4_array_nfs[2]}")"
    vboxnet_add_ipv6 "${vboxnetname}" "${IPV6_PUBLIC_CIDR}1" 64
    vboxnet_add_ipv4 "${vboxnetname}" "${IPV4_BASE_ADDR_NFS}" "255.255.255.0"
}

# Sets the RELOAD env variable with 1 if there is any VM printed by
# vagrant status.
function set_reload_if_vm_exists(){
    if [ -z "${RELOAD}" ]; then
        if [[ $(vagrant status 2>/dev/null | wc -l) -gt 1 && \
                ! $(vagrant status 2>/dev/null | grep "not created") ]]; then
            RELOAD=1
        fi
    fi
}


if [[ "${VAGRANT_DEFAULT_PROVIDER}" -eq "virtualbox" ]]; then
     vboxnet_addr_finder
fi

ipv6_internal_workers_addrs=() 
ipv6_podCIDR_workers_addrs=()
ipv6_public_workers_addrs=()

split_ipv4 ipv4_array "${MASTER_IPV4}"
export 'MASTER_IPV6'="${IPV6_INTERNAL_CIDR}$(printf '%02X' ${ipv4_array[3]})"
export 'MASTER_IPV6_PUBLIC'="${IPV6_PUBLIC_CIDR}$(printf '%02X' ${ipv4_array[3]})"
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


