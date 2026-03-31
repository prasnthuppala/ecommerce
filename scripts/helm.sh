for SVC in cart product payment auth notification; do
  case $SVC in
    cart) PORT=3000 ;;
    product) PORT=3001 ;;
    payment) PORT=3002 ;;
    auth) PORT=3003 ;;
    notification) PORT=3004 ;;
  esac

  cat > ./devops-portfolio/helm/${SVC}/Chart.yaml << EOF
apiVersion: v2
name: ${SVC}
description: ShopFlow ${SVC} microservice
type: application
version: 0.1.0
appVersion: "1.0.0"
EOF

  cat > ./devops-portfolio/helm/${SVC}/values.yaml << EOF
replicaCount: 1
image:
  repository: ghcr.io/prasnthuppala/devops-portfolio/${SVC}
  pullPolicy: IfNotPresent
  tag: "latest"
service:
  type: ClusterIP
  port: 80
  targetPort: ${PORT}
env:
  PORT: "${PORT}"
  NODE_ENV: production
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "200m"
livenessProbe:
  initialDelaySeconds: 15
  periodSeconds: 20
  failureThreshold: 3
readinessProbe:
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3
EOF

  cat > ./devops-portfolio/helm/${SVC}/values-prod.yaml << EOF
replicaCount: 2
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "500m"
EOF

  cat > ./devops-portfolio/helm/${SVC}/templates/deployment.yaml << HELMEOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: ${SVC}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: ${SVC}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: ${SVC}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "${PORT}"
        prometheus.io/path: "/metrics"
    spec:
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        runAsGroup: 1001
      containers:
        - name: ${SVC}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: ${PORT}
          env:
            - name: PORT
              value: "{{ .Values.env.PORT }}"
            - name: NODE_ENV
              value: "{{ .Values.env.NODE_ENV }}"
          resources:
            requests:
              memory: {{ .Values.resources.requests.memory }}
              cpu: {{ .Values.resources.requests.cpu }}
            limits:
              memory: {{ .Values.resources.limits.memory }}
              cpu: {{ .Values.resources.limits.cpu }}
          livenessProbe:
            httpGet:
              path: /health
              port: ${PORT}
            initialDelaySeconds: {{ .Values.livenessProbe.initialDelaySeconds }}
            periodSeconds: {{ .Values.livenessProbe.periodSeconds }}
            failureThreshold: {{ .Values.livenessProbe.failureThreshold }}
          readinessProbe:
            httpGet:
              path: /health
              port: ${PORT}
            initialDelaySeconds: {{ .Values.readinessProbe.initialDelaySeconds }}
            periodSeconds: {{ .Values.readinessProbe.periodSeconds }}
            failureThreshold: {{ .Values.readinessProbe.failureThreshold }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
HELMEOF

  cat > ./devops-portfolio/helm/${SVC}/templates/service.yaml << HELMEOF
apiVersion: v1
kind: Service
metadata:
  name: ${SVC}-service
  namespace: {{ .Release.Namespace }}
  labels:
    app: ${SVC}
spec:
  type: {{ .Values.service.type }}
  selector:
    app: ${SVC}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
HELMEOF

done
echo "All 5 Helm charts created successfully"
