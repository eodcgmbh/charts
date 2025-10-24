## OpenEO Argoworkflows Helm Chart

This chart deploys an OpenEO Api and OpenEO Processes deployment which gets executed on Argo Workflows. 

The deployment is intended to be a consumer of a STAC catalogue. The data provided by STAC should be available over http/s, so that it can be remotely consumed by the pods responsible for processing.

OpenEO Process Graphs that are provided, get parsed into an Argo Workflow which runs the executor. The executor is responsible for the deserialisation of the process graph, and will execute the corresponding process, if existing on the backend. The output of the processing is written to the job workspace.

Currently, persistent storage is handled via a persistent volume claim ( PVC ) which is known to both the api, and executor pods. Currently, dask gateway is not installed, but this PVC will additionally need to be mounted there in the future. It is not the responsibility of the helm chart to manage backing up the PVC that is used for the persistent storage of OpenEO jobs.


## Installation

Installation with microk8s into the kubernetes cluster. If not using microk8s, just remove the microk8s command.

### Microk8s
```
microk8s kubectl create ns test

microk8s helm dependency build

microk8s helm install openeo -n test -f values.yaml .
```


## Parameters

### Deployment values

| Key                | Description                                           | Value |
|--------------------|-------------------------------------------------------|-------|
| global.env.alembicDir         | Directory for Alembic migrations.          |   "/opt/openeo_argoworkflows_api/psql    |
| global.env.apiDns             | API DNS address. If localhost, include port.                                       |   127.0.0.1:8000    |
| global.env.apiTLS             | API TLS configuration (true/false)                    |   False    |
| global.env.apiTitle           | Title of the API                                      |   "OpenEO ArgoWorkflows"    |
| global.env.apiDescription     | Description of the API                                |   "A K8S deployment of the openeo api for argoworkflows."    |
| global.env.oidcUrl            | URL for OpenID Connect authentication                 |   "https://aai.egi.eu/auth/realms/egi"    |
| global.env.odicOrganisation   | Organisation for OpenID Connect authentication        |  "egi"   |
| global.env.oidcPolicies       | Policies for OpenID Connect authorization             |    ""  |
| global.env.stacCatalogueUrl   | URL for STAC catalogue                                |   "https://stac.eodc.eu/api/v1"    |
| global.env.workspaceRoot      | Root directory for user workspaces                    |   "/user_workspaces"    |
| global.env.executorImage      | Image for the executor                                |   "ghcr.io/eodcgmbh/openeo-argoworkflows:executor-2025.5.1"    |
| global.env.daskWorkerCores      | Cores available to the dask worker                               |   "4"    |
| global.env.daskWorkerMemory      | RAM available to the dask worker (in Gbs)                              |   "8"    |
| global.env.daskWorkerLimit      | Maximum number of workers available per job.                              |   "6"    |
| global.env.daskClusterTimeout      | How long an idle cluster can be left unused.                              |   "3600"    |
| image.repository      | Image for the OpenEO Api                                |   "ghcr.io/eodcgmbh/openeo-argoworkflows"    |
| image.tag      | Tag for the OpenEO Api                              | "api-2025.5.1"  |
| persistence.existingVolume      | The name of an existing Persistent Volume Claim to be used for the OpenEO Workspace.  | **Currently unavailable**  |
| persistence.capacity      |   The size of the Persistent Volume Claim to be used for the OpenEO Workspace        | "8Gi"  |

#### Example: global.env.oidcPolicies

Setting the oidcPolicies is explained [here](https://eodcgmbh.github.io/openeo-fastapi/package/client/settings/) in the OpenEO FastApi documentation. The list is provided via the helm chart as a single string. The default value in the chart is an empty string, this disables the policy check and allows any valid token from the issuer.


### Dependency values

These dependencies are required for the OpenEO Deployment. In theory existing deployments for each of dependencies could be used if they already exist, the helm chart has just not yet been configured to support this. For now, leave these values as is.

It is possible to configure the additional helm values for these charts.

| Key                | Description                                           | Value |
|--------------------|-------------------------------------------------------|-------|
|  postgresql.enabled     |   Whether to install postgresql within the OpenEO Deployment                            | True |
|  argoworkflows.enabled     |   Whether to install argoworkflows within the OpenEO Deployment     | True |
|  redis.enabled     |   Whether to install redis within the OpenEO Deployment   | True |

#### ! Notice !

The images used in this chart for redis and postgresql now must use the bitnamilegacy repository as a consequence of bitnami removing their publicly
available docker images. The default values have been updated to now parse the bitnamilegacy docker repo.

## Dependencies

**Argo Worfklows**

Argo Workflows is used for initializing the executor on the k8s cluster in order to consume the provided OpenEO process graph.

Helm Chart: https://github.com/argoproj/argo-helm/tree/main/charts/argo-workflows


**PostgreSQL**

PostgreSQL is used for keeping track of the OpenEO users that have accessed the backend, the user defined process graphs that they have created, and the jobs they have created and submitted to argo. The persistence for psql is handled independently from the persistent storage used for the physical OpenEO job results.

Helm Chart: https://github.com/bitnami/charts/tree/main/bitnami/postgresql


**Redis**

Redis is used in ordered to queue and limit the number of jobs that are submitted to Argo Workflows at any given time. Additionally, tasks are added to the queue to poll Argo Workflows untill the workflow is finished.

Helm Chart: https://github.com/bitnami/charts/tree/main/bitnami/redis


## Outstanding work

- Tiling the outputs of save result.

- Update helm chart to allow for disabling the installation of chart dependencies and reusing existing deployments.
