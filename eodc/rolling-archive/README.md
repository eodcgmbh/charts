# rolling-archive

Mirrors Copernicus Data Space Ecosystem (CDSE) Sentinel products into CEPH S3 with a
configurable, short retention window. CEPH S3 is the sole source of truth -- no
metadata database; retention is enforced purely via S3 bucket lifecycle policies
(applied separately by
[rolling-archive-scope-manager](https://git.eodc.eu/eodc/mission/access/rolling-archive-scope-manager),
not by this chart).

## Architecture: this chart deploys only the poller

The actual download/mirror/enrich pipeline runs as Airflow DAGs
([rolling-archive-dags](https://git.eodc.eu/eodc/mission/access/rolling-archive-dags) --
plain `dags/` subfolder, no Dockerfile/chart/ArgoCD Application of its own, deployed
via a `dagBundleConfigList` entry on the real Airflow instance), not by this chart.
This chart's **only workload is the pull poller** (`templates/poller-deployment.yaml`):
it watches CDSE pull subscriptions and triggers an Airflow DagRun per batch of
notifications via the REST API (`dag_run_id` derived from the batch, for
idempotent re-triggering).

## What this chart assumes already exists

- **CDSE, S3, and Airflow credentials, via Vault.** Every `existingSecret`
  referenced in `values.yaml` must already exist in the release namespace with
  REAL values -- this chart only ever writes `vault:...` placeholder strings into
  them (see the Secrets section below). If `vault.enabled: false` (e.g.
  local-testing), something else must create these Secrets with real plaintext
  values. The mechanism is the same everywhere: bank-vaults'
  `vault-secrets-webhook`, cluster-wide -- see below.
- **A reachable Airflow instance running the `rolling-archive-dags` DAGs**
  (`poller.airflow.baseUrl`), with `rolling-archive-priority`/`rolling-archive-normal`
  Airflow Pools already created -- neither is provisioned by this chart.

## Secrets mechanism: bank-vaults' `vault-secrets-webhook` (confirmed, cluster-wide)

Real, live precedent found in `cluster-mgmt/charts/resource-controllers`
(installs the OpenStack cloud-controller-manager's `cloud.conf` this exact way)
and confirmed installed on `k8s-infra` too (`inf-vault-webhook`/
`dev-vault-webhook` Applications): commit a plain Kubernetes `Secret` whose
values are literal `vault:<mount>/data/<path>#<field>` strings (NOT real
credentials), and annotate the consuming pod's template with
`vault.security.banzaicloud.io/vault-addr`/`vault-role` -- the cluster's
mutating admission webhook resolves the placeholder into a real value before
the container starts. Application code never sees the difference; it just reads
a normal environment variable.

When `vault.enabled: true`, this chart's `templates/secrets-from-vault.yaml`
creates all 7 Secrets below itself (deduplicated by `existingSecret` name) with
these placeholder values, and `templates/poller-deployment.yaml` adds the
required annotations to the poller pod template. `vault.mount: access` is the
KV-v2 mount dedicated to the `eodc/mission/access` GitLab subgroup Rolling
Archive is being ported to
(`https://vault.assembly.eodc.eu/ui/vault/secrets/access/list`);
`vault.basePath: rolling-archive` groups everything under
`access/rolling-archive/*`. **Still needed, and NOT something this chart or
Helm can do**: someone with write access to that Vault mount running
`vault kv put access/rolling-archive/<slug> <field>=<realvalue>` for each of the
7 rows below, and confirming the real `vault.role` (the Vault Kubernetes-auth
role that authorizes reading `access/data/rolling-archive/*` from
`k8s-production` -- other real examples at EODC use a role matching the
cluster/environment name, e.g. `"production"`, but that's precedent, not a
confirmed value for this specific mount. Ask Assembly Mission.).

## Secrets this chart needs (and shares with `rolling-archive-dags`)

Seven distinct Secrets, each consumed by **two** independent workloads that must
therefore agree on key names -- this chart's poller Deployments, and
`rolling-archive-dags/dags/_common.py`'s `KubernetesPodOperator` tasks (which run
in Airflow, not via this chart, but read the SAME underlying CDSE/S3 credentials).
One real secret value per row below, not two:

| `existingSecret` name | Keys | Vault path (`vault.enabled: true`) | Read by |
|---|---|---|---|
| `rolling-archive-s3-credentials` (`s3.existingSecret`) | `S3_HOST`, `S3_KEY`, `S3_SECRET` | `access/rolling-archive/s3` (`host`, `key`, `secret`) | Poller directly -- `S3_HOST` this way too when `vault.enabled: true` (`s3.host`'s plain value is only a fallback for `vault.enabled: false`, e.g. local-testing). Also the Airflow tasks, IF `ROLLING_ARCHIVE_S3_HOST`/`ROLLING_ARCHIVE_S3_SECRET=rolling-archive-s3-credentials`/`ROLLING_ARCHIVE_S3_KEY_KEY=S3_KEY`/`ROLLING_ARCHIVE_S3_SECRET_KEY_KEY=S3_SECRET` are set on the Airflow instance's own Helm values -- `_common.py` otherwise defaults to a `minio-credentials`/`root-user`/`root-password` local-testing convention that does NOT exist in a real cluster. |
| `rolling-archive-airflow-credentials` (`poller.airflow.existingSecret`) | `AIRFLOW_BASE_URL`, `AIRFLOW_USERNAME`, `AIRFLOW_PASSWORD` | `access/rolling-archive/airflow` (`url`, `username`, `password`) | Poller only -- `AIRFLOW_BASE_URL` this way too when `vault.enabled: true` (`poller.airflow.baseUrl`'s plain value is only a fallback for `vault.enabled: false`), so this URL can be rotated in one place if it changes (e.g. the platform team's OpenStack/cluster migration) without a chart/manifest edit. Needs a real Airflow API user with permission to trigger DAG runs, see the gotcha below. |
| `cdse-account1-credentials` … `cdse-account5-credentials` (one per `poller.entries[].existingSecret`, several entries share the same account) | `username`, `password`, optional `totp_secret` | `access/rolling-archive/cdse-account1` … `cdse-account5` (same field names) | Poller directly. Also the Airflow download task, IF `ROLLING_ARCHIVE_CDSE_ACCOUNTS` on the Airflow instance lists these same 5 names (comma-separated, contiguous `CDSE_ACCOUNT1.._5` order) -- `_common.py` otherwise defaults to a single `cdse-credentials` secret, which only covers a single-account local-testing setup. |

The `username`/`password`/`totp_secret` key casing for CDSE account Secrets is
deliberate and load-bearing: `_common.py` hardcodes those exact lowercase key
names (not configurable), so this chart's own poller template reads the same
keys rather than a chart-specific alternative -- otherwise one real CDSE account
would need its credentials duplicated under two different key names in two
different Secrets.

**Also required, but on the Airflow instance's own Helm values, not this
chart**: `ROLLING_ARCHIVE_NAMESPACE` (must match wherever the Airflow instance
actually schedules `KubernetesPodOperator` pods -- defaults to `airflow`, almost
certainly wrong for a real instance), `ROLLING_ARCHIVE_WORKER_IMAGE` /
`ROLLING_ARCHIVE_ENRICHER_IMAGE` (defaults to local-testing `:local` tags),
`ROLLING_ARCHIVE_S3_HOST` / `ROLLING_ARCHIVE_S3_SHARED_BUCKET` (should match this
chart's own `s3.host`/`s3.sharedBucket` exactly, same underlying CEPH bucket).
None of `_common.py`'s `ROLLING_ARCHIVE_*` env vars are set by this chart -- it
has no way to reach into a separate Airflow Application's Helm values.

## One poller Deployment per `rolling-archive-scope-manager` scope.yaml entry

`poller.entries` -- one Deployment per entry, not per tier or per account. This
granularity matters: scope-manager explicitly allows one CDSE account to be shared
across *both* tiers (no 1:1 account↔tier rule exists), so a poller keyed on account
alone could trigger the wrong tier's DAG. Since CDSE subscriptions carry no name of
their own (only exact `FilterParam` string equality identifies one), each entry
here just needs a `name` matching its scope.yaml counterpart exactly --
scope-manager writes a `{subscription_id, tier}` manifest object per entry after
each reconciliation, which the poller reads to resolve its subscription and target
DAG (`poller.airflow.dagIdPriority` vs `dagIdNormal`) without either repo
duplicating the other's `FilterParam`-matching logic.

`poller.replicas` defaults to **2, deliberately, live-tested safe**: two independent
readers of one CDSE pull subscription see the *exact same* backlog (one shared ack
cursor, not per-reader leases) and don't corrupt each other -- this gives failover,
not throughput scaling, at zero cost in custom leader-election logic. The only
"waste" when both replicas are healthy is occasional duplicate DagRun triggers,
already absorbed by `airflow_trigger.ensure_dag_run()`'s own idempotency check
(itself sitting on top of the download task's S3-existence-check idempotency).

## Airflow authentication -- a real, live-confirmed gotcha

Airflow's `simple` auth manager (the default for a fresh install) issues
short-lived **JWT bearer tokens via `POST /auth/token`**, not plain HTTP Basic Auth
on the API itself -- confirmed live against a local Airflow instance that Basic
Auth returns `401 Not authenticated` on `/api/v2/...` directly. `poller.airflow.
existingSecret`'s `AIRFLOW_USERNAME`/`AIRFLOW_PASSWORD` keys are used against
`/auth/token` (see `rolling-archive-worker`'s `airflow_trigger.get_token()`), which
the poller re-fetches fresh every poll cycle rather than caching across the loop --
simpler than tracking token expiry, and cheap at this poll interval.

## Multi-bucket layout: `s3.sharedBucket` is a fallback, not the only bucket

`s3.sharedBucket` (renamed from `s3.bucket`) is only where the poller's
subscription manifests and non-dedicated collections' objects live. High-volume/
high-object-count collections (e.g. `S2_MSI_L2A`) get their own dedicated bucket
instead, named by deriving from `s3.sharedBucket` itself
(`rolling_archive_worker.buckets.bucket_for()`, e.g. `eodag-s2-msi-l2a`) -- not a
chart value, so there's exactly one place (that function) deciding bucket
assignment across the poller, the Airflow tasks, and `rolling-archive-scope-
manager`'s lifecycle rules. Real dedicated buckets themselves are provisioned by
IT, not this chart -- same as `s3.sharedBucket` already is today.

## Validated so far

`helm lint`/`helm template` clean with default values and a multi-entry override.
The poller itself (real token fetch, idempotent trigger/skip) is live-tested
against a local Airflow instance directly -- see rolling-archive-worker's own
test suite and README -- but **not yet redeployed via this specific chart** to
confirm the `AIRFLOW_*` env vars render and resolve correctly end-to-end
in-cluster. Do that before trusting `poller-deployment.yaml` as-is in a real
environment.

Also caught and fixed, still applicable: Helm/Go renders large "round" numbers
piped through `| quote` in scientific notation (e.g. `1800000` rendering as the
literal string `"1.8e+06"`) -- unparseable by Python's `int()`, crashing the
container at startup despite clean `helm lint`/`template` (dry-run never actually
starts the container). Every genuinely-numeric env var value in
`poller-deployment.yaml` is piped through `| int | quote`, not bare `| quote`.

## Development

    helm lint .
    helm template test . --set poller.airflow.baseUrl=https://airflow-v3.dev.services.eodc.eu
