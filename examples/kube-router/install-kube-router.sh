#!/usr/bin/env bash
#
# Starts kube-router on kubernetes workers.
#######################################

if [[ "${3}" == *"--run-service-proxy=false"* ]]; then
    echo "Kube-Proxy will be used"
else
	echo "Cleaning up any kube-proxy rules before starting kube-router with services handling"
    sudo kube-proxy --cleanup
fi


if systemctl is-active kube-router | grep -q 'inactive'; then
 echo "kube-router not currently running"
else
	sudo systemctl stop kube-router
fi

sudo cp "${1}"kube-router "/usr/bin"

sudo tee /etc/systemd/system/kube-router.service <<EOF
[Unit]
Description=Kube-Router
Documentation=github.com/cloudnativelabs/kube-router
After=network.target

[Service]
ExecStart=/usr/bin/kube-router \\
  --router-id=${2} \\
  ${3}

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kube-router
sudo systemctl restart kube-router

sudo systemctl status kube-router --no-pager