{{- define "coverage-map.name" -}}
{{ .Release.Name }}
{{- end -}}
{{- define "coverage-map.fullname" -}}
{{ printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}
