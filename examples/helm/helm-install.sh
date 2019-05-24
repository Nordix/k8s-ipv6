#!/usr/bin/env bash

# NOTE: latest release should be pre-downloaded on the host machine from
# https://github.com/helm/helm/releases
sudo cp "${HELM_BASE_DIR}"latest-release/linux-amd64/* /usr/local/bin 

kubectl create -f "${HELM_BASE_DIR}"rbac-config.yaml

helm init --service-account tiller --history-max 200

helm repo update
