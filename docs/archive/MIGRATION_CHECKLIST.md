# 删除旧 API 前必须完成的工作

## 当前状态

- 新 API: `src/client/rpc_client/` (17 模块, 214K 行)
- 旧 API: `src/client/rpc_client/client.zig` (44,708 行)
- 默认导出: 旧 API (`SuiRpcClient = rpc_client.SuiRpcClient`)

## 必须迁移的文件

### 1. main.zig
- [ ] 更新 `client.SuiRpcClient` → `client.rpc_client_new.SuiRpcClient`
- [ ] 更新 `client.rpc_client.RpcRequest` → `client.rpc_client_new.RpcRequest`
- [ ] 更新所有测试中的 mock callback
- [ ] 更新 `printLastError` 函数

### 2. commands.zig
- [ ] 更新 `client.SuiRpcClient` → `client.rpc_client_new.SuiRpcClient`
- [ ] 更新所有函数签名
- [ ] 更新所有 RPC 调用
- [ ] 或者：完全删除，只使用 `commands/` 模块

### 3. root.zig
- [ ] 将新 API 设为默认
- [ ] 删除旧 API 导出
- [ ] 或者：保留旧 API 作为 `rpc_client_legacy`

## 迁移策略选项

### 选项 A: 完全替换 (推荐)
1. 更新 `root.zig` 将新 API 设为默认
2. 更新 `main.zig` 使用新 API
3. 删除 `commands.zig`，只使用 `commands/` 模块
4. 删除旧 `client.zig`

### 选项 B: 双版本共存
1. 保持当前状态
2. 新功能使用新 API
3. 逐步迁移旧代码
4. 最终删除旧 API

### 选项 C: 适配器模式
1. 创建适配器使新旧 API 兼容
2. 逐步替换使用点
3. 最终删除旧 API

## 风险评估

### 如果现在就删除旧 API
- ❌ 项目无法编译
- ❌ 所有测试失败
- ❌ CLI 无法使用

### 建议
- 完成 `main.zig` 和 `commands.zig` 的迁移后再删除旧 API
- 或者保持双版本共存，逐步迁移
