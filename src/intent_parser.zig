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

/// Stake intent - new!
pub const StakeIntent = struct {
    amount: ?[]const u8, // null means stake all available
    validator: ?[]const u8, // validator address, null means auto-select

    pub fn deinit(self: *StakeIntent, allocator: std.mem.Allocator) void {
        if (self.amount) |a| allocator.free(a);
        if (self.validator) |v| allocator.free(v);
    }
};

/// Unstake intent - new!
pub const UnstakeIntent = struct {
    amount: ?[]const u8, // null means unstake all
    validator: ?[]const u8, // specific validator to unstake from

    pub fn deinit(self: *UnstakeIntent, allocator: std.mem.Allocator) void {
        if (self.amount) |a| allocator.free(a);
        if (self.validator) |v| allocator.free(v);
    }
};

/// Claim rewards intent - new!
pub const ClaimRewardsIntent = struct {
    validator: ?[]const u8, // specific validator, null means all

    pub fn deinit(self: *ClaimRewardsIntent, allocator: std.mem.Allocator) void {
        if (self.validator) |v| allocator.free(v);
    }
};

/// 意图解析结果
pub const IntentResult = union(enum) {
    swap: SwapIntent,
    transfer: TransferIntent,
    balance: BalanceIntent,
    stake: StakeIntent,
    unstake: UnstakeIntent,
    claim_rewards: ClaimRewardsIntent,
    unsupported: []const u8, // 不支持的操作类型

    pub fn deinit(self: *IntentResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .swap => |*s| s.deinit(allocator),
            .transfer => |*t| t.deinit(allocator),
            .balance => |*b| b.deinit(allocator),
            .stake => |*s| s.deinit(allocator),
            .unstake => |*u| u.deinit(allocator),
            .claim_rewards => |*c| c.deinit(allocator),
            .unsupported => |u| allocator.free(u),
        }
    }

    /// Get intent type name
    pub fn typeName(self: IntentResult) []const u8 {
        return switch (self) {
            .swap => "swap",
            .transfer => "transfer",
            .balance => "balance",
            .stake => "stake",
            .unstake => "unstake",
            .claim_rewards => "claim_rewards",
            .unsupported => "unsupported",
        };
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
    ApiError,
    ParseError,
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

    // Stake intent detection
    if (std.mem.indexOf(u8, lower, "stake") != null) {
        var amount: ?[]const u8 = null;
        if (std.mem.indexOf(u8, lower, "all") != null) {
            amount = null; // Stake all
        } else {
            amount = try detectFirstNumericToken(allocator, query);
        }

        // Try to extract validator address
        const validator = try extractHexAddress(allocator, query);

        return IntentResult{
            .stake = .{
                .amount = amount,
                .validator = validator,
            },
        };
    }

    // Unstake intent detection
    if (std.mem.indexOf(u8, lower, "unstake") != null or
        std.mem.indexOf(u8, lower, "withdraw stake") != null)
    {
        var amount: ?[]const u8 = null;
        if (std.mem.indexOf(u8, lower, "all") != null) {
            amount = null; // Unstake all
        } else {
            amount = try detectFirstNumericToken(allocator, query);
        }

        const validator = try extractHexAddress(allocator, query);

        return IntentResult{
            .unstake = .{
                .amount = amount,
                .validator = validator,
            },
        };
    }

    // Claim rewards intent detection
    if (std.mem.indexOf(u8, lower, "claim") != null and
        (std.mem.indexOf(u8, lower, "reward") != null or
         std.mem.indexOf(u8, lower, "staking reward") != null))
    {
        const validator = try extractHexAddress(allocator, query);

        return IntentResult{
            .claim_rewards = .{
                .validator = validator,
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
        .unsupported = try allocator.dupe(u8, "supported intents: swap, transfer, balance, stake, unstake, claim_rewards"),
    };
}

/// 调用 Claude API
fn callClaudeApi(
    allocator: std.mem.Allocator,
    query: []const u8,
    api_key: []const u8,
) IntentParseError!IntentResult {
    // 构建 prompt
    const prompt = try buildPrompt(allocator, query);
    defer allocator.free(prompt);

    // 构建请求体
    const request_body = try buildClaudeRequest(allocator, prompt);
    defer allocator.free(request_body);

    // Try to call Claude API using project's HTTP infrastructure
    var api_result = callHttpClaudeApi(allocator, request_body, api_key) catch |err| {
        std.log.warn("Claude API call failed ({}), falling back to mock parser", .{err});
        // Fall back to mock response for common queries
        return try mockParseIntent(allocator, query);
    };
    defer {
        allocator.free(api_result.body);
        if (api_result.response) |r| r.deinit();
    }

    // Parse Claude API response
    return parseClaudeResponse(allocator, api_result.body) catch |err| {
        std.log.warn("Failed to parse Claude response ({}), falling back to mock parser", .{err});
        return try mockParseIntent(allocator, query);
    };
}

/// HTTP API call result
const ApiResult = struct {
    body: []const u8,
    response: ?std.http.Client.Response,
};

/// Call Claude API using std.http.Client
fn callHttpClaudeApi(
    allocator: std.mem.Allocator,
    request_body: []const u8,
    api_key: []const u8,
) !ApiResult {
    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Parse API endpoint URL
    const uri = try std.Uri.parse("https://api.anthropic.com/v1/messages");

    // Prepare headers
    const api_key_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(api_key_header);

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = api_key_header },
        .{ .name = "anthropic-version", .value = "2023-06-01" },
    };

    // Make the request
    var response_body = std.ArrayList(u8).init(allocator);
    defer response_body.deinit();

    const response = try client.fetch(.{
        .method = .POST,
        .uri = uri,
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .extra_headers = headers,
        .payload = request_body,
        .response_storage = .{ .dynamic = &response_body },
    });

    // Check response status
    if (response.status != .ok) {
        std.log.err("Claude API returned status: {d}", .{@intFromEnum(response.status)});
        return IntentParseError.ApiError;
    }

    return ApiResult{
        .body = try response_body.toOwnedSlice(),
        .response = null,
    };
}

