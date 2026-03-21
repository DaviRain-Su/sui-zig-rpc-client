# RPC Client 模块重构计划

## 目标
将 `src/client/rpc_client/client.zig` (44,708 行) 重构为模块化的结构

## 当前状态
- 文件大小: 44,708 行
- 主要内容:
  - 50+ 类型定义 (struct, union, enum)
  - SuiRpcClient 结构体 (约 24,000 行)
  - 100+ 方法 (查询、交易、对象、事件等)
  - 辅助函数和数据转换

## 重构策略

### 新模块结构
```
src/client/rpc_client/
├── root.zig              # 模块入口，重新导出
├── types.zig             # 核心类型定义
├── error.zig             # 错误处理类型
├── client.zig            # SuiRpcClient 核心 (简化)
├── query.zig             # 查询相关方法
├── transaction.zig       # 交易相关方法
├── object.zig            # 对象相关方法
├── event.zig             # 事件相关方法
├── move.zig              # Move 相关方法
├── coin.zig              # 代币相关方法
├── builder.zig           # 构建器方法
├── utils.zig             # 辅助函数
└── constants.zig         # 常量定义
```

### 迁移计划

#### Phase 1: 类型定义迁移
1. 将错误类型移动到 `error.zig`
2. 将核心类型移动到 `types.zig`
3. 将查询类型移动到 `query.zig`
4. 将常量移动到 `constants.zig`

#### Phase 2: 核心客户端简化
1. 保留 SuiRpcClient 基本结构
2. 移除具体方法实现，改为调用子模块
3. 保持向后兼容的 API

#### Phase 3: 方法分类迁移
1. 查询方法 → `query.zig`
2. 交易方法 → `transaction.zig`
3. 对象方法 → `object.zig`
4. 事件方法 → `event.zig`
5. Move 方法 → `move.zig`
6. 代币方法 → `coin.zig`
7. 构建器方法 → `builder.zig`

#### Phase 4: 辅助函数和集成
1. 辅助函数 → `utils.zig`
2. 更新 `root.zig` 重新导出
3. 添加模块级测试
4. 确保向后兼容

## 详细设计

### client.zig (简化版)
```zig
pub const SuiRpcClient = struct {
    allocator: Allocator,
    endpoint: []const u8,
    http_client: std.http.Client,
    // ... 基本字段

    // 核心方法
    pub fn init(...) !SuiRpcClient;
    pub fn deinit(self: *SuiRpcClient);
    pub fn call(self: *SuiRpcClient, method: []const u8, params: []const u8) ![]u8;

    // 查询方法 (委托给 query.zig)
    pub fn getBalance(...) !u64;
    pub fn getObject(...) !Object;
    // ...
};
```

### query.zig
```zig
pub fn getBalance(client: *SuiRpcClient, address: []const u8) !u64;
pub fn getObjectsOwnedByAddress(...) ![]Object;
pub fn getDynamicFields(...) ![]DynamicField;
// ...
```

### transaction.zig
```zig
pub fn simulateTransaction(...) !SimulationResult;
pub fn dryRunTransaction(...) !DryRunResult;
pub fn executeTransaction(...) !ExecutionResult;
// ...
```

## 风险与缓解

### 风险 1: API 破坏
- **缓解**: 保持 SuiRpcClient 作为统一入口
- **策略**: 方法委托给子模块，但 API 不变

### 风险 2: 循环依赖
- **缓解**: 仔细设计模块层次
- **设计**: 子模块依赖核心类型，不互相依赖

### 风险 3: 性能下降
- **缓解**: 使用 inline 或 comptime 优化
- **测试**: 对比重构前后的性能

## 成功标准
- [ ] 所有现有测试通过
- [ ] 新模块结构清晰
- [ ] 编译时间不显著增加
- [ ] 向后兼容保持
- [ ] 代码可维护性提升

## 时间估计
- Phase 1: 3-4 小时
- Phase 2: 2-3 小时
- Phase 3: 6-8 小时
- Phase 4: 2-3 小时
- **总计**: 13-18 小时
