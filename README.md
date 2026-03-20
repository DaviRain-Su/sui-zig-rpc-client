# sui-zig-rpc-client

Zig + `std` 实现的 Sui CLI/RPC 客户端骨架，复用你在 Solana 项目中的分层结构（CLI 解析、命令分发、可复用 RPC transport）。

## 项目介绍

`sui-zig-rpc-client` 是一个面向开发者和基础设施场景的 Sui CLI / RPC / transaction tooling 项目，核心目标不是只覆盖几条固定命令，而是逐步把“任意 Sui 合约调用”这件事做成一条可复用的通路。

这个项目当前重点解决的是：
- 用 Zig 原生实现可复用的 Sui RPC client surface
- 用统一 CLI 输入构造通用 Move call / programmable transaction
- 处理 signer、sender、对象选择、gas、dry-run、send、confirm 这些交易生命周期问题
- 让任意协议集成不必从零手写一套临时脚本

换句话说，这个仓库的长期价值不在“再多加几个 one-off 命令”，而在于把 Sui 上链交互沉淀成一个通用执行层。对于 Cetus、DeFi 协议、自定义 Move package、自动化脚本、测试工具链，这套能力都可以复用。

## 在 Sui 生态中的定位

如果按 Sui 生态方向来归类，这个项目主要属于：
- `Developer Tooling`
- `Infrastructure / RPC Client Tooling`
- `Contract Invocation / Transaction Automation`

更具体一点说，它不是钱包前端、不是浏览器、也不是某个单一协议 SDK；它更接近：
- Sui 合约交互工具链
- Sui 交易构造与执行工具
- 面向协议集成和自动化脚本的底层基础设施

所以我们的方向可以概括成一句话：

`Sui 开发者基础设施 + 通用合约调用工具链`

## 目标

以最小可运行状态接入：
- Sui RPC 请求发送（`rpc` 命令）
- 基础交易生命周期命令（`tx simulate` / `tx send` / `tx status` / `tx confirm|wait`）
- 统一错误处理与通用返回转发

后续可在此基础上继续补齐任意程序调用所需的指令构造与签名流程。

## 回归测试矩阵

这仓库已经把 `sui-move-bootcamp` 里最有价值的 programmable transaction / upgrade / execute-confirm / challenge 场景收成固定回归测试。

- 测试矩阵说明：[`docs/bootcamp-test-matrix.md`](/Users/davirian/dev/zig/sui-zig-rpc-client/docs/bootcamp-test-matrix.md)
- 本地 Move 合约测试矩阵规划：[`docs/move-contract-test-matrix.md`](/Users/davirian/dev/zig/sui-zig-rpc-client/docs/move-contract-test-matrix.md)
- `Tempo / MPP` 风格 Sui wallet 规划：[`docs/sui-wallet-mpp-plan.md`](/Users/davirian/dev/zig/sui-zig-rpc-client/docs/sui-wallet-mpp-plan.md)
- 建议执行：

```bash
zig build test --summary all
zig build move-fixture-test
```

`zig build test` 现在会同时跑：
- Zig 单元测试
- `fixtures/move/*` 本地 Move 合约矩阵

外部协议目标现在分两层：
- `Cetus`：轻量 live smoke，确认真实公共链上 ABI / discovery / artifact 主链没回退
- `MystenLabs/hashi`：已完成本地 Move 可行性验证，适合作为本地 publish /
  testnet publish 后的重协议交互样本，不直接替代 `Cetus` 的公共链上 smoke

`Hashi` 的第一条可重复 smoke 已经收成脚本：

```bash
bash scripts/hashi_publish_smoke.sh /tmp/hashi_inspect/packages/hashi
```

它会：
- 编译真实 `Hashi` Move 包
- 提取真实 publish `modules/dependencies`
- 用这个 CLI 本地构一笔 `Publish` programmable transaction block

第二条 smoke 现在也已经打通，直接覆盖：
- 用这个 CLI 本地 `Publish + TransferObjects(Result(0))`
- 自动抽取真实 `package_id` / shared `Hashi` / `UpgradeCap`
- 用 `move function ... --emit-template preferred-send-request`
  生成 `finish_publish` request artifact
- 再用 `tx send --request` 真实发出 `finish_publish`

```bash
bash scripts/hashi_finish_publish_smoke.sh /tmp/hashi_inspect/packages/hashi
```

第三条 smoke 继续往前推进到了真实协议 PTB：
- 复用 `publish -> finish_publish`
- 用 `tx send --commands` 串起
  `utxo_id -> utxo -> deposit_request -> coin::zero<SUI> -> deposit`
- 验证 `Result` 链接、shared object 输入、`clock` preset、`Option<address>`、
  以及真实 `DepositRequestedEvent`

```bash
bash scripts/hashi_deposit_smoke.sh /tmp/hashi_inspect/packages/hashi
```

`request_withdrawal` 这条也已经有 smoke 脚本，但它有真实前置条件：
- 先提供一个已 `publish + finish_publish` 完成的 `Hashi` 部署
  (`HASHI_PACKAGE_ID` / `HASHI_HASHI_OBJECT_ID`)
- sender 账户里必须已经有一枚 `Coin<${package_id}::btc::BTC>`
- 脚本会先自动探测 coin；如果没有，会明确报缺口并退出
- 有 coin 时，它会用 `move function ... --emit-template preferred-send-request`
  生成 withdrawal request artifact，再通过 `tx send --request` 发出

```bash
HASHI_PACKAGE_ID=0x... \
HASHI_HASHI_OBJECT_ID=0x... \
bash scripts/hashi_request_withdrawal_smoke.sh /tmp/hashi_inspect/packages/hashi
```

真实钱包的 testnet smoke 也已经单独收成脚本：

```bash
bash scripts/testnet_real_wallet_smoke.sh
```

它的默认行为是：
- 只允许在 `sui client active-env == testnet` 下运行
- 读取当前 active address 和默认 keystore
- 先打印 gas / resources
- 再跑一笔“split 一点 SUI 然后转回自己”的 `tx dry-run`
- 默认不会真实广播

常用开关：

```bash
# 地址没 gas 时，自动向 testnet faucet 申请
AUTO_FAUCET=1 bash scripts/testnet_real_wallet_smoke.sh

# keystore 里有多个 signer 时，显式指定 selector
SIGNER_SELECTOR=main bash scripts/testnet_real_wallet_smoke.sh

# 确认 dry-run 没问题后，才显式允许真实发送
ALLOW_SEND=1 bash scripts/testnet_real_wallet_smoke.sh
```

说明：
- `ALLOW_SEND=1` 会在 testnet 上真实发送一笔 self-transfer，虽然不会把币转给别人，但会改变钱包里的 coin object 形态
- 如果你确实要在别的网络试跑，必须显式给 `ALLOW_NON_TESTNET=1`

当前默认测试图覆盖：
- `C3 PTBs Introduction`
- `D4 Transaction submission, Balance Changes, and Gas Profiling`
- `H1 Upgrade preconditions and Versioned Shared Objects`
- `K2 ZKLogin / session-backed account flow`

本地 Move 合约矩阵现在已经开始落地，第一项是：
- [`fixtures/move/counter_baseline`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/counter_baseline)
  - 覆盖 `u64/bool/address`、by-value pure struct、多返回值顺序、sender 上下文，以及 entry / non-entry 两条调用路径
  - 可直接运行：

```bash
sui move test --path fixtures/move/counter_baseline
```

- [`fixtures/move/shared_state_lab`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/shared_state_lab)
  - 覆盖 shared object、owned admin cap、shared object 跨交易修改、version migration
  - 可直接运行：

```bash
sui move test --path fixtures/move/shared_state_lab
```

- [`fixtures/move/generic_vault`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/generic_vault)
  - 覆盖 `Vault<T>` owned object、`VaultConfig<T>` generic pure struct、`Balance<T>` seed、`Coin<T>` deposit、`Option<u64>` gate
  - 可直接运行：

```bash
sui move test --path fixtures/move/generic_vault
```

- [`fixtures/move/vector_router`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/vector_router)
  - 覆盖 `vector<object>`、`vector<Coin<T>>`、`vector<vector<u8>>` 和双 trailing amount 签名
  - 可直接运行：

```bash
sui move test --path fixtures/move/vector_router
```

- [`fixtures/move/receipt_flow_lab`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/receipt_flow_lab)
  - 覆盖 `borrow -> receipt -> repay`、capability/receipt object、多返回值链式调用和 change/fee 路径
  - 可直接运行：

```bash
sui move test --path fixtures/move/receipt_flow_lab
```

- [`fixtures/move/dynamic_registry`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/dynamic_registry)
  - 覆盖 content 不直接暴露目标 id、dynamic fields 间接找对象、content + dynamic fields 同时给不同对象
  - 可直接运行：

```bash
sui move test --path fixtures/move/dynamic_registry
```

- [`fixtures/move/admin_upgrade_lab`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/admin_upgrade_lab)
  - 覆盖 `AdminCap`、`UpgradeCap`、publisher proof、governance policy 和 test-only upgrade flow
  - 可直接运行：

```bash
sui move test --path fixtures/move/admin_upgrade_lab
```

- [`fixtures/move/pool_like_protocol_lab`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/pool_like_protocol_lab)
  - 覆盖 shared `Pool<X, Y>`、owned `Position`、owned `PoolManager`、dual-coin scalar/vector add-liquidity、receipt 和 snapshot
  - 可直接运行：

```bash
sui move test --path fixtures/move/pool_like_protocol_lab
```

接下来更关键的补强，不是继续堆 live 协议样例，而是把一组本地可控的复杂
Move package 收成固定矩阵。这样 shared/owned/generic/vector/receipt/dynamic
fields 这些能力才能被 deterministic 地锁住，而不是只靠 Cetus 主网 smoke
去间接证明。

## 运行

