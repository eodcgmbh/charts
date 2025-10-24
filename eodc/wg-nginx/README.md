# WG Nginx

---

```
microk8s helm upgrade --install wg-nginx . -f .values.yaml --namespace wireguard --create-namespace
```