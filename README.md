# sui-zig-rpc-client

Zig + `std` 实现的 Sui CLI/RPC 客户端骨架，复用你在 Solana 项目中的分层结构（CLI 解析、命令分发、可复用 RPC transport）。

## 目标

以最小可运行状态接入：
- Sui RPC 请求发送（`rpc` 命令）
- 基础交易生命周期命令（`tx simulate` / `tx send` / `tx status` / `tx confirm|wait`）
- 统一错误处理与通用返回转发

后续可在此基础上继续补齐任意程序调用所需的指令构造与签名流程。

## 运行

```bash
zig build run -- help
zig build run -- version
zig build run -- rpc sui_getLatestSuiSystemState
zig build run -- rpc sui_getLatestCheckpointSequenceNumber --timeout-ms 8000
zig build run -- tx payload --tx-bytes AA... --signature BASE64SIG --signature BASE64SIG2 --pretty
zig build run -- tx send --tx-bytes AA... --sig @sig.txt --pretty
zig build run -- tx confirm 0x... --poll-ms 1000 --confirm-timeout-ms 120000
```

## 命令

- `help`: 打印用法
- `version`: 打印版本
- `rpc <method> [params-json]`: 发送任意 Sui JSON-RPC 方法。
- `tx simulate [params-json]`: 调用 `sui_devInspectTransactionBlock`。
- `tx send [params-json]`: 调用 `sui_executeTransactionBlock`。
- `tx payload`: 通过 CLI 参数构造 `sui_executeTransactionBlock` 的 params
- `tx send --tx-bytes ... --signature ...`: 使用签名+tx bytes 直接调用 `sui_executeTransactionBlock`
- `tx send --from-keystore`: 当未提供 `--signature` 时，自动追加 `SUI_KEYSTORE` 中首条 key 作为签名参数
- `tx send/payload --signer`: 按 keystore 记录中的 `alias/address/key` 选择 signer 并追加签名（配合 `--from-keystore`）
- `tx status <digest>`: 查询 `sui_getTransactionBlock`（一次）。
- `tx confirm|wait <digest>`: 轮询 `sui_getTransactionBlock`，直到结果出现或超时。
- `tx build move-call`: 输出 MoveCall 指令 JSON；加 `--emit-tx-block` 可输出可直接提交的 `ProgrammableTransaction` JSON。
- `tx build programmable`: 提供 `--commands` JSON 数组直接构建任意 PTB `ProgrammableTransaction`。
- `tx build --signer`: 可复用 keystore 选择器（alias/address/key）；未提供 `--sender` 时优先使用首个可解析出地址的 signer。
- `account list`: 列出 keystore 条目。
- `account info <selector>`: 按索引或别名/地址/密钥字段查询并展示单条 keystore 记录；`--json` 输出 JSON。

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
- `--from-keystore`: 从 `SUI_KEYSTORE` 读取首条 key 并作为签名字符串透传（当前未实现真实签名计算）
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

参数 JSON 可以直接内联传入，也可用 `@path/to/file.json` 方式加载。

## 目录

- `src/main.zig`: CLI 入口与错误码映射
- `src/cli.zig`: 参数解析与 usage 输出
- `src/commands.zig`: 命令执行与响应输出
- `src/root.zig`: 可复用公共导出面
- `src/client/rpc_client/client.zig`: SUI RPC 客户端
- `src/client/rpc_client/transport.zig`: HTTP transport 与重试/超时处理
