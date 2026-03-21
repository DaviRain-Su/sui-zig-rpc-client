# Commands 模块重构总结

## 已完成的工作

### 1. 问题分析
- `src/commands.zig` 文件过大（33,000+ 行，250+ 函数）
- 包含多种功能：wallet、tx、account、move、request、intent 等
- 难以维护和测试

### 2. 重构计划设计
创建了详细的重构计划 (`docs/COMMANDS_REFACTOR_PLAN.md`)，包括：
- 目标架构：8 个子模块
- 实施步骤：7 个阶段
- 依赖关系图
- 风险与缓解策略

### 3. 子模块原型实现
创建了以下子模块的原型（已移除）：
- `types.zig` - 共享类型定义
- `shared.zig` - 共享工具函数（已存在，已更新）
- `provider.zig` - 程序化提供者相关功能
- `wallet.zig` - 钱包管理命令
- `tx.zig` - 交易相关命令（已存在）
- `move.zig` - Move 合约命令（已存在）
- `account.zig` - 账户命令（已存在）
- `dispatch.zig` - 命令分发逻辑
- `mod.zig` - 模块入口

### 4. 遇到的技术挑战

#### 挑战 1: Zig 模块系统限制
**问题**：Zig 不允许同一个文件属于多个模块。

当 `main.zig` 导入 `commands/mod.zig` 时，整个 `commands/` 目录成为 `root` 模块的一部分。
如果 `commands/types.zig` 又被其他模块导入，就会出现重复定义错误。

**错误信息**：
```
src/commands/types.zig:1:1: error: file exists in modules 'sui_client_zig' and 'root'
```

#### 挑战 2: 复杂的依赖关系
- `commands.zig` 依赖于 `sui_client_zig` 模块
- `main.zig` 同时导入 `commands.zig` 和 `sui_client_zig`
- 测试代码大量使用 `commands.runCommand`

### 5. 回滚决策
由于模块系统的限制，决定回滚重构的代码，保持现有的 `commands.zig` 结构。

## 重构计划（未来）

### 方案 1: 保持单文件，使用命名空间组织
在 `commands.zig` 中使用命名空间来组织代码：

```zig
pub const wallet = struct {
    pub fn runWalletCreateOrImport(...) !void { ... }
    pub fn runWalletUse(...) !void { ... }
    // ...
};

pub const tx = struct {
    pub fn sendExecuteAndMaybeWaitForConfirmation(...) !void { ... }
    // ...
};
```

### 方案 2: 使用 comptime 导入
使用 comptime 条件导入来避免模块重复：

```zig
pub const types = if (@hasDecl(@This(), "_commands_root")) 
    @import("types.zig") 
else 
    struct {};
```

### 方案 3: 重构 build.zig
重新设计模块结构，避免循环依赖：

```zig
// 创建独立的 commands 模块
const commands_module = b.addModule("commands", .{
    .root_source_file = b.path("src/commands/root.zig"),
});

// exe_module 导入 commands 模块
const exe_module = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .imports = &.{
        .{ .name = "sui_client_zig", .module = client_module },
        .{ .name = "commands", .module = commands_module },
    },
});
```

## 建议的下一步

1. **短期**：保持现有结构，添加更多内联文档
2. **中期**：使用命名空间组织 `commands.zig` 内部代码
3. **长期**：重新设计模块架构，可能需要重构 `build.zig`

## 文件变更

### 保留的文件
- `src/commands.zig` - 主命令模块（33,000+ 行）
- `src/commands/shared.zig` - 共享工具函数
- `src/commands/tx.zig` - 交易命令
- `src/commands/move.zig` - Move 命令
- `src/commands/account.zig` - 账户命令

### 创建后移除的文件
- `src/commands/types.zig` - 类型定义
- `src/commands/provider.zig` - 提供者功能
- `src/commands/wallet.zig` - 钱包功能
- `src/commands/dispatch.zig` - 命令分发
- `src/commands/mod.zig` - 模块入口

### 更新的文件
- `src/commands/shared.zig` - 更新为使用重新导出的类型

## 测试状态
- 所有 628 个测试通过
- 重构计划已记录供未来参考