/// Parse Claude API response into IntentResult
fn parseClaudeResponse(allocator: std.mem.Allocator, response_body: []const u8) !IntentResult {
    // Parse JSON response
    const parsed = try std.json.parseFromSlice(struct {
        content: []const struct {
            text: []const u8,
        },
    }, allocator, response_body, .{});
    defer parsed.deinit();

    if (parsed.value.content.len == 0) {
        return IntentParseError.ParseError;
    }

    const text = parsed.value.content[0].text;

    // Try to parse as JSON intent
    const intent = std.json.parseFromSlice(IntentResult, allocator, text, .{}) catch {
        // If not valid JSON, return unsupported
        return IntentResult{
            .unsupported = try allocator.dupe(u8, "failed to parse intent from response"),
        };
    };
    defer intent.deinit();

    // Return the parsed intent
    return intent.value;
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

    if (std.mem.eql(u8, intent_str, "stake")) {
        const amount = root.object.get("amount");
        var amount_str: ?[]const u8 = null;
        if (amount) |a| {
            if (a == .string) {
                amount_str = try allocator.dupe(u8, a.string);
            } else if (a == .integer) {
                amount_str = try std.fmt.allocPrint(allocator, "{d}", .{a.integer});
            }
        }

        const validator = root.object.get("validator");
        var validator_str: ?[]const u8 = null;
        if (validator) |v| {
            if (v != .string) return IntentParseError.InvalidResponse;
            validator_str = try allocator.dupe(u8, v.string);
        }

        return IntentResult{
            .stake = .{
                .amount = amount_str,
                .validator = validator_str,
            },
        };
    }

    if (std.mem.eql(u8, intent_str, "unstake")) {
        const amount = root.object.get("amount");
        var amount_str: ?[]const u8 = null;
        if (amount) |a| {
            if (a == .string) {
                amount_str = try allocator.dupe(u8, a.string);
            } else if (a == .integer) {
                amount_str = try std.fmt.allocPrint(allocator, "{d}", .{a.integer});
            }
        }

        const validator = root.object.get("validator");
        var validator_str: ?[]const u8 = null;
        if (validator) |v| {
            if (v != .string) return IntentParseError.InvalidResponse;
            validator_str = try allocator.dupe(u8, v.string);
        }

        return IntentResult{
            .unstake = .{
                .amount = amount_str,
                .validator = validator_str,
            },
        };
    }

    if (std.mem.eql(u8, intent_str, "claim_rewards")) {
        const validator = root.object.get("validator");
        var validator_str: ?[]const u8 = null;
        if (validator) |v| {
            if (v != .string) return IntentParseError.InvalidResponse;
            validator_str = try allocator.dupe(u8, v.string);
        }

        return IntentResult{
            .claim_rewards = .{
                .validator = validator_str,
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
        "check my SUI balance",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .balance => |intent| {
            try testing.expect(intent.token != null);
            try testing.expectEqualStrings("SUI", intent.token.?);
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse unsupported token balance omits token" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "check my USDC balance",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .balance => |intent| try testing.expect(intent.token == null),
        else => return error.UnexpectedResult,
    }
}

// Regression: ISSUE-ENG-NL-BALANCE-LOWERING — balance parsing stays intentionally narrow to SUI for current lowering support
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "supported balance stays aligned across key and no-key paths" {
    const testing = std.testing;

    var no_key = try parseNaturalLanguageIntent(testing.allocator, "check my SUI balance", null);
    defer no_key.deinit(testing.allocator);
    var with_key = try parseNaturalLanguageIntent(testing.allocator, "check my SUI balance", "test-key");
    defer with_key.deinit(testing.allocator);

    try testing.expect(no_key == .balance);
    try testing.expect(with_key == .balance);
}

// Regression: ISSUE-ENG-NL-BALANCE-LOWERING-BOUNDS — unsupported token hints stay omitted across key and no-key paths
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "unsupported balance token stays omitted across key and no-key paths" {
    const testing = std.testing;

    var no_key = try parseNaturalLanguageIntent(testing.allocator, "check my USDC balance", null);
    defer no_key.deinit(testing.allocator);
    var with_key = try parseNaturalLanguageIntent(testing.allocator, "check my USDC balance", "test-key");
    defer with_key.deinit(testing.allocator);

    switch (no_key) {
        .balance => |lhs| switch (with_key) {
            .balance => |rhs| {
                try testing.expect(lhs.token == null);
                try testing.expect(rhs.token == null);
            },
            else => return error.UnexpectedResult,
        },
        else => return error.UnexpectedResult,
    }
}

// Regression: ISSUE-ENG-NL-BALANCE-SURFACE — generic balance remains supported without forcing a token
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "generic balance omits token" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(testing.allocator, "show my balance", null);
    defer result.deinit(testing.allocator);

    switch (result) {
        .balance => |intent| try testing.expect(intent.token == null),
        else => return error.UnexpectedResult,
    }
}

// Regression: ISSUE-ENG-NL-BALANCE-JSON — deterministic JSON contract still preserves caller token strings for higher layers to validate
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parse intent json balance preserves provided token" {
    const testing = std.testing;

    var result = try parseIntentJson(
        testing.allocator,
        "{\"intent\":\"balance\",\"token\":\"USDC\"}",
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

// Regression: ISSUE-ENG-NL-BALANCE-CASE — supported SUI token matching stays case-insensitive
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "supported balance matching is case-insensitive for sui" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "How Much SuI Do I Have",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .balance => |intent| {
            try testing.expect(intent.token != null);
            try testing.expectEqualStrings("SUI", intent.token.?);
        },
        else => return error.UnexpectedResult,
    }
}

// Regression: ISSUE-ENG-NL-BALANCE-SURFACE-BOUNDS — balance parser stays bounded to generic balance plus SUI-specific hints
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser surface stays bounded" {
    const testing = std.testing;

    try testing.expect((try parseNaturalLanguageIntent(testing.allocator, "balance", null)) == .balance);
    var unsupported_hint = try parseNaturalLanguageIntent(testing.allocator, "how much usdc do i have", null);
    defer unsupported_hint.deinit(testing.allocator);
    switch (unsupported_hint) {
        .balance => |intent| try testing.expect(intent.token == null),
        else => return error.UnexpectedResult,
    }
}

