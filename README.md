<p align="center">
    <img width="400px" height=auto src="https://portal.services.eodc.eu/images/eodc-logo-panel3.svg" />
</p>

# The EODC Library for Kubernetes

Application helm charts, created by EODC, ready to launch on Kubernetes using Kubernetes Helm. Some of these charts provide common configurations to pre-existing helm charts which are regularly deployed independently across projects at EODC, and some charts are tailored solutions aimed at providing deployments for Earth Observation software on Kubernetes where it did not already exist.


## Contents

The following helm charts are available. Take a look at the respective README documents for more information.

| Chart                | Description                                                                                                           |
| -------------------- | --------------------------------------------------------------------------------------------------------------------- |
| [Cinder CSI](eodc/cinder-csi/README.md)          | A Helm chart for deploying the Cinder Container Storage Interface (CSI) driver to manage block storage in Kubernetes. |
| [Dashboards](eodc/dashboards/README.md)           | A Helm chart that provides a framework for installing dashboards developed at EODC.                                   |
| [Dask-Gateway](eodc/dask-gateway/README.md)         | A Helm chart to deploy Dask-Gateway in Kubernetes, with common configuration used at EODC.                            |
| [JupyterHub](eodc/jupyterhub/README.md)           | A Helm chart for deploying JupyterHub on Kubernetes, with common configuration used at EODC.                          |
| [OpenEO ArgoWorkflows](eodc/openeo-argo/README.md) | A Helm chart for deploying OpenEO on Kubernetes backed by Argo Workflows.                                             |
| [PyGeoAPI](eodc/pygeoapi/README.md)             | A Helm chart for deploying PyGeoAPI, an OGC-compliant geospatial API for serving geospatial data.                     |
| [Stac Browser](eodc/stac-browser/README.md)         | A Helm chart that deploys STAC Browser, a web application for browsing SpatioTemporal Asset Catalog (STAC) datasets.  |
| [WG Nginx](eodc/wg-nginx/README.md)             | A Helm chart instance for deploying Nginx along with WireGuard .                                                      |
