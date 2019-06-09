#!/usr/bin/env bash

function write_ipv6_cni_cfg(){
    if [[ "${CNI}" == "kube-router" && "${CNI_INSTALL_TYPE}" == "systemd" ]]; then
        write_cni_kuberouter_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}"
    elif [[ "${CNI}" == "calico" ]]; then
        write_cni_calico_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}" "IPv6"
    elif [ "${CNI}" == "bridge" ]; then
        write_cni_bridge_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}"
    fi
}

function write_ipv4_cni_cfg(){
    if [[ "${CNI}" == "kube-router" && "${CNI_INSTALL_TYPE}" == "systemd" ]]; then
        write_cni_kuberouter_cfg "${1}" "" "${3}" "${4}" "" "${6}"
    elif [[ "${CNI}" == "calico" ]]; then
        write_cni_calico_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}" "IPv4"
    elif [ "${CNI}" == "bridge" ]; then
        write_cni_bridge_cfg "${1}" "" "${3}" "${4}" "" "${6}"
    fi
}

function write_dual_stack_cni_cfg(){
	if [ "${CNI}" == "bridge" ]; then
        write_dual_stack_cni_bridge_cfg "${1}" "${2}" "${3}" "${4}" "${5}" "${6}" "${7}" "${8}" "${9}"
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
        "ranges": [
        	[
        		{
        			"subnet": "${ip_addr}/${mask_size}"
        		}
        	]
        ]   
    }
}
EOF

cat <<EOF >> "${filename}"

EOF
}


function write_dual_stack_cni_bridge_cfg(){
    node_index="${1}"
    master_ipv4_suffix="${2}"
    ipv4_addr="${3}"
    ipv4_mask_size="${4}"
    ipv4_gw_addr="${5}"
    ipv6_addr="${6}"
    ipv6_mask_size="${7}"
    ipv6_gw_addr="${8}"
    filename="${9}"

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
        "ranges": [
        	[
        		{
        			"subnet": "${ipv4_addr}/${ipv4_mask_size}"
        		}
        	],
        	[
        		{
        			"subnet": "${ipv6_addr}/${ipv6_mask_size}"
        		}
        	]
        ]   
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
#     "cniVersion": "0.6.0",
cat <<EOF >> "$filename"

cat <<EOF >> "/etc/cni/net.d/10-calico.conf"
{
    "name": "calico-k8s-network",
    "type": "calico",
    "etcd_endpoints": "${CALICO_ETCD_EP_V4}",
    "log_level": "DEBUG",
    "ipam": {
        "type": "calico-ipam"
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
    "etcd_endpoints": "${CALICO_ETCD_EP_V4}",
    "log_level": "DEBUG",
    "ipam": {
        "type": "calico-ipam",
        "assign_ipv4": "false",
        "assign_ipv6": "true"
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

    cat <<EOF > "${filename}"
#!/usr/bin/env bash

set -e

export IPV6_EXT="${IPV6_EXT}"
export K8S_VERSION="${K8S_VERSION}"
export VM_BASENAME="k8s"
export MASTER_IPV4="${MASTER_IPV4}"
export MASTER_IPV6="${MASTER_IPV6}"
export MASTER_IPV6_PUBLIC="${MASTER_IPV6_PUBLIC}"
export K8S_CLUSTER_CIDR="${K8S_CLUSTER_CIDR}"
export K8S_NODE_CIDR_MASK_SIZE="${K8S_NODE_CIDR_MASK_SIZE}"
export K8S_SERVICE_CLUSTER_IP_RANGE="${K8S_SERVICE_CLUSTER_IP_RANGE}"
export K8S_CLUSTER_API_SERVER_IP="${K8S_CLUSTER_API_SERVER_IP}"
export K8S_CLUSTER_DNS_IP="${K8S_CLUSTER_DNS_IP}"
export RUNTIME="${RUNTIME}"
export CNI_INSTALL_TYPE="${CNI_INSTALL_TYPE}"
export CNI_ARGS="${CNI_ARGS}"
MASTER=\${1}
ROUTER_ID=\${2}

EOF

    if [ "${CNI}" == "bridge" ]; then
    cat <<EOF >> "${filename}"
# bridge cni. nothing to do here.
EOF

    elif [ "${CNI}" == "calico" ]; then
    cat <<EOF >> "${filename}"
export CALICO_PATH="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/examples/calico/"
export CALICO_VAGRANT_BASE_DIR="${CALICO_VAGRANT_BASE_DIR}"
export CALICO_ETCD_EP_V4="${CALICO_ETCD_EP_V4}"
export CALICO_ETCD_EP_V6="${CALICO_ETCD_EP_V6}"
export CALICO_PRELOAD_LOCAL_IMAGES="${CALICO_PRELOAD_LOCAL_IMAGES}"

"\${CALICO_PATH}/install-calico.sh" \$MASTER \$ROUTER_ID
EOF

    else # kube-router is default
    cat <<EOF >> "${filename}"
kuberouter_path="/home/vagrant/go/src/github.com/Nordix/k8s-ipv6/examples/kube-router"
export KUBEROUTER_VAGRANT_BIN_DIR="${KUBEROUTER_VAGRANT_BIN_DIR}"
"\${kuberouter_path}/install-kube-router.sh" $MASTER $ROUTER_ID
EOF

    fi

}

