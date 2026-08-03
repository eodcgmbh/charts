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
- **The Argo Events controller -- only if `ingestion.mode: push`.** In that mode
  this chart creates `EventBus`/`EventSource`/`Sensor` custom resources, not the
  controller. Not needed at all in the default `pull` mode (see "Ingestion mode"
  below) -- nothing in this chart requires Argo Events unless you opt into push.
- **CDSE and S3 credentials, via Vault.** Every `existingSecret` referenced in
  `values.yaml` (`s3.existingSecret`, each `worker.<tier>.accounts[].existingSecret`,
  and in pull mode each `ingestion.poller.entries[].existingSecret`) must already
  exist in the release namespace -- this chart never creates Secrets with real
  credentials in them (see `cluster/secrets/*.yaml` in the infra repo).

Ask the cluster-managing team about the first two before deploying for real.

## Ingestion mode: `pull` (default) or `push` -- both kept, switchable, not deleted

`ingestion.mode` picks which whole subsystem this chart deploys to detect new CDSE
products and hand them to Kafka. Adopted `pull` as the default after a live
comparison found it simplifies deployment substantially (no public
endpoint/Ingress/DNS/TLS/webhook-Basic-Auth-workaround needed at all -- the poller
only makes outbound calls) with no cost to the two-tier `<1h`/`<24h` SLA (a 10-30s
poll interval is a rounding error against either budget) -- see
rolling-archive-hda-integration / pull-vs-push memory notes for the full write-up.
**Both code paths are real and kept, not one built and one theoretical** -- switching
back is just this one value.

### `pull` mode: one poller Deployment per scope.yaml entry

`ingestion.poller.entries` -- one Deployment per **`rolling-archive-scope-manager`
scope.yaml entry**, not per tier or per account. This granularity matters:
scope-manager explicitly allows one CDSE account to be shared across *both* tiers
(no 1:1 account↔tier rule exists), so a poller keyed on account alone could
silently publish a product to the wrong Kafka topic. Since CDSE subscriptions carry
no name of their own (only exact `FilterParam` string equality identifies one),
each entry here just needs a `name` matching its scope.yaml counterpart exactly --
scope-manager writes a `{subscription_id, tier}` manifest object per pull-mode
entry after each reconciliation, which the poller reads to resolve its subscription
and target topic (`download.high` vs `download.normal`) without either repo
duplicating the other's `FilterParam`-matching logic.

`ingestion.poller.replicas` defaults to **2, deliberately, live-tested safe**: two
independent readers of one CDSE pull subscription see the *exact same* backlog (one
shared ack cursor, not per-reader leases) and don't corrupt each other -- this gives
failover, not throughput scaling, at zero cost in custom leader-election logic. The
only "waste" when both replicas are healthy is occasional duplicate Kafka publishes,
already absorbed by the download worker's own S3-existence-check idempotency.

### `push` mode: routed by CDSE subscription, not message content

Tier (`priority`/`other`) is decided by which of two webhook paths
(`/cdse/priority`, `/cdse/other`) a CDSE subscription's `NotificationEndpoint` points
at -- set by `rolling-archive-scope-manager`'s reconciler, not by this chart. The
`Sensor` does a trivial 1:1 pass-through per path straight to
`download.high`/`download.normal`, with **no content-based classification at all**.
This replaced an earlier design that regex-matched message content downstream; that
worked but silently drifted out of sync once already (missed a GRD product variant) --
moving the tier decision upstream removes that whole bug class. Same principle pull
mode's manifest-based routing follows, just via a different handoff mechanism.

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

A **separate, single Deployment** (`assetMirror.*`, not part of `worker.*` above) --
`<fullname>-asset-mirror`, same image as the download worker, different entrypoint
(`command: ["rolling-archive-asset-mirror"]`) -- consumes `product.uploaded` on its
own Kafka consumer group and mirrors every product's individual files into this
bucket, under a separate `<providerId>_s3` prefix (a sibling of the whole-ZIP
object's own prefix -- matches EODC's own `eodag` convention of `cop_dataspace` vs
`cop_dataspace_s3` as two top-level folders, confirmed against real HDA URLs and the
`eodc_eodag` source), so EODC's HDA service can serve individual assets (e.g. one
Sentinel-2 band) straight from here instead of its slower Airflow-triggered on-demand
extraction path. Covers every collection this pipeline archives, not just the ones
HDA currently federates.

