# CLI 模块重构计划

## 目标
将 `src/cli.zig` (13,244 行) 重构为模块化的结构

## 当前状态
- 文件大小: 13,244 行
- 主要内容:
  - 命令枚举定义 (60+ 命令)
  - ParsedArgs 结构体 (300+ 字段)
  - 参数解析函数 (parseCliArgs - 约 4000 行)
  - 帮助文本生成 (约 1000 行)
  - 各种验证和辅助函数

## 重构策略

### 新模块结构
```
src/cli/
├── root.zig           # 模块入口，重新导出
├── types.zig          # 命令枚举和核心类型
├── parsed_args.zig    # ParsedArgs 结构体及其方法
├── parser.zig         # 参数解析逻辑
├── validator.zig      # 参数验证函数
├── help.zig           # 帮助文本生成
└── utils.zig          # 辅助函数
```

### 迁移计划

#### Phase 1: 类型定义迁移
1. 将 `Command` 枚举移动到 `cli/types.zig`
2. 将 `TxBuildKind` 和 `MoveFunctionTemplateOutput` 移动
3. 将 `ParsedArgs` 结构体移动到 `cli/parsed_args.zig`

#### Phase 2: 解析逻辑迁移
1. 将 `parseCliArgs` 函数分解为子函数
2. 按命令类别分组解析逻辑
3. 移动到 `cli/parser.zig`

#### Phase 3: 验证和帮助
1. 将验证函数移动到 `cli/validator.zig`
2. 将帮助生成移动到 `cli/help.zig`
3. 将辅助函数移动到 `cli/utils.zig`

#### Phase 4: 集成和测试
1. 更新 `cli/root.zig` 重新导出所有内容
2. 确保向后兼容
3. 添加模块级测试

## 详细设计

### cli/types.zig
```zig
pub const Command = enum { ... };
pub const TxBuildKind = enum { ... };
pub const MoveFunctionTemplateOutput = enum { ... };
pub const WalletCommand = enum { ... };
pub const TxCommand = enum { ... };
```

### cli/parsed_args.zig
```zig
pub const ParsedArgs = struct {
    // 核心字段
    command: Command = .help,
    has_command: bool = false,
    
    // 通用选项
    pretty: bool = false,
    rpc_url: []const u8 = default_rpc_url,
    
    // 钱包相关
    wallet: WalletArgs,
    
    // 交易相关
    tx: TxArgs,
    
    // ... 其他分组
};
```

### cli/parser.zig
```zig
pub fn parseCliArgs(allocator: Allocator, args: []const []const u8) !ParsedArgs;

// 子解析器
fn parseWalletCommand(args: *ParsedArgs, tokens: []const []const u8, idx: *usize) !void;
fn parseTxCommand(args: *ParsedArgs, tokens: []const []const u8, idx: *usize) !void;
fn parseAccountCommand(args: *ParsedArgs, tokens: []const []const u8, idx: *usize) !void;
```

## 风险与缓解

### 风险 1: 破坏现有功能
- **缓解**: 保持 `cli.zig` 存在，逐步迁移
- **测试**: 确保所有现有测试通过

### 风险 2: 循环依赖
- **缓解**: 仔细设计模块依赖关系
- **设计**: 底层类型不依赖高层逻辑

### 风险 3: 编译时间增加
- **缓解**: 使用 Zig 的惰性编译
- **优化**: 减少不必要的重新导出

## 成功标准
- [x] 所有现有测试通过
- [x] 新模块结构清晰
- [x] 编译时间不显著增加
- [x] 代码可维护性提升
- [x] 向后兼容保持

## 重构进度
- **Phase 1**: ✅ 完成 - 类型定义迁移 (3 模块, 25 测试)
- **Phase 2**: ✅ 完成 - 解析逻辑迁移 (1 模块, 15 测试)
- **Phase 3**: ✅ 完成 - 验证和帮助 (3 模块, 41 测试)
- **Phase 4**: ⏳ 待完成 - 集成和测试

## 时间估计
- Phase 1: 2-3 小时
- Phase 2: 4-6 小时
- Phase 3: 2-3 小时
- Phase 4: 2-3 小时
- **总计**: 10-15 小时