```bash
zig build run -- help
zig build run -- version
zig build run -- rpc sui_getLatestSuiSystemState
zig build run -- rpc sui_getLatestCheckpointSequenceNumber --timeout-ms 8000
zig build run -- tx build move-call --package 0x2 --module counter --function increment --args '[7]' --summarize
zig build run -- tx payload --package 0x2 --module counter --function increment --args '[7]' --sender 0xabc --signature sig-a --summarize
zig build run -- tx simulate --package 0x2 --module counter --function increment --sender 0xabc --summarize
zig build run -- tx payload --tx-bytes AA... --signature BASE64SIG --signature BASE64SIG2 --pretty
zig build run -- tx send --tx-bytes AA... --sig @sig.txt --summarize
zig build run -- tx send --tx-bytes AA... --sig @sig.txt --observe
zig build run -- tx status 0x... --summarize
zig build run -- tx confirm 0x... --poll-ms 1000 --confirm-timeout-ms 120000 --observe
zig build run -- account resources main --coin-type 0x2::sui::SUI --package 0x2 --module coin --limit 25
zig build run -- tx simulate --package 0x2 --module counter --function increment --sender 0xwallet
```

## 结构化输出模式

这套 CLI 现在已经把交易生命周期里的几类高频输出收成了稳定模式：

- `tx build --summarize`
  - 输出 transaction instruction / transaction block 的结构化 artifact summary
- `tx payload --summarize`
  - 输出 execute payload 的结构化 artifact summary
- `tx simulate --summarize`
  - 输出 dev-inspect 的结构化 inspect summary
- `tx send --summarize`
  - 输出 execute response 的结构化 execution summary
- `tx send --observe`
  - 输出 `digest + confirmed_response + insights`
- `tx status --summarize`
  - 输出 `sui_getTransactionBlock` 的结构化 execution summary
- `tx status --observe`
  - 输出 `digest + confirmed_response + insights`
- `tx confirm|wait --summarize`
  - 输出确认后的结构化 execution summary
- `tx confirm|wait --observe`
  - 输出确认后的 `digest + confirmed_response + insights`

典型示例：

```bash
# 1. 先看 build 产物的高层摘要
zig build run -- tx build move-call \
  --package 0x2 \
  --module counter \
  --function increment \
  --args '[7]' \
  --summarize

# 2. 再看 execute payload 的高层摘要
zig build run -- tx payload \
  --package 0x2 \
  --module counter \
  --function increment \
  --args '[7]' \
  --sender 0xabc \
  --signature sig-a \
  --summarize

# 3. inspect/dev-inspect 摘要
zig build run -- tx simulate \
  --package 0x2 \
  --module counter \
  --function increment \
  --sender 0xabc \
  --summarize

# 4. 发送后直接看 execute summary
zig build run -- tx send \
  --tx-bytes AA... \
  --signature sig-a \
  --summarize

# 5. 发送后直接进入 confirm + observe
zig build run -- tx send \
  --tx-bytes AA... \
  --signature sig-a \
  --observe

# 6. 对已有 digest 做一次 status/confirm 摘要
zig build run -- tx status 0x... --summarize
zig build run -- tx confirm 0x... --observe
```

## 资源发现

这套 CLI 现在已经把“交易前置资源发现”单独收成了稳定入口，适合在构造任意 PTB 前先做：
- gas coin discovery
- owned object discovery
- typed object filter narrowing

典型 CLI：

```bash
# 1. 看单一 coin type 的 coins
zig build run -- account coins main \
  --coin-type 0x2::sui::SUI \
  --limit 25

# 2. 看某个 StructType 的 owned objects
zig build run -- account objects main \
  --struct-type 0x2::coin::Coin<0x2::sui::SUI> \
  --show-type \
  --show-owner \
  --limit 25

# 3. 按 package/module 做 typed owned-object filter
zig build run -- account objects main \
  --package 0x2 \
  --module coin \
  --limit 25

# 4. 直接按 object id 缩小范围
zig build run -- account objects main \
  --object-id 0xobject-1

# 5. 一次拿 coins + owned objects
zig build run -- account resources main \
  --coin-type 0x2::sui::SUI \
  --package 0x2 \
  --module coin \
  --show-type \
  --limit 25

# 6. 需要机器可读结果时走 raw combined JSON
zig build run -- account resources main \
  --coin-type 0x2::sui::SUI \
  --struct-type 0x2::coin::Coin<0x2::sui::SUI> \
  --json
```

当前 owned-object typed filter 已经支持：
- `--struct-type`
- `--object-id`
- `--package`
- `--package + --module`

这些入口都直接站在共享 read/query surface 上，不是 CLI 私有旁路实现。

## Keystore account metadata / signer selectors

本地 keystore 现在已经支持两类常见 entry：
- raw string entry
  - 例如 `["<base64-private-key>"]`
- object entry
  - 例如 `{"alias":"main","privateKey":"<base64-private-key>"}`
  - 也支持这些 raw-key 字段别名：
    - `privateKey`
    - `private_key`
    - `secretKey`
    - `secret_key`
    - `secret`
    - `key`
    - `value`

如果 object entry 里没有显式：
- `address`
- `suiAddress`
- `publicKey`

CLI 现在会直接从 raw key 派生：
- `address`
- `public_key`

这意味着下面这些入口都能复用同一套派生结果：
- `account list`
- `account info`
- `--signer <selector>`
- `--from-keystore`
- sender inference

也就是说，selector 不只可以是：
- alias / name
- index
- 显式 address / publicKey

现在也可以直接用“派生地址”命中 object-style keystore entry。

显式 metadata 这边当前也兼容常见别名：
- address:
  - `address`
  - `accountAddress`
  - `account_address`
  - `walletAddress`
  - `wallet_address`
  - `suiAddress`
  - `sui_address`
- public key:
  - `publicKey`
  - `public_key`
  - `pubKey`
  - `pub_key`
  - `pub`

所以 `--signer <selector>` / `account info <selector>` 现在都可以稳定按这些值命中：
- alias / name
- index
- raw key string
- 显式 address aliases
- 显式 public-key aliases
- 派生 address
- 派生 public key

典型 keystore 形态：

```json
[
  {
    "alias": "main",
    "privateKey": "AAECAwQ..."
  },
  {
    "name": "builder",
    "key": "AAUGBwg..."
  },
  {
    "alias": "wallet",
    "secret_key": "AAkKCww...",
    "account_address": "0xwallet",
    "pub_key": "base64-public-key"
  }
]
```

典型 CLI：

```bash
# 1. 看派生后的 account metadata
zig build run -- account list --json

# 2. 按 alias/name/index 查单个 entry
zig build run -- account info main --json
zig build run -- account info 0 --json

# 3. 按派生地址查 entry
zig build run -- account info 0xderivedaddress --json

# 4. 让 programmatic tx 直接复用 keystore signer/source
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --args '[7]' \
  --signer main \
  --gas-budget 1000000

# 5. 或直接让 sender/signature 从 keystore 首个可派生地址补齐
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --args '[7]' \
  --from-keystore \
  --gas-budget 1000000
```

## Provider challenge prompt / `--session-response`

独立 CLI 现在支持通过 `--provider` 注入 session-backed account provider，并通过 `--session-response` 续跑已批准的 challenge-response 流程。

最小 provider 配置示例：

```json
{
  "kind": "passkey",
  "address": "0x1111111111111111111111111111111111111111111111111111111111111111",
  "session": {
    "kind": "passkey",
    "sessionId": "wallet-session-id"
  },
  "challenge": {
    "passkey": {
      "rpId": "wallet.example",
      "challengeB64url": "challenge-token"
    }
  },
  "authorizer": {
    "exec": ["wallet-helper", "authorize"]
  }
}
```

CLI 行为：
- 只传 `--provider` 时，`tx simulate|payload|send|build` 和 `move function --dry-run|--send` 会输出 challenge prompt JSON。
- 同时传 `--provider` 和 `--session-response` 时，会把 continuation request 发给 `authorizer.exec` 指定的外部命令，并继续完成 dry-run / payload / send / tx-block 构造。
- 如果 `authorizer.exec` 启动失败、非零退出、或返回坏 JSON，CLI 会打印 `request failed`，并在错误消息里附带 `stderr` / `stdout` 摘要。

支持的 provider kind：
- `passkey`
  - 典型 challenge: `challenge.passkey`
- `remote_signer`
  - 典型 challenge: `challenge.signPersonalMessage`
- `zklogin`
  - 典型 challenge: `challenge.zkloginNonce`
- `multisig`
  - 最常见是直接 executable authorizer；也可以携带通用 session challenge

其他 kind 最小示例：

```json
{
  "kind": "remote_signer",
  "address": "0x1111111111111111111111111111111111111111111111111111111111111111",
  "challenge": {
    "signPersonalMessage": {
      "domain": "wallet.example",
      "statement": "Sign in",
      "nonce": "nonce-1"
    }
  },
  "authorizer": {
    "exec": ["wallet-helper", "authorize"]
  }
}
```

```json
{
  "kind": "zklogin",
  "address": "0x2222222222222222222222222222222222222222222222222222222222222222",
  "challenge": {
    "zkloginNonce": {
      "nonce": "nonce-zk",
      "provider": "google",
      "maxEpoch": 44
    }
  },
  "authorizer": {
    "exec": ["wallet-helper", "authorize"]
  }
}
```

```json
{
  "kind": "multisig",
  "address": "0x3333333333333333333333333333333333333333333333333333333333333333",
  "authorizer": {
    "exec": ["wallet-helper", "authorize"]
  }
}
```

仓库内可复用 fixture：
- `examples/provider/passkey.json`
- `examples/provider/remote_signer.json`
- `examples/provider/zklogin.json`
- `examples/provider/multisig.json`
- `examples/provider/passkey-session-response.json`
- `examples/provider/remote_signer-session-response.json`
- `examples/provider/zklogin-session-response.json`
- `examples/provider/mock_authorizer.sh`

直接从仓库根目录试跑：

```bash
# 1. passkey prompt
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --arg 7 \
  --gas-budget 1200 \
  --provider @examples/provider/passkey.json

# 2. passkey continuation
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --arg 7 \
  --gas-budget 1200 \
  --provider @examples/provider/passkey.json \
  --session-response @examples/provider/passkey-session-response.json

# 3. remote signer continuation
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --arg 7 \
  --gas-budget 1200 \
  --provider @examples/provider/remote_signer.json \
  --session-response @examples/provider/remote_signer-session-response.json

# 4. multisig direct execute via mock authorizer
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --arg 7 \
  --gas-budget 1200 \
  --provider @examples/provider/multisig.json
```

