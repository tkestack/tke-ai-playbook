# MCP Registry Helm Chart

这是一个用于部署 MCP Registry 的 Helm Chart。

## 安装

### 前置条件

- Kubernetes 1.19+
- Helm 3.0+
- 获取Github OAuth和JWT配置：https://github.com/modelcontextprotocol/registry/blob/main/.env.example
### 安装 Chart

```bash
# 从本地安装
helm install mcp-registry ./helm/mcp-registry

# 或者指定命名空间
helm install mcp-registry ./helm/mcp-registry -n mcp-registry --create-namespace
```

### 卸载 Chart

```bash
helm uninstall mcp-registry
```