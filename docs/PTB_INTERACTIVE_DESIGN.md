# 交互式 PTB 构建器设计文档

## 概述

本文档描述了一个交互式 Programmable Transaction Block (PTB) 构建器的设计方案，旨在简化复杂的多步骤 DeFi 操作（如 Cetus flash swap）的构建过程。

## 当前问题

1. **手动构建复杂**：用户需要手动管理 `Result(N)` 和 `NestedResult(cmd, idx)` 引用
2. **类型顺序容易出错**：如 `Pool<USDC, SUI>` vs `Pool<SUI, USDC>` 的区别
3. **多步骤操作难以串联**：Flash swap 需要 `flash_swap` + `repay_flash_swap` 两个命令配合
4. **JSON 格式繁琐**：手动编写 `--commands @file.json` 容易出错

## 设计方案

### 1. 交互式构建器 (Interactive Builder)

```bash
sui-zig-rpc-client ptb interactive \
  --sender 0xb908f724ae9fd9f3859df7b42d1192649217bc4a677c99b58ec838db2ff6ec41 \
  --gas-budget 10000000
```

交互式提示符：
```
🚀 Interactive PTB Builder
Type 'help' for available commands, 'done' to finish, 'quit' to exit.

=== PTB Builder State ===
Commands: 0
Available Results: None
========================

ptb> split 1000000
✅ Added SplitCoins command (produces Result(0))

ptb> transfer 0 0xb5990d3fa28d6f67c1751d185c161c278d9ceb9818e938cb5fddefe19d29a858
✅ Added TransferObjects command

ptb> done

✅ Generated PTB:
{"commands":[{"kind":"SplitCoins","coin":"GasCoin","amounts":["1000000"]},{"kind":"TransferObjects","objects":[{"Result":0}],"address":"0xb599..."}],"sender":"0xb908...","gasBudget":10000000}

Execute this PTB? (dry-run/send/cancel): 
```

### 2. DeFi 预设模板 (DeFi Templates)

#### Cetus Swap 模板

```bash
sui-zig-rpc-client ptb template-swap \
  --sender 0xb908f724ae9fd9f3859df7b42d1192649217bc4a677c99b58ec838db2ff6ec41 \
  --pool-id 0x51e883ba7c0b566a26cbc8a94cd33eb0abd418a77cc1e60ad22fd9b1f29cd2ab \
  --initial-version 376543995 \
  --amount 100000000 \
  --a2b false  # false for SUI -> USDC (pool is Pool<USDC, SUI>)
```

生成的 PTB 结构：
```json
{
  "commands": [
    {
      "kind": "MoveCall",
      "package": "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb",
      "module": "pool",
      "function": "flash_swap",
      "typeArguments": ["0x2::sui::SUI", "0x...::usdc::USDC"],
      "arguments": [
        {"Input": 0},  // global config
        {"Input": 1},  // pool object
        {"Pure": false},  // a2b
        {"Pure": true},   // by_amount_in
        {"Pure": "100000000"},
        {"Pure": "0"},
        {"Input": 2}   // clock
      ]
    },
    {
      "kind": "MoveCall",
      "package": "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb",
      "module": "pool",
      "function": "repay_flash_swap",
      "typeArguments": ["0x2::sui::SUI", "0x...::usdc::USDC"],
      "arguments": [
        {"Input": 0},  // global config
        {"Result": 0}, // Balance<T0> from flash_swap
        {"Result": 1}, // Balance<T1> from flash_swap
        {"Result": 2}, // FlashSwapReceipt
        {"Input": 1}   // pool object
      ]
    }
  ]
}
```

#### Simple Transfer 模板

```bash
sui-zig-rpc-client ptb template-transfer \
  --sender 0x... \
  --recipient 0x... \
  --amount 1000000
```

### 3. 核心数据结构

```zig
/// 交互式 PTB 构建器状态
pub const InteractivePtbBuilder = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(CommandEntry),
    result_types: std.ArrayList(ResultType),
    sender: ?[]const u8 = null,
    gas_budget: ?u64 = null,
    
    const CommandEntry = struct {
        index: usize,
        kind: CommandKind,
        json_repr: []const u8,
        result_count: usize,
    };
    
    const CommandKind = enum {
        move_call,
        transfer_objects,
        split_coins,
        merge_coins,
        make_move_vec,
        publish,
        upgrade,
    };
    
    const ResultType = struct {
        command_index: usize,
        result_index: usize,
        type_desc: []const u8,
    };
    
    // Methods: addMoveCall, addTransferObjects, addSplitCoins, etc.
    // buildJson, getAvailableResults, printState
};

/// 参数值类型
pub const ArgValue = union(enum) {
    pure: []const u8,              // 纯值
    input: usize,                  // Input(N)
    result: usize,                 // Result(N)
    nested_result: struct { cmd: usize, idx: usize },
    gas_coin,                      // GasCoin
    object_id: []const u8,         // 对象 ID
};
```

