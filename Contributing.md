# Contribution Guidelines

[English](Contributing.md) | [中文](Contributing_zh.md)

### Commit Convention
- **Format Requirements**  
  Follow Conventional Commits specification:  
  `<type>[optional scope]: <description>`  
  Examples:  
  `feat(auth): add OAuth login support`  
  `fix(api): resolve request timeout issues`

---

### Branch Management
- **Branch Strategy**  
  - `main`: Stable production branch (merge requests only)  
  - `feature/*`: Feature development branches (e.g. `feature/user-profile`)  
  - `hotfix/*`: Emergency fixes  
  - `chore/*`: Miscellaneous tasks

---

### Pull Request Submission
1. **Issue Linking**  
   Reference related issues in PR description (e.g. `Closes #123`).
2. **Validation Checklist**  
   ```markdown
   ## Change Description
   ## Related Issues
   ```
3. **Code Review**  
   - Requires approval from at least 1 maintainer

---

### Issue Reporting
- **Template Requirements**  
  Include environment details and reproduction steps:
  ```markdown
  ## Environment
  - Cluster version: 1.28
  - GPU instance type: H20
  
  ## Reproduction Steps
  1. Execute `helm install xxx`
  2. Access service encounters xxx error
  ```

---

### Communication Channels
- Discussion platform: GitHub Discussions

_We appreciate your contributions!_
