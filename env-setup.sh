cat <<EOF >> /home/vagrant/.bashrc
alias kc="kubectl"
alias kgp="kubectl get pods --all-namespaces -o wide"
alias kgsa="kubectl get svc --all-namespaces -o wide"
alias kgep="kubectl get endpoints --all-namespaces -o wide"
alias kgds="kubectl get daemonsets --all-namespaces -o wide"
alias kgdp="kubectl get deployments --all-namespaces -o wide"

function kd () {
	kubectl delete -f "\$@" --grace-period=0 --force
}
function kbb () {
	kubectl run -i --tty "\$@" --image=busybox -- sh  # Run pod as interactive shell
}
function ke () {
	kubectl exec "\${1}" -- "\${2}"
}

EOF

echo 'cd ~/go/src/github.com/Nordix/k8s-ipv6' >> /home/vagrant/.bashrc