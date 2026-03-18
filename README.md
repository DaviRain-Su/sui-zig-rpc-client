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
- 建议执行：

```bash
zig build test --summary all
```

当前默认测试图覆盖：
- `C3 PTBs Introduction`
- `D4 Transaction submission, Balance Changes, and Gas Profiling`
- `H1 Upgrade preconditions and Versioned Shared Objects`
- `K2 ZKLogin / session-backed account flow`

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
zig build run -- tx simulate --package 0x2 --module counter --function increment --sender 0xwallet --session-response @session-response.json
zig build run -- tx payload --package 0x2 --module counter --function increment --sender 0xwallet --session-response @session-response.json
zig build run -- tx send --package 0x2 --module counter --function increment --sender 0xwallet --session-response @session-response.json --wait --summarize
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

session-backed wallet / remote signer / passkey 账户现在已经可以直接走同一条 CLI 主路径：

1. 第一次运行命令，不带 `--session-response`
   - 如果 provider 需要 challenge，会输出结构化 prompt JSON
2. 外部 wallet / agent 完成 challenge 后，生成 response JSON
3. 用同一条命令追加 `--session-response <json|@file>` 继续执行

当前已接通的 CLI 路径：
- `tx build --emit-tx-block`
- `tx simulate`
- `tx payload`
- `tx send`

典型 CLI：

```bash
# 1. 先拿 challenge prompt
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --args '[7]' \
  --sender 0xwallet

# 2. wallet / agent 完成 challenge 后继续 send
zig build run -- tx send \
  --package 0x2 \
  --module counter \
  --function increment \
  --args '[7]' \
  --sender 0xwallet \
  --session-response @session-response.json \
  --wait \
  --summarize

# 3. 同样的 continuation 也支持 simulate
zig build run -- tx simulate \
  --package 0x2 \
  --module counter \
  --function increment \
  --sender 0xwallet \
  --session-response @session-response.json \
  --summarize

# 4. build-only 路径支持 tx block / payload continuation
zig build run -- tx build programmable \
  --command '{"kind":"TransferObjects","objects":["0xcoin"],"address":"0xreceiver"}' \
  --sender 0xwallet \
  --emit-tx-block \
  --session-response @session-response.json \
  --summarize

zig build run -- tx payload \
  --package 0x2 \
  --module counter \
  --function increment \
  --args '[7]' \
  --sender 0xwallet \
  --session-response @session-response.json \
  --summarize
```

`--session-response` 当前要求：
- 只能用于 programmatic transaction path
- `tx build` 只支持 `--emit-tx-block` 路径
- 如果当前命令不需要 challenge，传 response 也不会额外走第二套 pipeline，而是继续复用同一条 shared client surface

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
- `move function <package-id-or-alias> <module> <function>`: 调用 `sui_getNormalizedMoveFunction`，查看参数/返回类型；`--summarize` 会额外输出 CLI lowering hint 和可复用的 transaction 模板。可选 `--type-arg/--type-args` 会在本地先按具体类型实参特化 summary。`--sender` / `--signer` / `--from-keystore` 会把 owner 上下文回填到 owned-object discovery hint 里。
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

参数 JSON 可以直接内联传入，也可用 `@path/to/file.json` 方式加载。

`move` ABI 发现命令示例：

