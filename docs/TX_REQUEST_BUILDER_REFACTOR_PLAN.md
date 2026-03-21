# TX Request Builder 模块重构计划

## 目标
将 `src/tx_request_builder.zig` (6,748 行, 83 测试) 重构为模块化的结构

## 当前状态
- 文件大小: 6,748 行
- 测试数量: 83 个
- 主要内容:
  - 40+ 类型定义 (struct, union, enum)
  - 交易请求构建逻辑
  - 授权和签名处理
  - 会话管理
  - PTB (Programmable Transaction Block) 参数处理

## 重构策略

### 新模块结构
```
src/tx_request_builder/
├── root.zig              # 模块入口，重新导出
├── types.zig             # 核心类型定义
├── argument.zig          # 参数处理 (ArgumentValue, PtbArgumentSpec)
├── handle.zig            # 命令结果句柄 (CommandResultHandle, CommandOutputHandle)
├── account.zig           # 账户提供者 (AccountProvider, 各种账户类型)
├── session.zig           # 会话管理 (SessionChallenge, 挑战/响应)
├── authorization.zig     # 授权计划 (AuthorizationPlan)
├── builder.zig           # 构建逻辑 (request building)
└── utils.zig             # 辅助函数
```

### 迁移计划

#### Phase 1: 类型定义迁移
1. 将参数相关类型移动到 `argument.zig`
2. 将句柄类型移动到 `handle.zig`
3. 将账户类型移动到 `account.zig`
4. 将会话类型移动到 `session.zig`

#### Phase 2: 核心逻辑迁移
1. 将授权计划移动到 `authorization.zig`
2. 将构建逻辑移动到 `builder.zig`

#### Phase 3: 集成和测试
1. 更新 `root.zig` 重新导出
2. 确保所有测试通过
3. 添加模块级文档

## 详细设计

### types.zig
```zig
pub const CommandResultAliases = std.StringHashMapUnmanaged(u16);
pub const NestedResultSpec = struct { ... };
// 基础类型
```

### argument.zig
```zig
pub const ArgumentValue = union(enum) { ... };
pub const PtbArgumentSpec = union(enum) { ... };
pub const ResolvedArgumentValue = struct { ... };
// 参数解析和转换
```

### handle.zig
```zig
pub const CommandResultHandle = struct { ... };
pub const CommandOutputHandle = struct { ... };
// 结果引用和输出处理
```

### account.zig
```zig
pub const AccountProvider = union(enum) { ... };
pub const DirectSignatureAccount = struct { ... };
pub const RemoteSignerAccount = struct { ... };
// 账户提供者逻辑
```

### session.zig
```zig
pub const SessionChallenge = union(enum) { ... };
pub const SessionChallengeRequest = struct { ... };
pub const SessionChallengeResponse = struct { ... };
// 会话挑战和响应
```

### authorization.zig
```zig
pub const AuthorizationPlan = struct { ... };
pub fn authorizationPlan(...) AuthorizationPlan;
// 授权计划和执行
```

### builder.zig
```zig
pub fn buildTransactionBlockFromCommandSource(...) !TransactionBlock;
pub fn buildArtifact(...) !Artifact;
// 构建逻辑
```

## 风险与缓解

### 风险 1: API 破坏
- **缓解**: 保持公共 API 不变
- **策略**: 通过 root.zig 重新导出所有公共类型

### 风险 2: 循环依赖
- **缓解**: 仔细设计模块层次
- **设计**: 基础类型 → 组合类型 → 业务逻辑

## 成功标准
- [ ] 所有现有测试通过 (83 个)
- [ ] 新模块结构清晰
- [ ] 向后兼容保持
- [ ] 代码可维护性提升

## 时间估计
- Phase 1: 2-3 小时
- Phase 2: 2-3 小时
- Phase 3: 1-2 小时
- **总计**: 5-8 小时
