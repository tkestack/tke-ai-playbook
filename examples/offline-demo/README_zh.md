# offline-demo

该 demo 主要用于演示如何在 TKE 上结合 Kueue 进行离线任务推理的排队调度。

## 图片脱敏工作流

playbook: 
- `workflow/face-mosaic-processor.yaml`: 不包含 kueue 的版本
- `workflow/face-mosaic-processor-job.yaml`: 使用 kueue 进行作业调度

该 playbook 用于启动一个人脸打码脱敏工作流：
1. read-images: 从 cos 桶的 images 路径下读取所有图片到 kafka。
2. inference: 由推理服务识别人脸区域，将人脸区域坐标输出到 kafka。
3. write-images: 根据坐标对图片进行脱敏，并将脱敏后的图片写入到 cos 桶的 outputs 路径下。

## 前置条件

1. 需要创建一个 cos 作为数据来源。
- 可以参考 [创建存储桶](https://cloud.tencent.com/document/product/436/13309) 来创建一个新的存储桶。
- 可以在 [API 密钥管理](https://console.cloud.tencent.com/cam/capi?from_column=20423&from=20423) 创建 secret id 和 secret key。
```bash
COS_REGION: cos 桶所在的地区，如 ap-guangzhou
COS_BUCKET: cos 桶名
COS_SECRET_ID: 用于访问 cos 桶的 secret id
COS_SECRET_KEY: 用于访问 cos 桶的 secret key
```

2. 需要一个 kafka 来进行中间数据的传递，可以参考 [创建 Ckafka 实例](https://cloud.tencent.com/document/product/597/53207) 来在控制台创建一个新的 kafka 实例。
```bash
KAFKA_SERVERS: kafka 地址
KAFKA_SASL_PLAIN_USERNAME: 用于 sasl 认证的 kafka 用户名
KAFKA_SASL_PLAIN_PASSWORD: 用于 sasl 认证的 kafka 密码
IMAGES_TOPIC: 读取原图片后写入的 topic
BBOXES_TOPIC: 用于写入推理服务的推理结果的 topic
KAFKA_CONSUMER_GROUP_ID: kafka 消费者组 ID
```

3. 在集群中安装 `Kueue`。
> https://kueue.sigs.k8s.io/docs/installation/#install-a-released-version
> kueue 镜像在 TKE 国内地域无法拉取，建议先保存到 ccr 再替换

```bash
# 设置要安装的 Kueue 的版本
export KUEUE_VERSION=v0.12.1
# 安装指定版本的 Kueue 到 kueue-system 命名空间下
kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/manifests.yaml

# 验证 Kueue 的 Pod 均正常运行
kubectl -n kueue-system get pods
```

4. 在集群中安装 `Argo Workflow`。
> https://argo-workflows.readthedocs.io/en/latest/installation/#installation-methods
```bash
# 设置要安装的 Argo Workflow 的版本
export ARGO_WORKFLOW_VERSION=v3.6.7
# 安装指定版本的 Argo Workflow 到 argo 命名空间下
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/${ARGO_WORKFLOW_VERSION}/install.yaml

# 验证 Argo Workflow 的 Pod 均正常运行
kubectl -n argo get pods
```

5. 访问 Argo Workflow UI。
```bash
# 开启 LoadBalancer
kubectl -n argo patch svc argo-server -p '{"spec": {"type": "LoadBalancer"}}'
# 获取登录 Token
kubectl -n argo exec -it deploy/argo-server -- argo auth token
```
通过 `https://<load-balancer-ip>:<port>` 访问 Argo Workflow UI，并输入 Token 进行验证。

## 使用方法

### face-mosaic-processor

该 Workflow 会启动一个具有以下三个步骤的工作流：
- read-images: 从 cos 桶的 images 路径下读取所有图片到 kafka。
- inference: 由推理服务识别人脸区域，将人脸区域坐标输出到 kafka。
- write-images: 根据坐标对图片进行脱敏，并将脱敏后的图片写入到 cos 桶的 outputs 路径下。

1. 在 cos 桶的 images 路径下准备好需要进行脱敏的图片。

2. 修改 workflow/face-mosaic-processor.yaml 中的参数。
```yaml
spec.volumes：挂载模型文件的 PVC
spec.arguments 如下
# kafka 地址
- name: kafka_servers
  value: "10.11.12.13:9092"
# kafka SASL 认证用户名
- name: kafka_sasl_plain_username
  value: "ckafka-a5b5c5e5#username"
# kafka SASL 认证密码
- name: kafka_sasl_plain_password
  value: "password@test"
# 用于保存原始图片的 topic
- name: images_topic
  value: "raw_images"
# 用于保存推理结果的 topic
- name: bboxes_topic
  value: "image_bboxes"
# 消费者组 id
- name: kafka_consumer_group_id
  value: "tke-ai-playbook"
# cos 地域
- name: cos_region
  value: "ap-guangzhou"
# cos 桶名
- name: cos_bucket
  value: "cos-test-1145140042"
# 用于访问 cos 的 secret id
- name: cos_secret_id
  value: "<secret_id>"
# 用于访问 cos 的 secret key
- name: cos_secret_key
  value: "<secret_key>"
# 可选参数，用于设置 write-images 步骤的具体动作
# - mosaic: 打马赛克
# - bboxes: 打标注框
- name: draw_type
  value: "mosaic"
# 启动大模型的参数，只要是 vllm 支持的参数均可
- name: vllm_engine_kwargs
  value: |
    {
        "model": "/models/Qwen/Qwen2.5-VL-7B-Instruct-AWQ",
        "served_model_name": "Qwen/Qwen2.5-VL-7B-Instruct-AWQ",
        "max_model_len": 8192,
        "dtype": "half", 
        "enforce_eager": true
    }
```


3. 启动工作流。
```bash
# 创建 workflow template
kubectl apply --server-side -f template/face-mosaic-processor.tmpl.yaml

# 创建 workflow
kubeclt create -f workflow/face-mosaic-processor.yaml
```

4. 在 Argo UI 查看执行结果。

5. 在 cos 桶的 outpus 路径下查看处理后的图片。

效果展示：

原图片: ![input](./images/input.jpg)
脱敏后的图片: ![result](./images/result.jpg)