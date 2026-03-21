# 代码重构计划

## 阶段 1: 拆分 `commands.zig` (32,802 行 → 目标: 每文件 <3K 行)

### 新目录结构
```
src/commands/
├── mod.zig              # 模块导出，主分发逻辑 (~500 行)
├── tx.zig               # 交易相关命令 (~2,500 行)
│   ├── tx_send
│   ├── tx_build
│   ├── tx_simulate
│   └── tx_dry_run
├── move.zig             # Move 合约命令 (~3,000 行)
│   ├── move_function
│   ├── move_module
│   └── move_package
├── wallet.zig           # 钱包管理 (~2,000 行)
│   ├── wallet_create
│   ├── wallet_import
│   └── wallet_accounts
├── account.zig          # 账户查询 (~2,000 行)
│   ├── account_list
│   ├── account_coins
│   └── account_objects
├── object.zig           # 对象查询 (~1,500 行)
├── request.zig          # 请求生命周期 (~2,500 行)
├── shared/
│   ├── json.zig         # JSON 解析辅助函数
│   ├── display.zig      # 输出格式化
│   └── validation.zig   # 参数验证
└── tests/               # 命令测试拆分
    ├── tx_tests.zig
    ├── move_tests.zig
    └── ...
```

### 阶段 2: 拆分 `client/rpc_client/client.zig` (44,528 行)

### 新目录结构
```
src/client/rpc_client/
├── mod.zig              # 主客户端结构和通用逻辑 (~2,000 行)
├── transport.zig        # HTTP 传输层 (现有)
├── types.zig            # 共享类型定义 (~1,000 行)
├── read/
│   ├── mod.zig          # 读取操作接口
│   ├── object.zig       # 对象查询 (~3,000 行)
│   ├── move.zig         # Move 合约查询 (~4,000 行)
│   ├── account.zig      # 账户查询 (~3,000 行)
│   ├── events.zig       # 事件查询 (~2,000 行)
│   └── coins.zig        # 代币查询 (~1,500 行)
├── write/
│   ├── mod.zig          # 写入操作接口
│   ├── transaction.zig  # 交易执行 (~3,000 行)
│   └── request.zig      # 请求构建 (~2,000 行)
├── discovery/
│   ├── mod.zig          # 对象发现接口
│   ├── owned.zig        # 自有对象发现 (~4,000 行)
│   ├── shared.zig       # 共享对象发现 (~3,000 行)
│   └── events.zig       # 事件驱动发现 (~2,000 行)
├── selection/
│   ├── mod.zig          # 对象选择接口
│   ├── scoring.zig      # 候选评分 (~3,000 行)
│   ├── linking.zig      # 跨参数链接 (~2,500 行)
│   └── planning.zig     # 完整计划生成 (~3,000 行)
└── cache/
    ├── mod.zig          # 缓存接口
    └── impl.zig         # 缓存实现 (~2,000 行)
```

## 重构优先级

### P0 (立即执行)
1. 提取 `commands.zig` 中的辅助函数到 `shared/` 目录
2. 将 `client.zig` 中的测试代码分离到 `tests/` 目录

### P1 (本周内)
3. 按命令类型拆分 `commands.zig`
4. 将 `client.zig` 按功能领域拆分

### P2 (下月)
5. 统一错误处理模式
6. 提取公共 JSON 处理逻辑

## 预期收益
- 编译时间减少 30-50%
- 代码导航效率提升
- 并行开发能力增强
- 测试隔离性改善
