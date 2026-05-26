{{/*
Return the chart name
*/}}
{{- define "zarr-browser.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/*
Return the full name for resources (usually chart name + release name)
*/}}
{{- define "zarr-browser.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "zarr-browser.labels" -}}
app.kubernetes.io/name: {{ include "zarr-browser.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