`examples/provider/mock_authorizer.sh` 是最小 mock：
- 会读取 stdin，但不会真正解析 request JSON
- 只按 profile 返回一个固定的批准结果
- 适合联调 CLI 合同，不适合真实签名

response JSON 结构最小形态：

```json
{
  "supportsExecute": true,
  "session": {
    "kind": "passkey",
    "sessionId": "wallet-session-id"
  }
}
```

兼容字段：
- `supportsExecute` / `supports_execute`
- `session.sessionId` / `session.session_id`
- `session.userId` / `session.user_id`
- `session.expiresAtMs` / `session.expires_at_ms`

provider JSON 兼容字段：
- `supportsExecute` / `supports_execute`
- `challenge.passkey.rpId` / `challenge.passkey.rp_id`
- `challenge.passkey.challengeB64url` / `challenge.passkey.challenge_b64url`
- `challenge.signPersonalMessage` / `challenge.sign_personal_message`
- `challenge.zkloginNonce` / `challenge.zklogin_nonce`
- `session.sessionId` / `session.session_id`
- `session.userId` / `session.user_id`
- `session.expiresAtMs` / `session.expires_at_ms`

`authorizer.exec` stdin/stdout 契约：
- stdin 是一个 JSON object，字段最关键的是：
  - `options`: 当前 programmatic request options
  - `accountAddress`: provider address
  - `accountSession`: 当前 session 状态
  - `txBytesBase64`: 需要签名/执行时会带上 tx bytes；纯 prompt / inspect / build 类路径可能为 `null`
- stdout 必须是一个 JSON object，最关键的返回字段是：
  - `sender`: 可选；如果返回，必须和当前 sender 一致
  - `signatures`: execute 路径通常必填
  - `session`: 可选；用于更新 session id / user id / expiresAtMs
  - `supportsExecute`: 是否允许当前 continuation 直接执行

最小 stdout 示例：

```json
{
  "sender": "0x1111111111111111111111111111111111111111111111111111111111111111",
  "signatures": ["sig-a"],
  "session": {
    "kind": "remote_signer",
    "sessionId": "approved-session"
  },
  "supportsExecute": true
}
```

## 库级 API 示例

CLI 之上的高层库入口已经可以直接覆盖：
- generic command source
- account provider
- unified action dispatcher
- inspect / execute / observe / artifact summarize
- object / dynamic field 读取

统一 action surface 的最小例子：

```zig
const std = @import("std");
const sui = @import("sui_client_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rpc = try sui.SuiRpcClient.init(allocator, "https://fullnode.mainnet.sui.io:443");
    defer rpc.deinit();

    const source = sui.tx_builder.CommandSource{
        .command_items = &.{
            "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
        },
    };
    const config = sui.tx_request_builder.CommandRequestConfig{
        .sender = "0xsender",
        .gas_budget = 1_000,
        .gas_price = 7,
        .options_json = "{\"showEffects\":true}",
    };
    const provider = sui.tx_request_builder.AccountProvider{
        .direct_signatures = .{
            .sender = "0xsender",
            .signatures = &.{"sig-a"},
        },
    };

    var artifact_result = try rpc.runCommandsWithAccountProvider(
        allocator,
        source,
        config,
        provider,
        .{ .build_artifact_summarize = .execute_payload },
    );
    defer artifact_result.deinit(allocator);

    switch (artifact_result) {
        .artifact_summarized => |summary| switch (summary) {
            .execute_payload => |payload| {
                std.debug.print("payload commands={d} signatures={d}\n", .{
                    payload.command_count,
                    payload.signature_count,
                });
            },
            else => unreachable,
        },
        else => unreachable,
    }

    var inspect_result = try rpc.runCommandsWithAccountProvider(
        allocator,
        source,
        config,
        provider,
        .inspect_summarize,
    );
    defer inspect_result.deinit(allocator);

    switch (inspect_result) {
        .inspect_summarized => |summary| {
            std.debug.print("inspect status={s} results={d} events={d}\n", .{
                @tagName(summary.status),
                summary.results_count,
                summary.events_count,
            });
        },
        else => unreachable,
    }

    var execute_result = try rpc.runCommandsWithAccountProvider(
        allocator,
        source,
        config,
        provider,
        .{ .execute_confirm_observe = .{
            .timeout_ms = 60_000,
            .poll_ms = 1_000,
        } },
    );
    defer execute_result.deinit(allocator);

    switch (execute_result) {
        .observed => |observation| {
            std.debug.print("digest={s} gas={?d}\n", .{
                observation.digest,
                observation.insights.gas_summary.computation_cost,
            });
        },
        else => unreachable,
    }
}
```

如果账户面是 session-backed wallet / remote signer，同一套入口可以直接切到：
- `runCommandsOrChallengePromptWithAccountProvider(...)`
- `runCommandsWithChallengeResponseWithAccountProvider(...)`

也就是说，调用方不必分叉一套新的执行 pipeline，只需要在 challenge-required 时补一段 approval/response。

更直接的 prompt/response 例子：

```zig
var prompt_or_result = try rpc.runCommandsOrChallengePromptWithAccountProvider(
    allocator,
    source,
    config,
    provider,
    .{ .execute_confirm_summarize = .{
        .timeout_ms = 60_000,
        .poll_ms = 1_000,
    } },
);
defer prompt_or_result.deinit(allocator);

switch (prompt_or_result) {
    .challenge_required => |prompt| {
        std.debug.print("challenge for {s}\n", .{prompt.account_address orelse "unknown"});
    },
    .completed => |result| {
        result.deinit(allocator);
    },
}

const response = sui.tx_request_builder.SessionChallengeResponse{
    .supports_execute = true,
    .session = .{
        .kind = .passkey,
        .session_id = "wallet-session-id",
    },
};

var continued = try rpc.runCommandsWithChallengeResponseWithAccountProvider(
    allocator,
    source,
    config,
    provider,
    response,
    .{ .execute_confirm_summarize = .{
        .timeout_ms = 60_000,
        .poll_ms = 1_000,
    } },
);
defer continued.deinit(allocator);
```

如果你走的是 builder / selected-resource 高层入口，同样的 continuation 能力也已经对齐到：
- `runDslBuilderOrChallengePrompt...`
- `runDslBuilderWithChallengeResponse...`
- `SelectedArgumentDslBuilder.runOrChallengePrompt...`
- `SelectedArgumentDslBuilder.runWithChallengeResponse...`

读链面的最小例子：

```zig
const std = @import("std");
const sui = @import("sui_client_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rpc = try sui.SuiRpcClient.init(allocator, "https://fullnode.mainnet.sui.io:443");
    defer rpc.deinit();

    var object = try rpc.getObjectAndSummarize(
        allocator,
        "0xobject",
        "{\"showType\":true,\"showOwner\":true,\"showContent\":true}",
    );
    defer object.deinit(allocator);

    var fields = try rpc.getAllDynamicFields(
        allocator,
        "0xparent_object",
        50,
    );
    defer fields.deinit(allocator);

    std.debug.print("object exists={any} dynamic_fields={d}\n", .{
        object.exists,
        fields.entries.len,
    });
}
```

这些高层入口现在已经能直接支撑：
- read -> build -> inspect/execute
- summarize / observe
- default keystore / direct signatures / session-backed account provider

如果你要在发送前先做资源发现，直接走统一 read surface：

```zig
const std = @import("std");
const sui = @import("sui_client_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rpc = try sui.SuiRpcClient.init(allocator, "https://fullnode.mainnet.sui.io:443");
    defer rpc.deinit();

    var result = try rpc.runReadQueryAction(
        allocator,
        .{
            .resources = .{
                .coins = .{
                    .page = .{
                        .owner = "0xowner",
                        .request = .{
                            .coin_type = "0x2::sui::SUI",
                            .limit = 25,
                        },
                    },
                },
                .owned_objects = .{
                    .page = .{
                        .owner = "0xowner",
                        .request = .{
                            .filter = .{
                                .move_module = .{
                                    .package = "0x2",
                                    .module = "coin",
                                },
                            },
                            .options = .{
                                .typed = .{
                                    .show_type = true,
                                    .show_owner = true,
                                },
                            },
                            .limit = 25,
                        },
                    },
                },
            },
        },
        .summarize,
    );
    defer result.deinit(allocator);

    switch (result) {
        .summarized => |summary| {
            std.debug.print("coins={?d} owned_objects={?d}\n", .{
                if (summary.resources.coins) |coins| coins.entries.len else null,
                if (summary.resources.owned_objects) |objects| objects.entries.len else null,
            });
        },
        else => unreachable,
    }
}
```

## 命令

- `help`: 打印用法
- `version`: 打印版本
- `rpc <method> [params-json]`: 发送任意 Sui JSON-RPC 方法。
- `events`: 调用 `suix_queryEvents`；支持 raw `--filter <json|@file>`，也支持 typed `--package --module`、`--event-type`、`--sender`、`--tx`，可用于协议对象和行为发现。
- `move package <package-id-or-alias>`: 调用 `sui_getNormalizedMoveModulesByPackage`，发现 package 下有哪些模块。
- `move module <package-id-or-alias> <module>`: 调用 `sui_getNormalizedMoveModule`，查看模块里的 structs / exposed functions。
- `move function <package-id-or-alias> <module> <function>`: 调用 `sui_getNormalizedMoveFunction`，查看参数/返回类型；`--summarize` 会额外输出 CLI lowering hint 和可复用的 transaction 模板。可选 `--type-arg/--type-args` 会在本地先按具体类型实参特化 summary。`--args` / `--arg` 可以把你已知的显式参数先回填到 preferred template 里；`--arg-at <index> <value>` 可以按参数位精确覆盖某个参数；`--object-arg-at <index> <object-id-or-alias>` 会直接查对象元数据并回填精确 `object_input`；`--sender` / `--signer` / `--from-keystore` 会把 owner 上下文回填到 owned-object discovery hint 里。`--emit-template <kind>` 可以直接把生成好的 `commands` / `request artifact` 单独输出出来；`--dry-run` / `--send` 会直接消费 preferred request artifact 并进入执行路径。

