# 贡献指南

[English](Contributing.md) | [中文](Contributing_zh.md)

### 提交规范
- **提交格式**  
  采用约定式提交（Conventional Commits）：  
  `<类型>[可选范围]: <描述>`  
  示例：  
  `feat(auth): add OAuth login support`  
  `fix(api): resolve request timeout issues`

---

### 分支管理
- **分支策略**  
  - `main`：生产环境稳定分支，仅接受合并请求  
  - `feature/*`：新功能开发分支（如 `feature/user-profile`）  
  - `hotfix/*`：紧急修复分支  
  - `chore/*`: 其它

---

### 提交 Pull Request
1. **关联 Issue**  
   在 PR 描述中标注关联的 Issue 编号（例：`Closes #123`）。
2. **自测清单**  
   ```markdown
   ## 变更说明
   ## 关联问题
   ```
3. **代码审查**  
   - 需至少 1 名维护者批准  

---

### 问题反馈
- **提交 Issue**  
  按模板填写环境信息、复现步骤和日志, 例子:
  ```markdown
  ## 环境
  - 集群版本：1.28
  - GPU 机器类型：H20
  ## 复现步骤
  1. 执行 `helm install xxx`
  2. 访问 svc, 出现 xxx 问题
  ```

---

### 沟通渠道
- 讨论区：GitHub Discussions  

_感谢您的贡献！_  
