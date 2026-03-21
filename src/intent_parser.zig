const std = @import("std");
const builtin = @import("builtin");

/// 解析的交换意图
pub const SwapIntent = struct {
    amount: ?[]const u8, // "100" 或 "all"
    from_token: []const u8, // "SUI"
    to_token: []const u8, // "USDC"
    slippage_bps: u64, // 默认 50 (0.5%)

    pub fn deinit(self: *SwapIntent, allocator: std.mem.Allocator) void {
        if (self.amount) |a| allocator.free(a);
        allocator.free(self.from_token);
        allocator.free(self.to_token);
    }
};

pub const TransferIntent = struct {
    amount: []const u8,
    token: []const u8,
    recipient: []const u8,

    pub fn deinit(self: *TransferIntent, allocator: std.mem.Allocator) void {
        allocator.free(self.amount);
        allocator.free(self.token);
        allocator.free(self.recipient);
    }
};

pub const BalanceIntent = struct {
    token: ?[]const u8,

    pub fn deinit(self: *BalanceIntent, allocator: std.mem.Allocator) void {
        if (self.token) |token| allocator.free(token);
    }
};

/// 意图解析结果
pub const IntentResult = union(enum) {
    swap: SwapIntent,
    transfer: TransferIntent,
    balance: BalanceIntent,
    unsupported: []const u8, // 不支持的操作类型

    pub fn deinit(self: *IntentResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .swap => |*s| s.deinit(allocator),
            .transfer => |*t| t.deinit(allocator),
            .balance => |*b| b.deinit(allocator),
            .unsupported => |u| allocator.free(u),
        }
    }
};

/// 解析错误
pub const IntentParseError = error{
    MissingApiKey,
    NetworkError,
    Timeout,
    InvalidResponse,
    InvalidJson,
    MissingRequiredField,
    AmbiguousIntent,
    OutOfMemory,
};

/// Claude API 请求体
const ClaudeRequest = struct {
    model: []const u8 = "claude-3-5-sonnet-20241022",
    max_tokens: u32 = 256,
    temperature: f32 = 0,
    messages: []const ClaudeMessage,

    const ClaudeMessage = struct {
        role: []const u8,
        content: []const u8,
    };
};

/// 提示模板 - 使用 @embedFile 加载外部文件
const PROMPT_TEMPLATE = @embedFile("prompts/swap_intent.txt");

/// 解析自然语言意图
/// 测试模式下（builtin.is_test）返回 mock 响应
pub fn parseNaturalLanguageIntent(
    allocator: std.mem.Allocator,
    query: []const u8,
    api_key: ?[]const u8,
) IntentParseError!IntentResult {
    // 测试模式或预览模式（无 API key）：使用 mock 响应
    if (builtin.is_test or api_key == null) {
        return try mockParseIntent(allocator, query);
    }

    // 生产模式：调用 Claude API
    return try callClaudeApi(allocator, query, api_key.?);
}

fn detectFirstNumericToken(allocator: std.mem.Allocator, query: []const u8) !?[]const u8 {
    var it = std.mem.splitScalar(u8, query, ' ');
    while (it.next()) |word| {
        if (std.fmt.parseInt(u64, word, 10)) |_| {
            return try allocator.dupe(u8, word);
        } else |_| {}
    }
    return null;
}

fn dupOptionalUpperToken(allocator: std.mem.Allocator, lower_query: []const u8, token: []const u8) !?[]const u8 {
    if (std.mem.indexOf(u8, lower_query, token) == null) return null;
    return try std.ascii.allocUpperString(allocator, token);
}

fn extractHexAddress(allocator: std.mem.Allocator, query: []const u8) !?[]const u8 {
    var it = std.mem.splitScalar(u8, query, ' ');
    while (it.next()) |word| {
        if (word.len >= 3 and std.mem.startsWith(u8, word, "0x")) {
            var valid = true;
            for (word[2..]) |ch| {
                if (!std.ascii.isHex(ch)) {
                    valid = false;
                    break;
                }
            }
            if (valid) return try allocator.dupe(u8, word);
        }
    }
    return null;
}

