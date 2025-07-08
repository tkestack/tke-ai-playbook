# llm-monitor

## 安装

```bash
kubectl create ns monitor
helm -n monitor install llm-monitor -f values.yaml .
```

## 使用

### 访问 prometheus

```bash
PROM_IP=$(kubectl -n monitor get svc | grep prometheus-server | awk '{print $4}')
echo "访问 'http://${PROM_IP}' 查看 prometheus"
```

### 访问 grafana

```bash
GRAFANA_HOST=$(kubectl -n monitor get svc | grep grafana | awk '{print $4}')
GRAFANA_PASSWD=$(kubectl -n monitor get secret llm-monitor-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
echo "访问 'http://${GRAFANA_HOST}' 查看 grafana"
echo "账号: 'admin'"
echo "密码: '${GRAFANA_PASSWD}'"
```

