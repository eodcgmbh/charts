# PyGeoApi

---

Deploys the PyGeoApi alongside Postgresql.

---

### PyGeoApi

Values for the **local.config.yaml** file can be defined under **pygeoapi.server.config.data** in the values file. Currently the chart only supports piping this config.

### PostGis

PostGis can't be configured by a config item. Currently it requires executing the command in the psql container, as the postgres user. The credentials for this user are populated by the helmchart into the secret **postgres-credentials**, this secret can't currently be configured otherwise.

##### Get login credentials & exec into container
```
$ export POSTGRES_PASSWORD=$(kubectl get secret -n default postgres-credentials -o jsonpath="{.data.postgresPassword}" | base64 --decode)

kubectl exec -n default -it pygeoapi-postgresql-0 -- /bin/bash
```

##### Enable postgis
```
$ postgres=# CREATE EXTENSION postgis;
CREATE EXTENSION

$ postgres=# SELECT PostGIS_Version();
            postgis_version            
---------------------------------------
 2.5 USE_GEOS=1 USE_PROJ=1 USE_STATS=1
(1 row)
```
