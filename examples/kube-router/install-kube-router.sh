#!/usr/bin/env bash
#
# Starts kube-router on kubernetes workers.
#######################################

sudo systemctl stop kube-router
sudo cp "${1}"kube-router "/usr/bin"

sudo tee /etc/systemd/system/kube-router.service <<EOF
[Unit]
Description=Kube-Router
Documentation=github.com/cloudnativelabs/kube-router
After=network.target

[Service]
ExecStart=/usr/bin/kube-router \\
  --v=3 \\
  --kubeconfig=/home/vagrant/.kube/config \\
  --run-firewall=false \\
  --run-service-proxy=false \\
  --run-router=true  \\
  --advertise-cluster-ip=true \\
  --routes-sync-period=10s \\
  --router-id=${2}

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kube-router
sudo systemctl restart kube-router

sudo systemctl status kube-router --no-pager