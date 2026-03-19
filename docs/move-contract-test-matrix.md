# Move Contract Test Matrix

这份矩阵的目标不是再找一个新的 live 协议，而是补一组本地可控、可重复、
能稳定覆盖 CLI 通用调用面的 Move 测试合约。

`Cetus` 这类真实协议继续保留作为 live smoke target，但它解决的是
“真实主网链路有没有回退”，不是“每一种 Move 特性都被 deterministic 地锁住”。

如果要证明这个 CLI 最终真的能调用任意 Sui 合约，就必须同时有两层：

- live protocol smoke：确认真实主网 ABI / discovery / request artifact 还在工作
- local Move package matrix：确认复杂类型、shared/owned/capability/receipt/vector/generic
  这些行为能被稳定回归

## 设计原则

1. 每个 package 都要覆盖一类明确的 generic invocation 风险，而不是做协议特例。
2. 每个 package 都要能映射回 CLI 的某条通用 surface：
   - `move function --summarize`
   - `--emit-template preferred-*`
   - `--dry-run/--send`
   - `tx build/tx dry-run --commands`
3. 每个 package 都应该尽量小，但必须包含真实约束关系，而不是只做 toy counter。
4. 能在本地 deterministic 复现的，不要留给 live 主网去猜。

## 建议合约矩阵

### 1. `counter_baseline`

用途：保留最小可运行基线，避免复杂测试把最基本的纯值调用搞坏。

建议覆盖：
- `u64/bool/address/signer`
- by-value pure struct
- entry / non-entry function
- 返回值和多参数位顺序

主要验证：
- CLI parser
- pure lowering
- sender/signer 填充
- direct `move function --dry-run`

### 2. `shared_state_lab`

用途：锁定 shared object 输入和版本化 shared object 行为。

当前状态：
- 已落地：[`fixtures/move/shared_state_lab`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/shared_state_lab)
- 已验证：`sui move test --path fixtures/move/shared_state_lab`

建议覆盖：
- `&T` / `&mut T` shared object
- shared object creation / mutation
- versioned shared object
- shared object 与普通 owned object 混合参数

主要验证：
- shared candidate discovery
- `object_input(shared)` 生成
- direct execution request artifact

### 3. `generic_vault`

用途：专门打 generic type substitution 和 generic pure/object lowering。

当前状态：
- 已落地：[`fixtures/move/generic_vault`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/generic_vault)
- 已验证：`sui move test --path fixtures/move/generic_vault`

建议覆盖：
- `Vault<T>`
- `Balance<T>`
- `Coin<T>`
- `Option<T>`
- generic receipt / generic config

主要验证：
- concrete type-arg specialization
- generic owned discovery
- generic pure struct lowering
- `Coin<T>` / `Balance<T>` 混合路径

### 4. `vector_router`

用途：锁定 `vector<T>` 相关的本地 builder 路径。

当前状态：
- 已落地：[`fixtures/move/vector_router`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/vector_router)
- 已验证：`sui move test --path fixtures/move/vector_router`

建议覆盖：
- `vector<object>`
- `vector<Coin<T>>`
- `vector<vector<u8>>`
- `MakeMoveVec`
- 多个 trailing amount 配对多个 coin/vector coin 参数

主要验证：
- vector lowering
- split / merge / make-move-vec planning
- coin 去重
- PTB result chaining

### 5. `receipt_flow_lab`

用途：模拟 flash-loan / repay / claim 一类 receipt-driven 流程。

当前状态：
- 已落地：[`fixtures/move/receipt_flow_lab`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/receipt_flow_lab)
- 已验证：`sui move test --path fixtures/move/receipt_flow_lab`

建议覆盖：
- `borrow -> receipt -> repay`
- capability / receipt object
- 多步命令链
- nested result / assigned alias

主要验证：
- receipt object discovery
- result handle 传递
- `MoveCall -> MoveCall` 联动
- `preferred_commands_json` 的多步模板

### 6. `dynamic_registry`

用途：锁定 dynamic fields / object table / indirect object discovery。

当前状态：
- 已落地：[`fixtures/move/dynamic_registry`](/Users/davirian/dev/zig/sui-zig-rpc-client/fixtures/move/dynamic_registry)
- 已验证：`sui move test --path fixtures/move/dynamic_registry`

建议覆盖：
- object content 不直接暴露目标 id
- 必须通过 dynamic fields 找对象
- content 和 dynamic fields 同时给出不同对象

主要验证：
- seed-object discovery
- dynamic field fallback
- content + dynamic fields 聚合
- related object linking

### 7. `admin_upgrade_lab`

用途：覆盖 capability、admin policy、publish/upgrade 尾部能力。

建议覆盖：
- `AdminCap`
- `UpgradeCap`
- package upgrade precondition
- policy object / governance object

主要验证：
- capability object resolution
- publish / upgrade PTB command path
- builder 与 execution path 对齐

### 8. `pool_like_protocol_lab`

用途：做一个本地“类 Cetus/类 DeFi”协议，不依赖主网数据，但结构复杂度接近真实协议。

建议覆盖：
- shared `Pool<T0, T1>`
- owned `Position`
- `Coin<T0>` / `Coin<T1>` / `vector<Coin<T>>`
- receipt / snapshot / manager object
- shared + owned + coin + gas 同时参与一笔交易

主要验证：
- transaction-level joint selection
- `Pool + Position + Coin + gas` 联动
- preferred request artifact 生成
- unresolved placeholder 继续缩减

## 推荐落地顺序

如果要按收益排序，不建议从最大最复杂的 pool-like package 开始。

推荐顺序：

1. `counter_baseline`
2. `shared_state_lab`
3. `generic_vault`
4. `vector_router`
5. `receipt_flow_lab`
6. `dynamic_registry`
7. `admin_upgrade_lab`
8. `pool_like_protocol_lab`

## 这组矩阵真正要回答的问题

当这 8 类 package 都有稳定回归后，我们才更有资格说：

- 这个 CLI 不只是“能和 Cetus 交互”
- 而是“对任意 Sui 合约调用已经具备足够泛化的覆盖面”

换句话说，`Cetus` 是 smoke test，`Move contract matrix` 才是通用能力证明。