/// Mock 解析 - 用于测试
fn mockParseIntent(allocator: std.mem.Allocator, query: []const u8) !IntentResult {
    const lower = try std.ascii.allocLowerString(allocator, query);
    defer allocator.free(lower);

    if (std.mem.indexOf(u8, lower, "balance") != null or
        std.mem.indexOf(u8, lower, "how much") != null or
        std.mem.indexOf(u8, lower, "check my") != null)
    {
        return IntentResult{
            .balance = .{
                .token = try dupOptionalUpperToken(allocator, lower, "sui"),
            },
        };
    }

    if ((std.mem.indexOf(u8, lower, "send") != null or std.mem.indexOf(u8, lower, "transfer") != null)) {
        const amount = try detectFirstNumericToken(allocator, query) orelse try allocator.dupe(u8, "1");
        const recipient = try extractHexAddress(allocator, query) orelse try allocator.dupe(u8, "0x2");
        const token = try dupOptionalUpperToken(allocator, lower, "usdc") orelse try allocator.dupe(u8, "SUI");
        return IntentResult{
            .transfer = .{
                .amount = amount,
                .token = token,
                .recipient = recipient,
            },
        };
    }

    if (std.mem.indexOf(u8, lower, "swap") != null and
        std.mem.indexOf(u8, lower, "sui") != null and
        std.mem.indexOf(u8, lower, "usdc") != null)
    {
        var amount: ?[]const u8 = null;
        if (std.mem.indexOf(u8, lower, "all") != null) {
            amount = try allocator.dupe(u8, "all");
        } else {
            amount = try detectFirstNumericToken(allocator, query);
            if (amount == null) amount = try allocator.dupe(u8, "100");
        }

        const sui_idx = std.mem.indexOf(u8, lower, "sui").?;
        const usdc_idx = std.mem.indexOf(u8, lower, "usdc").?;
        const from_sui = sui_idx < usdc_idx;

        return IntentResult{
            .swap = .{
                .amount = amount,
                .from_token = if (from_sui) try allocator.dupe(u8, "SUI") else try allocator.dupe(u8, "USDC"),
                .to_token = if (from_sui) try allocator.dupe(u8, "USDC") else try allocator.dupe(u8, "SUI"),
                .slippage_bps = 50,
            },
        };
    }

    return IntentResult{
        .unsupported = try allocator.dupe(u8, "only swap, transfer, and balance intents are supported in preview mode"),
    };
}

/// 调用 Claude API
fn callClaudeApi(
    allocator: std.mem.Allocator,
    query: []const u8,
    api_key: []const u8,
) IntentParseError!IntentResult {
    _ = api_key;
    // 构建 prompt
    const prompt = try buildPrompt(allocator, query);
    defer allocator.free(prompt);

    // 构建请求体
    const request_body = try buildClaudeRequest(allocator, prompt);
    defer allocator.free(request_body);

    // TODO: Implement HTTP call using the project's transport infrastructure
    // For now, return a mock response for common swap queries
    const lower = try std.ascii.allocLowerString(allocator, query);
    defer allocator.free(lower);

    return try mockParseIntent(allocator, query);
}

/// 构建 prompt
fn buildPrompt(allocator: std.mem.Allocator, query: []const u8) ![]u8 {
    // 替换模板中的 {{USER_INPUT}}
    const placeholder = "{{USER_INPUT}}";
    const idx = std.mem.indexOf(u8, PROMPT_TEMPLATE, placeholder) orelse {
        // 如果模板中没有占位符，直接返回模板 + 查询
        return try std.fmt.allocPrint(allocator, "{s}\n\nUser: {s}", .{
            PROMPT_TEMPLATE,
            query,
        });
    };

    const before = PROMPT_TEMPLATE[0..idx];
    const after = PROMPT_TEMPLATE[idx + placeholder.len ..];

    return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        before,
        query,
        after,
    });
}

