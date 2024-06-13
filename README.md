# The EODC Library for Kubernetes

---

Application helm charts, created by EODC, ready to launch on Kubernetes using Kubernetes Helm.

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: openeo-argo-access-sa.service-account-token
  annotations:
    kubernetes.io/service-account.name: openeo-argo-access-sa
type: kubernetes.io/service-account-token
EOF