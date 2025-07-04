# 弹性伸缩依赖组件

[English](README.md) | [中文](README_zh.md)

`autoscaler-stack` 用于部署弹性伸缩相关依赖组件，包括：

- argo-workflows: argo 工作流
- dcgm-exporter: GPU 监控组件
- kube-prometheus-stack: prometheus 监控组件
- keda: keda 弹性伸缩组件
- lws: LeaderWorkerSet 组件

同时，也支持如下多种 grafana 监控面板， 包括：

- [vllm-dashboard](./dashboards/vllm-dashboard.json)
- [sglang-dashboard](./dashboards/sglang-dashboard.json)
- [hpa-dashboard](./dashboards/hpa-dashboard.json)
- [dcgm-exporter-dashboard](./dashboards/dcgm-exporter-dashboard.json)
- [crane-dashboard](./dashboards/crane-dashboard.json)

## 部署说明

注意：删除 v1beta1.custom.metrics.k8s.io 的 apiservice，否则会报错。

```shell
kubectl delete apiservice v1beta1.custom.metrics.k8s.io
```

执行如下命令进行部署：

```shell
helm install autoscaler-stack ./autoscaler-stack
```