/// 构建 Claude API 请求体
fn buildClaudeRequest(allocator: std.mem.Allocator, prompt: []const u8) ![]u8 {
    const request = ClaudeRequest{
        .messages = &[_]ClaudeRequest.ClaudeMessage{
            .{
                .role = "user",
                .content = prompt,
            },
        },
    };

    return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(request, .{
        .emit_null_optional_fields = false,
    })});
}

/// 解析意图 JSON (public API for Claude Code integration)
pub fn parseIntentJson(
    allocator: std.mem.Allocator,
    json_str: []const u8,
) IntentParseError!IntentResult {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    ) catch {
        return IntentParseError.InvalidJson;
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return IntentParseError.InvalidResponse;

    const intent = root.object.get("intent") orelse {
        return IntentParseError.MissingRequiredField;
    };
    if (intent != .string) return IntentParseError.InvalidResponse;

    const intent_str = intent.string;

    if (std.mem.eql(u8, intent_str, "swap")) {
        const from_token = root.object.get("from") orelse {
            return IntentParseError.MissingRequiredField;
        };
        const to_token = root.object.get("to") orelse {
            return IntentParseError.MissingRequiredField;
        };
        const amount = root.object.get("amount");

        if (from_token != .string or to_token != .string) {
            return IntentParseError.InvalidResponse;
        }

        var slippage_bps: u64 = 50;
        if (root.object.get("slippage_bps")) |s| {
            if (s == .integer) {
                slippage_bps = @intCast(@max(0, s.integer));
            } else if (s == .float) {
                slippage_bps = @intFromFloat(@max(0, s.float));
            }
        }

        var amount_str: ?[]const u8 = null;
        if (amount) |a| {
            if (a == .string) {
                amount_str = try allocator.dupe(u8, a.string);
            } else if (a == .integer) {
                amount_str = try std.fmt.allocPrint(allocator, "{d}", .{a.integer});
            } else if (a == .float) {
                amount_str = try std.fmt.allocPrint(allocator, "{d}", .{@as(u64, @intFromFloat(a.float))});
            }
        }

        return IntentResult{
            .swap = .{
                .amount = amount_str,
                .from_token = try allocator.dupe(u8, from_token.string),
                .to_token = try allocator.dupe(u8, to_token.string),
                .slippage_bps = slippage_bps,
            },
        };
    }

    if (std.mem.eql(u8, intent_str, "transfer")) {
        const amount = root.object.get("amount") orelse return IntentParseError.MissingRequiredField;
        const recipient = root.object.get("recipient") orelse return IntentParseError.MissingRequiredField;
        const token = root.object.get("token") orelse return IntentParseError.MissingRequiredField;
        if (recipient != .string or token != .string) return IntentParseError.InvalidResponse;

        const amount_str = switch (amount) {
            .string => try allocator.dupe(u8, amount.string),
            .integer => try std.fmt.allocPrint(allocator, "{d}", .{amount.integer}),
            .float => try std.fmt.allocPrint(allocator, "{d}", .{@as(u64, @intFromFloat(amount.float))}),
            else => return IntentParseError.InvalidResponse,
        };

        return IntentResult{
            .transfer = .{
                .amount = amount_str,
                .token = try allocator.dupe(u8, token.string),
                .recipient = try allocator.dupe(u8, recipient.string),
            },
        };
    }

    if (std.mem.eql(u8, intent_str, "balance")) {
        const token = root.object.get("token");
        var token_str: ?[]const u8 = null;
        if (token) |value| {
            if (value != .string) return IntentParseError.InvalidResponse;
            token_str = try allocator.dupe(u8, value.string);
        }
        return IntentResult{
            .balance = .{
                .token = token_str,
            },
        };
    }

    return IntentResult{
        .unsupported = try allocator.dupe(u8, intent_str),
    };
}

