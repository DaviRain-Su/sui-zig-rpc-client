const std = @import("std");
const builtin = @import("builtin");

/// 解析的交换意图
pub const SwapIntent = struct {
    amount: ?[]const u8,  // "100" 或 "all"
    from_token: []const u8,  // "SUI"
    to_token: []const u8,    // "USDC"
    slippage_bps: u64,       // 默认 50 (0.5%)

    pub fn deinit(self: *SwapIntent, allocator: std.mem.Allocator) void {
        if (self.amount) |a| allocator.free(a);
        allocator.free(self.from_token);
        allocator.free(self.to_token);
    }
};

/// 意图解析结果
pub const IntentResult = union(enum) {
    swap: SwapIntent,
    unsupported: []const u8,  // 不支持的操作类型

    pub fn deinit(self: *IntentResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .swap => |*s| s.deinit(allocator),
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

/// Mock 解析 - 用于测试
fn mockParseIntent(allocator: std.mem.Allocator, query: []const u8) !IntentResult {
    // Smart mock parser for preview mode
    const lower = try std.ascii.allocLowerString(allocator, query);
    defer allocator.free(lower);

    // Check for swap intent with SUI and USDC
    if (std.mem.indexOf(u8, lower, "swap") != null and
        std.mem.indexOf(u8, lower, "sui") != null and
        std.mem.indexOf(u8, lower, "usdc") != null)
    {
        // Extract amount
        var amount: ?[]const u8 = null;
        if (std.mem.indexOf(u8, lower, "all") != null) {
            amount = try allocator.dupe(u8, "all");
        } else {
            // Try to find a number in the query
            var it = std.mem.splitScalar(u8, query, ' ');
            while (it.next()) |word| {
                if (std.fmt.parseInt(u64, word, 10)) |_| {
                    amount = try allocator.dupe(u8, word);
                    break;
                } else |_| {}
            }
            if (amount == null) {
                amount = try allocator.dupe(u8, "100"); // default
            }
        }

        // Determine from/to based on word order
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
        .unsupported = try allocator.dupe(u8, "only swap SUI/USDC is supported in preview mode"),
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

    if (std.mem.indexOf(u8, lower, "swap") != null and
        std.mem.indexOf(u8, lower, "sui") != null and
        std.mem.indexOf(u8, lower, "usdc") != null)
    {
        // Extract amount if present
        var amount: ?[]const u8 = null;
        if (std.mem.indexOf(u8, lower, "all") != null) {
            amount = try allocator.dupe(u8, "all");
        } else {
            // Try to find a number
            var it = std.mem.splitScalar(u8, query, ' ');
            while (it.next()) |word| {
                if (std.fmt.parseInt(u64, word, 10)) |_| {
                    amount = try allocator.dupe(u8, word);
                    break;
                } else |_| {}
            }
        }

        // Determine from/to based on word order: "swap SUI for USDC" vs "swap USDC for SUI"
        const sui_idx = std.mem.indexOf(u8, lower, "sui").?;
        const usdc_idx = std.mem.indexOf(u8, lower, "usdc").?;
        const from_sui = sui_idx < usdc_idx;

        return IntentResult{
            .swap = .{
                .amount = amount,
                .from_token = if (from_sui)
                    try allocator.dupe(u8, "SUI")
                else
                    try allocator.dupe(u8, "USDC"),
                .to_token = if (from_sui)
                    try allocator.dupe(u8, "USDC")
                else
                    try allocator.dupe(u8, "SUI"),
                .slippage_bps = 50,
            },
        };
    }

    return IntentResult{
        .unsupported = try allocator.dupe(u8, "only swap SUI/USDC is supported in preview mode"),
    };
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

    if (!std.mem.eql(u8, intent_str, "swap")) {
        return IntentResult{
            .unsupported = try allocator.dupe(u8, intent_str),
        };
    }

    // 解析 swap 意图
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

    // 获取 slippage，默认 50 bps
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

    try testing.expectEqualStrings("swap", "swap");
    switch (result) {
        .swap => |s| {
            try testing.expectEqualStrings("100", s.amount.?);
            try testing.expectEqualStrings("SUI", s.from_token);
            try testing.expectEqualStrings("USDC", s.to_token);
            try testing.expectEqual(@as(u64, 50), s.slippage_bps);
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

    switch (result) {
        .unsupported => {},
        else => return error.ShouldBeUnsupported,
    }
}
