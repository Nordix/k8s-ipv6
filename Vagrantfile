# test	# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.require_version ">= 2.0.0"

if ARGV.first == "up" && ENV['EARVWAN_SCRIPT'] != 'true'
    raise Vagrant::Errors::VagrantError.new, <<END
Calling 'vagrant up' directly is not supported.  Instead, please run the following:
  export NWORKERS=n
  ./start.sh
END
end

$node_ip_base = ENV['IPV4_BASE_ADDR'] || ""
$node_nfs_base_ip = ENV['IPV4_BASE_ADDR_NFS'] || ""
$num_workers = (ENV['NWORKERS'] || 0).to_i
$workers_ipv4_addrs = $num_workers.times.collect { |n| $node_ip_base + "#{n+(ENV['FIRST_IP_SUFFIX']).to_i+1}" }
$workers_ipv4_addrs_nfs = $num_workers.times.collect { |n| $node_nfs_base_ip + "#{n+(ENV['FIRST_IP_SUFFIX_NFS']).to_i+1}" }
$master_ip = ENV['MASTER_IPV4']
$master_ipv6 = ENV['MASTER_IPV6_PUBLIC']
$workers_ipv6_addrs_str = ENV['IPV6_PUBLIC_WORKERS_ADDRS'] || ""
$workers_ipv6_addrs = $workers_ipv6_addrs_str.split(' ')

$vm_base_name = "k8s"

servers = YAML.load_file('./servers.yaml')

