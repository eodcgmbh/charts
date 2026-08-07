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

{{/* Name of a per-entry poller Deployment, e.g. <fullname>-poller-s1-grd-cog-aux-global. */}}
{{- define "rolling-archive.pollerDeploymentName" -}}
{{- printf "%s-poller-%s" (include "rolling-archive.fullname" .context) .entry.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
A bank-vaults placeholder value, resolved into a real secret by the cluster's
vault-secrets-webhook at pod admission time -- NOT a real value itself. See
templates/secrets-from-vault.yaml for the full explanation and precedent.
Usage: include "rolling-archive.vaultRef" (dict "context" $ "slug" "s3" "field" "key")
*/}}
{{- define "rolling-archive.vaultRef" -}}
vault:{{ .context.Values.vault.mount }}/data/{{ .context.Values.vault.basePath }}/{{ .slug }}#{{ .field }}
{{- end }}