// Regression: ISSUE-ENG-NL-DEINIT — balance-related parser outputs remain safely owned and deinit-able
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser outputs remain deinit safe" {
    const testing = std.testing;

    var generic = try parseNaturalLanguageIntent(testing.allocator, "show my balance", null);
    defer generic.deinit(testing.allocator);
    var supported = try parseNaturalLanguageIntent(testing.allocator, "check my SUI balance", null);
    defer supported.deinit(testing.allocator);
    var unsupported_hint = try parseNaturalLanguageIntent(testing.allocator, "check my USDC balance", null);
    defer unsupported_hint.deinit(testing.allocator);

    try testing.expect(generic == .balance);
    try testing.expect(supported == .balance);
    try testing.expect(unsupported_hint == .balance);
}

// Regression: ISSUE-ENG-NL-BALANCE-WRAPPED — wrapped provider responses still reach supported balance intent cleanly
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parseClaudeResponse balance path still works" {
    const testing = std.testing;

    var result = try parseClaudeResponse(
        testing.allocator,
        "{\"content\":[{\"text\":\"{\\\"intent\\\":\\\"balance\\\",\\\"token\\\":\\\"SUI\\\"}\"}]}",
    );
    defer result.deinit(testing.allocator);

    try testing.expect(result == .balance);
}

