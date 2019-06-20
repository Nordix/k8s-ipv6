#!/usr/bin/env bash

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

# get_ipv6_node_cidr constructs the ipv6 node cidr in ${1} from the IPv4 address
# in ${2}.
function get_ipv6_node_cidr(){
	local ipv4_array_l
    split_ipv4 ipv4_array_l "${2}"
	if [ -n "${EMBED_IPV4}" ]; then
	    hexIPv4=$(printf "%02X%02X:%02X%02X" "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}" "${ipv4_array_l[3]}")
	    eval "${1}=${CILIUM_IPV6_NODE_CIDR}${hexIPv4}:0:0"
	else
	    hexIPv4=$(printf "%02X::" "${ipv4_array_l[3]}")
		eval "${1}=${CILIUM_IPV6_NODE_CIDR}${hexIPv4}0:0"
	fi
}

function get_ipv6_node_cidr_gw_addr(){
	local ipv4_array_l
    split_ipv4 ipv4_array_l "${2}"
	if [ -n "${EMBED_IPV4}" ]; then
	    hexIPv4=$(printf "%02X%02X:%02X%02X" "${ipv4_array_l[0]}" "${ipv4_array_l[1]}" "${ipv4_array_l[2]}" "${ipv4_array_l[3]}")
	    eval "${1}=${CILIUM_IPV6_NODE_CIDR}${hexIPv4}:0:1"
	else
	    hexIPv4=$(printf "%02X::" "${ipv4_array_l[3]}")
		eval "${1}=${CILIUM_IPV6_NODE_CIDR}${hexIPv4}:0:1"
	fi
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

# write_ipv6_netcfg_header writes the internal network
# configuration for the vm IP ${1}. Sets the master's hostname with IPv6 address
# in ${2}.
function write_ipv6_netcfg_header(){
    vm_ipv6="${1}"
    master_ipv6="${2}"
    filename="${3}"
    cat <<EOF >> "${filename}"

			# IPv6 #

ip -6 a a ${vm_ipv6}/16 dev enp0s8

echo '${master_ipv6} ${VM_BASENAME}1' >> /etc/hosts
sysctl -w net.ipv6.conf.all.forwarding=1

# For ipv6, default route will point to s9 interface
ip -6 r a default via ${IPV6_PUBLIC_CIDR}1 dev enp0s9

EOF
}

# write_ipv4_netcfg_header writes the internal network
# configuration for the vm IP ${1}. Sets the master's hostname with IPv4 address
# in ${2}.
function write_ipv4_netcfg_header(){
    vm_ipv4="${1}"
    master_ipv4="${2}"
    filename="${3}"
    cat <<EOF >> "${filename}"
            
            # IPv4 #

echo '${master_ipv4} ${VM_BASENAME}1' >> /etc/hosts
sysctl -w net.ipv4.conf.all.forwarding=1

EOF
}


function write_master_route(){
    master_ipv4_suffix="${1}"
    master_ipv6_node_cidr="${2}"
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

function write_ipv4_route_entry(){
    podcidr="${1}"
    node_ipv4="${2}"
    filename="${3}"
# sudo ip r a <podCIDR>  via <host's ip > 
cat <<EOF >> "${filename}"
ip r a ${podcidr}/24 via ${node_ipv4}
EOF
}

# add_ipv4_podCIDR_routes_on_master adds routes for the podCIDR of all the workers
# on the master node.
function add_ipv4_podCIDR_routes_on_master(){
    filename="${1}"         
cat <<EOF >> "${filename}"
# Manual routes for podCIDRs:  
EOF
    if [ -n "${NWORKERS}" ]; then
        for i in `seq 0 $(( NWORKERS - 1 ))`; do
            write_ipv4_route_entry "${ipv4_podCIDR_workers_addrs[i]}" "${ipv4_internal_workers_addrs[i]}" "${filename}"
        done
    fi

}

# add_ipv4_podCIDR_routes_on_workers adds routes for podCIDRs of each node. 
# This is required for the cni bridge plugin for multi-node communication. 
function add_ipv4_podCIDR_routes_on_workers(){
    node_index="${1}"
    filename="${2}"

cat <<EOF >> "${filename}"
# Manual routes for podCIDRs:  
EOF

    # Add master podCIDR to worker
    write_ipv4_route_entry "10.128.0.0" "${MASTER_IPV4}" "${filename}"

    # Add entry of each worker, skipping self.
    for j in `seq 0 $(( NWORKERS - 1 ))`; do
        idx=$(expr $j + 2)
        if [ "${idx}" -eq "${node_index}" ]; then
            continue
        fi
        write_ipv4_route_entry "${ipv4_podCIDR_workers_addrs[j]}" "${ipv4_internal_workers_addrs[j]}" "${filename}"
    done
      
}


function write_ipv6_route_entry(){
    podcidr="${1}"
    node_ipv6="${2}"
    filename="${3}"
# sudo ip -6 r a fd02::c0a8:210c:0:0/96  via fd01::c 
cat <<EOF >> "${filename}"
ip -6 r a ${podcidr}/${CILIUM_IPV6_NODE_MASK_SIZE} via ${node_ipv6}
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
			write_ipv6_route_entry "${ipv6_podCIDR_workers_addrs[i]}" "${ipv6_internal_workers_addrs[i]}" "${filename}"
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

    get_ipv6_node_cidr master_ipv6_node_cidr "${MASTER_IPV4}"

cat <<EOF >> "${filename}"
# Manual routes for podCIDRs:  
EOF

	# Add master podCIDR to worker
	write_ipv6_route_entry "${master_ipv6_node_cidr}" "${master_ipv6}" "${filename}"

	# Add entry of each worker, skipping self.
    for j in `seq 0 $(( NWORKERS - 1 ))`; do
        idx=$(expr $j + 2)
        if [ "${idx}" -eq "${node_index}" ]; then
            continue
        fi
		write_ipv6_route_entry "${ipv6_podCIDR_workers_addrs[j]}" "${ipv6_internal_workers_addrs[j]}" "${filename}"
    done
      
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
    if [ -z "${IPV6_EXT}" ] && [ -z "${NFS}" ] && [ -z "${IPV4_EXT}" ]; then
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
        if [ "${YES_TO_ALL}" -eq "0" ]; then
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
        if [ "${YES_TO_ALL}" -eq "0" ]; then
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