**Why a separate Deployment, not part of the download worker**: this used to run
inline in the download worker, but a real, live-tested 373-asset Sentinel-1 product
took long enough to extract that it tripped Kafka's `max.poll.interval.ms` on the
download worker's own consumer group, evicting it mid-processing. Splitting it out
means the download worker (CDSE-download-bound, never that slow on its own) and this
consumer (extraction-bound, no download-SLA urgency at all) tune their poll-loop
timing independently -- `assetMirror.kafkaMaxPollIntervalMs` defaults to 30 minutes,
vs. Kafka's plain 5-minute default for the download worker. Also simpler to deploy:
no per-CDSE-account fan-out needed here at all (the default strategy needs no CDSE
credential of any kind), so it's a plain single/multi-replica Deployment like the
enricher, not the download worker's N-Deployments-per-tier pattern.

`assetMirror.assetMirrorStrategy` picks how assets get mirrored -- two
interchangeable strategies, both real and tested, chosen after an A/B comparison
against real data:
- **`zip_extract` (default)**: re-reads the whole-ZIP object already archived in OUR
  OWN bucket -- no CDSE fetch at all, no CDSE-S3 credential needed. Measurably halves
  CDSE bandwidth/request consumption per product versus the alternative, which
  matters given CDSE's real, quantified transfer quotas (see
  rolling-archive-hda-integration memory notes -- consumer-tier accounts cap at
  12 TB/month, shared between OData and S3 access as best as could be confirmed).
- **`cdse_s3`**: re-fetch every file from CDSE's own S3
  (`eodata.dataspace.copernicus.eu`) a second time. Needs
  `assetMirror.cdseS3.existingSecret` -- CDSE S3 access-key credentials (generated
  via CDSE's dashboard, no API for this), **not** the download worker's per-account
  OAuth secrets. Kept as a fallback, not removed, in case real Service Account quota
  numbers ever make it preferable again (e.g. if `zip_extract`'s per-pod resource
  cost turns out to matter more than the extra CDSE fetch).

Set `assetMirror.mirrorAssets: false` to disable this Deployment's mirroring without
needing `cdseS3.existingSecret` to exist at all, regardless of strategy (or just
don't deploy it -- it's independent of the download worker either way).

## Ingress and CDSE's push auth (only relevant if `ingestion.mode: push`)

The Ingress template never renders at all in the default `pull` mode, regardless of
`eventSource.ingress.enabled`'s value. In `push` mode, it's still disabled by
default (`eventSource.ingress.enabled: false`) -- enable it plus a real ingress
controller, DNS, and TLS (ask the cluster team) to actually receive CDSE's push
callbacks.

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
`assetMirror.mirrorAssets` both `true` (default) and `false`, `assetMirror.
assetMirrorStrategy` both `zip_extract` (default) and `cdse_s3`, and with
`ingestion.mode` both `pull` (default -- confirms Argo Events/Ingress/RBAC/
ServiceAccount are all absent, poller Deployment renders) and `push` (confirms the
reverse: EventBus/EventSource/Sensor/RBAC/ServiceAccount render, poller doesn't,
and Ingress renders too when `eventSource.ingress.enabled` is also set). Every
rendered resource, in both ingestion modes, passed a `kubectl apply
--dry-run=server` against a real cluster with the actual Argo Events and Strimzi
CRDs installed (caught one real bug this way, in an earlier pass: `KafkaTopic`'s
`apiVersion` was written as the now-unserved `kafka.strimzi.io/v1beta2`, fixed to a
configurable `kafka.topicApiVersion`, default `kafka.strimzi.io/v1` -- **check this
against the real target cluster's actual Strimzi version before deploying, don't
assume the default is right there**). Never deployed against a real cluster for
real, and push-mode/ingress/basic-auth has no *live* (non-dry-run) verification at
all -- pull mode's poller has been live-tested (see rolling-archive-hda-integration
memory notes), but not yet via this chart specifically, only via
`local-testing`'s own k8s manifests.

## Development

    helm lint . --set enricher.stacApiBaseUrl=https://stac.example.eodc.eu
    helm template test . --set enricher.stacApiBaseUrl=https://stac.example.eodc.eu
