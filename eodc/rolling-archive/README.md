# rolling-archive

Mirrors Copernicus Data Space Ecosystem (CDSE) Sentinel products into CEPH S3 with a
configurable, short retention window. CEPH S3 is the sole source of truth -- no
metadata database; retention is enforced purely via S3 bucket lifecycle policies
(applied separately by
[rolling-archive-scope-manager](https://git.eodc.eu/sreimond/rolling-archive-scope-manager),
not by this chart).

## What this chart assumes already exists

- **A Kafka cluster (Strimzi) in the target cluster.** This chart only creates
  `KafkaTopic`s on top of it (`kafka.clusterName` must match the existing `Kafka` CR's
  name) -- it does not provision the broker cluster itself.
- **The Argo Events controller.** This chart creates `EventBus`/`EventSource`/`Sensor`
  custom resources, not the controller.
- **CDSE and S3 credentials, via Vault.** Every `existingSecret` referenced in
  `values.yaml` (`s3.existingSecret`, each `worker.<tier>.accounts[].existingSecret`)
  must already exist in the release namespace -- this chart never creates Secrets with
  real credentials in them (see `cluster/secrets/*.yaml` in the infra repo).

Ask the cluster-managing team about the first two before deploying for real.

## Two-tier priority: routed by CDSE subscription, not message content

Tier (`priority`/`other`) is decided by which of two webhook paths
(`/cdse/priority`, `/cdse/other`) a CDSE subscription's `NotificationEndpoint` points
at -- set by `rolling-archive-scope-manager`'s reconciler, not by this chart. The
`Sensor` does a trivial 1:1 pass-through per path straight to
`download.high`/`download.normal`, with **no content-based classification at all**.
This replaced an earlier design that regex-matched message content downstream; that
worked but silently drifted out of sync once already (missed a GRD product variant) --
moving the tier decision upstream removes that whole bug class.

## CDSE accounts: one Deployment per account, no in-code pooling

`worker.priority.accounts`/`worker.other.accounts` are lists -- one `Deployment` (fixed
at `replicas: 1`) is templated per entry, each with its own `existingSecret`
(`CDSE_USERNAME`/`CDSE_PASSWORD` keys). All accounts within a tier share one Kafka
consumer group (`<release>-worker-<tier>`), so Kafka load-balances `download.high`/
`download.normal` across however many account-Deployments exist in that tier --
scaling account count is just adding entries to the list, no code change. Deliberately
NOT a `StatefulSet` with ordinal-based account selection (considered and rejected --
more k8s machinery than N Deployments for the same outcome), and deliberately NOT an
in-code account-pooling scheduler (a decision already made earlier this project, kept
intact here: account assignment lives entirely at the Helm layer, not in the worker's
own code).

S3/CEPH credentials are shared across every worker replica regardless of tier/account
(`s3.existingSecret`) -- CDSE account and S3 access are independent concerns.

## Per-asset mirroring for HDA's fast-path cache (ACM26-257)

`worker.mirrorAssets` (default `true`) mirrors every product's individual files into
this bucket, under a separate `<providerId>_s3` prefix (a sibling of the whole-ZIP
object's own prefix -- matches EODC's own `eodag` convention of `cop_dataspace` vs
`cop_dataspace_s3` as two top-level folders, confirmed against real HDA URLs and the
`eodc_eodag` source), so EODC's HDA service can serve individual assets (e.g. one
Sentinel-2 band) straight from here instead of its slower Airflow-triggered on-demand
extraction path. Covers every collection this pipeline archives, not just the ones
HDA currently federates.

`worker.assetMirrorStrategy` picks how those assets get mirrored -- two
interchangeable strategies, both real and tested, chosen after an A/B comparison
against real data:
- **`zip_extract` (default)**: extract from the ZIP already downloaded for
  archival -- no second CDSE fetch at all, no CDSE-S3 credential needed. Measurably
  halves CDSE bandwidth/request consumption per product versus the alternative,
  which matters given CDSE's real, quantified transfer quotas (see
  rolling-archive-hda-integration memory notes -- consumer-tier accounts cap at
  12 TB/month, shared between OData and S3 access as best as could be confirmed).
- **`cdse_s3`**: re-fetch every file from CDSE's own S3
  (`eodata.dataspace.copernicus.eu`) a second time. Needs `worker.cdseS3.existingSecret`
  -- CDSE S3 access-key credentials (generated via CDSE's dashboard, no API for
  this), **not** the per-account OAuth secrets above. Kept as a fallback, not
  removed, in case real Service Account quota numbers ever make it preferable again
  (e.g. if `zip_extract`'s per-pod resource cost turns out to matter more than the
  extra CDSE fetch).

Set `worker.mirrorAssets: false` to disable across every worker replica without
needing `cdseS3.existingSecret` to exist at all, regardless of strategy.

## Ingress and CDSE's push auth

Disabled by default (`eventSource.ingress.enabled: false`) -- pull-mode subscriptions
(the only mode validated end-to-end so far) need no public endpoint at all. Push mode
needs `eventSource.ingress.enabled: true` plus a real ingress controller, DNS, and TLS
(ask the cluster team).

CDSE's real push callback authenticates with plain HTTP Basic Auth, using the
`NotificationEpUsername`/`NotificationEpPassword` credentials registered on the
subscription (confirmed against CloudFerro's
[push_subscription_endpoint_example](https://gitlab.cloudferro.com/cat_public/push_subscription_endpoint_example)
reference implementation). Argo Events' own webhook `EventSource` only supports a
Bearer-token `authSecret`, not Basic Auth, so this chart validates it at the Ingress
layer instead: set `eventSource.ingress.basicAuth.enabled: true` plus
`username`/`password` (or `existingSecret` for an already-htpasswd-formatted Secret),
and the Ingress gets `nginx.ingress.kubernetes.io/auth-*` annotations. **This assumes
an nginx-ingress controller** -- this charts repo has examples using both `nginx` and
`apisix` elsewhere, adjust if the real target cluster uses something else. Never
actually exercised against a real CDSE push delivery yet.

## Validated so far

`helm lint` and `helm template` clean with both default values and a multi-account
(2 priority + 3 other accounts) + ingress/basic-auth override, with
`worker.mirrorAssets` both `true` (default) and `false`, and with
`worker.assetMirrorStrategy` both `zip_extract` (default, confirms the CDSE-S3 env
vars/secret reference are absent) and `cdse_s3` (confirms they appear correctly).
Every rendered resource
passed a `kubectl apply --dry-run=server` against a real cluster with the actual
Argo Events and Strimzi CRDs installed (caught one real bug this way: `KafkaTopic`'s
`apiVersion` was written as the now-unserved `kafka.strimzi.io/v1beta2`, fixed to a
configurable `kafka.topicApiVersion`, default `kafka.strimzi.io/v1` -- **check this
against the real target cluster's actual Strimzi version before deploying, don't
assume the default is right there**). Never deployed against a real cluster for real,
and push-mode/ingress/basic-auth has no live verification at all.

## Development

    helm lint . --set enricher.stacApiBaseUrl=https://stac.example.eodc.eu
    helm template test . --set enricher.stacApiBaseUrl=https://stac.example.eodc.eu
