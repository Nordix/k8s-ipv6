#!/usr/bin/env bash
#
# Installs and Starts Calico 
#######################################

MASTER=${1}
ROUTER_ID=${2}

# pre-load docker images
if [ "${CALICO_PRELOAD_LOCAL_IMAGES}" == "true" ]; then
	echo "attempting to load prebuilt images of calico components"
	sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"node/calico-node-latest.tar
	sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"cni-plugin/calico-cni-latest.tar
	sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"kube-controllers/calico-kube-controllers-latest.tar
	# sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"calicoctl/calico-ctl-latest.tar
	sudo docker image ls

	sudo cp "${CALICO_VAGRANT_BASE_DIR}"calicoctl/bin/* /usr/local/bin 
	sudo chmod +x /usr/local/bin/calicoctl-linux-amd64
	sudo ln -s /usr/local/bin/calicoctl-linux-amd64 calicoctl
fi

if [ "${CNI_INSTALL_TYPE}" == "systemd" ]; then
	# Reference:
	# https://docs.projectcalico.org/v3.7/getting-started/kubernetes/installation/integration

	sudo cp "${CALICO_VAGRANT_BASE_DIR}"cni-plugin/bin/amd64/* /opt/cni/bin 
	sudo chmod +x /opt/cni/bin/calico /opt/cni/bin/calico-ipam

	if [ "${MASTER}" == "true" ]; then
		# start a local etcd cluster for use by calico 
		# sudo etcd --data-dir="/home/vagrant/default.etcd" --listen-client-urls="${CALICO_ETCD_EP_V6}","${CALICO_ETCD_EP_V4}" --advertise-client-urls="${CALICO_ETCD_EP_V6}" &
		# sudo etcd --data-dir="/home/vagrant/default.etcd" --listen-client-urls=http://[::1]:6666,http://127.0.0.1:6666 --advertise-client-urls=http://[::1]:6666
		
		# sudo etcd --name=calico --data-dir=/var/etcd/calico --advertise-client-urls="${CALICO_ETCD_EP_V4}" --listen-client-urls=http://0.0.0.0:6666 --listen-peer-urls=http://0.0.0.0:6667 &
		sudo tee /etc/systemd/system/calico-etcd.service <<EOF
[Unit]
Description=calico-etcd
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
User=root
Type=notify
ExecStart=/usr/bin/etcd --name=calico --data-dir=/var/etcd/calico \
  --advertise-client-urls="${CALICO_ETCD_EP_V4}" --listen-client-urls=http://0.0.0.0:6666 \
  --listen-peer-urls=http://0.0.0.0:6667 
Restart=always
RestartSec=10s
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target

EOF
		sudo systemctl enable calico-etcd
		sudo systemctl restart calico-etcd
		sudo systemctl status calico-etcd --no-pager

		cp "${CALICO_PATH}calico-kube-controllers-template.yaml" "${CALICO_PATH}calico-kube-controllers.yaml"
		sed -i -e "s?ADD_ETCD_ENDPOINTS_HERE?$CALICO_ETCD_EP_V4?g" "${CALICO_PATH}calico-kube-controllers.yaml"
		kubectl apply -f "${CALICO_PATH}calico-kube-controllers.yaml"

		kubectl apply -f "${CALICO_PATH}rbac-etcd-calico.yaml"

	fi

	if [[ -n "${IPV6_EXT}" ]]; then
		CALICO_IPV6POOL_CIDR="${K8S_CLUSTER_CIDR}"
		CALICO_IPV4POOL_CIDR=""
		FELIX_IPV6SUPPORT=true
	else
		CALICO_IPV6POOL_CIDR=""
		CALICO_IPV4POOL_CIDR="${K8S_CLUSTER_CIDR}"
	fi


	sudo tee /etc/systemd/system/calico-node.service <<EOF
[Unit]
Description=calico-node
After=docker.service
Requires=docker.service

[Service]
User=root
Environment=ETCD_ENDPOINTS=${CALICO_ETCD_EP_V4}
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run --net=host --privileged --name=calico-node \
  -e ETCD_ENDPOINTS=${CALICO_ETCD_EP_V4} \
  -e NODENAME=${HOSTNAME} \
  -e IP= \
  -e IP6= \
  -e AS= \
  -e NO_DEFAULT_POOLS= \
  -e CALICO_LIBNETWORK_ENABLED=false \
  -e CALICO_NETWORKING_BACKEND=bird \
  -e FELIX_DEFAULTENDPOINTTOHOSTACTION=ACCEPT \
  -e CALICO_STARTUP_LOGLEVEL=debug \
  -e IP_AUTODETECTION_METHOD=interface=enp0s8 \
  -e CALICO_IPV4POOL_CIDR=${CALICO_IPV4POOL_CIDR} \
  -e CALICO_IPV6POOL_CIDR=${CALICO_IPV6POOL_CIDR} \
  -e FELIX_IPV6SUPPORT=${FELIX_IPV6SUPPORT} \
  -v /lib/modules:/lib/modules \
  -v /run/docker/plugins:/run/docker/plugins \
  -v /var/run/calico:/var/run/calico \
  -v /var/log/calico:/var/log/calico \
  -v /var/lib/calico:/var/lib/calico \
  calico/node:latest-amd64 
ExecStop=/usr/bin/docker rm -f calico-node
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target

EOF

	sudo systemctl enable calico-node
	sudo systemctl restart calico-node
	sudo systemctl status calico-node --no-pager


else # [ "${CNI_INSTALL_TYPE}" == "daemonset" ]; then
	echo "installing calico via k8s daemonsets"
	if [[ -n "${IPV6_EXT}" ]]; then
		if [ "${MASTER}" == "true" ]; then
			kubectl apply -f "${CALICO_PATH}calico.yaml"
		fi
	else
		if [ "${MASTER}" == "true" ]; then
			cp "${CALICO_PATH}calico-ipv4-template.yaml" "${CALICO_PATH}calico-ipv4.yaml"
			CALICO_IPV4POOL_CIDR="${K8S_CLUSTER_CIDR}" 
			sed -i -e "s?192.168.0.0/16?$CALICO_IPV4POOL_CIDR?g" "${CALICO_PATH}calico-ipv4.yaml"
			kubectl apply -f "${CALICO_PATH}calico-ipv4.yaml"
		fi
	fi
fi 