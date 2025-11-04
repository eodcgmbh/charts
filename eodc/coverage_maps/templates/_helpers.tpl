{{/*
Return the chart name
*/}}
{{- define "coverage-map.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/*
Return the full name for resources (usually chart name + release name)
*/}}
{{- define "coverage-map.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
