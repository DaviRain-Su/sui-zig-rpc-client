# RPC Client 迁移计划 - 完全替换旧实现

## 目标
将新的模块化 RPC Client (`rpc_client_new`) 功能完善，完全替换旧的 44,708 行实现 (`rpc_client`)

## 当前状态

### 已实现 ✅
- 基础 RPC 调用 (`call`, `sendJsonRpcRequest`)
- 查询方法 (`getBalance`, `getObject`, `getReferenceGasPrice`, 等)
- 交易方法 (`simulateTransaction`, `executeTransaction`)
- 事件查询 (`queryEvents`)
- Move 模块查询 (`getNormalizedMoveModule`)

### 待实现 ⏳

#### Phase 1: 核心构建功能
- [ ] `buildMoveCallTxBytes` - 构建 Move 调用交易字节
- [ ] `buildBatchTransactionTxBytes` - 构建批量交易
- [ ] `buildCommandSourceTxBytes` - 从命令源构建交易

#### Phase 2: 参数选择和解析
- [ ] `parseSelectedArgumentRequestToken` - 解析参数选择请求
- [ ] `selectArgumentValue` - 选择参数值
- [ ] `selectArgumentValueFromToken` - 从 token 选择参数值
- [ ] `selectArgumentValuesFromTokens` - 批量选择参数值

#### Phase 3: 高级执行功能
- [ ] `buildCommandSourceExecutePayloadWithSignatures` - 构建带签名的执行负载
- [ ] `buildCommandSourceExecutePayloadFromDefaultKeystore` - 从默认密钥库构建
- [ ] `buildCommandSourceExecutePayloadWithAutoGasPayment` - 自动 Gas 支付

#### Phase 4: 对象输入处理
- [ ] `resolveImmOrOwnedObjectInputJson` - 解析拥有的对象输入
- [ ] `resolveReceivingObjectInputJson` - 解析接收对象输入
- [ ] `resolveSharedObjectInputJson` - 解析共享对象输入
- [ ] `buildGasDataJson` - 构建 Gas 数据 JSON

#### Phase 5: 类型系统和 BCS 编码
- [ ] 完整的 BCS 编码支持
- [ ] Move 类型系统支持
- [ ] 结构体类型参数处理

## 实施策略

### 1. 创建 builder 模块
将交易构建功能组织到 `builder.zig` 模块

### 2. 创建 selector 模块
将参数选择功能组织到 `selector.zig` 模块

### 3. 创建 object_input 模块
将对象输入处理组织到 `object_input.zig` 模块

### 4. 扩展类型系统
在现有 `types.zig` 基础上扩展 Move 类型支持

## 代码统计

| 模块 | 当前行数 | 预计行数 | 状态 |
|------|---------|---------|------|
| client_core.zig | 9,800 | 15,000 | 进行中 |
| builder.zig | 0 | 20,000 | 待创建 |
| selector.zig | 0 | 15,000 | 待创建 |
| object_input.zig | 0 | 10,000 | 待创建 |
| types.zig | 11,200 | 20,000 | 待扩展 |
| 其他 | 81,800 | 85,000 | 已完成 |
| **总计** | **~128K** | **~165K** | **进行中** |

## 迁移检查清单

- [ ] 所有旧 client 的公共 API 在新模块中可用
- [ ] 所有测试通过
- [ ] 性能不下降
- [ ] 文档完整
- [ ] 向后兼容（提供迁移指南）

## 时间估计

- Phase 1: 4-6 小时
- Phase 2: 4-6 小时
- Phase 3: 3-4 小时
- Phase 4: 3-4 小时
- Phase 5: 2-3 小时
- **总计**: 16-23 小时