如果 preferred request artifact 里还残留 unresolved placeholder，但基础 request artifact 已经可执行，`move function --dry-run` / `--send` 现在会自动安全回退到基础 request，而不是直接报 `UnresolvedMoveFunctionExecutionTemplate`。
- `tx simulate [params-json]`: 调用 `sui_devInspectTransactionBlock`。
- `tx dry-run [tx-bytes|@file]`: 调用 `sui_dryRunTransactionBlock`。
- `tx send [params-json]`: 调用 `sui_executeTransactionBlock`。
- `tx payload`: 通过 CLI 参数构造 `sui_executeTransactionBlock` 的 params
- `tx payload --summarize`: 输出 execute payload 的结构化 artifact summary
- `tx dry-run --summarize`: 输出 dry-run 的结构化 execution summary
- `tx send --tx-bytes ... --signature ...`: 使用签名+tx bytes 直接调用 `sui_executeTransactionBlock`
- `tx send --from-keystore`: 当未提供 `--signature` 时，优先从默认 keystore 本地签名；若命令源支持本地 programmable builder，会直接构造 tx bytes 并签名发送
- `tx send/payload --signer`: 按 keystore 记录中的 `alias/address/key` 选择 signer 并追加签名（配合 `--from-keystore`）
- `tx send --summarize`: 输出 execute response 的结构化 execution summary
- `tx send --observe`: 输出 `digest + confirmed_response + insights`
- `tx status <digest>`: 查询 `sui_getTransactionBlock`（一次）。
- `tx status --summarize|--observe`: 输出结构化 execution summary，或 `digest + confirmed_response + insights`
- `tx confirm|wait <digest>`: 轮询 `sui_getTransactionBlock`，直到结果出现或超时。
- `tx confirm|wait --summarize|--observe`: 输出结构化 execution summary，或 `digest + confirmed_response + insights`
- `tx build move-call`: 输出 MoveCall 指令 JSON；加 `--emit-tx-block` 可输出可直接提交的 `ProgrammableTransaction` JSON。
- `tx build move-call|programmable --summarize`: 输出 build artifact 的结构化 summary

对于 keystore-backed signer source 或 direct-signature 的 `tx payload` / `tx send` programmable 路径，如果已经给了显式 `--gas-budget`，但没有显式 `--gas-payment`，CLI 现在会优先在本地 builder 路径里自动挑一枚 gas coin，而不是直接退回 `unsafe_moveCall` / `unsafe_batchTransaction`；这条路径同样覆盖带 selected-argument token 的命令源，不必先手工把对象参数展开成 raw object ref。
同样的隐式 gas-payment 本地 fallback 现在也覆盖 `tx build --emit-tx-block`、`tx simulate`、`tx dry-run` 的 programmable 路径，尽量让构造、模拟、执行走同一条本地 builder 主线。
复用型的 `run/build command-source` helper 现在也对齐到了这条本地主线：direct-signature 和 default-keystore 在做 selected-argument 解析或 auto gas payment 后，会继续通过本地 authorized request 构造 execute payload，而不是再退回远端 `unsafe_*` builder。
同样，`AccountProvider` 里的 direct-signatures、keystore-contents、default-keystore，以及已经完成 challenge-response 的 remote/future-wallet provider，在 command-source execute helper 里也会优先留在本地 authorized-request / local builder 路径；只有仍然显式依赖远端 `tx_bytes` 契约的分支，才继续走旧的 real-builder 路径。
本地 programmable command-source execute payload 路径现在也和这条行为对齐了：对 challenge-approved 的 account-provider，即使显式给了自定义 `expiration`，也会直接走 owned-plan / local builder，而不是先落成 `tx_bytes` 再交给 provider authorizer。
`runCommandSource*WithChallengeResponseWithAccountProvider` 这一层现在也对齐到同一条 owned-plan / local builder 主线，不再自己单独拼 execute payload；challenge-response 之后的 command-source 执行会和 `options/commands` helper 一样，把 provider authorizer 继续喂成结构化 `options`，而不是退回 `tx_bytes_base64`。
对 still-legacy 的 `buildCommandSourceExecutePayloadWithSignatures` / `...FromDefaultKeystore` helper，只要已经给了明确 `gas_object_id`，CLI 现在也会先把它解析成本地 `gasPayment + gasPrice`，再优先走 local programmable builder，而不是直接落回 `unsafe_moveCall` / `unsafe_batchTransaction`。
同样，legacy 的 `buildCommandSourceTxBytes` helper 在 `gas_object_id` 已知且命令源本地可 lowering 时，也会先走 local programmable builder，而不是直接落回 `unsafe_moveCall` / `unsafe_batchTransaction`。
更底层的 `buildMoveCallTxBytes` / `buildBatchTransactionTxBytes` 在 `gas_object_id` 已知且输入本地可 lowering 时，也会优先走同一条 local programmable builder 主线，避免旧 helper 绕开这层收口。
同样，当这些 tx-bytes helper 已知 `sender + gasBudget` 但没有显式 `gas_object_id` 时，也会先在本地自动选 gas coin 并继续走 local programmable builder，而不是直接把这类情况整体退回 `unsafe_*`。
对带显式 `sender` 的 direct-signature / provider programmable `tx payload` / `tx send` 路径，CLI 现在也优先留在标准 programmatic local builder 主线，不再因为历史上的 `unsafe` dispatch 规则先绕一次旧 command-source helper。
如果 command source 本身已经是本地 programmable builder 支持的形状，CLI 现在也不会再因为 default-keystore / provider 的 signer-resolution 需求，把 `tx payload` / `tx send` 硬路由回 legacy unsafe dispatcher；这类路径会继续留在统一的 programmatic local builder 主线。
- `tx build programmable`: 提供 `--commands` JSON 数组直接构建任意 PTB `ProgrammableTransaction`。
- `tx build --signer`: 可复用 keystore 选择器（alias/address/key）；未提供 `--sender` 时优先使用首个可解析出地址的 signer。
- `account list`: 列出 keystore 条目。
- `account info <selector>`: 按索引或别名/地址/密钥字段查询并展示单条 keystore 记录；`--json` 输出 JSON。
- `account coins <selector|0xaddress>`: 查询 owner 的 coin page；支持 `--coin-type`、`--limit`、`--all`、`--json`。
- `account objects <selector|0xaddress>`: 查询 owner 的 owned objects；支持 raw filter JSON 和 typed filters：
  - `--struct-type`
  - `--object-id`
  - `--package <package-id-or-alias>`
  - `--package --module`
- `account resources <selector|0xaddress>`: 一次查询 `coins + owned_objects`，适合 transaction build 前的资源发现；`--package` 同样支持 package alias。

## 通用参数

- `--rpc <url>`: RPC 节点（默认 `https://fullnode.mainnet.sui.io:443`）
- `SUI_RPC_URL`: 指定 RPC URL；优先于 `SUI_CONFIG`，低于 `--rpc`。
- `SUI_CONFIG`: 指向配置文件；优先级为 `--rpc` > `SUI_RPC_URL` > `SUI_CONFIG`（默认文件 `~/.sui/sui_config/client.yaml`）。
  - 非 `SUI_CONFIG` 指定时会自动读取 `~/.sui/sui_config/client.yaml`
  - 支持 JSON 字符串：`"https://fullnode.mainnet.sui.io:443"`
  - 支持 JSON 对象：`{ "rpc_url": "...", "json_rpc_url": "..." }`
  - 支持 Sui 官方 `client.yaml` 风格：`active_env` + `envs` 列表
  - 非 JSON/YAML 结构时按纯文本按原样解析为 URL（会 trim 空白）
- `SUI_CONFIG` 示例：
  - `client.yaml` 示例：
    - `cat > ~/.sui/sui_config/client.yaml <<'EOF'`
    - `active_env: mainnet`
    - `envs:`
    - `  - alias: mainnet`
    - `    rpc: https://fullnode.mainnet.sui.io:443`
    - `EOF`
    - `sui-zig-rpc-client rpc sui_getLatestCheckpointSequenceNumber`
  - JSON 对象文件示例：
    - `echo '{ "rpc_url":"https://rpc.example.com" }' > ~/.sui/config.json`
    - `SUI_CONFIG=~/.sui/config.json sui-zig-rpc-client rpc sui_getLatestCheckpointSequenceNumber`
  - JSON 字符串文件示例：
    - `echo '"https://rpc.example.com"' > ~/.sui/config.json`
    - `SUI_CONFIG=~/.sui/config.json sui-zig-rpc-client rpc sui_getLatestCheckpointSequenceNumber`
  - 纯文本文件示例：
    - `echo 'https://rpc.example.com' > ~/.sui/config.txt`
    - `SUI_CONFIG=~/.sui/config.txt sui-zig-rpc-client rpc sui_getLatestCheckpointSequenceNumber`
- `SUI_KEYSTORE` 示例：
  - `cat > ~/.sui/sui_config/sui.keystore <<'EOF'`
  - `["<base58_secret_key_1>", "<base58_secret_key_2>"]`
  - `EOF`
  - `SUI_KEYSTORE=~/.sui/sui_config/sui.keystore`
- `SUI_KEYSTORE` 示例（对象格式）：
  - `cat > ~/.sui/sui_config/sui.keystore <<'EOF'`
  - `[{"privateKey":"<base58_secret_key>"}]`
  - `EOF`
