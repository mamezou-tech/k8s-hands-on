#!/bin/bash

MASTER_IP=172.16.10.11
BASEDIR=$(dirname "$0")
SHARED_DIR=${1:-$BASEDIR/local-cluster/ubuntu1804/shared}
 
kubectl config set-cluster local-k8s --server=https://${MASTER_IP}:6443 \
  --certificate-authority=${SHARED_DIR}/ca.crt --embed-certs
kubectl config set-credentials admin \
  --client-certificate=${SHARED_DIR}/k8s-admin.crt \
  --client-key=${SHARED_DIR}/k8s-admin.key \
  --embed-certs
kubectl config set-context local-k8s-tester \
  --cluster=local-k8s --namespace=default --user=admin

kubectl config use-context local-k8s-tester

which helm
rc=$?
if [[ $rc != 0 ]] ;then
  curl -L https://git.io/get_helm.sh | bash
fi
# add stable repo
helm repo add bitnami https://charts.bitnami.com/bitnami

# MetalLB
kubectl create namespace metallb-system
helm upgrade metallb --install bitnami/metallb --namespace metallb-system --wait
rc=$?
if [[ $rc != 0 ]] ;then
  echo "unable to install MetalLB..."
  exit 1
fi
kubectl apply -f https://raw.githubusercontent.com/kudoh/k8s-hands-on/master/ingress/metallb-configmap.yaml
sleep 5

# Nginx Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create ns nginx-ingress
helm upgrade nginx-ingress --install ingress-nginx/ingress-nginx \
   --namespace nginx-ingress --set controller.replicaCount=2
rc=$?
if [[ $rc != 0 ]] ;then
  echo "unable to install Ingress Controller..."
  exit 1
fi

# OpenEBS
for n in $(kubectl get node -l 'node-role.kubernetes.io/master!=' -o jsonpath='{.items[*].metadata.name}' | grep -i worker); do 
  kubectl label nodes $n node=openebs
done
kubectl create ns openebs
helm repo add openebs https://openebs.github.io/charts
helm repo update
helm upgrade openebs --install openebs/openebs --namespace openebs --version 2.3.1 \
  --set apiserver.sparse.enabled=true \
  --set ndm.sparse.count=1 \
  --set ndm.sparse.size=32212254720 \
  --wait

rc=$?
if [[ $rc != 0 ]] ;then
  echo "unable to install OpenEBS..."
  exit 1
fi
# no more needed, openebs generate default resources
# kubectl apply -f https://raw.githubusercontent.com/kudoh/k8s-hands-on/master/storage/cstor-pool-config.yaml
# kubectl apply -f https://raw.githubusercontent.com/kudoh/k8s-hands-on/master/storage/storageclass.yaml

echo "Done!!"