/// 解析 Claude API 响应
fn parseClaudeResponse(
    allocator: std.mem.Allocator,
    response_body: []const u8,
) IntentParseError!IntentResult {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        response_body,
        .{},
    ) catch {
        return IntentParseError.InvalidJson;
    };
    defer parsed.deinit();

    // 提取 content 中的 JSON
    const root = parsed.value;
    if (root != .object) return IntentParseError.InvalidResponse;

    const content = root.object.get("content") orelse {
        return IntentParseError.InvalidResponse;
    };

    // 解析 content 数组
    if (content != .array) return IntentParseError.InvalidResponse;
    if (content.array.items.len == 0) return IntentParseError.InvalidResponse;

    const first_content = content.array.items[0];
    if (first_content != .object) return IntentParseError.InvalidResponse;

    const text = first_content.object.get("text") orelse {
        return IntentParseError.InvalidResponse;
    };
    if (text != .string) return IntentParseError.InvalidResponse;

    // 解析意图 JSON
    return try parseIntentJson(allocator, text.string);
}

// ============== 测试 ==============

test "mock parse swap intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "swap 100 SUI for USDC",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .swap => |intent| {
            try testing.expect(intent.amount != null);
            try testing.expectEqualStrings("100", intent.amount.?);
            try testing.expectEqualStrings("SUI", intent.from_token);
            try testing.expectEqualStrings("USDC", intent.to_token);
            try testing.expectEqual(@as(u64, 50), intent.slippage_bps);
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse transfer intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "send 42 SUI to 0x1234",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .transfer => |intent| {
            try testing.expectEqualStrings("42", intent.amount);
            try testing.expectEqualStrings("SUI", intent.token);
            try testing.expectEqualStrings("0x1234", intent.recipient);
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse balance intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "check my USDC balance",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .balance => |intent| {
            try testing.expect(intent.token != null);
            try testing.expectEqualStrings("USDC", intent.token.?);
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse unsupported intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "stake my SUI",
        null,
    );
    defer result.deinit(testing.allocator);

    try testing.expect(result == .unsupported);
}

// Regression: ISSUE-ENG-NL-LOWERING — parser must support all 3 MVP intents
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parse intent json covers swap transfer and balance" {
    const testing = std.testing;

    var swap_result = try parseIntentJson(
        testing.allocator,
        "{\"intent\":\"swap\",\"from\":\"SUI\",\"to\":\"USDC\",\"amount\":\"100\",\"slippage_bps\":75}",
    );
    defer swap_result.deinit(testing.allocator);
    var transfer_result = try parseIntentJson(
        testing.allocator,
        "{\"intent\":\"transfer\",\"amount\":25,\"token\":\"SUI\",\"recipient\":\"0xabc\"}",
    );
    defer transfer_result.deinit(testing.allocator);
    var balance_result = try parseIntentJson(
        testing.allocator,
        "{\"intent\":\"balance\",\"token\":\"SUI\"}",
    );
    defer balance_result.deinit(testing.allocator);

    switch (swap_result) {
        .swap => |intent| {
            try testing.expect(intent.amount != null);
            try testing.expectEqualStrings("100", intent.amount.?);
            try testing.expectEqual(@as(u64, 75), intent.slippage_bps);
        },
        else => return error.UnexpectedResult,
    }
    switch (transfer_result) {
        .transfer => |intent| {
            try testing.expectEqualStrings("25", intent.amount);
            try testing.expectEqualStrings("SUI", intent.token);
            try testing.expectEqualStrings("0xabc", intent.recipient);
        },
        else => return error.UnexpectedResult,
    }
    switch (balance_result) {
        .balance => |intent| {
            try testing.expect(intent.token != null);
            try testing.expectEqualStrings("SUI", intent.token.?);
        },
        else => return error.UnexpectedResult,
    }
}