- `--timeout-ms <ms>`: HTTP 超时
- `--confirm-timeout-ms <ms>`: tx 确认超时时间
- `--poll-ms <ms>`: tx 确认轮询间隔
- `SUI_KEYSTORE`: 指向 keystore 文件；未设置时读取 `~/.sui/sui_config/sui.keystore`
- `--from-keystore`: 从 `SUI_KEYSTORE` 读取 signer；在 `tx send/payload` 的本地 programmable builder / tx-bytes 路径里会直接做本地签名
- `--signer <alias|address|key>`: 从 keystore 里选 signer，配合 `--from-keystore` 使用（可重复）
- `--version`: 打印版本
- `--pretty`: 美化返回 JSON
- `--rpc` 优先级示例: `sui-zig-rpc-client --rpc http://cli.example rpc sui_getLatestCheckpointSequenceNumber`
- `SUI_RPC_URL` 优先级示例: `SUI_RPC_URL=http://env.example sui-zig-rpc-client rpc sui_getLatestCheckpointSequenceNumber`
- `SUI_CONFIG` 优先级示例: `SUI_CONFIG=/path/to/conf.json sui-zig-rpc-client rpc sui_getLatestCheckpointSequenceNumber`

`tx send/payload` 的输入参数：
- `--tx-bytes <base64>` 或 `--tx-bytes @bytes.b64`
- `--signature <sig>`（可重复）或 `--signature-file <path>`（读取文件内容）
- `--signer <alias|address|key>`（可重复）
- `--options <json|@json-file>`（可选）

对于 `tx send/payload --from-keystore`，只要命令源能走本地 programmable builder，并且 gas payment 可显式给出或通过 `--auto-gas-payment` 选出，CLI 现在即使没写 `--gas-price` 也会自动读取 reference gas price，再本地构造 tx bytes 和签名。

当 `--auto-gas-payment` 与已解析的业务对象参数同时存在时，CLI 现在会尽量避开已经被命令参数占用的 object id，避免把同一个 `Coin<SUI>` 同时拿去做业务输入和 gas payment。这条排除规则不仅覆盖直接传给 `MoveCall` 的 coin，也覆盖 preferred 模板里自动插出来的 `MergeCoins` / `SplitCoins` 业务 coin。

`tx build move-call` 常用参数：
- `--package <package-id>`
- `--module <module-name>`
- `--function <function-name>`
- `--type-args <json array|@file>`（可选）
- `--args <json array|@file>`（可选）
- `--sender <address|selector>`（可选）
- `--signer <alias|address|key>`（可选）：与 `--sender` 互补；未提供 sender 时用于推断 sender
- `--gas-budget <uint64>`（可选）
- `--gas-price <uint64>`（可选）
- `--emit-tx-block`（可选）：输出 `{"kind":"ProgrammableTransaction",...}`

`tx build programmable` 常用参数：
- `--commands <json-array|@file>`: PTB commands 数组，如 `[{"kind":"TransferObjects",...}, ...]`
- `--sender <address|selector>`（可选）
- `--signer <alias|address|key>`（可选）：与 `--sender` 互补；未提供 sender 时用于推断 sender
- `--gas-budget <uint64>`（可选）
- `--gas-price <uint64>`（可选）

`tx dry-run` 常用参数：
- `--tx-bytes <base64|@file>`（可选）：已构造好的 tx bytes
- `--package <package-id-or-alias>` / `--module` / `--function`
- `--type-args <json array|@file>` / `--args <json array|@file>`
- `--commands <json-array|@file>`
- `--sender <address|selector>` / `--signer <alias|address|key>` / `--from-keystore`
- `--gas-budget <uint64>` / `--gas-price <uint64>`
- `--gas-payment <json|@file>` / `--auto-gas-payment`

例如：

```bash
zig build run -- tx dry-run \
  --package cetus_clmm_mainnet \
  --module pool \
  --function swap \
  --args '[...]' \
  --sender 0x... \
  --gas-budget 100000000 \
  --gas-price 1000 \
  --gas-payment @gas-payment.json \
  --summarize
```

参数 JSON 可以直接内联传入，也可用 `@path/to/file.json` 方式加载；写成 `@-` 时会直接从 stdin 读取，这样可以把 `move function --emit-template ...` 直接管道给 `tx dry-run/send --request @-`。

`move` ABI 发现命令示例：

```bash
zig build run -- move package cetus_clmm_mainnet --summarize
zig build run -- move module cetus_clmm_mainnet pool --summarize
zig build run -- move function cetus_clmm_mainnet pool swap --summarize
zig build run -- move function cetus_clmm_mainnet pool add_liquidity_fix_coin \
  --type-arg 0x2::sui::SUI \
  --type-arg 0x2::sui::SUI \
  --summarize
zig build run -- move function cetus_clmm_mainnet pool swap \
  --emit-template preferred-dry-run-request > dry-run-request.json
```

`events` 查询命令示例：

```bash
zig build run -- events \
  --package cetus_clmm_mainnet \
  --module pool \
  --limit 5 \
  --descending

zig build run -- events \
  --event-type 0x2::coin::Minted \
  --limit 10

zig build run -- events \
  --filter @event-filter.json \
  --json
```

这个命令面向通用协议发现，不是 Cetus 特例。像 Cetus 这类大量依赖 shared object 的协议，`events --package --module` 可以先帮你看到真实模块事件流，再配合 `move function --summarize`、`object get --summarize` 和现有 `object_input` token 继续收敛到具体对象和交易参数。

对于 `move function --summarize`，输出里的 `parameters[*].lowering_kind` 会告诉你当前 CLI 对这个参数的本地 lowering 能力：
- `object`
- `vector`
- `address`
- `signer`
- `boolean`
- `u8/u16/u32/u64/u128/u256`
- `vector_u8`
- `utf8_string`（`0x1::string::String`）
- `ascii_string`（`0x1::ascii::String`）
- `object_id`（`0x2::object::ID`）
- `option`（`0x1::option::Option<T>`，当前要求 `T` 已经是具体 pure 类型）
- `runtime`（例如 `TxContext`，CLI 不要求你显式提供）
- `unsupported`

同一个 summary 里现在还会带两层调用模板：
- `parameters[*].placeholder_json`: 这个参数建议放进 `--args` JSON 的占位片段
- `parameters[*].explicit_arg_json`: 如果你在 `move function --summarize` 时同时给了 `--args` / `--arg`，CLI 会把已经能对应上的显式参数先落到这里
- `parameters[*].auto_selected_arg_json`: 如果 CLI 已经找到确定的 candidate，会把这个参数直接收口成可放进 `--args` 的 JSON 片段
- `parameters[*].omitted_from_explicit_args`: `true` 表示这是 runtime 注入参数，比如 `TxContext`，不需要你手工传
- `parameters[*].shared_object_input_select_token`: 如果参数是 by-reference object，CLI 会额外给一个 direct `object_input(shared)` 候选
- `parameters[*].shared_object_event_query_argv`: 如果参数是非 preset 的 by-reference object，CLI 会额外给一个 `events --package --module` 的 shared object 发现模板；事件来源优先使用当前查询函数的发布包/模块，这样对升级过包地址但保留旧类型地址的协议也更稳
- `parameters[*].shared_object_candidates`: 对已经 concrete 的 shared object 类型，CLI 会尝试从 recent module events 里抽取 object id，再用 `object get --summarize` 过滤出类型匹配的 shared object 候选；当前会连续扫描多页 recent events，而不只看第一页；如果当前函数模块的 recent events 不够有用，CLI 还会继续把 shared 类型自己的 `package/module` 也作为第二事件来源一起聚合，而不是二选一覆盖；如果 owner-context 已经发现到的 owned object 内容里还引用了额外 shared object，这些候选也会一起聚合进来，而不是和 events 发现互斥覆盖；而且已经发现到的 shared candidates 自身内容也会继续作为下一轮 shared discovery seed，帮助多个 shared 参数互相带出候选。对于这些 seed object，`content` 和 `dynamic fields` 现在也会一起参与 shared fallback discovery，而不是只在 `content` 完全没给出 object id 时才退到 dynamic fields
- `parameters[*].imm_or_owned_object_input_select_token`: object 参数通用的 direct `object_input(imm_or_owned)` 候选
- `parameters[*].receiving_object_input_select_token`: 如果参数是 by-value object，CLI 会额外给一个 `object_input(receiving)` 候选
- `parameters[*].object_get_argv`: 对应的 `object get` 查询模板；preset object 会直接用 alias，其他 object 用 object-id 占位符
- `parameters[*].coin_with_min_balance_select_token`: 如果参数是 scalar `Coin<T>`，CLI 现在会额外给一个可直接执行的 `coin_with_min_balance` 选择 token；基础 `placeholder_json` 也会优先落成这个 token，而不是泛化 object-id 占位符
- `parameters[*].vector_item_coin_with_min_balance_select_token`: 如果参数是 `vector<Coin<T>>`，CLI 会给单个元素的 `coin_with_min_balance` 选择 token；基础 `placeholder_json` 会优先落成一项数组模板
- `parameters[*].vector_item_imm_or_owned_object_input_select_token`: 如果参数是 `vector<object>`，CLI 会给单个元素的 direct `object_input(imm_or_owned)` 候选
- `parameters[*].vector_item_owned_object_select_token`: 如果参数是 `vector<concrete object struct>`，CLI 会给单个元素的 `owned_object_struct_type` 候选
- `parameters[*].vector_item_object_get_argv`: `vector<object>` 单个元素的 `object get` 查询模板
- `parameters[*].vector_item_owned_object_query_argv`: `vector<concrete object struct>` 单个元素的查询模板；对 `Coin<T>` 会优先落成 `account coins --coin-type`
- `parameters[*].vector_item_owned_object_candidates`: 如果你同时给了 `--sender`、`--signer` 或 `--from-keystore`，CLI 会尝试直接查出一组单元素对象候选，并回填成精确 `object_input(imm_or_owned, version, digest)` token；对 `Coin<T>` 候选还会带 `balance`
- `parameters[*].owned_object_select_token`: 如果参数类型是 concrete object struct，CLI 会额外给一个 `owned_object_struct_type` 选择 token 候选
- `parameters[*].owned_object_query_argv`: 对应的查询模板；对 `Coin<T>` 会优先落成 `account coins --coin-type`
- `parameters[*].owned_object_candidates`: 如果有 owner 上下文，CLI 会直接查出一组 concrete owned object 候选，并给出可直接放进 `--args` 的精确 `object_input(imm_or_owned, version, digest)` token；对 `Coin<T>` 候选会补 `balance`，而 scalar `Coin<T>` 在多候选时会默认优先最大余额。普通 owned object discovery 现在也会聚合全部 `suix_getOwnedObjects` 分页结果，而不只看第一页；此外，已发现对象内容里反推出的同类型 owned object 也会继续并入候选集，而不是只依赖 owner-page 查询
- `call_template.type_args_json`: 直接可改的 `--type-args` JSON 模板
- `call_template.args_json`: 直接可改的 `--args` JSON 模板
- `call_template.preferred_args_json`: 在保留原始模板的同时，优先把 CLI 已经能自动选出的参数回填进去
- `call_template.preferred_resolution`: 结构化展示每个参数当前是 `explicit`、`auto_selected`、`auto_selected_tiebreak`、`placeholder` 还是 `runtime_omitted`，并给出 `is_executable`、`candidate_count` / `top_selection_score` / `unresolved_parameter_indices`，方便直接看出 CLI 认为的“当前最佳组合”，以及还剩哪些参数位会真正阻塞执行
- `call_template.move_call_command_json`: 直接可放进 `--commands` / `--command` 的 raw `MoveCall` command 模板
- `call_template.commands_json`: 直接可放进 `--commands` 的 commands array 模板
- `call_template.preferred_commands_json`: 如果存在 auto-selected candidate，则给一份优先回填 candidate 的 commands array 模板
- `call_template.tx_dry_run_request_json`: 基于 `--commands` 路径的完整 `tx dry-run` request artifact
- `call_template.preferred_tx_dry_run_request_json`: 如果存在 auto-selected candidate，则给一份优先回填 candidate 的 `tx dry-run` request artifact
- `call_template.tx_dry_run_argv`: 直接可执行的 `tx dry-run` argv 模板
- `call_template.preferred_tx_dry_run_argv`: 如果存在 auto-selected candidate，则给一条更接近可执行的 `tx dry-run` argv 模板
- `call_template.tx_send_from_keystore_request_json`: 基于 `--commands` 路径的完整 `tx send --from-keystore` request artifact
- `call_template.preferred_tx_send_from_keystore_request_json`: 如果存在 auto-selected candidate，则给一份优先回填 candidate 的 `tx send --from-keystore` request artifact
- `call_template.tx_send_from_keystore_argv`: 直接可改的 `tx send --from-keystore` argv 模板
- `call_template.preferred_tx_send_from_keystore_argv`: 如果存在 auto-selected candidate，则给一条更接近可执行的 `tx send --from-keystore` argv 模板