```bash
zig build run -- move package cetus_clmm_mainnet --summarize
zig build run -- move module cetus_clmm_mainnet pool --summarize
zig build run -- move function cetus_clmm_mainnet pool swap --summarize
zig build run -- move function cetus_clmm_mainnet pool add_liquidity_fix_coin \
  --type-arg 0x2::sui::SUI \
  --type-arg 0x2::sui::SUI \
  --summarize
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
- `parameters[*].auto_selected_arg_json`: 如果 CLI 已经找到确定的 candidate，会把这个参数直接收口成可放进 `--args` 的 JSON 片段
- `parameters[*].omitted_from_explicit_args`: `true` 表示这是 runtime 注入参数，比如 `TxContext`，不需要你手工传
- `parameters[*].shared_object_input_select_token`: 如果参数是 by-reference object，CLI 会额外给一个 direct `object_input(shared)` 候选
- `parameters[*].shared_object_event_query_argv`: 如果参数是非 preset 的 by-reference object，CLI 会额外给一个 `events --package --module` 的 shared object 发现模板；事件来源优先使用当前查询函数的发布包/模块，这样对升级过包地址但保留旧类型地址的协议也更稳
- `parameters[*].shared_object_candidates`: 对已经 concrete 的 shared object 类型，CLI 会尝试从 recent module events 里抽取 object id，再用 `object get --summarize` 过滤出类型匹配的 shared object 候选
- `parameters[*].imm_or_owned_object_input_select_token`: object 参数通用的 direct `object_input(imm_or_owned)` 候选
- `parameters[*].receiving_object_input_select_token`: 如果参数是 by-value object，CLI 会额外给一个 `object_input(receiving)` 候选
- `parameters[*].object_get_argv`: 对应的 `object get` 查询模板；preset object 会直接用 alias，其他 object 用 object-id 占位符
- `parameters[*].vector_item_imm_or_owned_object_input_select_token`: 如果参数是 `vector<object>`，CLI 会给单个元素的 direct `object_input(imm_or_owned)` 候选
- `parameters[*].vector_item_owned_object_select_token`: 如果参数是 `vector<concrete object struct>`，CLI 会给单个元素的 `owned_object_struct_type` 候选
- `parameters[*].vector_item_object_get_argv`: `vector<object>` 单个元素的 `object get` 查询模板
- `parameters[*].vector_item_owned_object_query_argv`: `vector<concrete object struct>` 单个元素的 `account objects --struct-type` 查询模板
- `parameters[*].vector_item_owned_object_candidates`: 如果你同时给了 `--sender`、`--signer` 或 `--from-keystore`，CLI 会尝试直接查出一组单元素对象候选，并回填成精确 `object_input(imm_or_owned, version, digest)` token
- `parameters[*].owned_object_select_token`: 如果参数类型是 concrete object struct，CLI 会额外给一个 `owned_object_struct_type` 选择 token 候选
- `parameters[*].owned_object_query_argv`: 对应的 `account objects --struct-type` 查询模板
- `parameters[*].owned_object_candidates`: 如果有 owner 上下文，CLI 会直接查出一组 concrete owned object 候选，并给出可直接放进 `--args` 的精确 `object_input(imm_or_owned, version, digest)` token
- `call_template.type_args_json`: 直接可改的 `--type-args` JSON 模板
- `call_template.args_json`: 直接可改的 `--args` JSON 模板
- `call_template.preferred_args_json`: 在保留原始模板的同时，优先把 CLI 已经能自动选出的参数回填进去
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

这层模板现在同时覆盖两条路径：
- typed `--package/--module/--function` argv
- 更通用的 `--commands` request artifact

现在 `tx dry-run` 和 `tx send` 也支持直接吃这类 artifact：

```bash
zig build run -- tx dry-run --request @dry-run-request.json
zig build run -- tx send --request @send-request.json
```

如果你在 `move function --summarize` 时已经给了 `--sender` 或 `--signer`，这些值现在会直接回填到 `call_template.tx_dry_run_*` 和 `call_template.tx_send_from_keystore_*`。当只有 `--sender` 时，`tx send --from-keystore` 模板会回退用这个 sender 地址作为 address-compatible signer selector。

真正执行时，你仍然需要自己补 gas 和具体 object id / select token；如果 summary 阶段没有给 sender / signer，上述模板里仍然会保留占位符。

如果你给了 `move function --type-arg/--type-args`，summary 还会带：
- `applied_type_args_json`

它表示这是一个“本地按具体类型实参特化后的 summary”，不是链上多了一条新的 RPC。输出会是 canonicalized type-tag JSON。这样做的好处是像 `Pool<T0, T1>`、`Coin<T>`、`vector<Coin<T>>` 这类泛型参数，在查看 summary、lowering hint、模板和 discovery hint 时都会更接近真实调用形态。

如果参数类型能映射到现有 object preset，`placeholder_json` 现在会直接优先生成 preset token，而不是泛泛的 object id 占位符。例如：
- `&0x2::clock::Clock` -> `select:{"kind":"object_preset","name":"clock"}`
- Cetus mainnet `&config::GlobalConfig` -> `select:{"kind":"object_preset","name":"cetus_clmm_global_config_mainnet"}`

对于没法直接映射成 preset、但类型已经是 concrete struct 的 object 参数，CLI 现在还会额外给 discovery 候选。例如 `Position` 一类 owned object 会带出：
- `parameters[*].shared_object_input_select_token`
- `parameters[*].imm_or_owned_object_input_select_token`
- `parameters[*].object_get_argv`
- `parameters[*].owned_object_select_token`
- `parameters[*].owned_object_query_argv`

这些字段都是“候选调用/发现路径”，不是 ownership 或 sharedness 断言。像 Cetus `Pool<T0,T1>` 这类非 preset shared object，CLI 现在除了 `object get` 和 `object_input(shared)` 骨架，还会给出 `events --package --module` discovery argv；如果 recent event 里能抽出匹配 object id，还会直接带 `shared_object_candidates`。而 `Position` 这类 concrete owned object 还会额外带 `account objects --struct-type` 查询模板。

对于 `vector<Coin<T>>` 这类对象向量，summary 现在也会补“单个元素”的 discovery/input skeleton。这对 Cetus 一类要求 coin vector 的接口更实用，因为你可以先拿 `vector_item_owned_object_query_argv` 找一批候选 coin，再把返回的 object id 或 select token 填回 `--args` 数组。

如果你在 `move function --summarize` 时同时给了 `--sender`、`--signer` 或 `--from-keystore`，CLI 现在还会进一步把 owner 上下文带进 discovery 流程。对 concrete owned object 和 `vector<concrete owned object>` 参数，summary 会直接尝试 `suix_getOwnedObjects`，把找到的候选对象填进 `owned_object_candidates` / `vector_item_owned_object_candidates`。这一步不会替你自动做最终选择，但已经把“提示层”推进成了“候选集层”。

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

如果函数本身是泛型的，只要你传入的是 concrete `typeArguments`，CLI 现在也会先用这些类型实参替换 ABI 里的 `TypeParameter`，再做本地 lowering。典型场景包括：
- `vector<T>` 在 `T = u64` 时自动 lower 成 `MakeMoveVec`
- `0x1::option::Option<T>` 在 `T = u64` 这类 concrete pure 类型时直接按 BCS 编码
- `vector<Coin<T>>` 在 `T = 0x2::sui::SUI` 这类 concrete struct type arg 时按对象向量处理，而不再因为泛型参数卡住

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