// Regression: ISSUE-ENG-NL-MOCK-FALLBACK — no API key behavior must stay explicit and stable
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parseNaturalLanguageIntent with and without api key stays aligned" {
    const testing = std.testing;

    var no_key_transfer = try parseNaturalLanguageIntent(testing.allocator, "send 7 USDC to 0x9999", null);
    defer no_key_transfer.deinit(testing.allocator);
    var key_transfer = try parseNaturalLanguageIntent(testing.allocator, "send 7 USDC to 0x9999", "test-key");
    defer key_transfer.deinit(testing.allocator);
    var no_key_balance = try parseNaturalLanguageIntent(testing.allocator, "show my balance", null);
    defer no_key_balance.deinit(testing.allocator);
    var key_balance = try parseNaturalLanguageIntent(testing.allocator, "show my balance", "test-key");
    defer key_balance.deinit(testing.allocator);

    try testing.expect(no_key_transfer == .transfer);
    try testing.expect(key_transfer == .transfer);
    try testing.expect(no_key_balance == .balance);
    try testing.expect(key_balance == .balance);
}

// Regression: ISSUE-ENG-NL-CONTRACT — malformed JSON and wrapped provider responses must fail loudly
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parse intent json malformed variants fail loudly" {
    const testing = std.testing;

    try testing.expectError(IntentParseError.MissingRequiredField, parseIntentJson(testing.allocator, "{}"));
    try testing.expectError(IntentParseError.InvalidResponse, parseIntentJson(testing.allocator, "[]"));
    try testing.expectError(IntentParseError.InvalidResponse, parseIntentJson(testing.allocator, "{\"intent\":123}"));
    try testing.expectError(IntentParseError.MissingRequiredField, parseIntentJson(testing.allocator, "{\"intent\":\"transfer\",\"amount\":1,\"token\":\"SUI\"}"));
    try testing.expectError(IntentParseError.InvalidResponse, parseIntentJson(testing.allocator, "{\"intent\":\"balance\",\"token\":123}"));
}

test "parseClaudeResponse covers wrapped intents and rejects malformed payloads" {
    const testing = std.testing;

    var balance_result = try parseClaudeResponse(
        testing.allocator,
        "{\"content\":[{\"text\":\"{\\\"intent\\\":\\\"balance\\\",\\\"token\\\":\\\"SUI\\\"}\"}]}",
    );
    defer balance_result.deinit(testing.allocator);
    var transfer_result = try parseClaudeResponse(
        testing.allocator,
        "{\"content\":[{\"text\":\"{\\\"intent\\\":\\\"transfer\\\",\\\"amount\\\":1,\\\"token\\\":\\\"SUI\\\",\\\"recipient\\\":\\\"0x1\\\"}\"}]}",
    );
    defer transfer_result.deinit(testing.allocator);
    var swap_result = try parseClaudeResponse(
        testing.allocator,
        "{\"content\":[{\"text\":\"{\\\"intent\\\":\\\"swap\\\",\\\"from\\\":\\\"SUI\\\",\\\"to\\\":\\\"USDC\\\"}\"}]}",
    );
    defer swap_result.deinit(testing.allocator);
    var unsupported_result = try parseClaudeResponse(
        testing.allocator,
        "{\"content\":[{\"text\":\"{\\\"intent\\\":\\\"stake\\\"}\"}]}",
    );
    defer unsupported_result.deinit(testing.allocator);

    try testing.expect(balance_result == .balance);
    try testing.expect(transfer_result == .transfer);
    try testing.expect(swap_result == .swap);
    try testing.expect(unsupported_result == .unsupported);

    try testing.expectError(IntentParseError.InvalidResponse, parseClaudeResponse(testing.allocator, "{\"content\":[]}"));
    try testing.expectError(IntentParseError.InvalidResponse, parseClaudeResponse(testing.allocator, "{\"content\":[{}]}"));
    try testing.expectError(IntentParseError.InvalidJson, parseClaudeResponse(testing.allocator, "{\"content\":[{\"text\":\"{not-json}\"}]}"));
}