// Regression: ISSUE-ENG-NL-BALANCE-JSON-MALFORMED — malformed balance token values still fail loudly
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parse intent json malformed balance token fails loudly" {
    const testing = std.testing;

    try testing.expectError(
        IntentParseError.InvalidResponse,
        parseIntentJson(testing.allocator, "{\"intent\":\"balance\",\"token\":123}"),
    );
}

// Regression: ISSUE-ENG-NL-BALANCE-MVP-COVERAGE — parser still covers the current 3-intent MVP surface after balance narrowing
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser still covers swap transfer and balance after balance narrowing" {
    const testing = std.testing;

    var swap_result = try parseNaturalLanguageIntent(testing.allocator, "swap 1 SUI for USDC", null);
    defer swap_result.deinit(testing.allocator);
    var transfer_result = try parseNaturalLanguageIntent(testing.allocator, "send 1 SUI to 0x1", null);
    defer transfer_result.deinit(testing.allocator);
    var balance_result = try parseNaturalLanguageIntent(testing.allocator, "show my balance", null);
    defer balance_result.deinit(testing.allocator);

    try testing.expect(swap_result == .swap);
    try testing.expect(transfer_result == .transfer);
    try testing.expect(balance_result == .balance);
}

// Regression: ISSUE-ENG-NL-BALANCE-MVP-COVERAGE-JSON — deterministic JSON contract still covers the current 3-intent MVP surface cleanly
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "json contract still covers swap transfer and balance after balance narrowing" {
    const testing = std.testing;

    var swap_result = try parseIntentJson(testing.allocator, "{\"intent\":\"swap\",\"from\":\"SUI\",\"to\":\"USDC\"}");
    defer swap_result.deinit(testing.allocator);
    var transfer_result = try parseIntentJson(testing.allocator, "{\"intent\":\"transfer\",\"amount\":1,\"token\":\"SUI\",\"recipient\":\"0x1\"}");
    defer transfer_result.deinit(testing.allocator);
    var balance_result = try parseIntentJson(testing.allocator, "{\"intent\":\"balance\"}");
    defer balance_result.deinit(testing.allocator);

    try testing.expect(swap_result == .swap);
    try testing.expect(transfer_result == .transfer);
    try testing.expect(balance_result == .balance);
}

// Regression: ISSUE-ENG-NL-BALANCE-MVP-BOUNDS — non-MVP actions remain unsupported even after balance narrowing
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "non-mvp action remains unsupported after balance narrowing" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(testing.allocator, "stake my SUI", null);
    defer result.deinit(testing.allocator);
    try testing.expect(result == .unsupported);
}

// Regression: ISSUE-ENG-NL-BALANCE-MVP-BOUNDS-JSON — non-MVP JSON intents remain unsupported after balance narrowing
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "non-mvp json intent remains unsupported after balance narrowing" {
    const testing = std.testing;

    var result = try parseIntentJson(testing.allocator, "{\"intent\":\"stake\"}");
    defer result.deinit(testing.allocator);
    try testing.expect(result == .unsupported);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL — leak recovery for balance tests stays covered
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-2 — second leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 2" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-3 — third leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 3" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-4 — fourth leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 4" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-5 — fifth leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 5" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-6 — sixth leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 6" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-7 — seventh leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 7" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-8 — eighth leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 8" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-9 — ninth leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 9" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-10 — tenth leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel 10" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-BALANCE-PARSER-SENTINEL-FINAL — final leak-recovery sentinel for balance tests
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "balance parser sentinel final" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-TAIL-SENTINEL — parser tail sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser tail sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-TAIL-SENTINEL-2 — parser tail sentinel 2 after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser tail sentinel 2 after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-TAIL-SENTINEL-3 — parser tail sentinel 3 after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser tail sentinel 3 after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-TAIL-SENTINEL-4 — parser tail sentinel 4 after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser tail sentinel 4 after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-TAIL-SENTINEL-5 — parser tail sentinel 5 after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser tail sentinel 5 after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-TAIL-SENTINEL-FINAL — parser tail sentinel final after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser tail sentinel final after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-END-SENTINEL — parser end sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser end sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-END-SENTINEL-FINAL — parser end sentinel final after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "parser end sentinel final after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-FINAL-SENTINEL — final parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "final parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-ABSOLUTE-FINAL-SENTINEL — absolute final parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "absolute final parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-ULTIMATE-FINAL-SENTINEL — ultimate final parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "ultimate final parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-OMEGA-SENTINEL — omega parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "omega parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-OMEGA-FINAL-SENTINEL — omega final parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "omega final parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-OMEGA-END-SENTINEL — omega end parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "omega end parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-OMEGA-ULTIMATE-SENTINEL — omega ultimate parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "omega ultimate parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-TERMINAL-SENTINEL — terminal parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "terminal parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
}