### 4. DeFi 模板库

```zig
pub const DefiTemplates = struct {
    /// Cetus flash swap + repay 完整流程
    pub fn cetusSwap(
        builder: *InteractivePtbBuilder,
        pool_id: []const u8,
        pool_initial_version: u64,
        a2b: bool,
        amount: u64,
        sqrt_price_limit: []const u8,
    ) !void;
    
    /// Simple SUI transfer
    pub fn simpleTransfer(
        builder: *InteractivePtbBuilder,
        recipient: []const u8,
        amount: u64,
    ) !void;
    
    /// Cetus add liquidity
    pub fn cetusAddLiquidity(...) !void;
    
    /// Cetus remove liquidity  
    pub fn cetusRemoveLiquidity(...) !void;
    
    /// Kamino deposit
    pub fn kaminoDeposit(...) !void;
    
    /// Kamino borrow
    pub fn kaminoBorrow(...) !void;
};
```

## 实现文件结构

```
src/
├── ptb_interactive.zig      # 核心交互式构建器
├── commands/
│   ├── ptb.zig              # PTB 命令处理
│   └── ...
└── ...
```

## 技术挑战与解决方案

### 挑战 1: 模块循环依赖

**问题**：`ptb_interactive.zig` 需要被 `commands/ptb.zig` 和 `root.zig` 同时导入，导致模块重复。

**解决方案**：
- 将 `ptb_interactive.zig` 放在 `src/commands/` 目录下
- 只在 `commands/ptb.zig` 中导入，不在 `root.zig` 中导出

### 挑战 2: 类型参数顺序

**问题**：Cetus pool 类型 `Pool<T0, T1>` 的顺序需要正确匹配。

**解决方案**：
- 模板函数内部自动处理类型顺序
- 用户只需指定 `a2b` 参数，模板自动推导类型参数

### 挑战 3: Result 引用管理

**问题**：`flash_swap` 返回 3 个值，需要正确传递给 `repay_flash_swap`。

**解决方案**：
- 构建器自动跟踪每个命令的结果数量和类型
- 提供 `Result(N)` 和 `NestedResult(cmd, idx)` 的自动生成功能

## 下一步工作

1. **实现核心构建器**：`InteractivePtbBuilder` 结构体和基本方法
2. **添加交互式 CLI**：命令解析和状态管理
3. **实现 DeFi 模板**：Cetus 和 Kamino 的常用操作
4. **集成到主 CLI**：添加 `ptb` 子命令
5. **测试覆盖**：单元测试和集成测试

## 示例用法

### 完整 Cetus Swap 流程

```bash
# Step 1: 获取 pool 信息
sui-zig-rpc-client object-get \
  --id 0x51e883ba7c0b566a26cbc8a94cd33eb0abd418a77cc1e60ad22fd9b1f29cd2ab

# Step 2: 使用模板构建 swap
sui-zig-rpc-client ptb template-swap \
  --sender 0xb908f724ae9fd9f3859df7b42d1192649217bc4a677c99b58ec838db2ff6ec41 \
  --pool-id 0x51e883ba7c0b566a26cbc8a94cd33eb0abd418a77cc1e60ad22fd9b1f29cd2ab \
  --initial-version 376543995 \
  --amount 100000000 \
  --a2b false > swap_ptb.json

# Step 3: 模拟交易
sui-zig-rpc-client tx simulate --commands @swap_ptb.json

# Step 4: 发送交易
sui-zig-rpc-client tx send --commands @swap_ptb.json
```

### 交互式构建

```bash
sui-zig-rpc-client ptb interactive --sender 0x...

ptb> help
ptb> split 1000000
ptb> transfer 0 0x...
ptb> call 0x1::coin::transfer --type-args 0x2::sui::SUI --args Result(0) Input(0)
ptb> done
```

## 参考资源

- [Cetus CLMM 合约地址](https://suiscan.xyz/mainnet/object/0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb)
- [SUI/USDC Pool](https://suiscan.xyz/mainnet/object/0x51e883ba7c0b566a26cbc8a94cd33eb0abd418a77cc1e60ad22fd9b1f29cd2ab)
- [Sui PTB 文档](https://docs.sui.io/concepts/transactions/prog-txn-blocks)