当存在 preferred request artifact 时，CLI 现在也会把同一份结构化结果嵌进 request JSON 的 `preferredResolution` 字段。这样你即使只消费 `--emit-template preferred-dry-run-request` / `preferred-send-request`，也能直接看到当前自动选中的参数组合和剩余 unresolved 参数位。

如果 shared object 候选来自模块事件发现、但当前没有更强的引用分数，CLI 现在也会按 discovery 顺序做一个低置信度 `auto_selected_tiebreak`。这不会伪装成普通 `auto_selected`，但能把一部分“只差多候选打平”的调用继续往可执行方向推进。

对 owned object 也是同样的思路：如果 owner-context 已经找到了多枚同类型 concrete owned object，但当前还没有更强的引用分数，CLI 现在也会按稳定排序给出一个低置信度 `auto_selected_tiebreak`，而不是一律停在 unresolved。

如果你在 `move function --summarize` 时给的显式参数少于总参数个数，CLI 会优先把这些值按“非 object 参数位”做稀疏回填，而不是强行占掉前面的 object 参数位。这样像 `Coin<T>, u64, TxContext` 这类常见签名里，只传 `--arg 13` 就会优先落到 `u64` 金额参数上；同时前一个 `Coin<T>` 的 `coin_with_min_balance_select_token` 会把 `minBalance` 自动抬到 `13`。

如果你已经知道某个参数应该落到哪个位置，不想依赖稀疏回填，可以直接用 `--arg-at <index> <value>`。这里的 `index` 就是 summary 里 `parameters[*]` 的索引；它会覆盖对应参数位的 `explicit_arg_json`，并继续参与 `preferred_*` 模板生成。`TxContext` 这类 runtime 参数仍然不能手工覆盖。

如果你手上只有裸 `object id` 或 alias，不想自己先跑 `object get --summarize` 再抄 `select:{...}`，可以直接用 `--object-arg-at <index> <object-id-or-alias>`。CLI 会按该参数的 Move 签名自动查询对象 owner/version/digest/shared version，并把它落成精确 `object_input` token；对 shared object 会自动选对 `mutable`，对 owned/immutable object 会落成 exact `imm_or_owned` token。

如果目标参数是 `vector<object>`，`--object-arg-at` 也可以直接传 JSON 字符串数组，例如 `--object-arg-at 0 '["0xcoin1","0xcoin2"]'`。CLI 会逐个查对象元数据，再把整组参数落成 `["select:{...}","select:{...}"]` 这种可直接执行的向量参数。

如果同时又有 owner 上下文和真实 `Coin<T>` 候选，CLI 现在还会把这类显式金额继续用于 `preferred_*` 自动选币：
- scalar `Coin<T>` 会优先选“最小满足金额”的 coin，而不是盲目选最大余额
- `vector<Coin<T>>` 会优先收敛成一组能覆盖该金额的 coin 子集

如果签名是 `vector<Coin<T>>, amount` 这类常见形态，preferred command 模板现在还会继续往前走一步：当需要多枚 coin 才能覆盖金额时，CLI 会自动生成 `MergeCoins -> SplitCoins -> MakeMoveVec -> MoveCall`，把精确金额的 split 结果包装成单元素 coin vector 再传给目标函数。

这套规则也已经能处理多币、多金额的声明顺序配对。例如 `vector<Coin<A>>, vector<Coin<B>>, u64, u64` 这类签名里，CLI 会按参数声明顺序把两个 trailing amount 依次配对到前面的两个 coin 参数，并分别生成自己的 `MergeCoins` / `SplitCoins` / `MakeMoveVec` 片段，再把两边结果一起接到同一个 `MoveCall` 里。

对同币种的多标量 coin 参数，这套 preferred 规划现在也会避免重复复用同一枚 owned coin。也就是说，像 `Coin<SUI>, Coin<SUI>, u64, u64` 这类签名在自动选币时，会优先给两个参数分配不同的 source coin；只有真的没有足够的独立候选时，CLI 才会停在未解析，而不会生成表面可执行、实际会因为一枚 coin 被业务参数重复占用而冲突的模板。

这条“不复用业务 coin”的约束现在也会继续延伸到 mixed scalar/vector 场景。像 `Coin<SUI>, vector<Coin<SUI>>` 这类签名里，后面的 coin vector 自动选择会先剔除前一个标量参数已经占用的 coin，再生成 `preferred_args_json` 和后续 request artifact。
同样地，后面如果有显式给出的 coin 参数，前面的 auto-selected coin 参数现在也会先把这些显式 object id 预留掉，不再生成“前面自动选中了后面已经显式指定的 coin”这种坏模板。
这条约束也已经接进了 preferred `MergeCoins / SplitCoins` 规划，不只是 summary 里的 `auto_selected_arg_json`。也就是说，后面的显式 coin 参数现在同样会从前面的自动 split source 候选里被排除。
在直接执行层，selected-argument token 解析现在也会复用同一批 `suix_getCoins` 结果。也就是说，同一个 `(owner, coin type)` 在一次 `MoveCall` / `MergeCoins` / `SplitCoins` / `MakeMoveVec` 选参过程中，不会因为多个 coin selector 再反复打同一页 coin 查询。
同样地，selected-argument 里的 owned object 选择现在也会复用同一个 `(owner, owned-object request)` 的分页结果，不会因为多个相同 object selector 在一次执行里反复打 `suix_getOwnedObjects`。
如果同一个 `object_input` / `object_preset` 在一次 selected-argument 选参里被重复引用，CLI 现在也会复用同一个 `sui_getObject(showOwner)` 结果，而不是重复读取同一对象元数据。

普通 owned object 现在也有同类的跨参数去重。像 `Position, Position` 或 `Position, vector<Position>` 这类签名里，后面的 auto-selected 参数会优先避开前面已经占用的同一 owned object，尽量不再生成“同一个 object input 被多个业务参数重复使用”的坏模板。

这层去重现在也会先尊重整条调用里所有显式给出的 object 参数。也就是说，如果你用 `--object-arg-at` 把后面的某个 `Position` 明确锁成 `0xabc...`，前面的 auto-selection 会先把这枚对象预留出去，不会先一步把它抢走。

这层模板现在同时覆盖两条路径：
- typed `--package/--module/--function` argv
- 更通用的 `--commands` request artifact

现在 `tx dry-run` 和 `tx send` 也支持直接吃这类 artifact：

```bash
zig build run -- tx dry-run --request @dry-run-request.json
zig build run -- tx send --request @send-request.json
```

如果 request artifact 带了 `autoGasBudget: true`，CLI 会先用模板里的预算做一次 dry-run 估算，再把估算出的 budget 回填到最终本地构造/执行路径。这条能力现在已经接到 `move function --dry-run` / `--send` 默认产出的 request artifact 上。

本地 programmable builder 现在还会在单次 lowering 里复用相同 `MoveCall(package,module,function)` 的 normalized ABI，不再为同一笔 transaction 里的重复 `MoveCall` 反复打 `sui_getNormalizedMoveFunction`。

如果你不想先拿整个 summary 再从里面手工拷 `call_template.*` 字段，`move function` 现在也支持直接输出单个模板：

