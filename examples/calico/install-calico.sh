#!/usr/bin/env bash
#
# Installs and Starts Calico 
#######################################

CNI_INSTALL_TYPE=${1}
CALICO_VAGRANT_BASE_DIR=${2}
CNI_ARGS=${4}

# Ensure that these match with values in start.sh
CALICO_ETCD_EP_V6="http://[::1]:6666"
CALICO_ETCD_EP_V4="http://127.0.0.1:6666"
cp "${CALICO_VAGRANT_BASE_DIR}"cni-plugin/bin/amd64/* /opt/cni/bin 
chmod +x /opt/cni/bin/calico /opt/cni/bin/calico-ipam
cp "${CALICO_VAGRANT_BASE_DIR}"calicoctl/bin/* /usr/local/bin 
chmod +x /usr/local/bin/calicoctl-linux-amd64
ln -s /usr/local/bin/calicoctl-linux-amd64 calicoctl

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
sudo /usr/bin/docker rm calico-node
sudo /usr/bin/docker load --input "${CALICO_VAGRANT_BASE_DIR}"node/calico-node-latest.tar
sudo docker image ls


sudo systemctl enable calico-node
sudo systemctl restart calico-node
sudo systemctl status calico-node --no-pager