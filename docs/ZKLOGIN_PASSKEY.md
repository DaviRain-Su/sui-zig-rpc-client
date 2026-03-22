# Sui zkLogin 和 Passkey 支持

## 概述

Sui 原生支持两种先进的身份验证方式：

1. **zkLogin** - 使用 Google/Twitch 等 OAuth 登录，通过零知识证明保护隐私
2. **Passkey** - 使用生物识别（指纹/面部识别）或硬件安全密钥

## zkLogin 详解

### 工作原理

```
用户 -> OAuth Provider (Google/Twitch) -> JWT Token
                                        |
                                        v
                              zkProof Generation (Groth16)
                                        |
                                        v
                              Sui Transaction ( ephemeral key + zkProof )
```

### 关键组件

1. **OAuth Provider**: Google, Twitch (测试网支持 Facebook, Apple)
2. **JWT Token**: 包含用户标识 (sub) 和随机数 (nonce)
3. **zkProof**: 使用 Groth16 证明 JWT 有效性而不暴露内容
4. **Ephemeral Key**: 临时密钥对，用于签署交易
5. **Salt**: 用户提供的熵，用于派生唯一地址

### 地址派生

```
address = hash(issuer, sub, salt)
```

- `issuer`: OAuth 提供商 (e.g., "https://accounts.google.com")
- `sub`: 用户唯一标识
- `salt`: 用户提供的 16 字节随机值

### 交易结构

```rust
struct ZkLoginTx {
    tx_data: TransactionData,
    ephemeral_signature: Signature,  // 临时密钥签名
    zk_proof: ZkProof,               // 零知识证明
    jwt_header: JwtHeader,           // JWT 头部
    salt: [u8; 16],                  // 盐值
}
```

## Passkey 详解

### 工作原理

```
用户 -> 生物识别/安全密钥 -> WebAuthn API
                                    |
                                    v
                          创建/使用 Credential
                                    |
                                    v
                          签署 Sui 交易
```

### 关键组件

1. **Authenticator**: 设备内置（Touch ID, Face ID）或硬件密钥（YubiKey）
2. **Credential**: 包含公钥和元数据
3. **Client Data**: 包含交易哈希和挑战
4. **Authenticator Data**: 包含设备信息和计数器

### 交易结构

```rust
struct PasskeyTx {
    tx_data: TransactionData,
    authenticator_data: [u8],        // 验证器数据
    client_data_json: String,        // 客户端数据
    signature: [u8; 64],             // ECDSA/P256 签名
}
```

## CLI 实现计划

### zkLogin 命令

```bash
# 初始化 zkLogin 会话
sui-zig zklogin init --provider google --salt <random_salt>

# 生成 OAuth URL
sui-zig zklogin auth-url

# 完成登录（输入 JWT）
sui-zig zklogin complete --jwt <token>

# 查看 zkLogin 地址
sui-zig zklogin address

# 使用 zkLogin 发送交易
sui-zig zklogin send --to <address> --amount <amount>

# 生成 zkProof（需要 prover 服务）
sui-zig zklogin prove --tx <tx_bytes>
```

### Passkey 命令

```bash
# 创建 Passkey
sui-zig passkey create --name "My Passkey"

# 列出 Passkeys
sui-zig passkey list

# 使用 Passkey 签名
sui-zig passkey sign --credential-id <id> --tx <tx_bytes>

# 使用 Passkey 发送交易
sui-zig passkey send --to <address> --amount <amount>

# 导出 Passkey 公钥
sui-zig passkey export --credential-id <id>
```

## 技术挑战

### zkLogin

1. **Prover 服务**: 需要运行 Groth16 证明生成
   - 选项 A: 本地 WASM 证明（慢但私密）
   - 选项 B: 远程证明服务（快但需信任）
   
2. **JWT 验证**: 需要验证 JWT 签名和声明

3. **地址派生**: 需要正确的哈希算法

### Passkey

1. **WebAuthn 协议**: 需要实现 CTAP2/WebAuthn 客户端
   - Zig 没有现成库
   - 可能需要调用系统 API 或外部工具

2. **平台支持**: 
   - macOS: Touch ID / Secure Enclave
   - iOS: Face ID / Touch ID
   - Android: BiometricPrompt
   - Linux: libfido2

3. **交易编码**: 需要将 Sui 交易转换为 WebAuthn 挑战格式

## 当前实现状态

### 已完成 ✅

- [x] 传统 Ed25519 签名
- [x] Keystore 管理
- [x] 交易构建和执行

### 计划中 📋

- [ ] zkLogin 基础结构
- [ ] JWT 解析和验证
- [ ] 地址派生
- [ ] Passkey 基础结构
- [ ] WebAuthn 客户端集成
- [ ] 跨平台支持

### 依赖项

- zkLogin: 需要 Groth16 证明库（arkworks 或类似）
- Passkey: 需要 WebAuthn/CTAP2 库

## 参考资源

- Sui zkLogin 文档: https://docs.sui.io/concepts/cryptography/zklogin
- WebAuthn 规范: https://www.w3.org/TR/webauthn-2/
- Sui 源代码: https://github.com/MystenLabs/sui/tree/main/crates/sui/src/zklogin
