# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# 역할 분리 구조
#   Vagrant  : VM 3대 생성 (CPU, 메모리, 네트워크)        -> vagrant up
#   Ansible  : K3s 클러스터 구성 (ansible/site.yml)       -> ansible-playbook site.yml
#
# 기본 provider 는 VirtualBox. VMware 를 쓰려면
#   vagrant up --provider=vmware_desktop
#   + ansible/group_vars/all.yml 의 vagrant_provider 도 vmware_desktop 으로 변경

ENV["VAGRANT_DEFAULT_PROVIDER"] ||= "virtualbox"

BOX = "bento/ubuntu-24.04"

# 이름과 IP 는 ansible/inventory.ini 와 맞춰야 한다
NODES = [
  { name: "k3s-cp", ip: "192.168.56.10", cpu: 2, mem: 2048 },
  { name: "k3s-w1", ip: "192.168.56.11", cpu: 2, mem: 2048 },
  { name: "k3s-w2", ip: "192.168.56.12", cpu: 2, mem: 2048 },
]

Vagrant.configure("2") do |config|
  config.vm.box = BOX
  config.vm.box_check_update = false

  NODES.each do |n|
    config.vm.define n[:name] do |node|
      node.vm.hostname = n[:name]
      node.vm.network "private_network", ip: n[:ip]

      # Provider별 설정 (실행한 provider 블록만 적용된다)
      node.vm.provider "virtualbox" do |vb|
        vb.name         = n[:name]
        vb.cpus         = n[:cpu]
        vb.memory       = n[:mem]
        vb.linked_clone = true
      end
      node.vm.provider "vmware_desktop" do |v|
        v.gui                = false
        v.linked_clone       = true
        v.vmx["displayName"] = n[:name]
        v.vmx["numvcpus"]    = n[:cpu].to_s
        v.vmx["memsize"]     = n[:mem].to_s
      end
    end
  end
end
