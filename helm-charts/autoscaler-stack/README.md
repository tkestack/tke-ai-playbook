# Elastic Scaling Dependency Components

[English](README.md) | [中文](README_zh.md)

The `autoscaler-stack` is used to deploy dependency components for elastic scaling, including:

- argo-workflows: Argo Workflows component
- dcgm-exporter: GPU monitoring component
- kube-prometheus-stack: Prometheus monitoring stack
- keda: KEDA elastic scaling component
- lws: LeaderWorkerSet component

It also supports the following Grafana dashboards:

- [vllm-dashboard](./dashboards/vllm-dashboard.json)
- [sglang-dashboard](./dashboards/sglang-dashboard.json)
- [hpa-dashboard](./dashboards/hpa-dashboard.json)
- [dcgm-exporter-dashboard](./dashboards/dcgm-exporter-dashboard.json)
- [crane-dashboard](./dashboards/crane-dashboard.json)

## Deployment Instructions

Note: Delete the `v1beta1.custom.metrics.k8s.io` APIService, otherwise errors may occur.

```shell
kubectl delete apiservice v1beta1.custom.metrics.k8s.io
```

Deploy using the following command:

```shell
helm install autoscaler-stack ./autoscaler-stack
```