# mobile-sandbox

在腾讯云容器服务（TKE）上部署 Android 容器，用于移动应用测试和自动化。

## 快速开始

### 前置要求

- TKE 集群 v1.28+
- 节点池配置：
  - 机型：**S6 系列**
  - 操作系统：**Ubuntu Server 24.04 LTS 64位** (`img-mmytdhbn`)
  - 内核版本：**6.8.0-87**（通过初始化脚本升级）

### 安装步骤

**1. 创建节点池**

选择 S6 系列机型和 Ubuntu 24.04：

![节点池配置](docs/images/image1.png)

在"节点初始化后"中添加内核升级脚本：

![初始化脚本](docs/images/image2.png)

脚本 `upgrade_kernel_to_6.8.0-87.sh` 已包含在本项目中。

**2. 部署 Chart**

修改 values 指定节点池 id。
```bash
helm install mobile-sandbox ./helm-charts/mobile-sandbox
```

**3. 验证部署**

```bash
kubectl get pods -l k8s-app=redroid
kubectl get daemonset -l app=redroid-ubuntu-module-loader
```

## 使用方法

### 通过 ADB 连接

**直连方式（通过 EIP）：**
```bash
# 获取 EIP
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations.tke\.cloud\.tencent\.com/eip-public-ip}'

# 连接设备
adb connect <EIP>:5555
```

### 示例：微信测试

**1. 连接设备**

```bash
adb connect <POD_IP>:5555
```

![ADB 连接](docs/images/image3.png)

**2. 安装 APK**

```bash
adb push weixin.apk /sdcard/
adb install /sdcard/weixin.apk
```

![传输 APK](docs/images/image4.png)

**3. 打开界面**

```bash
scrcpy -s <DEVICE_ID>
```

![Android 界面](docs/images/image5.png)

![微信主屏](docs/images/image6.png)

**4. 启动微信**

![启动微信](docs/images/image7.png)

**5. 功能测试**

登入：

![微信登录](docs/images/image8.png)

发送消息：

![发送消息](docs/images/image9.png)

小程序：

![小程序](docs/images/image10.png)

截图：

![截图](docs/images/image11.png)

## 配置说明

### 主要参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `redroid.replicas` | Android 实例数量 | `1` |
| `redroid.nodeAffinity.nodepoolIds` | 调度到的节点池 ID | `[np-xxxxxxxx]` |
| `redroid.container.resources.requests.cpu` | 单实例 CPU 请求 | `6500m` |
| `redroid.container.resources.requests.memory` | 单实例内存请求 | `10Gi` |
| `moduleLoader.nodeAffinity.nodepoolIds` | 模块加载器运行的节点池 | `[np-xxxxxxxx]` |

### Android 配置

```yaml
redroid:
  container:
    args:
      - androidboot.redroid_width=1080      # 屏幕宽度
      - androidboot.redroid_height=1920     # 屏幕高度
      - androidboot.redroid_dpi=480         # 屏幕 DPI
      - androidboot.redroid_fps=30          # 帧率
```
更多参数参考: https://github.com/ERSTT/redroid

### 网络配置

每个 Pod 自动配置：
- **EIP**：公网 IP，100Mbps 带宽
- **ENI**：TKE 路由 ENI 模式
- **路由守护**：Sidecar 容器维护路由表

## 架构说明

```
┌─────────────────────────────────────────┐
│  模块加载器 DaemonSet                   │
│  • 加载 binder_linux、ashmem_linux      │
│  • 加载 iptables 模块                   │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Redroid StatefulSet                    │
│  ┌─────────────────────────────────┐   │
│  │ Pod                             │   │
│  │ ├─ redroid (Android 11)         │   │
│  │ └─ route-setup (网络)           │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### 组件说明

- **redroid**：Android 11 系统，支持 Houdini ARM 转译
- **route-setup**：维护 TKE ENI 网络路由
- **module-loader**：在每个节点上加载内核模块

## 故障排查

### Pod 无法启动

```bash
# 检查模块加载器
kubectl logs -l app=redroid-ubuntu-module-loader

# 验证内核模块
kubectl exec -it <module-loader-pod> -- lsmod | grep -E "binder|ashmem"
```

### ADB 连接失败

```bash
# 检查 Redroid 运行状态
kubectl logs <pod-name> -c redroid

# 验证 ADB 端口
kubectl exec -it <pod-name> -c redroid -- netstat -tlnp | grep 5555
```

### 网络问题

```bash
# 检查路由配置
kubectl logs <pod-name> -c route-setup

# 测试网络连通性
kubectl exec -it <pod-name> -c redroid -- ping -c 3 8.8.8.8
```

## 卸载

```bash
helm uninstall mobile-sandbox
```

**注意**：EIP 默认保留，如需删除请在 TKE 控制台手动操作。

## 参考文档

- [Redroid 文档](https://github.com/ERSTT/redroid)
- [TKE 文档](https://cloud.tencent.com/document/product/457)
- [创建 TKE 集群](https://cloud.tencent.com/document/product/457/103981)
