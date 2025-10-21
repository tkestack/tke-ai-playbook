# MCP Registry Helm Chart

这是一个用于部署 MCP Registry 的 Helm Chart。

## 安装

### 前置条件

- Kubernetes 1.19+
- Helm 3.0+

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

## 配置

以下是主要的配置参数：

### Registry 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `registry.image.repository` | Registry 镜像仓库 | `modelcontextprotocol/registry` |
| `registry.image.tag` | Registry 镜像标签 | `dev` |
| `registry.image.pullPolicy` | 镜像拉取策略 | `Never` |
| `registry.replicaCount` | 副本数量 | `1` |
| `registry.service.type` | Service 类型 | `ClusterIP` |
| `registry.service.port` | Service 端口 | `8080` |

### PostgreSQL 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `postgresql.enabled` | 是否启用 PostgreSQL | `true` |
| `postgresql.image.repository` | PostgreSQL 镜像仓库 | `postgres` |
| `postgresql.image.tag` | PostgreSQL 镜像标签 | `16-alpine` |
| `postgresql.auth.database` | 数据库名称 | `mcp-registry` |
| `postgresql.auth.username` | 数据库用户名 | `mcpregistry` |
| `postgresql.auth.password` | 数据库密码 | `mcpregistry` |

### 环境变量配置

所有环境变量都可以通过 `registry.env` 进行配置。详见 `values.yaml` 文件。

## 自定义配置

创建一个 `custom-values.yaml` 文件来覆盖默认值：

```yaml
registry:
  image:
    tag: latest
  env:
    environment: production
    github:
      clientId: "your-client-id"
      clientSecret: "your-client-secret"

postgresql:
  auth:
    password: "your-secure-password"
```

然后使用自定义配置安装：

```bash
helm install mcp-registry ./helm/mcp-registry -f custom-values.yaml
```

## 访问应用

安装完成后，可以通过以下方式访问应用：

```bash
# 端口转发
kubectl port-forward svc/mcp-registry 8080:8080

# 然后访问 http://localhost:8080
```

## 注意事项

1. 默认配置使用 `imagePullPolicy: Never`，适用于本地开发环境
2. PostgreSQL 默认不启用持久化存储，生产环境请修改 `postgresql.primary.persistence.enabled: true`
3. 默认密码和密钥仅用于测试，生产环境请务必修改
