{{/* Expand the name of the chart. */}}
{{- define "rolling-archive.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name. */}}
{{- define "rolling-archive.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "rolling-archive.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "rolling-archive.labels" -}}
helm.sh/chart: {{ include "rolling-archive.chart" . }}
{{ include "rolling-archive.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "rolling-archive.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rolling-archive.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Name of the ServiceAccount used by the Sensor. */}}
{{- define "rolling-archive.serviceAccountName" -}}
{{- printf "%s-sensor" (include "rolling-archive.fullname" .) }}
{{- end }}

{{/* Name of a per-account worker Deployment, e.g. <fullname>-worker-priority-account1. */}}
{{- define "rolling-archive.workerDeploymentName" -}}
{{- printf "%s-worker-%s-%s" (include "rolling-archive.fullname" .context) .tier .account.name | trunc 63 | trimSuffix "-" }}
{{- end }}
