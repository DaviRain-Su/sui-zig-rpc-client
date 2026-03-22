# Commands 模块重构计划

## 当前状态

- `src/commands.zig`: ~33,000 行，250+ 函数
- 包含：wallet、tx、account、move、request、intent 等多种功能
- 结构复杂，难以维护

## 目标架构

```
src/commands/
├── mod.zig          # 模块入口，重新导出公共接口
├── shared.zig       # 共享工具函数（已存在）
├── types.zig        # 命令相关类型定义
├── tx.zig           # 交易命令（已存在，需扩展）
├── move.zig         # Move 合约命令（已存在，需扩展）
├── account.zig      # 账户命令（已存在，需扩展）
├── wallet.zig       # 钱包管理命令（新增）
├── request.zig      # 请求生命周期命令（新增）
├── intent.zig       # 意图解析命令（新增）
├── provider.zig     # 程序化提供者相关（新增）
└── dispatch.zig     # 命令分发逻辑（新增）
```

## 重构阶段

### 阶段 1: 类型和共享工具 (已完成)
- ✅ `shared.zig` - 共享工具函数

### 阶段 2: 创建新子模块

#### 2.1 types.zig - 命令类型定义
从 commands.zig 提取：
- `OwnedCliProgrammaticProvider`
- `CliProviderKind`
- `SessionChallengeAction` 相关类型
- `CommandResult` (从 shared.zig 移动)
- `TxBuildError` (从 shared.zig 移动)

#### 2.2 wallet.zig - 钱包管理
从 commands.zig 提取钱包相关函数：
- `runWalletCreateOrImport`
- `runWalletUse`
- `runWalletAccounts`
- `runWalletConnect`
- `runWalletDisconnect`
- `runWalletPasskeyRegister`
- `runWalletPasskeyLogin`
- `runWalletPasskeyRevoke`
- `runWalletSessionCreate`
- `runWalletSessionList`
- `runWalletSessionRevoke`
- `runWalletPolicyInspect`
- `runWalletFund`
- 所有 `resolveWallet*` 辅助函数
- 所有 `formatWallet*` 辅助函数
- 钱包相关的结构体定义

#### 2.3 request.zig - 请求生命周期
从 commands.zig 提取：
- `buildRequestArtifactJsonFromArgs`
- `buildRequestInspectSummaryJson`
- `summarizeRequestLifecycleOutput`
- `upsertRequestLifecycleEntry`
- `runTrackedRequestStatusLikeCommand`
- 所有 request lifecycle 相关的辅助函数

#### 2.4 intent.zig - 意图解析
从 commands.zig 提取：
- `buildWalletIntentJsonFromArgs`
- 意图相关的解析函数

#### 2.5 provider.zig - 程序化提供者
从 commands.zig 提取：
- `ownCliProgrammaticProvider`
- `ownProgrammaticProviderWithDelegatedSession`
- `runLocalCommandSourceAction`
- `runProgrammaticActionMaybeAutoGasPayment`
- `runProgrammaticActionMaybeAutoGasPaymentOrChallengePrompt`
- `runSelectedProgrammaticAction`
- 所有 provider 相关的辅助函数
- 挑战/授权相关的函数

#### 2.6 dispatch.zig - 命令分发
从 commands.zig 提取：
- `runCommandWithProgrammaticProvider` 的主 switch
- `runCommand`
- 命令路由逻辑

### 阶段 3: 扩展现有子模块

#### 3.1 扩展 tx.zig
添加以下函数：
- `sendExecuteAndMaybeWaitForConfirmation` (从 commands.zig)
- `sendDryRunAndMaybeSummarize` (从 commands.zig)
- `buildExecutePayloadFromArgs` (从 commands.zig)
- `buildDryRunPayloadFromArgs` (从 commands.zig)
- `buildPayloadFromArgs` (从 commands.zig)
- 所有 tx_payload、tx_simulate、tx_dry_run、tx_send 相关的处理逻辑

#### 3.2 扩展 move.zig
添加以下函数：
- `printMoveFunctionTemplateOutput`
- `moveFunctionExecutionRequestArtifact`
- `ensureExecutableMoveFunctionRequestArtifact`
- `moveFunctionRequestArtifactIsExecutable`
- `buildDerivedMoveFunctionExecutionArgs`
- 所有 Move 函数模板相关的辅助函数

#### 3.3 扩展 account.zig
添加以下函数：
- `printBalanceSummaryForOwner`
- `runResourceQueryAction`
- `resourceQueryFromArgs`
- `resourceQueryActionFromArgs`
- 所有账户资源查询相关的辅助函数

### 阶段 4: 清理 commands.zig

最终 commands.zig 应该只包含：
- 向后兼容的重新导出
- 测试（逐步迁移到子模块）

## 依赖关系图

```
dispatch.zig
    ├── wallet.zig
    ├── tx.zig
    ├── move.zig
    ├── account.zig
    ├── request.zig
    ├── intent.zig
    └── provider.zig

所有模块依赖：
    ├── types.zig
    ├── shared.zig
    ├── cli.zig
    └── root.zig (sui_client_zig)
```

## 实施步骤

### 第 1 步: 创建 types.zig
- 提取所有命令相关的类型定义
- 更新 shared.zig 移除已移动的类型
- 更新所有子模块导入 types.zig

### 第 2 步: 创建 provider.zig
- 提取程序化提供者相关函数
- 这是其他许多模块的依赖，优先处理

### 第 3 步: 创建 wallet.zig
- 提取所有钱包相关函数
- 钱包命令相对独立，容易提取

### 第 4 步: 创建 request.zig 和 intent.zig
- 提取请求生命周期和意图相关函数

### 第 5 步: 扩展现有子模块
- 扩展 tx.zig、move.zig、account.zig

### 第 6 步: 创建 dispatch.zig
- 提取命令分发逻辑
- 更新 main.zig 使用新的 dispatch 模块

### 第 7 步: 清理和测试
- 运行所有测试确保功能完整
- 清理 commands.zig

## 风险与缓解

### 风险 1: 循环依赖
**缓解**: 仔细设计模块依赖关系，types.zig 和 shared.zig 作为基础层不依赖其他模块。

### 风险 2: 测试失败
**缓解**: 每个阶段完成后运行完整测试套件，确保功能完整。

### 风险 3: 公共 API 变更
**缓解**: 保持向后兼容，commands.zig 可以继续重新导出公共接口。

## 预期结果

- commands.zig: 33,000 行 → ~500 行（仅重新导出）
- 每个子模块: 2,000-5,000 行，专注单一职责
- 更好的可维护性和可测试性
- 更快的编译时间（增量编译）
