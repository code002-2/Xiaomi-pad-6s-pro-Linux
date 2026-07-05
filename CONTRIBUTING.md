# 贡献指南

欢迎为本项目贡献力量！在阅读本指南后，请确保遵循以下规范。

## 添加新的发行版支持

1. 参考现有脚本（如 `sheng-rootfs_build.sh`）创建新的 rootfs 构建脚本
2. **必须** `source lib/rootfs-common.sh` 以使用公共函数
3. 仅实现发行版特定的逻辑（包管理器、桌面环境、特有配置）
4. 通用步骤使用公共库函数：
   - `create_image` — 创建磁盘镜像
   - `setup_chroot_mounts` — 挂载伪文件系统
   - `setup_dns` — DNS 配置
   - `configure_touchscreen` — 触摸屏校准
   - `fix_wifi_firmware` — WiFi 固件修复
   - `setup_users` — 用户创建
   - `generate_fstab` — 分区表生成
   - `teardown_mounts` — 卸载清理
   - `pack_sparse_image` — 镜像打包

## 编码规范

- 所有脚本必须使用 `set -euo pipefail`
- **禁止**在脚本中硬编码密码 — 使用环境变量：
  ```bash
  ROOT_PASS="${ROOT_PASS:-1234}"
  USER_PASS="${USER_PASS:-luser}"
  USER_NAME="${USER_NAME:-luser}"
  ```
- 使用双引号包裹所有变量引用：`"$VAR"` 而非 `$VAR`
- 使用 `=` 而非 `==` 进行字符串比较（POSIX 兼容）
- 避免在脚本中使用 emoji 前缀（不利于 CI 日志解析）

## CI/CD 工作流

- 新的 rootfs 构建工作流**必须**使用 `_rootfs-template.yml` 作为模板
- 工作流文件应精简为 dispatcher（~15-20 行）
- `push` 触发器必须包含 `paths:` 过滤，避免无关提交触发全量构建
- 内核配置变更应提交最小 diff，而非完整的 9000+ 行 `.config` 文件

## 安全检查清单

提交 PR 前请确认：
- [ ] 无硬编码密码
- [ ] 所有下载使用 HTTPS
- [ ] 未禁用 GPG 验证（`--no-check-gpg`、`[trusted=yes]`）
- [ ] 未将编译二进制文件提交到 git
- [ ] `.gitignore` 已更新以排除构建产物

## 提交 PR

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/my-feature`)
3. 提交更改 (`git commit -m 'Add: my feature'`)
4. 推送到分支 (`git push origin feature/my-feature`)
5. 打开 Pull Request

## 代码审查

本项目使用 CODEOWNERS 机制，不同模块由不同维护者审查：
- Rootfs 脚本 → `@code002-2`
- 内核构建 → `@map220v`
- CI 工作流 → `@code002-2`
- 文档 → `@code002-2`
