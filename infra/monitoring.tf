resource "helm_release" "kube_prometheus_stack" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  values = [
    file("${path.module}/values/prometheus-values.yaml"),
    file("${path.module}/values/grafana-values.yaml"),
    file("${path.module}/values/alertmanager-values.yaml"),
    file("${path.module}/values/node-exporter-values.yaml")
  ]
}