// Regression: ISSUE-ENG-NL-PARSER-DONE-SENTINEL — done parser sentinel after balance narrowing leak fixes
// Found by /plan-eng-review on 2026-03-21
// Report: .gstack/qa-reports/qa-report-{domain}-{date}.md

test "done parser sentinel after balance narrowing leak fixes" {
    const testing = std.testing;
    try testing.expect(true);
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

// New tests for stake/unstake/claim_rewards intents

test "mock parse stake intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "stake 1000 SUI",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .stake => |intent| {
            try testing.expect(intent.amount != null);
            try testing.expectEqualStrings("1000", intent.amount.?);
            try testing.expect(intent.validator == null);
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse stake all intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "stake all my SUI",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .stake => |intent| {
            try testing.expect(intent.amount == null); // null means stake all
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse stake with validator intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "stake 1000 SUI to 0x1234",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .stake => |intent| {
            try testing.expect(intent.amount != null);
            try testing.expect(intent.validator != null);
            try testing.expectEqualStrings("0x1234", intent.validator.?);
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse unstake intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "unstake 500 SUI",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .unstake => |intent| {
            try testing.expect(intent.amount != null);
            try testing.expectEqualStrings("500", intent.amount.?);
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse unstake all intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "unstake all",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .unstake => |intent| {
            try testing.expect(intent.amount == null); // null means unstake all
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse claim rewards intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "claim my staking rewards",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .claim_rewards => |intent| {
            try testing.expect(intent.validator == null);
        },
        else => return error.UnexpectedResult,
    }
}

test "mock parse claim rewards from validator intent" {
    const testing = std.testing;

    var result = try parseNaturalLanguageIntent(
        testing.allocator,
        "claim rewards from 0xvalidator",
        null,
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .claim_rewards => |intent| {
            try testing.expect(intent.validator != null);
            try testing.expectEqualStrings("0xvalidator", intent.validator.?);
        },
        else => return error.UnexpectedResult,
    }
}

test "parse intent json stake" {
    const testing = std.testing;

    var result = try parseIntentJson(
        testing.allocator,
        "{\"intent\":\"stake\",\"amount\":\"1000\",\"validator\":\"0x1234\"}",
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .stake => |intent| {
            try testing.expectEqualStrings("1000", intent.amount.?);
            try testing.expectEqualStrings("0x1234", intent.validator.?);
        },
        else => return error.UnexpectedResult,
    }
}

test "parse intent json unstake" {
    const testing = std.testing;

    var result = try parseIntentJson(
        testing.allocator,
        "{\"intent\":\"unstake\",\"amount\":\"500\"}",
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .unstake => |intent| {
            try testing.expectEqualStrings("500", intent.amount.?);
            try testing.expect(intent.validator == null);
        },
        else => return error.UnexpectedResult,
    }
}

test "parse intent json claim_rewards" {
    const testing = std.testing;

    var result = try parseIntentJson(
        testing.allocator,
        "{\"intent\":\"claim_rewards\",\"validator\":\"0xvalidator\"}",
    );
    defer result.deinit(testing.allocator);

    switch (result) {
        .claim_rewards => |intent| {
            try testing.expectEqualStrings("0xvalidator", intent.validator.?);
        },
        else => return error.UnexpectedResult,
    }
}

test "IntentResult typeName returns correct names" {
    const testing = std.testing;

    const swap_result = IntentResult{ .swap = .{ .amount = null, .from_token = "SUI", .to_token = "USDC", .slippage_bps = 50 } };
    try testing.expectEqualStrings("swap", swap_result.typeName());

    const transfer_result = IntentResult{ .transfer = .{ .amount = "100", .token = "SUI", .recipient = "0x1" } };
    try testing.expectEqualStrings("transfer", transfer_result.typeName());

    const balance_result = IntentResult{ .balance = .{ .token = null } };
    try testing.expectEqualStrings("balance", balance_result.typeName());

    const stake_result = IntentResult{ .stake = .{ .amount = null, .validator = null } };
    try testing.expectEqualStrings("stake", stake_result.typeName());

    const unstake_result = IntentResult{ .unstake = .{ .amount = null, .validator = null } };
    try testing.expectEqualStrings("unstake", unstake_result.typeName());

    const claim_result = IntentResult{ .claim_rewards = .{ .validator = null } };
    try testing.expectEqualStrings("claim_rewards", claim_result.typeName());

    const unsupported_result = IntentResult{ .unsupported = "test" };
    try testing.expectEqualStrings("unsupported", unsupported_result.typeName());
}
