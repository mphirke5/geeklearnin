#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}[1/12] Installing required packages...${NC}"
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y kernel-devel-$(uname -r) containerd.io firewalld wget curl --nobest --allowerasing

echo -e "${GREEN}[2/12] Loading kernel modules...${NC}"
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

echo -e "${GREEN}[3/12] Configuring sysctl for Kubernetes...${NC}"
cat <<EOF | tee /etc/sysctl.d/kubernetes.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

echo -e "${GREEN}[4/12] Disabling swap...${NC}"
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

echo -e "${GREEN}[5/12] Setting up containerd...${NC}"
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo -e "${GREEN}[6/12] Configuring firewall...${NC}"
firewall-cmd --zone=public --permanent --add-port=6443/tcp
firewall-cmd --zone=public --permanent --add-port=2379-2380/tcp
firewall-cmd --zone=public --permanent --add-port=10250/tcp
firewall-cmd --zone=public --permanent --add-port=10251/tcp
firewall-cmd --zone=public --permanent --add-port=10252/tcp
firewall-cmd --zone=public --permanent --add-port=10255/tcp
firewall-cmd --zone=public --permanent --add-port=5473/tcp
firewall-cmd --reload

echo -e "${GREEN}[7/12] Adding Kubernetes repo...${NC}"
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo -e "${GREEN}[8/12] Installing Kubernetes tools...${NC}"
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

echo -e "${GREEN}[9/12] Pulling Kubernetes images...${NC}"
kubeadm config images pull

echo -e "${GREEN}[10/12] Initializing Kubernetes cluster...${NC}"
kubeadm init --pod-network-cidr=10.128.0.0/14

echo -e "${GREEN}[11/12] Setting up kubeconfig...${NC}"
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

echo -e "${GREEN}[12/12] Installing Flannel network plugin...${NC}"
curl -LO https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
sed -i 's/10.244.0.0\/16/10.128.0.0\/14/g' kube-flannel.yml
kubectl apply -f kube-flannel.yml

echo -e "${GREEN}✅ Kubernetes cluster setup completed successfully!${NC}"
