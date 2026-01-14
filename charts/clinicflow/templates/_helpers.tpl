{{- define "clinicflow.name" -}}
clinicflow
{{- end -}}

{{- define "clinicflow.namespace" -}}
{{ .Values.global.namespace }}
{{- end -}}

{{- define "clinicflow.labels" -}}
app.kubernetes.io/name: {{ include "clinicflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/part-of: clinicflow
env: {{ .Values.global.envName | quote }}
{{- end -}}
