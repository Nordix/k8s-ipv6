#!/usr/bin/env bash
#
# Installs and Starts Calico 
#######################################

ROUTER_ID=${1}

# pre-load docker images
if [ "${CALICO_PRELOAD_LOCAL_IMAGES}" == "true" ]; then
	echo "attempting to load prebuilt images of calico components"
	sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"node/calico-node-latest.tar
	sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"cni-plugin/calico-cni-latest.tar
	sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"kube-controllers/calico-kube-controllers-latest.tar
	# sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"calicoctl/calico-ctl-latest.tar
	sudo docker image ls
fi

sudo cp "${CALICO_VAGRANT_BASE_DIR}"calicoctl/bin/* /usr/local/bin 
sudo chmod +x /usr/local/bin/calicoctl-linux-amd64
sudo ln -s /usr/local/bin/calicoctl-linux-amd64 calicoctl


if [ "${CNI_INSTALL_TYPE}" == "systemd" ]; then

	sudo cp "${CALICO_VAGRANT_BASE_DIR}"cni-plugin/bin/amd64/* /opt/cni/bin 
	sudo chmod +x /opt/cni/bin/calico /opt/cni/bin/calico-ipam

	# start a local etcd cluster for use by calico 
	sudo etcd --data-dir="/home/vagrant/default.etcd" --listen-client-urls="${CALICO_ETCD_EP_V6}","${CALICO_ETCD_EP_V4}" --advertise-client-urls="${CALICO_ETCD_EP_V6}" &
	# sudo etcd --data-dir="/home/vagrant/default.etcd" --listen-client-urls=http://[::1]:6666,http://127.0.0.1:6666 --advertise-client-urls=http://[::1]:6666

sudo tee /etc/systemd/system/calico-node.service <<EOF
[Unit]
Description=calico node
After=docker.service
Requires=docker.service

[Service]
User=root
Environment=ETCD_ENDPOINTS=${CALICO_ETCD_EP_V6}
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run --net=host --privileged --name=calico-node \
  -e ETCD_ENDPOINTS=${CALICO_ETCD_EP_V6} \
  -e NODENAME=${HOSTNAME} \
  -e IP= \
  -e NO_DEFAULT_POOLS= \
  -e AS= \
  -e CALICO_LIBNETWORK_ENABLED=true \
  -e FELIX_DEFAULTENDPOINTTOHOSTACTION=ACCEPT \
  -e IP6= \
  -e CALICO_NETWORKING_BACKEND=bird \
  -e CALICO_STARTUP_LOGLEVEL=debug \
  -e IP_AUTODETECTION_METHOD=interface=enp0s8 \
  -e KUBECONFIG=/home/vagrant/.kube/config \
  -e CALICO_IPV4POOL_CIDR= \
  -v /var/run/calico:/var/run/calico \
  -v /var/lib/calico:/var/lib/calico \
  -v /lib/modules:/lib/modules \
  -v /run/docker/plugins:/run/docker/plugins \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/log/calico:/var/log/calico \
  calico/node:latest-amd64 
ExecStop=/usr/bin/docker rm -f calico-node
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# /usr/bin/docker run --net=host --privileged --name=calico-node -e ETCD_ENDPOINTS=http://[::1]:6666 -e NODENAME=k8s1 -e IP= -e NO_DEFAULT_POOLS= -e AS= -e CALICO_LIBNETWORK_ENABLED=true -e FELIX_DEFAULTENDPOINTTOHOSTACTION=ACCEPT -e IP6= -e CALICO_NETWORKING_BACKEND=bird -v /var/run/calico:/var/run/calico -v /lib/modules:/lib/modules -v /run/docker/plugins:/run/docker/plugins -v /var/run/docker.sock:/var/run/docker.sock -v /var/log/calico:/var/log/calico calico/node:latest-amd64

	sudo systemctl enable calico-node
	sudo systemctl restart calico-node
	sudo systemctl status calico-node --no-pager

else # [ "${CNI_INSTALL_TYPE}" == "daemonset" ]; then
	echo "installing calico via k8s daemonsets"
	if [[ -n "${IPV6_EXT}" ]]; then
		kubectl apply -f "${CALICO_PATH}calico.yaml"
	else
		cp "${CALICO_PATH}calico-ipv4-template.yaml" "${CALICO_PATH}calico-ipv4.yaml"
		CALICO_IPV4POOL_CIDR="${K8S_CLUSTER_CIDR}" 
		sed -i -e "s?192.168.0.0/16?$CALICO_IPV4POOL_CIDR?g" "${CALICO_PATH}calico-ipv4.yaml"
		kubectl apply -f "${CALICO_PATH}calico-ipv4.yaml"
	fi
fi 