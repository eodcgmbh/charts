# FastGeoApi

---

Deploys Fastgeoapi.

---

### FastGeoApi

Fastgeoapi will be used as a replacement for pygeoapi. It provides an OPA integration for restricted access, which can be managed in the `opa-policy.yaml`. The setup does not include a PostGis data base, as fastgeoapi can load the data from s3 instead. For initial tests, the existing pygeoapi PostGis db was used. The s3 credentials need to be provided as kubectl secrets in the respective namespace.