```bash
zig build run -- move function cetus_clmm_mainnet pool swap \
  --emit-template commands

zig build run -- move function cetus_clmm_mainnet pool swap \
  --emit-template preferred-dry-run-request > dry-run-request.json

zig build run -- move function cetus_clmm_mainnet pool swap \
  --emit-template preferred-send-request > send-request.json

zig build run -- move function cetus_clmm_mainnet pool swap \
  --sender 0x... \
  --arg 7 \
  --dry-run

zig build run -- move function cetus_clmm_mainnet pool add_liquidity \
  --object-arg-at 1 0x51e883ba7c0b566a26cbc8a94cd33eb0abd418a77cc1e60ad22fd9b1f29cd2ab \
  --arg-at 2 'select:{"kind":"object_input","objectId":"0x...","inputKind":"imm_or_owned","version":1,"digest":"0x..."}' \
  --arg 1000 \
  --emit-template preferred-dry-run-request
```

支持的 `--emit-template` 值有：
- `commands`
- `preferred-commands`
- `dry-run-request`
- `preferred-dry-run-request`
- `send-request`
- `preferred-send-request`

其中 `preferred-*` 会在存在 auto-selected candidate 时优先输出 preferred 版本；如果当前还没有唯一候选，就会自动回退到基础模板，不会输出空值。

如果你在 `move function --summarize` 时已经给了 `--sender` 或 `--signer`，这些值现在会直接回填到 `call_template.tx_dry_run_*` 和 `call_template.tx_send_from_keystore_*`。当只有 `--sender` 时，`tx send --from-keystore` 模板会回退用这个 sender 地址作为 address-compatible signer selector。

同一份 owner 上下文现在也会继续作用到纯 `address` / `signer` 参数位。也就是说，如果目标函数签名本身显式要求传 `address` 或 `signer`，`move function --summarize` / `--dry-run` / `--send` 会优先把已解析的 sender 地址直接落成 `auto_selected_arg_json`，而不是继续保留 `0x<argN-address>` / `0x<argN-signer>` 这类 placeholder。

真正执行时，你仍然需要自己补 gas 和具体 object id / select token；如果 summary 阶段没有给 sender / signer，上述模板里仍然会保留占位符。

如果你不想再手工中转 `request artifact`，`move function` 现在还支持直接执行：

```bash
zig build run -- move function cetus_clmm_mainnet pool swap \
  --sender 0x... \
  --arg 7 \
  --dry-run

zig build run -- move function cetus_clmm_mainnet pool swap \
  --from-keystore \
  --signer main \
  --arg 7 \
  --send
```

这条直接执行路径只会在 template 已经足够具体时继续往下走；如果 `preferred-*` 里还残留 `<arg...>`、`0x<sender>`、`<alias-or-address>` 这类占位符，CLI 会先报错，要求你继续补 sender / signer / object candidate，而不是把一个注定失败的模板直接送进 tx builder。

如果你给了 `move function --type-arg/--type-args`，summary 还会带：
- `applied_type_args_json`

它表示这是一个“本地按具体类型实参特化后的 summary”，不是链上多了一条新的 RPC。输出会是 canonicalized type-tag JSON。这样做的好处是像 `Pool<T0, T1>`、`Coin<T>`、`vector<Coin<T>>` 这类泛型参数，在查看 summary、lowering hint、模板和 discovery hint 时都会更接近真实调用形态。

如果参数类型能映射到现有 object preset，`placeholder_json` 现在会直接优先生成 preset token，而不是泛泛的 object id 占位符。例如：
- `&0x2::clock::Clock` -> `select:{"kind":"object_preset","name":"clock"}`
- Cetus mainnet `&config::GlobalConfig` -> `select:{"kind":"object_preset","name":"cetus_clmm_global_config_mainnet"}`

这些 preset 现在已经按职责拆开：链级 built-in object 走 built-in preset 层，协议级固定对象走独立的 protocol object registry。也就是说，preset 只是“已知固定对象的快捷层”，不是任意合约 object 解析的主路径；通用对象交互仍然默认走 `object get` / `object_input` / owner/shared candidate discovery。

对于没法直接映射成 preset、但类型已经是 concrete struct 的 object 参数，CLI 现在还会额外给 discovery 候选。例如 `Position` 一类 owned object 会带出：
- `parameters[*].shared_object_input_select_token`
- `parameters[*].imm_or_owned_object_input_select_token`
- `parameters[*].object_get_argv`
- `parameters[*].owned_object_select_token`
- `parameters[*].owned_object_query_argv`

这些字段都是“候选调用/发现路径”，不是 ownership 或 sharedness 断言。像 Cetus `Pool<T0,T1>` 这类非 preset shared object，CLI 现在除了 `object get` 和 `object_input(shared)` 骨架，还会给出 `events --package --module` discovery argv；如果 recent event 里能抽出匹配 object id，还会直接带 `shared_object_candidates`。如果事件里没有 usable candidate，但另一个已选/已发现的 owned object 内容里引用了 shared object id，CLI 现在还会把这些引用 id 当成第二层 discovery source，再过滤成匹配类型的 shared candidate。除此之外，已经显式给出的 object 参数和已自动选中的 object 参数，也会继续参与 shared candidate 打分，所以像 `Position -> Pool` 这种关系在多候选时会更容易自动收口。 而 `Position` 这类 concrete owned object 还会额外带 `account objects --struct-type` 查询模板。
如果 recent module events 的 `parsedJson` 本身直接暴露了 object id，CLI 会先把这些 id 纳入 shared/owned discovery；同时也会继续用这些事件的 `txDigest` 去读 `sui_getTransactionBlock(showObjectChanges)`，把 `objectChanges` 里补出来的 id 一起聚合进同一批 discovery source，而不是把 `parsedJson` 和 `objectChanges` 当成互斥来源。
在这条 event discovery 路径里，没直接暴露 object id 的事件 `txDigest` 现在会优先触发 `showObjectChanges` 跟进；已经在 `parsedJson` 里给过 object id 的事件，会放到后面作为 supplemental source，减少高层 live 路径里的无效 `sui_getTransactionBlock`。
在单次 `move function` 模板构建里，重复命中的 shared module-event discovery 结果现在也会缓存复用，不再因为多个相同 shared 参数或 fixed-point 轮次而反复扫描同一个模块。

对于 `vector<Coin<T>>` 这类对象向量，summary 现在也会补“单个元素”的 discovery/input skeleton。这对 Cetus 一类要求 coin vector 的接口更实用，因为你可以先拿 `vector_item_owned_object_query_argv` 找一批候选 coin，再把返回的 object id 或 select token 填回 `--args` 数组。

如果你在 `move function --summarize` 时同时给了 `--sender`、`--signer` 或 `--from-keystore`，CLI 现在还会进一步把 owner 上下文带进 discovery 流程。对 concrete owned object 和 `vector<concrete owned object>` 参数，summary 会直接尝试 `suix_getOwnedObjects`，把找到的候选对象填进 `owned_object_candidates` / `vector_item_owned_object_candidates`。这里的 concrete owned object 也包括已经特化完成的 generic struct，例如 `0x2::balance::Balance<0x2::sui::SUI>` 或 receipt 一类类型；只要签名里不再残留 `T0/T1` 这类未解析 type parameter，就会进入同一套 owned discovery。如果 owner-page 查询本身没找到结果，CLI 现在会继续把当前交易里已选/已发现 seed object 的 `content` 和 `dynamic fields` 里暴露出来的 object id 一起聚合进 owned fallback source，再按 owner 和 struct type 过滤成匹配候选，而不是把这两类来源当成互斥备选。除此之外，只要当前查询函数本身有明确的 `package/module`，CLI 还会把 recent module events 里的 object id 作为下一层 owned fallback；如果 owned type 自己的 `package/module` 也不同，当前函数模块和类型模块两边的事件候选会一起聚合、统一排序，而不是只在前者为空时才回退到后者。为了避免 fixed-point 联动时反复扫同一模块，这些 owned event fallback 结果现在会在单次 `move function` 模板生成里缓存复用；同一个 `(owner, struct type)` 的初始 owner-page 查询结果也会在同一轮模板生成里复用，不会因为多个相同 owned 参数重复请求 `suix_getOwnedObjects`。 这一步不会替你自动做最终选择，但已经把“提示层”推进成了“候选集层”。
owned module-event fallback 候选在内部合并热路径里现在也会直接借用缓存，不再先临时 clone 一份候选数组再马上释放。
同一轮模板生成里，重复命中的 seed object `showContent` 读取现在也会缓存复用，所以 shared/owned fallback、候选打分和 fixed-point 联动不会再反复读取同一个对象内容。
而且同一个 seed object 从 `showContent` 内容里抽出来的 object id 列表本身也会缓存复用，不再在 shared/owned fallback 和候选评分里重复解析同一份内容 JSON。
同样地，seed object 的 `dynamic fields` 扫描现在也会在单次模板构建里缓存复用，不再因为 shared/owned fallback 交替推进而重复扫同一个对象。
而且 dynamic-field 发现结果在 shared/owned fallback 热路径里现在也会直接借用缓存，不再每次都 clone/free 一份临时 object id 列表。
除此之外，shared/owned fallback 现在还会在单轮参数扫描里复用已经收集好的 seed object id 集合；只有当某个参数在当前轮里真的新增了候选或自动选择，才会失效并重建 seed 集合，避免每个参数都从整组参数重新收集一遍 seeds。
固定点联动里反复读取 `explicit_arg_json` / `auto_selected_arg_json` 提取 selected object ids 的路径，现在也会复用同一轮模板构建内的解析缓存，不再对相同参数 JSON 一遍遍做 `std.json.parseFromSlice`。
而且这些 selected object id buckets 现在还会按“显式/自动选择状态指纹”做借用缓存；只要当前轮里相关参数没变，后续 shared/owned/joint scoring 都会复用同一份 buckets，而不是每个评分函数再重新扫一遍参数。
候选过滤阶段复用的 `object get --summarize` 读取现在也会在单次模板构建里缓存复用，所以相同 object id 不会因为多个参数或多轮联动重复做 summary 过滤。
而且 shared/owned candidate filtering 现在也会直接借用这层 cached object summary，不再在内部热路径里反复 clone/free 同一份摘要结构。
连通簇联合评分这层也不再反复扫原始 `showContent` JSON，而是直接复用前面已经缓存好的 content-derived object id 列表来判断候选之间的引用关系和锚定关系。
而且这些 content-derived object id 在内部评分/发现 hot path 里现在会直接借用缓存结果，不再每次都 clone/free 一份临时列表。
同一个 `package/module` 的 recent module-event object-id 发现结果，现在也会在 shared/owned 两条 discovery 路径之间复用，不再分别重扫一遍同一模块事件和对应交易的 `objectChanges`。
而且 seed-object discovery 现在会优先保留显式/已选 object，再对每个参数只继续追少量排序靠前的 candidate，并做全局封顶，避免 owner-context 高层路径因为大批低价值候选而把后续 `showContent` / `dynamic fields` 扫描放大。
对已经有稳定显式/自动选择的参数，CLI 现在也不会再把它整组 candidate 当成 seed 继续扩散；只有 unresolved 或低置信度 `auto_selected_tiebreak` 参数，才会继续把候选对象拿去驱动下一层 discovery。
而且同一组 seed object ids 聚合出来的 discovered object id 列表，现在也会在 shared/owned fallback 之间缓存复用，不再各自重新遍历一遍同样的 seeds 和内容发现结果。

