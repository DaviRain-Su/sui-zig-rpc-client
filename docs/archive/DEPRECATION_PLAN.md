# API 废弃计划

## 概述

本文档描述了旧 API 的废弃计划和迁移策略。

## 状态: ✅ 已完成

所有旧 API 文件已成功移除，项目已完全迁移到新的模块化架构。

## 移除的文件

| 文件 | 行数 | 状态 | 替代方案 |
|------|------|------|----------|
| `client/rpc_client/client.zig` | 44,708 | ✅ 已删除 | `client/rpc_client/root.zig` |
| `commands.zig` | 33,426 | ✅ 已删除 | `commands/root.zig` |
| `cli.zig` | 13,244 | ✅ 已删除 | `cli/root.zig` |
| `tx_request_builder.zig` | 6,748 | ✅ 已删除 | `tx_request_builder/root.zig` |
| `ptb_bytes_builder.zig` | 2,059 | ✅ 已删除 | `ptb_bytes_builder/root.zig` |
| `main_legacy.zig` | 61,098 | ✅ 已删除 | `main.zig` |
| `cli/integration.zig` | 13,549 | ✅ 已删除 | `cli/root.zig` |
| `tx_pipeline.zig` | 23,538 | ✅ 已删除 | 内置于 `main.zig` |

**总计删除: ~198,370 行代码**

## 新架构

### 模块化结构

```
src/
├── cli/                    # 8 个模块
│   ├── root.zig
│   ├── types.zig
│   ├── parser.zig
│   ├── parsed_args.zig
│   ├── validator.zig
│   ├── help.zig
│   ├── utils.zig
│   └── e2e_test.zig
│
├── client/rpc_client/      # 17 个模块
│   ├── root.zig
│   ├── client_core.zig
│   ├── builder.zig
│   ├── query.zig
│   ├── move.zig
│   ├── object.zig
│   ├── error.zig
│   └── ...
│
├── commands/               # 11 个模块
│   ├── root.zig
│   ├── mod.zig
│   ├── dispatch.zig
│   ├── tx.zig
│   ├── account.zig
│   └── ...
│
├── tx_request_builder/     # 7 个模块
│   ├── root.zig
│   ├── builder.zig
│   ├── types.zig
│   └── ...
│
└── ptb_bytes_builder/      # 5 个模块
    ├── root.zig
    ├── types.zig
    ├── bcs_encoder.zig
    ├── json_parser.zig
    └── transaction.zig
```

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
var parsed = try cli.parseCliArgs(allocator, args);
```

## 时间线

| 阶段 | 日期 | 状态 | 说明 |
|------|------|------|------|
| 阶段 1 | 2026-03-22 | ✅ 完成 | 标记废弃，创建文档 |
| 阶段 2 | 2026-03-22 | ✅ 完成 | 迁移关键依赖 |
| 阶段 3 | 2026-03-22 | ✅ 完成 | 移除旧文件 |
| 阶段 4 | 2026-03-22 | ✅ 完成 | 最终清理 |

## 备份

已创建备份分支: `backup/old-apis-before-removal`

如需恢复旧文件:
```bash
git checkout backup/old-apis-before-removal -- src/cli.zig src/commands.zig ...
```

## 相关文档

- [CLIENT_REFACTOR_PLAN.md](CLIENT_REFACTOR_PLAN.md)
- [COMMANDS_REFACTOR_PLAN.md](COMMANDS_REFACTOR_PLAN.md)
- [CLI_REFACTOR_PLAN.md](CLI_REFACTOR_PLAN.md)
- [CODE_REVIEW_REPORT.md](CODE_REVIEW_REPORT.md)
- [COMMANDS_REFACTOR_SUMMARY.md](COMMANDS_REFACTOR_SUMMARY.md)
