cat <<EOF >> /home/vagrant/.bashrc
alias kc="kubectl"
alias kgpa="kubectl get pods --all-namespaces"
alias kgp="kubectl get pods -o wide"
alias kgs="kubectl get services"
alias kgsa="kubectl get svc --all-namespaces"
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