当某个 shared / owned candidate 已经进入跨参数联动评分时，summary 里的 candidate 现在还会带 `selection_score`，并按“分数降序、discovery 顺序升序、object id 升序”排序。对 shared candidate，这个分数会同时综合“已选 object 的直接引用”和“owned candidate 的引用提示”，前者权重更高；而且显式给出的 object 参数，会再比 auto-selected object 参数有更高权重。对 `vector<concrete object struct>`，`vector_item_owned_object_candidates` 也会按同样的引用分数排序，`auto_selected_arg_json` 会跟着输出这组排序后的对象向量。当前这套联动已经会多轮迭代到稳定，而且对仍然打平的参数，还会额外把 candidate graph 的连通簇大小、“是否被当前交易里已显式/已选对象锚定”、以及簇内部跨参数引用是否更自洽一起作为 bonus 打进去；如果这些维度仍然完全打平，就继续按整组候选簇的确定性 key 收口；而如果只剩低置信度平分，CLI 也会优先保留 recent events、owner pages、seed-object discovery 的原始发现顺序，而不是退回单个 object id 的局部字典序。所以像 `Pool2 + Position2 + Receipt2*` 这种更完整、更自洽、而且已经被当前交易上下文指向的对象组合，也能自动压过只有 `Pool1 + Position1` 的更弱候选簇；而在多组组合都同样合理时，最终自动选择也会稳定落在同一组上。这样即使当前还不能安全自动选中全部参数，你也能直接从输出里看出 CLI 认为哪组对象更接近最终可执行组合。

当 ABI 显示参数是非 `vector<u8>` 的 `vector<T>` 时，CLI 现在会在本地 programmable builder 路径里自动插入 `MakeMoveVec`。这对 Cetus 一类需要 `vector<Coin<_>>` 的调用很重要，因为你可以直接传：

```bash
--args '[
  ["0xcoin_a","0xcoin_b"]
]'
```

而不必先手工写一条额外的 `MakeMoveVec` PTB 命令。只有空向量且元素类型仍然无法从 ABI 推导成具体 `TypeTag` 时，才会继续拒绝本地 lowering。

对于常见 pure wrapper struct，CLI 现在也会直接按 ABI 做本地 BCS lowering，而不再把它们误判成 object。比如：

```bash
--args '[
  "hello",
  "0x1111111111111111111111111111111111111111111111111111111111111111",
  7,
  "ASCII"
]'
```

可以直接覆盖：
- `0x1::string::String`
- `0x2::object::ID`
- `0x1::option::Option<u64>`（`null`/`option:none` 表示 none，普通值或 `some(...)` 表示 some）
- `0x1::ascii::String`
- 通过 `sui_getNormalizedMoveModule` 字段定义解析出来的 concrete pure struct。
  例如 `0x2::balance::Balance<0x2::sui::SUI>` 这类单字段 wrapper 现在可以直接传 `7`，
  多字段 struct 则可以传按字段名的 JSON object 或按声明顺序的 JSON array。

如果函数本身是泛型的，只要你传入的是 concrete `typeArguments`，CLI 现在也会先用这些类型实参替换 ABI 里的 `TypeParameter`，再做本地 lowering。典型场景包括：
- `vector<T>` 在 `T = u64` 时自动 lower 成 `MakeMoveVec`
- `0x1::option::Option<T>` 在 `T = u64` 这类 concrete pure 类型时直接按 BCS 编码
- `vector<Coin<T>>` 在 `T = 0x2::sui::SUI` 这类 concrete struct type arg 时按对象向量处理，而不再因为泛型参数卡住
- `0x1::option::Option<Config<T>>`、`vector<Balance<T>>` 这类 nested generic/container 组合，
  现在也会继续按 `sui_getNormalizedMoveModule` 的字段定义递归 lower，而不是退回 unsafe fallback

对于 generic pure struct，如果你用 JSON object 传参，当前也允许省略 `Option<T>` 字段；缺失字段会按 `none` 编码，而不是要求必须显式写 `null`。例如：

```bash
--args '[
  {"owner":"0x1111111111111111111111111111111111111111111111111111111111111111","spending":7,"weights":[1,2]}
]'
```

这里缺失的 `limit: Option<u64>` 会直接当成 `none`。

手写 raw PTB 的 `MakeMoveVec` 现在也支持 concrete Move type 字符串，并会在本地 builder 路径里自动 canonicalize 成可编码的 type tag。比如：

```bash
--commands '[{"kind":"MakeMoveVec","type":"0x1::string::String","elements":["hello","world"]}]'
```

这样即使不是 move-call 参数自动 lowering，任意协议需要的独立向量构造也能直接走本地 tx bytes / dry-run 路径。

`--package <package-id-or-alias>` 现在已经支持内置 alias：
- `sui` / `sui_framework` / `framework` -> `0x2`
- `sui_system` / `system` -> `0x3`
- `cetus_clmm_mainnet` / `cetus.mainnet.clmm` -> Cetus CLMM mainnet latest `PublishedAt`
- `cetus_clmm_testnet` / `cetus.testnet.clmm` -> Cetus CLMM testnet latest `PublishedAt`

对象读取命令也支持内置 object alias：
- `object get <object-id-or-alias>`
- `object dynamic-fields <object-id-or-alias>`
- `object dynamic-field-object <object-id-or-alias> ...`

例如：

```bash
zig build run -- object get clock --show-type --summarize
zig build run -- object dynamic-fields preset:cetus.mainnet.clmm.global_config --summarize
```

也支持 `preset:` / `pkg:` 前缀，例如：

```bash
zig build run -- tx build move-call \
  --package cetus_clmm_mainnet \
  --module pool \
  --function swap \
  --type-args '["0x2::sui::SUI","<coin-b>"]' \
  --args '[...]'

zig build run -- tx simulate \
  --package preset:cetus.mainnet.clmm \
  --module pool \
  --function flash_swap \
  --args '[...]'
```

Move 参数里也支持 `select:` 资源解析 token。除了按 owner/structType 自动选对象之外，现在还能把显式 `objectId` 直接提升成 PTB object input：

```bash
# built-in well-known object preset
select:{"kind":"object_preset","name":"clock"}

# Cetus CLMM fixed shared object preset
select:{"kind":"object_preset","name":"cetus_clmm_global_config_mainnet"}

# shared object
select:{"kind":"object_input","objectId":"0xabc123","inputKind":"shared","mutable":true}

# imm/owned object
select:{"kind":"object_input","objectId":"0xdef456","inputKind":"imm_or_owned"}

# receiving object
select:{"kind":"object_input","objectId":"0xfeed01","inputKind":"receiving"}

# shared object without extra lookup
select:{"kind":"object_input","objectId":"0x6","inputKind":"shared","initialSharedVersion":1}

# imm/owned object without extra lookup
select:{"kind":"object_input","objectId":"0xdef456","inputKind":"imm_or_owned","version":7,"digest":"<object-digest>"}
```

目前内置的 preset 已覆盖：
- `clock`
- `cetus_clmm_global_config_mainnet`
- `cetus_clmm_global_config_testnet`

这些 preset 现在既能用于 `select:{"kind":"object_preset",...}` 事务参数，也能直接用于对象读取/发现命令。`clock` 等价于 shared `0x6` + `initialSharedVersion:1`；Cetus 的 `GlobalConfig` preset 则会按 object id 走 `sui_getObject` 自动补全 shared object 元数据。如果你已经知道对象元数据，CLI 也可以直接本地构造 PTB object input；缺字段时才回退 RPC。这对 Cetus 这类大量使用 fixed shared config/pool object 的协议更实用，因为 CLI 不再要求你先手工查 `initialSharedVersion` 再自己拼 PTB JSON。

`object get --summarize` 现在也会直接把对象摘要提升成 transaction input 提示：
- address/object/immutable owner 对象会带 `imm_or_owned_object_input_select_token` 和 `receiving_object_input_select_token`
- shared 对象会带 `shared_object_input_select_token` 和 `mutable_shared_object_input_select_token`

当你走 `object get --summarize` 的默认路径时，CLI 还会自动补 `showOwner` 和 `showType`，这样 shared object 的 `initialSharedVersion` 和 concrete type 能稳定进入 summary。只有你显式传 raw `--options-json` 时，CLI 才不会强行改写这些字段。

这意味着像 Cetus `Pool` 这类非 preset shared object，即使还没有“全局 shared object 搜索”，你也已经可以走一条稳定的闭环：
1. 用 `move function --summarize` 拿到 `object_get_argv`
2. 用 `object get <pool-id> --summarize` 读取对象
3. 直接复制输出里的精确 shared `select token` 回填到 `tx dry-run` / `tx send`

## 目录

- `src/main.zig`: CLI 入口与错误码映射
- `src/cli.zig`: 参数解析与 usage 输出
- `src/commands.zig`: 命令执行与响应输出
- `src/root.zig`: 可复用公共导出面
- `src/client/rpc_client/client.zig`: SUI RPC 客户端
- `src/client/rpc_client/transport.zig`: HTTP transport 与重试/超时处理
