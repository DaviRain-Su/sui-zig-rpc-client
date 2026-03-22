# PTB Bytes Builder 模块重构计划

## 目标
将 `src/ptb_bytes_builder.zig` (2,059 行, 10 测试) 重构为模块化的结构

## 当前状态
- 文件大小: 2,059 行
- 测试数量: 10 个
- 主要内容:
  - 20+ 类型定义 (ObjectRef, CallArg, Command, etc.)
  - BCS 编码/解码逻辑
  - 交易数据构建
  - JSON 解析和转换

## 重构策略

### 新模块结构
```
src/ptb_bytes_builder/
├── root.zig              # 模块入口，重新导出
├── types.zig             # 核心类型定义
├── bcs_encoder.zig       # BCS 编码逻辑
├── json_parser.zig       # JSON 解析
├── transaction.zig       # 交易数据构建
└── utils.zig             # 辅助函数
```

### 迁移计划

#### Phase 1: 类型定义迁移
1. 将核心类型移动到 `types.zig`
2. 将 BCS 相关类型移动到 `bcs_encoder.zig`

#### Phase 2: 逻辑迁移
1. 将 BCS 编码逻辑移动到 `bcs_encoder.zig`
2. 将 JSON 解析移动到 `json_parser.zig`
3. 将交易构建移动到 `transaction.zig`

#### Phase 3: 集成和测试
1. 更新 `root.zig` 重新导出
2. 确保所有测试通过

## 详细设计

### types.zig
```zig
pub const Address = [32]u8;
pub const ObjectDigest = [32]u8;
pub const ObjectRef = struct { ... };
pub const CallArg = union(enum) { ... };
pub const Command = union(enum) { ... };
```

### bcs_encoder.zig
```zig
pub fn encodeBcsValue(...) ![]u8;
pub fn encodeBcsPureValue(...) ![]u8;
pub fn parseBcsValueSpec(...) ![]u8;
```

### json_parser.zig
```zig
pub fn parseRawBytesJsonValue(...) ![]u8;
pub fn parseSimplifiedTypeTag(...) !TypeTag;
pub fn encodeSimplifiedTypeTagFromString(...) !TypeTag;
```

### transaction.zig
```zig
pub fn buildTransactionDataV1Bytes(...) ![]u8;
pub fn buildTransactionDataV1Base64(...) ![]u8;
pub fn buildTransactionDataV1BytesFromJson(...) ![]u8;
```

## 成功标准
- [ ] 所有现有测试通过 (10 个)
- [ ] 新模块结构清晰
- [ ] 向后兼容保持
- [ ] 代码可维护性提升

## 时间估计
- Phase 1: 1 小时
- Phase 2: 1 小时
- Phase 3: 0.5 小时
- **总计**: 2.5 小时
