# Bootcamp Regression Matrix

这个仓库把 `MystenLabs/sui-move-bootcamp` 中最贴近 programmable transaction、账户授权和交易生命周期的场景，收敛成了一组固定回归测试。

目标不是复刻 bootcamp 的前端或 TypeScript 实现，而是把高价值场景锁定为 Zig SDK/CLI 的稳定行为。

参考模块：
- `C3 PTBs Introduction`
- `D4 Transaction submission, Balance Changes, and Gas Profiling`
- `H1 Upgrade preconditions and Versioned Shared Objects`
- `K2 ZKLogin Demo`

## 运行

```bash
zig build test --summary all
```

当前这组矩阵已经纳入默认测试图，不需要单独注册测试文件。

## 场景矩阵

### C3: PTBs Introduction

1. `split -> transfer`
- `SplitCoins` 产出 `coin_split.0`
- `TransferObjects` 消费结果引用
- 锁定三条输入面：
  - typed DSL
  - raw `--commands`
  - CLI fragments

2. `move-call -> assign -> nested result`
- `MoveCall` 结果可通过：
  - `alias.0`
  - `ptb:name:<alias>:0`
  进入后续命令
- 锁定 nested result 归一化一致性

3. `make-move-vec with result refs`
- `MakeMoveVec` 混合：
  - `@0x...`
  - `ptb:name:*`
  - `vector[...]`
- 锁定容器 token 的递归展开和结果引用

4. `raw batch local index rebasing`
- raw batch 追加到已有命令后
- `result:0` / `output:0:0` 会按当前 command count 自动偏移成全局索引

### H1: Upgrade preconditions and Versioned Shared Objects

5. `publish -> upgrade`
- `Publish` 后分配 alias
- `Upgrade.ticket` 消费前面命令结果
- 锁定 upgrade payload 的结构稳定性

### Account handling

6. `default keystore sender/signature resolution`
- `--sender <alias>` + `--signer <alias>`
- 锁定三条路径都会解析出相同 sender/signature：
  - helper path
  - client path
  - CLI path

### D4: Transaction submission, Balance Changes, and Gas Profiling

7. `execute -> confirm`
- 统一 action surface 的 `execute_confirm`
- 锁定它确实进入 confirm 路径，而不是只发交易

8. `gas / balance change response fixtures`
- 使用 D4 风格 fixture
- 抽取并锁定：
  - `status`
  - `status_error`
  - `gas_summary`
  - `balance_changes`
  - `netGasSpent()`

### K2: ZKLogin / session-backed flows

9. `inspect challenge flow`
- future wallet / remote signer 需要 challenge 时
- 先返回 structured prompt，不发 inspect RPC
- 应用 challenge response 后再 inspect

10. `execute challenge flow`
- passkey / zklogin 风格 account provider
- 锁定：
  - challenge
  - apply response
  - execute / executeAndConfirm

## 覆盖层级

这些场景不是只测某个函数，而是刻意分布在几层：

- `src/cli.zig`
  - CLI token、alias、fragment、raw command 路径
- `src/tx_request_builder.zig`
  - typed DSL、value token、result handle、artifact/request builder
- `src/tx_pipeline.zig`
  - helper path、default keystore provider、artifact construction
- `src/client/rpc_client/client.zig`
  - account provider
  - challenge prompt / apply response
  - authorize / inspect / execute / confirm
  - unified action dispatcher
- `src/tx_result.zig`
  - execute response summary extraction

## 使用原则

- 新增 programmable transaction 能力时，优先复用现有场景，而不是只补单点测试
- 新增账户/session 行为时，优先补到 challenge-aware matrix
- 新增 execute/confirm 响应处理时，优先补 D4 风格 fixture

如果某个新功能无法自然映射到这 10 个场景之一，通常意味着它还没有被放进足够稳定的 end-to-end surface。
