#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}[1/8] Installing required packages...${NC}"
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y kernel-devel-$(uname -r) containerd.io firewalld wget curl --nobest --allowerasing

echo -e "${GREEN}[2/8] Loading kernel modules...${NC}"
cat <<EOF | tee /etc/modules-load.d/kubernetes.conf
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
overlay
EOF

modprobe br_netfilter
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe overlay

echo -e "${GREEN}[3/8] Configuring sysctl for Kubernetes...${NC}"
cat <<EOF | tee /etc/sysctl.d/kubernetes.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

echo -e "${GREEN}[4/8] Disabling swap...${NC}"
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

echo -e "${GREEN}[5/8] Setting up containerd...${NC}"
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo -e "${GREEN}[6/8] Configuring firewall...${NC}"
firewall-cmd --zone=public --permanent --add-port=10250/tcp
firewall-cmd --zone=public --permanent --add-port=10255/tcp
firewall-cmd --zone=public --permanent --add-port=30000-32767/tcp
firewall-cmd --reload

echo -e "${GREEN}[7/8] Adding Kubernetes repo...${NC}"
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo -e "${GREEN}[8/8] Installing Kubernetes tools...${NC}"
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

echo -e "${GREEN}✅ Worker node setup completed!${NC}"
echo -e "${GREEN}➡ Please join this node to the cluster using the 'kubeadm join' command from the master node.${NC}"