n = 0
Vagrant.configure(2) do |config|
    # Always use Vagrant's default insecure key
    config.ssh.insert_key = true
    servers.each do |servers|
        config.vm.define servers["name"], primary: true do |srv|
            srv.vm.box = servers["box"] 
            srv.vm.box_version = servers["box_version"]
            config.vm.provider "virtualbox" do |vb|
                # Do not inherit DNS server from host, use proxy
                vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
                vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]

                vb.name = servers["name"]
                vb.memory = servers["ram"]
                vb.cpus = servers["vcpu"]                
            end
            if ENV["NFS"] then
                mount_type = "nfs"
                # Don't forget to enable this ports on your host before starting the VM
                # in order to have nfs working
                # iptables -I INPUT -p udp -s 192.168.34.0/24 --dport 111 -j ACCEPT
                # iptables -I INPUT -p udp -s 192.168.34.0/24 --dport 2049 -j ACCEPT
                # iptables -I INPUT -p udp -s 192.168.34.0/24 --dport 20048 -j ACCEPT
            else
                mount_type = ""
            end
            config.vm.synced_folder '.', '/home/vagrant/go/src/github.com/Nordix/k8s-ipv6', type: mount_type        
            config.vm.synced_folder '../../../k8s.io', '/home/vagrant/go/src/k8s.io', type: mount_type
            config.vm.synced_folder '../../cloudnativelabs/kube-router', '/home/vagrant/go/src/github.com/cloudnativelabs/kube-router', type: mount_type
            config.vm.synced_folder '../../projectcalico/cni-plugin', '/home/vagrant/go/src/github.com/projectcalico/cni-plugin', type: mount_type
            config.vm.synced_folder '../../projectcalico/node', '/home/vagrant/go/src/github.com/projectcalico/node', type: mount_type    
            config.vm.synced_folder '../../projectcalico/calicoctl', '/home/vagrant/go/src/github.com/projectcalico/calicoctl', type: mount_type    

            if servers["master"] then
                node_ip = "#{$master_ip}"
                srv.vm.network "forwarded_port", guest: 6443, host: 7443
                srv.vm.network "private_network", ip: "#{$master_ip}",
                    virtualbox__intnet: "earvwan-test",
                    :libvirt__guest_ipv6 => "yes",
                    :libvirt__dhcp_enabled => false
                if ENV["NFS"] || ENV["IPV6_EXT"] then
                    if ENV['FIRST_IP_SUFFIX_NFS'] then
                        $nfs_ipv4_master_addr = $node_nfs_base_ip + "#{ENV['FIRST_IP_SUFFIX_NFS']}"
                    end
                    srv.vm.network "private_network", ip: "#{$nfs_ipv4_master_addr}", bridge: "enp0s9"
                    # Add IPv6 address this way or we get hit by a virtualbox bug
                    puts "Running ipv6-config with master_ipv6 #{$master_ipv6}/16 on enp0s9"
                    srv.vm.provision "ipv6-config",
                        type: "shell",
                        run: "always",
                        privileged: true,
                        inline: "ip -6 a a #{$master_ipv6}/16 dev enp0s9"
                    node_ip = "#{$nfs_ipv4_master_addr}"
                    if ENV["IPV6_EXT"] then
                        node_ip = "#{$master_ipv6}"
                    end
                end
                srv.vm.hostname = servers["name"]
                if ENV['EARVWAN_TEMP'] then
                    script = "#{ENV['EARVWAN_TEMP']}/install-packages.sh"
                    srv.vm.provision "install-packages", type: "shell", privileged: true, run: "always", path: script
                    script = "#{ENV['EARVWAN_TEMP']}/env-setup.sh"
                    srv.vm.provision "env-setup", type: "shell", privileged: false, run: "always", path: script
                    script = "#{ENV['EARVWAN_TEMP']}/node-1.sh"
                    srv.vm.provision "config-install", type: "shell", privileged: true, run: "always", path: script

                    if ENV["K8S"] then
                       k8sinstall = "#{ENV['EARVWAN_TEMP']}/k8s-install-1st-part.sh"
                       srv.vm.provision "k8s-install-master-part-1",
                           type: "shell",
                           run: "always",
                           env: {"node_ip" => node_ip}, # EARVWAN: used as kubelet option: --node-ip=${node_ip}
                           privileged: true,
                           path: k8sinstall
                    end
                    # Only run install-kube-router after node-X above. node-X sets up the cni conf files.
                    if ENV["CNI"] == "kube-router" then
                        routerID = "0x1"
                        script = "./examples/kube-router/install-kube-router.sh"
                        srv.vm.provision "install-kube-router", type: "shell", privileged: true, run: "always", path: script, args: ["#{ENV['CNI_INSTALL_TYPE']}", "#{ENV['KUBEROUTER_VAGRANT_BIN_DIR']}", "#{routerID}", "#{ENV['CNI_ARGS']}"]
                    elsif ENV["CNI"] == "calico" then
                        script = "./examples/calico/install-calico.sh"
                        srv.vm.provision "install-calico", type: "shell", privileged: true, run: "always", path: script, args: ["#{ENV['CNI_INSTALL_TYPE']}", "#{ENV['CALICO_VAGRANT_BASE_DIR']}", "#{ENV['CNI_ARGS']}"]
                    end

                    if ENV["GOBGP"] then
                        script = "./client-vm/gobgp-setup.sh"
                        srv.vm.provision "gobgp-setup", type: "shell", privileged: true, run: "always", path: script
                    end
                   if ENV["K8S"] then
                       k8sinstall = "#{ENV['EARVWAN_TEMP']}/k8s-install-2nd-part.sh"
                       srv.vm.provision "k8s-install-master-part-2",
                           type: "shell",
                           run: "always",
                           env: {"node_ip" => node_ip},
                           privileged: true,
                           path: k8sinstall
                   end
                end
            else
                node_ip = $workers_ipv4_addrs[n]
                # srv.vm.network "forwarded_port", guest: 6443, host: 8443
                srv.vm.network "private_network", ip: "#{node_ip}",
                    virtualbox__intnet: "earvwan-test",
                    :libvirt__guest_ipv6 => 'yes',
                    :libvirt__dhcp_enabled => false
                if ENV["NFS"] || ENV["IPV6_EXT"] then
                    nfs_ipv4_addr = $workers_ipv4_addrs_nfs[n]
                    node_ip = "#{nfs_ipv4_addr}"
                    ipv6_addr = $workers_ipv6_addrs[n]
                    srv.vm.network "private_network", ip: "#{nfs_ipv4_addr}", bridge: "enp0s9"
                    # Add IPv6 address this way or we get hit by a virtualbox bug
                    # puts "Running ipv6-config with worker #{$ipv6_addr}/16 on enp0s9"
                    srv.vm.provision "ipv6-config",
                        type: "shell",
                        run: "always",
                        privileged: true,
                        inline: "ip -6 a a #{ipv6_addr}/16 dev enp0s9"
                    if ENV["IPV6_EXT"] then
                        node_ip = "#{ipv6_addr}"
                    end
                end
                srv.vm.hostname = servers["name"]
                if ENV['EARVWAN_TEMP'] then
                    script = "#{ENV['EARVWAN_TEMP']}/install-packages.sh"
                    srv.vm.provision "install-packages", type: "shell", privileged: true, run: "always", path: script
                    script = "#{ENV['EARVWAN_TEMP']}/env-setup.sh"
                    srv.vm.provision "env-setup", type: "shell", privileged: false, run: "always", path: script
                    script = "#{ENV['EARVWAN_TEMP']}/node-#{n+2}.sh"
                    srv.vm.provision "config-install", type: "shell", privileged: true, run: "always", path: script
                    
                    if ENV["K8S"] then
                        k8sinstall = "#{ENV['EARVWAN_TEMP']}/k8s-install-1st-part.sh"
                        srv.vm.provision "k8s-install-node-part-1",
                            type: "shell",
                            run: "always",
                            env: {"node_ip" => node_ip},
                            privileged: true,
                            path: k8sinstall
                    end
                    # Only run install-kube-router after node-X above. node-X sets up the cni conf files.
                    if ENV["CNI"] == "kube-router" then
                        routerID = "0x#{n+2}"
                        script = "./examples/kube-router/install-kube-router.sh"
                        srv.vm.provision "install-kube-router", type: "shell", privileged: true, run: "always", path: script, args: ["#{ENV['CNI_INSTALL_TYPE']}", "#{ENV['KUBEROUTER_VAGRANT_BIN_DIR']}", "#{routerID}", "#{ENV['CNI_ARGS']}"]
                    elsif ENV["CNI"] == "calico" then
                        script = "./examples/calico/install-calico.sh"
                        srv.vm.provision "install-calico", type: "shell", privileged: true, run: "always", path: script, args: ["#{ENV['CNI_INSTALL_TYPE']}", "#{ENV['CALICO_VAGRANT_BASE_DIR']}", "#{ENV['CNI_ARGS']}"]
                    end
                    if ENV["GOBGP"] then
                        script = "./client-vm/gobgp-setup.sh"
                        srv.vm.provision "gobgp-setup", type: "shell", privileged: true, run: "always", path: script
                    end
                    if ENV["K8S"] then
                        k8sinstall = "#{ENV['EARVWAN_TEMP']}/k8s-install-2nd-part.sh"
                        srv.vm.provision "k8s-install-node-part-2",
                            type: "shell",
                            run: "always",
                            env: {"node_ip" => node_ip},
                            privileged: true,
                            path: k8sinstall
                    end
                end
                n = n +1
            end
        end
    end 
end
