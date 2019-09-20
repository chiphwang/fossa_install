#!/bin/bash
if [ "$(id -u)" != "0" ]; then
exec sudo "$0" "$@"
fi
cd /opt/
#Check OS to use appropriate package manager & turn off selinux for Centos 7
if [ -f /etc/redhat-release ]; then
  OS_CHECK=yumpm
  sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config
  set enforce 0 sestatus
fi

if [ -f /etc/lsb-release ]; then
  OS_CHECK=aptgetpm
fi

##Prompt for FOSSA server hostname
#read -ep "Enter the hostname for the FOSSA server " fossa_hostname

##Prompt for Minio hostname
#read -ep "Enter the hostname for the Minio server " minio_hostname


##Prompt for path and file names for FOSSA key
#read -ep "Enter directory path for FOSSA Certificate Files (Example: /xxx/yyy/certs) " fossa_file_dir
#capture key file name
#read -ep "Enter the file name of your FOSSA key file " fossa_key
#capture certificate file name
#read -ep "Enter the file name of your FOSSA certificate file " fossa_cert
#mkdir /root/fossacerts/
#cp $fossa_file_dir/$fossa_key /root/fossacerts/tls.key
#cp $fossa_file_dir/$fossa_cert /root/fossacerts/tls.crt

##Prompt for path and file names for Minio key
#read -ep "Enter directory path for Minio Certificate Files (Example: /xxx/yyy/certs) " minio_file_dir
#capture key file name
#read -ep "Enter the file name of your Minio key file " minio_key
#capture certificate file name
#read -ep "Enter the file name of your Minio certificate file " minio_cert
#mkdir /root/miniocerts/
#cp $minio_file_dir/$minio_key /root/miniocerts/tls.key
#cp $minio_file_dir/$minio_cert /root/miniocerts/tls.crt
#cp $minio_file_dir/$minio_cert /root/miniocerts/minio.pem
    

#Check for EC2
#Set Environment Variables
#read -p "Install in EC2 (y/n)? " ec2_answer
#case ${ec2_answer:0:1} in
#    y|Y )
#       export PRIMARY_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
#        #export PRIMARY_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
#        export FQN=$(curl http://169.254.169.254/latest/meta-data/public-hostname)
#    ;;
#    * )
#        export PRIMARY_IP=$(ip route get 1 | awk '{print $NF;exit}')
#        export FQN=$(nslookup $(hostname -i)) ; fqn=${fqn##*name = } ; fqn=${fqn%.*} ; echo $fqn
#    ;;
#esac




#Update packages
if [ "$OS_CHECK" = "aptgetpm" ]; then
    sudo apt-get update -y
    #Install expect
    sudo apt-get install -y expect
    ################################################################################################
    #Install Docker
    sudo apt-get -y install docker.io
    #Create links
    sudo ln -sf /usr/bin/docker.io /usr/local/bin/docker

    ################################################################################################
    #Install PostgreSQL
    #sudo apt-get -y install postgresql postgresql-contrib
fi
if [ "$OS_CHECK" = "yumpm" ]; then
    sudo yum update -y
    #Install expect
    sudo yum install -y expect
    #Install XXD which is used in the configure.sh
    sudo yum install -y vim-common
    ################################################################################################

    ###############################################################################################
    ####download setup.sh for Centos support
#    sudo mv /opt/fossa/setup.sh /opt/fossa/setup.sh.bak
    yum install -y wget
#    wget -c https://raw.githubusercontent.com/joey-fossa/fossa-install/master/setup_centos.sh -O /opt/fossa/setup.sh
#    sudo chmod +x /opt/fossa/setup.sh
fi
################################################################################################
################################################################################################
# Get the Docker gpg key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
#Add the Docker repository:
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
#Get the Kubernetes gpg key
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
# Add the Kubernetes repository:
cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
#Update packages
sudo apt-get update
#turn swap off
sudo swapoff –a
#Install Docker, kubelet, kubeadm and kubectl
sudo apt-get install -y docker-ce=18.06.1~ce~3-0~ubuntu kubelet=1.13.5-00 kubeadm=1.13.5-00 kubectl=1.13.5-00
#Hold them at the current version:
sudo apt-mark hold docker-ce kubelet kubeadm kubectl
#Add the iptables rules to sysctl.conf
echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf
#enable iptables immediately:
sudo sysctl -p
#Initialize the cluster (run only on the master)
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
#set up local kubeconfig:
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
sudo chmod +r $HOME/.kube/config
#Apply Flannel CNI network overlay:
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml
#Verify the kubernetes node:
kubectl get nodes
#Remove tain from the master node
kubectl taint nodes --all node-role.kubernetes.io/master-
###################################################################################################
#Deplyo FOSSA
###################################################################################################
cd /opt/
#Clone Github repo for Fossa
git clone https://github.com/chiphwang/fossa_helm.git
#create FOSSA namespace
kubectl create ns fossa
#Create FOSSA directories
cd /opt; mkdir fossa; cd fossa; mkdir database; mkdir minio; chmod 777 database; chmod 777 minio
# Create image pull secret for Quay to pull images
cd /opt/fossa_helm/

# install helm
curl -LO https://git.io/get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh

# install Tiller

kubectl -n kube-system create serviceaccount tiller

kubectl create clusterrolebinding tiller \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:tiller

# initialize Helm

helm init --service-account tiller

# move to working directory
cd /opt/fossa_helm

