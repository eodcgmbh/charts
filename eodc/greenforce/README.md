# GreenFORCE Helm chart

Deploys the GreenFORCE Streamlit demonstrator to Kubernetes, using an image you
host yourself. This sidesteps the GHCR pull-access issues — you build the image
from the repo's `Dockerfile`, push it to a registry you control, and the chart
pulls from there.

## 1. Build and push a self-hosted image

From the repo root (where the `Dockerfile` lives):

```bash
# Point at the registry you control.
REGISTRY=registry.example.com
TAG=$(git rev-parse --short HEAD)   # or a release version like 1.0.0

docker build -t $REGISTRY/greenforce:$TAG .
docker push $REGISTRY/greenforce:$TAG
```

If the registry is private, create a pull secret in the target namespace:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=$REGISTRY \
  --docker-username=<user> \
  --docker-password=<token>
```

## 2. Install

### From the public EODC Helm repo

This chart is published to the public EODC charts repo (GitHub Pages), so you
can install it without any registry credentials:

```bash
helm repo add eodc https://eodcgmbh.github.io/charts
helm repo update
helm install greenforce eodc/greenforce \
  --version 0.1.0 -n greenforce --create-namespace \
  --set secrets.s3AccessKey=<key> --set secrets.s3SecretKey=<secret>
```

### From a local checkout

```bash
helm install greenforce ./helm/greenforce \
  --namespace greenforce --create-namespace \
  --set image.repository=$REGISTRY/greenforce \
  --set image.tag=$TAG \
  --set secrets.s3AccessKey=<key> \
  --set secrets.s3SecretKey=<secret>
```

For a private registry add: `--set imagePullSecrets[0].name=regcred`.

Prefer a values file for anything sensitive or long-lived:

```yaml
# my-values.yaml
image:
  repository: registry.example.com/greenforce
  tag: "1.0.0"
imagePullSecrets:
  - name: regcred
secrets:
  s3AccessKey: "..."
  s3SecretKey: "..."
  s3EndpointUrl: "https://objects.eodc.eu"
  s3Region: "us-east-1"
persistence:
  size: 50Gi
  storageClass: "fast-ssd"
ingress:
  enabled: true
  className: nginx
  host: greenforce.example.com
```

```bash
helm upgrade --install greenforce ./helm/greenforce -n greenforce -f my-values.yaml
```

## Notes & limitations

- **Single replica.** The app holds Streamlit session state in memory, syncs
  rasters to a ReadWriteOnce volume, and runs an in-process pool of tile
  servers. `replicaCount` is 1 and the deployment uses the `Recreate` strategy.
- **Tile-server ports.** The app opens tile servers on a port range (default
  `8010-8059`, controlled by `tileserver.portBase`/`portRange`). These are
  published on the Service because the browser fetches tiles directly from
  them. A standard Ingress only routes the UI port (`8501`); for external tile
  access use a `LoadBalancer` or `NodePort` Service.
- **Secrets.** The chart creates a Kubernetes Secret with the `S3_*` values and
  injects them as env vars. The app reads these when `secrets.json` is absent
  (`greenforce/s3_sync.py`). Set `secrets.existingSecret` to reuse a Secret you
  manage yourself (keys: `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_ENDPOINT_URL`,
  `S3_REGION`).

## Uninstall

```bash
helm uninstall greenforce -n greenforce
```

The rasters PVC is retained by default; delete it manually if no longer needed.
