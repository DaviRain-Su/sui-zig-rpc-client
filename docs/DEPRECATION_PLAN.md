# API 废弃计划

## 概述

本文档描述了旧 API 的废弃计划和迁移策略。

## 当前状态

### 新 API (推荐使用)
- ✅ `client/rpc_client/root.zig` - 新 RPC 客户端
- ✅ `commands/root.zig` - 新命令模块
- ✅ `cli/root.zig` - 新 CLI 模块
- ✅ `tx_request_builder/root.zig` - 新交易请求构建器
- ✅ `ptb_bytes_builder/root.zig` - 新 PTB 字节构建器

### 旧 API (准备废弃)
- ⚠️ `client/rpc_client/client.zig` (44,708 行)
- ⚠️ `commands.zig` (33,426 行)
- ⚠️ `cli.zig` (13,244 行)
- ⚠️ `tx_request_builder.zig` (6,748 行)
- ⚠️ `ptb_bytes_builder.zig` (2,059 行)

## 依赖分析

### 仍在使用旧 API 的文件

| 文件 | 依赖的旧 API | 迁移难度 | 优先级 |
|------|-------------|----------|--------|
| `main_legacy.zig` | `cli.zig`, `commands.zig` | 低 | 保留 |
| `cli/integration.zig` | `cli.zig`, `commands.zig` | 中 | 低 |
| `tx_pipeline.zig` | `cli.zig` | 高 | 中 |
| `commands/account.zig` | `cli.zig` | 高 | 中 |
| `commands/dispatch.zig` | `cli.zig` | 高 | 中 |
| `commands/wallet.zig` | `cli.zig` | 高 | 中 |
| `commands.zig` | `cli.zig` | 高 | 低 |
| `client/rpc_client/client.zig` | `tx_request_builder.zig`, `ptb_bytes_builder.zig` | 中 | 低 |

## 废弃策略

### 阶段 1: 标记废弃 (当前)
- [x] 在旧 API 文件头部添加废弃警告注释
- [x] 创建废弃计划文档
- [ ] 在 README 中说明废弃状态

### 阶段 2: 迁移关键依赖 (1-2 周)
- [ ] 迁移 `tx_pipeline.zig` 到新 CLI API
- [ ] 迁移 `commands/account.zig` 到新 CLI API
- [ ] 迁移 `commands/dispatch.zig` 到新 CLI API
- [ ] 迁移 `commands/wallet.zig` 到新 CLI API

### 阶段 3: 移除旧文件 (2-4 周)
- [ ] 移除 `ptb_bytes_builder.zig`
- [ ] 移除 `tx_request_builder.zig`
- [ ] 移除 `cli.zig`
- [ ] 移除 `commands.zig`
- [ ] 移除 `client/rpc_client/client.zig`

### 阶段 4: 清理 (可选)
- [ ] 移除 `main_legacy.zig` (如果不再需要)
- [ ] 移除 `cli/integration.zig` (如果不再需要)

## 迁移指南

### 从旧 RPC 客户端迁移

**旧代码:**
```zig
const client = @import("client/rpc_client/client.zig");
var rpc = try client.SuiRpcClient.init(allocator, endpoint);
```

**新代码:**
```zig
const rpc = @import("client/rpc_client/root.zig");
var client = try rpc.SuiRpcClient.init(allocator, endpoint);
const balance = try rpc.getBalance(&client, address, null);
```

### 从旧 Commands 迁移

**旧代码:**
```zig
const commands = @import("commands.zig");
try commands.runCommand(...);
```

**新代码:**
```zig
const commands = @import("commands/root.zig");
const result = try commands.dispatch.run(...);
```

### 从旧 CLI 迁移

**旧代码:**
```zig
const cli = @import("cli.zig");
var args = try cli.parseArgs(allocator);
```

**新代码:**
```zig
const cli = @import("cli/root.zig");
var parser = cli.Parser.init(allocator);
var args = try parser.parse(argv);
```

## 向后兼容性

### 保留的文件
以下文件将保留用于向后兼容，但不再维护：
- `main_legacy.zig` - 旧的主入口点

### 废弃警告
在编译时使用旧 API 将显示警告：
```
warning: Using deprecated API 'client/rpc_client/client.zig'. 
         Please migrate to 'client/rpc_client/root.zig'.
```

## 时间线

| 阶段 | 时间 | 目标 |
|------|------|------|
| 阶段 1 | 2026-03-22 | 标记废弃，创建文档 |
| 阶段 2 | 2026-04-05 | 迁移关键依赖 |
| 阶段 3 | 2026-04-19 | 移除旧文件 |
| 阶段 4 | 2026-05-03 | 最终清理 |

## 风险评估

### 低风险
- 新 API 已全面测试
- 向后兼容性保持
- 旧文件保留作为备份

### 中风险
- 外部依赖可能使用旧 API
- 需要更新文档和示例

### 缓解措施
- 提供详细的迁移指南
- 保留旧文件至少 1 个月
- 提供迁移脚本（如需要）

## 决策记录

### 2026-03-22: 决定保留旧文件
**原因:**
- 一些文件（如 `tx_pipeline.zig`）深度依赖旧 API
- 完全迁移需要大量时间
- 保留向后兼容性更重要

**决定:**
- 标记旧 API 为废弃
- 创建迁移指南
- 逐步迁移依赖
- 在未来版本中移除

## 相关文档
- [CLIENT_REFACTOR_PLAN.md](CLIENT_REFACTOR_PLAN.md)
- [COMMANDS_REFACTOR_PLAN.md](COMMANDS_REFACTOR_PLAN.md)
- [CLI_REFACTOR_PLAN.md](CLI_REFACTOR_PLAN.md)
- [CODE_REVIEW_REPORT.md](CODE_REVIEW_REPORT.md)
