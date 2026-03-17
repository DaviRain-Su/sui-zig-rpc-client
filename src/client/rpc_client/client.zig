const std = @import("std");

const transport = @import("./transport.zig");
const tx_builder = @import("../../tx_builder.zig");
const keystore = @import("../../keystore.zig");
const tx_request_builder = @import("../../tx_request_builder.zig");

pub const ClientError = error{
    Timeout,
    HttpError,
    RpcError,
    InvalidResponse,
};

pub const RpcErrorDetail = struct {
    code: ?i64 = null,
    message: []const u8,
};

pub const TransportStats = struct {
    request_count: usize = 0,
    elapsed_time_ms: u64 = 0,
    rate_limited_time_ms: u64 = 0,
};

pub const RequestSender = struct {
    context: *anyopaque,
    callback: *const fn (*anyopaque, std.mem.Allocator, struct {
        id: u64,
        method: []const u8,
        params_json: []const u8,
        request_body: []const u8,
    }) std.mem.Allocator.Error![]u8,
};

const RpcRequest = @typeInfo(@typeInfo(RequestSender).@"struct".fields[1].type).pointer.child.@"fn".params[2].type.?;

fn parseJsonResultExists(allocator: std.mem.Allocator, response: []const u8) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return false;
    const result = parsed.value.object.get("result") orelse return false;

    return switch (result) {
        .null => false,
        else => true,
    };
}

fn extractExecuteDigest(allocator: std.mem.Allocator, response: []const u8) !?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const result = parsed.value.object.get("result") orelse return null;
    if (result != .object) return null;
    const digest = result.object.get("digest") orelse return null;
    if (digest != .string) return null;
    return try allocator.dupe(u8, digest.string);
}

pub const ExecuteOrChallengeTextResult = union(enum) {
    challenge_required: []u8,
    executed: []u8,

    pub fn deinit(self: *ExecuteOrChallengeTextResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .challenge_required => |value| allocator.free(value),
            .executed => |value| allocator.free(value),
        }
    }
};

fn dupeOptionalString(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    const slice = value orelse return null;
    return try allocator.dupe(u8, slice);
}

fn dupeStringList(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    if (values.len == 0) return &.{};

    const duped = try allocator.alloc([]const u8, values.len);
    errdefer allocator.free(duped);

    for (values, 0..) |value, index| {
        duped[index] = try allocator.dupe(u8, value);
        errdefer {
            var i: usize = 0;
            while (i < index) : (i += 1) allocator.free(duped[i]);
        }
    }

    return duped;
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    if (values.len == 0) return;
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

pub const OwnedSessionChallengePrompt = struct {
    account_address: ?[]u8 = null,
    current_session: tx_request_builder.AccountSession = .{},
    action: tx_request_builder.SessionChallengeAction = .execute,
    challenge: tx_request_builder.SessionChallenge,
    text: []u8,

    pub fn deinit(self: *OwnedSessionChallengePrompt, allocator: std.mem.Allocator) void {
        if (self.account_address) |value| allocator.free(value);
        if (self.current_session.session_id) |value| allocator.free(value);
        if (self.current_session.user_id) |value| allocator.free(value);

        switch (self.challenge) {
            .sign_personal_message => |value| {
                allocator.free(value.domain);
                allocator.free(value.statement);
                allocator.free(value.nonce);
                if (value.address) |address| allocator.free(address);
                if (value.uri) |uri| allocator.free(uri);
                allocator.free(value.chain);
                freeStringList(allocator, value.resources);
            },
            .passkey => |value| {
                allocator.free(value.rp_id);
                allocator.free(value.challenge_b64url);
                if (value.user_name) |user_name| allocator.free(user_name);
                if (value.user_display_name) |user_display_name| allocator.free(user_display_name);
            },
            .zklogin_nonce => |value| {
                allocator.free(value.nonce);
                if (value.provider) |provider| allocator.free(provider);
            },
        }

        allocator.free(self.text);
    }
};

fn buildOwnedSessionChallengePrompt(
    allocator: std.mem.Allocator,
    request: tx_request_builder.SessionChallengeRequest,
    text: []u8,
) !OwnedSessionChallengePrompt {
    return .{
        .account_address = try dupeOptionalString(allocator, request.account_address),
        .current_session = .{
            .kind = request.current_session.kind,
            .session_id = try dupeOptionalString(allocator, request.current_session.session_id),
            .user_id = try dupeOptionalString(allocator, request.current_session.user_id),
            .expires_at_ms = request.current_session.expires_at_ms,
        },
        .action = request.action,
        .challenge = switch (request.challenge) {
            .sign_personal_message => |value| .{
                .sign_personal_message = .{
                    .domain = try allocator.dupe(u8, value.domain),
                    .statement = try allocator.dupe(u8, value.statement),
                    .nonce = try allocator.dupe(u8, value.nonce),
                    .address = try dupeOptionalString(allocator, value.address),
                    .uri = try dupeOptionalString(allocator, value.uri),
                    .chain = try allocator.dupe(u8, value.chain),
                    .issued_at_ms = value.issued_at_ms,
                    .expires_at_ms = value.expires_at_ms,
                    .resources = try dupeStringList(allocator, value.resources),
                },
            },
            .passkey => |value| .{
                .passkey = .{
                    .rp_id = try allocator.dupe(u8, value.rp_id),
                    .challenge_b64url = try allocator.dupe(u8, value.challenge_b64url),
                    .user_name = try dupeOptionalString(allocator, value.user_name),
                    .user_display_name = try dupeOptionalString(allocator, value.user_display_name),
                    .timeout_ms = value.timeout_ms,
                },
            },
            .zklogin_nonce => |value| .{
                .zklogin_nonce = .{
                    .nonce = try allocator.dupe(u8, value.nonce),
                    .provider = try dupeOptionalString(allocator, value.provider),
                    .max_epoch = value.max_epoch,
                },
            },
        },
        .text = text,
    };
}

pub const ExecuteOrChallengePromptResult = union(enum) {
    challenge_required: OwnedSessionChallengePrompt,
    executed: []u8,

    pub fn deinit(self: *ExecuteOrChallengePromptResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .challenge_required => |*value| value.deinit(allocator),
            .executed => |value| allocator.free(value),
        }
    }
};

pub const InspectOrChallengePromptResult = union(enum) {
    challenge_required: OwnedSessionChallengePrompt,
    inspected: []u8,

    pub fn deinit(self: *InspectOrChallengePromptResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .challenge_required => |*value| value.deinit(allocator),
            .inspected => |value| allocator.free(value),
        }
    }
};

pub const AuthorizeOrChallengePromptResult = union(enum) {
    challenge_required: OwnedSessionChallengePrompt,
    authorized: tx_request_builder.AuthorizedPreparedRequest,

    pub fn deinit(self: *AuthorizeOrChallengePromptResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .challenge_required => |*value| value.deinit(allocator),
            .authorized => |*value| value.deinit(allocator),
        }
    }
};

pub const ArtifactOrChallengePromptResult = union(enum) {
    challenge_required: OwnedSessionChallengePrompt,
    artifact: []u8,

    pub fn deinit(self: *ArtifactOrChallengePromptResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .challenge_required => |*value| value.deinit(allocator),
            .artifact => |value| allocator.free(value),
        }
    }
};

pub const ProgrammaticClientAction = union(enum) {
    authorize,
    inspect,
    execute,
    execute_confirm: struct {
        timeout_ms: u64,
        poll_ms: u64,
    },
    build_artifact: tx_request_builder.ProgrammaticArtifactKind,
};

pub const ProgrammaticClientActionResult = union(enum) {
    authorized: tx_request_builder.AuthorizedPreparedRequest,
    inspected: []u8,
    executed: []u8,
    artifact: []u8,

    pub fn deinit(self: *ProgrammaticClientActionResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .authorized => |*value| value.deinit(allocator),
            .inspected => |value| allocator.free(value),
            .executed => |value| allocator.free(value),
            .artifact => |value| allocator.free(value),
        }
    }
};

pub const ProgrammaticClientActionOrChallengePromptResult = union(enum) {
    challenge_required: OwnedSessionChallengePrompt,
    completed: ProgrammaticClientActionResult,

    pub fn deinit(self: *ProgrammaticClientActionOrChallengePromptResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .challenge_required => |*value| value.deinit(allocator),
            .completed => |*value| value.deinit(allocator),
        }
    }
};

pub const SuiRpcClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    http_client: std.http.Client,
    request_sender: ?RequestSender,
    request_id: u64,
    request_timeout_ms: ?u64,
    last_error: ?RpcErrorDetail,
    transport_stats: TransportStats,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) !SuiRpcClient {
        return .{
            .allocator = allocator,
            .endpoint = try allocator.dupe(u8, endpoint),
            .http_client = .{ .allocator = allocator },
            .request_sender = null,
            .request_id = 1,
            .request_timeout_ms = null,
            .last_error = null,
            .transport_stats = .{},
        };
    }

    pub fn initWithTimeout(allocator: std.mem.Allocator, endpoint: []const u8, request_timeout_ms: ?u64) !SuiRpcClient {
        return .{
            .allocator = allocator,
            .endpoint = try allocator.dupe(u8, endpoint),
            .http_client = .{ .allocator = allocator },
            .request_sender = null,
            .request_id = 1,
            .request_timeout_ms = request_timeout_ms,
            .last_error = null,
            .transport_stats = .{},
        };
    }

    pub fn deinit(self: *SuiRpcClient) void {
        self.http_client.deinit();
        self.allocator.free(self.endpoint);
        if (self.last_error) |error_value| {
            self.allocator.free(error_value.message);
        }
    }

    fn setError(self: *SuiRpcClient, message: []const u8, code: ?i64) void {
        if (self.last_error) |error_value| {
            self.allocator.free(error_value.message);
        }
        self.last_error = .{ .code = code, .message = message };
    }

    pub fn getLastError(self: *const SuiRpcClient) ?RpcErrorDetail {
        return self.last_error;
    }

    fn clearError(self: *SuiRpcClient) void {
        if (self.last_error) |error_value| {
            self.allocator.free(error_value.message);
        }
        self.last_error = null;
    }

    fn extractErrorFromResponse(self: *SuiRpcClient, response: []const u8) !void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch return;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return;

        const error_value = root.object.get("error") orelse return;
        if (error_value != .object) return;

        var code: ?i64 = null;
        if (error_value.object.get("code")) |code_value| {
            if (code_value == .integer) {
                code = code_value.integer;
            }
        }

        if (error_value.object.get("message")) |message_value| {
            if (message_value == .string) {
                self.setError(try self.allocator.dupe(u8, message_value.string), code);
                return;
            }
        }

        self.setError(try self.allocator.dupe(u8, "rpc error"), code);
    }

    pub fn call(self: *SuiRpcClient, method: []const u8, params_json: []const u8) ![]u8 {
        self.clearError();
        const response = try transport.sendRequest(self, method, params_json);
        errdefer self.allocator.free(response);

        self.extractErrorFromResponse(response) catch {};

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response, .{});
        defer parsed.deinit();
        const root = parsed.value;
        if (root != .object) return error.InvalidResponse;

        if (root.object.get("error") != null) {
            return error.RpcError;
        }

        return response;
    }

    pub fn sendTxInspect(self: *SuiRpcClient, params_json: []const u8) ![]u8 {
        return try self.call("sui_devInspectTransactionBlock", params_json);
    }

    pub fn sendTxExecute(self: *SuiRpcClient, params_json: []const u8) ![]u8 {
        return try self.call("sui_executeTransactionBlock", params_json);
    }

    pub fn getTransactionBlock(self: *SuiRpcClient, params_json: []const u8) ![]u8 {
        return try self.call("sui_getTransactionBlock", params_json);
    }

    pub fn waitForTransactionConfirmation(
        self: *SuiRpcClient,
        digest: []const u8,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        const start_ts = std.time.milliTimestamp();

        while (true) {
            const params = try std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{digest});
            defer self.allocator.free(params);

            const response = self.getTransactionBlock(params) catch |err| {
                if (err == ClientError.RpcError) {
                    if (self.getLastError()) |last_error| {
                        if (last_error.code) |code| {
                            if (code == -32602 or code == -32603) {
                                std.Thread.sleep(poll_ms * std.time.ns_per_ms);
                                if (std.time.milliTimestamp() - start_ts > @as(i64, @intCast(timeout_ms))) {
                                    return error.Timeout;
                                }
                                continue;
                            }
                        }
                    }
                }
                return err;
            };

            if (try parseJsonResultExists(self.allocator, response)) {
                return response;
            }

            self.allocator.free(response);

            if (std.time.milliTimestamp() - start_ts > @as(i64, @intCast(timeout_ms))) {
                return error.Timeout;
            }

            std.Thread.sleep(poll_ms * std.time.ns_per_ms);
        }
    }

    pub fn executePayloadAndConfirm(
        self: *SuiRpcClient,
        payload: []const u8,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        const response = try self.sendTxExecute(payload);
        defer self.allocator.free(response);

        const digest = try extractExecuteDigest(self.allocator, response) orelse return error.InvalidResponse;
        defer self.allocator.free(digest);

        return try self.waitForTransactionConfirmation(digest, timeout_ms, poll_ms);
    }

    pub fn inspectProgrammaticTransaction(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        context: *const tx_builder.ProgrammaticTxContext,
    ) ![]u8 {
        const payload = try context.buildInspectPayload(allocator);
        defer allocator.free(payload);
        return try self.sendTxInspect(payload);
    }

    pub fn inspectRequest(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
    ) ![]u8 {
        return try self.inspectOptions(
            allocator,
            tx_request_builder.optionsFromRequest(request),
        );
    }

    pub fn inspectPreparedRequest(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        prepared: *const tx_builder.PreparedProgrammaticTxRequest,
    ) ![]u8 {
        const payload = try prepared.buildInspectPayload(allocator);
        defer allocator.free(payload);
        return try self.sendTxInspect(payload);
    }

    pub fn executeProgrammaticTransaction(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        context: *const tx_builder.ProgrammaticTxContext,
        signatures: []const []const u8,
    ) ![]u8 {
        const payload = try context.buildExecutePayload(allocator, signatures);
        defer allocator.free(payload);
        return try self.sendTxExecute(payload);
    }

    pub fn executeProgrammaticTransactionAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        context: *const tx_builder.ProgrammaticTxContext,
        signatures: []const []const u8,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        const payload = try context.buildExecutePayload(allocator, signatures);
        defer allocator.free(payload);
        return try self.executePayloadAndConfirm(payload, timeout_ms, poll_ms);
    }

    pub fn executeRequest(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
    ) ![]u8 {
        return try self.executeOptions(
            allocator,
            tx_request_builder.optionsFromRequest(request),
        );
    }

    pub fn executePreparedRequest(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        prepared: *const tx_builder.PreparedProgrammaticTxRequest,
    ) ![]u8 {
        const payload = try prepared.buildExecutePayload(allocator);
        defer allocator.free(payload);

        if (prepared.request.wait_for_confirmation) {
            return try self.executePayloadAndConfirm(
                payload,
                prepared.request.confirm_timeout_ms,
                prepared.request.confirm_poll_ms,
            );
        }

        return try self.sendTxExecute(payload);
    }

    pub fn inspectAuthorizedPreparedRequest(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        prepared: *tx_request_builder.AuthorizedPreparedRequest,
    ) ![]u8 {
        const payload = try prepared.buildInspectPayload(allocator);
        defer allocator.free(payload);
        return try self.sendTxInspect(payload);
    }

    pub fn executeAuthorizedPreparedRequest(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        prepared: *tx_request_builder.AuthorizedPreparedRequest,
    ) ![]u8 {
        const payload = try prepared.buildExecutePayload(allocator);
        defer allocator.free(payload);

        if (prepared.prepared.request.wait_for_confirmation) {
            return try self.executePayloadAndConfirm(
                payload,
                prepared.prepared.request.confirm_timeout_ms,
                prepared.prepared.request.confirm_poll_ms,
            );
        }

        return try self.sendTxExecute(payload);
    }

    pub fn planOptionsWithAccountProvider(
        self: *const SuiRpcClient,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) tx_request_builder.AuthorizationPlan {
        _ = self;
        return tx_request_builder.authorizationPlan(options, provider);
    }

    pub fn planOptionsFromDefaultKeystore(
        self: *const SuiRpcClient,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
    ) tx_request_builder.AuthorizationPlan {
        return self.planOptionsWithAccountProvider(options, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn planRequestWithAccountProvider(
        self: *const SuiRpcClient,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
    ) tx_request_builder.AuthorizationPlan {
        _ = self;
        return tx_request_builder.authorizationPlanFromRequest(request, provider);
    }

    pub fn planRequestFromDefaultKeystore(
        self: *const SuiRpcClient,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
    ) tx_request_builder.AuthorizationPlan {
        return self.planRequestWithAccountProvider(request, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn planCommandsWithAccountProvider(
        self: *const SuiRpcClient,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) tx_request_builder.AuthorizationPlan {
        _ = self;
        return tx_request_builder.authorizationPlanFromCommandSource(source, config, provider);
    }

    pub fn planCommandsFromDefaultKeystore(
        self: *const SuiRpcClient,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
    ) tx_request_builder.AuthorizationPlan {
        return self.planCommandsWithAccountProvider(source, config, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn ownedPlanOptionsWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) !tx_request_builder.OwnedAuthorizationPlan {
        _ = self;
        return (try tx_request_builder.ownOptions(allocator, options)).authorizationPlan(provider);
    }

    pub fn ownedPlanRequestWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
    ) !tx_request_builder.OwnedAuthorizationPlan {
        _ = self;
        return (try tx_request_builder.ownRequest(allocator, request)).authorizationPlan(provider);
    }

    pub fn ownedPlanCommandsWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) !tx_request_builder.OwnedAuthorizationPlan {
        _ = self;
        return (try tx_request_builder.ownOptionsFromCommandSource(allocator, source, config)).authorizationPlan(provider);
    }

    pub fn ownedPlanOptionsFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
    ) !tx_request_builder.OwnedAuthorizationPlan {
        return try self.ownedPlanOptionsWithAccountProvider(allocator, options, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn ownedPlanRequestFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
    ) !tx_request_builder.OwnedAuthorizationPlan {
        return try self.ownedPlanRequestWithAccountProvider(allocator, request, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn ownedPlanCommandsFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
    ) !tx_request_builder.OwnedAuthorizationPlan {
        return try self.ownedPlanCommandsWithAccountProvider(allocator, source, config, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn authorizePlan(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        _ = self;
        return try plan.authorize(allocator);
    }

    pub fn buildPlanArtifact(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        _ = self;
        return try plan.buildArtifact(allocator, kind);
    }

    pub fn runPlan(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return switch (action) {
            .authorize => .{ .authorized = try self.authorizePlan(allocator, plan) },
            .inspect => .{ .inspected = try self.inspectPlan(allocator, plan) },
            .execute => .{ .executed = try self.executePlan(allocator, plan) },
            .execute_confirm => |value| .{
                .executed = try self.executePlanAndConfirm(allocator, plan, value.timeout_ms, value.poll_ms),
            },
            .build_artifact => |kind| .{ .artifact = try self.buildPlanArtifact(allocator, plan, kind) },
        };
    }

    pub fn authorizePlanOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
    ) !AuthorizeOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .authorized = try self.authorizePlan(allocator, plan) };
    }

    pub fn buildPlanArtifactOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .artifact = try self.buildPlanArtifact(allocator, plan, kind) };
    }

    pub fn runPlanOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .completed = try self.runPlan(allocator, plan, action) };
    }

    pub fn inspectPlan(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
    ) ![]u8 {
        var prepared = try self.authorizePlan(allocator, plan);
        defer prepared.deinit(allocator);
        return try self.inspectAuthorizedPreparedRequest(allocator, &prepared);
    }

    pub fn inspectPlanOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
    ) !InspectOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .inspected = try self.inspectPlan(allocator, plan) };
    }

    pub fn executePlan(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
    ) ![]u8 {
        var prepared = try self.authorizePlan(allocator, plan);
        defer prepared.deinit(allocator);
        return try self.executeAuthorizedPreparedRequest(allocator, &prepared);
    }

    pub fn executePlanAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var confirmed_plan = plan;
        confirmed_plan.options.wait_for_confirmation = true;
        confirmed_plan.options.confirm_timeout_ms = timeout_ms;
        confirmed_plan.options.confirm_poll_ms = poll_ms;
        return try self.executePlan(allocator, confirmed_plan);
    }

    pub fn executePlanOrChallengeText(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
    ) !ExecuteOrChallengeTextResult {
        if (try plan.challengeText(allocator)) |text| {
            return .{ .challenge_required = text };
        }
        return .{ .executed = try self.executePlan(allocator, plan) };
    }

    pub fn executePlanOrChallengeTextAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengeTextResult {
        if (try plan.challengeText(allocator)) |text| {
            return .{ .challenge_required = text };
        }
        return .{ .executed = try self.executePlanAndConfirm(allocator, plan, timeout_ms, poll_ms) };
    }

    pub fn executePlanOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
    ) !ExecuteOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .executed = try self.executePlan(allocator, plan) };
    }

    pub fn executePlanOrChallengePromptAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .executed = try self.executePlanAndConfirm(allocator, plan, timeout_ms, poll_ms) };
    }

    pub fn authorizePlanWithChallengeResponse(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizePlan(allocator, try plan.withChallengeResponse(response));
    }

    pub fn buildPlanArtifactWithChallengeResponse(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildPlanArtifact(allocator, try plan.withChallengeResponse(response), kind);
    }

    pub fn runPlanWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runPlan(allocator, try plan.withChallengeResponse(response), action);
    }

    pub fn inspectPlanWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        return try self.inspectPlan(allocator, try plan.withChallengeResponse(response));
    }

    pub fn executePlanWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        return try self.executePlan(allocator, try plan.withChallengeResponse(response));
    }

    pub fn executePlanWithChallengeResponseAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: tx_request_builder.AuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        return try self.executePlanAndConfirm(
            allocator,
            try plan.withChallengeResponse(response),
            timeout_ms,
            poll_ms,
        );
    }

    pub fn inspectOwnedPlan(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
    ) ![]u8 {
        var prepared = try plan.authorize(allocator);
        defer prepared.deinit(allocator);
        return try self.inspectAuthorizedPreparedRequest(allocator, &prepared);
    }

    pub fn authorizeOwnedPlan(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        _ = self;
        return try plan.authorize(allocator);
    }

    pub fn buildOwnedPlanArtifact(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        _ = self;
        return try plan.buildArtifact(allocator, kind);
    }

    pub fn runOwnedPlan(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return switch (action) {
            .authorize => .{ .authorized = try self.authorizeOwnedPlan(allocator, plan) },
            .inspect => .{ .inspected = try self.inspectOwnedPlan(allocator, plan) },
            .execute => .{ .executed = try self.executeOwnedPlan(allocator, plan) },
            .execute_confirm => |value| .{
                .executed = try self.executeOwnedPlanAndConfirm(allocator, plan, value.timeout_ms, value.poll_ms),
            },
            .build_artifact => |kind| .{ .artifact = try self.buildOwnedPlanArtifact(allocator, plan, kind) },
        };
    }

    pub fn authorizeOwnedPlanOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
    ) !AuthorizeOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.owned_options.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .authorized = try self.authorizeOwnedPlan(allocator, plan) };
    }

    pub fn buildOwnedPlanArtifactOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.owned_options.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .artifact = try self.buildOwnedPlanArtifact(allocator, plan, kind) };
    }

    pub fn runOwnedPlanOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.owned_options.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .completed = try self.runOwnedPlan(allocator, plan, action) };
    }

    pub fn inspectOwnedPlanOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
    ) !InspectOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.owned_options.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .inspected = try self.inspectOwnedPlan(allocator, plan) };
    }

    pub fn executeOwnedPlan(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
    ) ![]u8 {
        var prepared = try plan.authorize(allocator);
        defer prepared.deinit(allocator);
        return try self.executeAuthorizedPreparedRequest(allocator, &prepared);
    }

    pub fn executeOwnedPlanAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var confirmed_plan = plan.plan();
        confirmed_plan.options.wait_for_confirmation = true;
        confirmed_plan.options.confirm_timeout_ms = timeout_ms;
        confirmed_plan.options.confirm_poll_ms = poll_ms;
        return try self.executePlan(allocator, confirmed_plan);
    }

    pub fn executeOwnedPlanOrChallengeText(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
    ) !ExecuteOrChallengeTextResult {
        if (try plan.challengeText(allocator)) |text| {
            return .{ .challenge_required = text };
        }
        return .{ .executed = try self.executeOwnedPlan(allocator, plan) };
    }

    pub fn executeOwnedPlanOrChallengeTextAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengeTextResult {
        if (try plan.challengeText(allocator)) |text| {
            return .{ .challenge_required = text };
        }
        return .{ .executed = try self.executeOwnedPlanAndConfirm(allocator, plan, timeout_ms, poll_ms) };
    }

    pub fn executeOwnedPlanOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
    ) !ExecuteOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.owned_options.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .executed = try self.executeOwnedPlan(allocator, plan) };
    }

    pub fn executeOwnedPlanOrChallengePromptAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *const tx_request_builder.OwnedAuthorizationPlan,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        if (try self.getOwnedSessionChallengePrompt(allocator, plan.owned_options.options, plan.provider)) |prompt| {
            return .{ .challenge_required = prompt };
        }
        return .{ .executed = try self.executeOwnedPlanAndConfirm(allocator, plan, timeout_ms, poll_ms) };
    }

    pub fn executeOwnedPlanWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *tx_request_builder.OwnedAuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        try plan.withChallengeResponse(response);
        return try self.executeOwnedPlan(allocator, plan);
    }

    pub fn inspectOwnedPlanWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *tx_request_builder.OwnedAuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        try plan.withChallengeResponse(response);
        return try self.inspectOwnedPlan(allocator, plan);
    }

    pub fn executeOwnedPlanWithChallengeResponseAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *tx_request_builder.OwnedAuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        try plan.withChallengeResponse(response);
        return try self.executeOwnedPlanAndConfirm(allocator, plan, timeout_ms, poll_ms);
    }

    pub fn authorizeOwnedPlanWithChallengeResponse(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *tx_request_builder.OwnedAuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        try plan.withChallengeResponse(response);
        return try self.authorizeOwnedPlan(allocator, plan);
    }

    pub fn buildOwnedPlanArtifactWithChallengeResponse(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *tx_request_builder.OwnedAuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        try plan.withChallengeResponse(response);
        return try self.buildOwnedPlanArtifact(allocator, plan, kind);
    }

    pub fn runOwnedPlanWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        plan: *tx_request_builder.OwnedAuthorizationPlan,
        response: tx_request_builder.SessionChallengeResponse,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        try plan.withChallengeResponse(response);
        return try self.runOwnedPlan(allocator, plan, action);
    }

    pub fn authorizeDslBuilder(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        _ = self;
        return try builder.authorize(allocator, provider);
    }

    pub fn buildDslBuilderArtifact(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        _ = self;
        return try builder.buildArtifact(allocator, provider, kind);
    }

    pub fn runDslBuilder(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return switch (action) {
            .authorize => .{ .authorized = try self.authorizeDslBuilder(allocator, builder, provider) },
            .inspect => .{ .inspected = try self.inspectDslBuilder(allocator, builder, provider) },
            .execute => .{ .executed = try self.executeDslBuilder(allocator, builder, provider) },
            .execute_confirm => |value| .{
                .executed = try self.executeDslBuilderAndConfirm(
                    allocator,
                    builder,
                    provider,
                    value.timeout_ms,
                    value.poll_ms,
                ),
            },
            .build_artifact => |kind| .{ .artifact = try self.buildDslBuilderArtifact(allocator, builder, provider, kind) },
        };
    }

    pub fn authorizeDslBuilderOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
    ) !AuthorizeOrChallengePromptResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.authorizeOwnedPlanOrChallengePrompt(allocator, &plan);
    }

    pub fn buildDslBuilderArtifactOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.buildOwnedPlanArtifactOrChallengePrompt(allocator, &plan, kind);
    }

    pub fn runDslBuilderOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.runOwnedPlanOrChallengePrompt(allocator, &plan, action);
    }

    pub fn inspectDslBuilder(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        var prepared = try self.authorizeDslBuilder(allocator, builder, provider);
        defer prepared.deinit(allocator);
        return try self.inspectAuthorizedPreparedRequest(allocator, &prepared);
    }

    pub fn inspectDslBuilderOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
    ) !InspectOrChallengePromptResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.inspectOwnedPlanOrChallengePrompt(allocator, &plan);
    }

    pub fn executeDslBuilder(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        var prepared = try self.authorizeDslBuilder(allocator, builder, provider);
        defer prepared.deinit(allocator);
        return try self.executeAuthorizedPreparedRequest(allocator, &prepared);
    }

    pub fn executeDslBuilderAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.executeOwnedPlanAndConfirm(allocator, &plan, timeout_ms, poll_ms);
    }

    pub fn executeDslBuilderOrChallengeText(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
    ) !ExecuteOrChallengeTextResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.executeOwnedPlanOrChallengeText(allocator, &plan);
    }

    pub fn executeDslBuilderOrChallengeTextAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengeTextResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.executeOwnedPlanOrChallengeTextAndConfirm(
            allocator,
            &plan,
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeDslBuilderOrChallengePrompt(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
    ) !ExecuteOrChallengePromptResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.executeOwnedPlanOrChallengePrompt(allocator, &plan);
    }

    pub fn executeDslBuilderOrChallengePromptAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.executeOwnedPlanOrChallengePromptAndConfirm(
            allocator,
            &plan,
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeDslBuilderWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.executeOwnedPlanWithChallengeResponse(allocator, &plan, response);
    }

    pub fn inspectDslBuilderWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.inspectOwnedPlanWithChallengeResponse(allocator, &plan, response);
    }

    pub fn authorizeDslBuilderWithChallengeResponse(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.authorizeOwnedPlanWithChallengeResponse(allocator, &plan, response);
    }

    pub fn buildDslBuilderArtifactWithChallengeResponse(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.buildOwnedPlanArtifactWithChallengeResponse(allocator, &plan, response, kind);
    }

    pub fn runDslBuilderWithChallengeResponse(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.runOwnedPlanWithChallengeResponse(allocator, &plan, response, action);
    }

    pub fn executeDslBuilderWithChallengeResponseAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        builder: *tx_request_builder.ProgrammaticDslBuilder,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var plan = try builder.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try self.executeOwnedPlanWithChallengeResponseAndConfirm(
            allocator,
            &plan,
            response,
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeOptionsAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var confirmed_options = options;
        confirmed_options.wait_for_confirmation = true;
        confirmed_options.confirm_timeout_ms = timeout_ms;
        confirmed_options.confirm_poll_ms = poll_ms;
        return try self.executeOptions(allocator, confirmed_options);
    }

    pub fn executeOptionsAndConfirmFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var confirmed_options = options;
        confirmed_options.wait_for_confirmation = true;
        confirmed_options.confirm_timeout_ms = timeout_ms;
        confirmed_options.confirm_poll_ms = poll_ms;
        return try self.executeOptionsFromDefaultKeystore(allocator, confirmed_options, preparation);
    }

    pub fn executeOptionsAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var confirmed_options = options;
        confirmed_options.wait_for_confirmation = true;
        confirmed_options.confirm_timeout_ms = timeout_ms;
        confirmed_options.confirm_poll_ms = poll_ms;
        return try self.executeOptionsWithAccountProvider(allocator, confirmed_options, provider);
    }

    pub fn executeRequestAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var confirmed_request = request;
        confirmed_request.wait_for_confirmation = true;
        confirmed_request.confirm_timeout_ms = timeout_ms;
        confirmed_request.confirm_poll_ms = poll_ms;
        return try self.executeRequest(allocator, confirmed_request);
    }

    pub fn executeRequestAndConfirmFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var confirmed_request = request;
        confirmed_request.wait_for_confirmation = true;
        confirmed_request.confirm_timeout_ms = timeout_ms;
        confirmed_request.confirm_poll_ms = poll_ms;
        return try self.executeRequestFromDefaultKeystore(allocator, confirmed_request, preparation);
    }

    pub fn executeRequestAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        var confirmed_request = request;
        confirmed_request.wait_for_confirmation = true;
        confirmed_request.confirm_timeout_ms = timeout_ms;
        confirmed_request.confirm_poll_ms = poll_ms;
        return try self.executeRequestWithAccountProvider(allocator, confirmed_request, provider);
    }

    pub fn authorizeOptionsWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        _ = self;
        return try tx_request_builder.prepareAuthorizedRequest(allocator, options, provider);
    }

    pub fn authorizeOptionsWithChallengeResponseWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizePlanWithChallengeResponse(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            response,
        );
    }

    pub fn authorizeOptionsOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) !AuthorizeOrChallengePromptResult {
        return try self.authorizePlanOrChallengePrompt(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
        );
    }

    pub fn buildOptionsArtifactWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildPlanArtifact(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            kind,
        );
    }

    pub fn buildOptionsArtifactOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        return try self.buildPlanArtifactOrChallengePrompt(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            kind,
        );
    }

    pub fn runOptionsWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runPlan(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            action,
        );
    }

    pub fn runOptionsOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        return try self.runPlanOrChallengePrompt(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            action,
        );
    }

    pub fn inspectOptionsOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) !InspectOrChallengePromptResult {
        return try self.inspectPlanOrChallengePrompt(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
        );
    }

    pub fn inspectOptionsWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        return try self.inspectPlanWithChallengeResponse(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            response,
        );
    }

    pub fn buildOptionsArtifactWithChallengeResponseWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildPlanArtifactWithChallengeResponse(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            response,
            kind,
        );
    }

    pub fn runOptionsWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runPlanWithChallengeResponse(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            response,
            action,
        );
    }

    pub fn buildOptionsArtifactFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildOptionsArtifactWithAccountProvider(
            allocator,
            options,
            .{ .default_keystore = .{ .preparation = preparation } },
            kind,
        );
    }

    pub fn buildOptionsArtifactOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        return try self.buildOptionsArtifactOrChallengePromptWithAccountProvider(
            allocator,
            options,
            .{ .default_keystore = .{ .preparation = preparation } },
            kind,
        );
    }

    pub fn runOptionsFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runOptionsWithAccountProvider(
            allocator,
            options,
            .{ .default_keystore = .{ .preparation = preparation } },
            action,
        );
    }

    pub fn runOptionsOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        return try self.runOptionsOrChallengePromptWithAccountProvider(
            allocator,
            options,
            .{ .default_keystore = .{ .preparation = preparation } },
            action,
        );
    }

    pub fn inspectOptionsOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
    ) !InspectOrChallengePromptResult {
        return try self.inspectOptionsOrChallengePromptWithAccountProvider(allocator, options, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn executeOptionsOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) !ExecuteOrChallengePromptResult {
        return try self.executePlanOrChallengePrompt(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
        );
    }

    pub fn executeOptionsOrChallengePromptAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        return try self.executePlanOrChallengePromptAndConfirm(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeOptionsWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        return try self.executePlanWithChallengeResponse(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            response,
        );
    }

    pub fn executeOptionsWithChallengeResponseAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        return try self.executePlanWithChallengeResponseAndConfirm(
            allocator,
            self.planOptionsWithAccountProvider(options, provider),
            response,
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeOptionsOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
    ) !ExecuteOrChallengePromptResult {
        return try self.executeOptionsOrChallengePromptWithAccountProvider(allocator, options, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn executeOptionsOrChallengePromptAndConfirmFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        return try self.executeOptionsOrChallengePromptAndConfirmWithAccountProvider(
            allocator,
            options,
            .{ .default_keystore = .{ .preparation = preparation } },
            timeout_ms,
            poll_ms,
        );
    }

    pub fn authorizeOptionsFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizeOptionsWithAccountProvider(allocator, options, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn authorizeOptionsOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
    ) !AuthorizeOrChallengePromptResult {
        return try self.authorizeOptionsOrChallengePromptWithAccountProvider(allocator, options, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn authorizeRequestWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizeOptionsWithAccountProvider(
            allocator,
            tx_request_builder.optionsFromRequest(request),
            provider,
        );
    }

    pub fn authorizeRequestWithChallengeResponseWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizePlanWithChallengeResponse(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            response,
        );
    }

    pub fn authorizeRequestOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
    ) !AuthorizeOrChallengePromptResult {
        return try self.authorizePlanOrChallengePrompt(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
        );
    }

    pub fn buildRequestArtifactWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildPlanArtifact(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            kind,
        );
    }

    pub fn buildRequestArtifactOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        return try self.buildPlanArtifactOrChallengePrompt(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            kind,
        );
    }

    pub fn runRequestWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runPlan(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            action,
        );
    }

    pub fn runRequestOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        return try self.runPlanOrChallengePrompt(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            action,
        );
    }

    pub fn inspectRequestOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
    ) !InspectOrChallengePromptResult {
        return try self.inspectPlanOrChallengePrompt(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
        );
    }

    pub fn inspectRequestWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        return try self.inspectPlanWithChallengeResponse(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            response,
        );
    }

    pub fn buildRequestArtifactWithChallengeResponseWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildPlanArtifactWithChallengeResponse(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            response,
            kind,
        );
    }

    pub fn runRequestWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runPlanWithChallengeResponse(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            response,
            action,
        );
    }

    pub fn buildRequestArtifactFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildRequestArtifactWithAccountProvider(
            allocator,
            request,
            .{ .default_keystore = .{ .preparation = preparation } },
            kind,
        );
    }

    pub fn buildRequestArtifactOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        return try self.buildRequestArtifactOrChallengePromptWithAccountProvider(
            allocator,
            request,
            .{ .default_keystore = .{ .preparation = preparation } },
            kind,
        );
    }

    pub fn runRequestFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runRequestWithAccountProvider(
            allocator,
            request,
            .{ .default_keystore = .{ .preparation = preparation } },
            action,
        );
    }

    pub fn runRequestOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        return try self.runRequestOrChallengePromptWithAccountProvider(
            allocator,
            request,
            .{ .default_keystore = .{ .preparation = preparation } },
            action,
        );
    }

    pub fn inspectRequestOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
    ) !InspectOrChallengePromptResult {
        return try self.inspectRequestOrChallengePromptWithAccountProvider(allocator, request, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn executeRequestOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
    ) !ExecuteOrChallengePromptResult {
        return try self.executePlanOrChallengePrompt(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
        );
    }

    pub fn executeRequestOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
    ) !ExecuteOrChallengePromptResult {
        return try self.executeRequestOrChallengePromptWithAccountProvider(allocator, request, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn executeRequestOrChallengePromptAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        return try self.executePlanOrChallengePromptAndConfirm(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeRequestWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        return try self.executePlanWithChallengeResponse(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            response,
        );
    }

    pub fn executeRequestWithChallengeResponseAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        return try self.executePlanWithChallengeResponseAndConfirm(
            allocator,
            self.planRequestWithAccountProvider(request, provider),
            response,
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeRequestOrChallengePromptAndConfirmFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        return try self.executeRequestOrChallengePromptAndConfirmWithAccountProvider(
            allocator,
            request,
            .{ .default_keystore = .{ .preparation = preparation } },
            timeout_ms,
            poll_ms,
        );
    }

    pub fn authorizeRequestFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizeRequestWithAccountProvider(allocator, request, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn authorizeRequestOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
    ) !AuthorizeOrChallengePromptResult {
        return try self.authorizeRequestOrChallengePromptWithAccountProvider(allocator, request, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn authorizeCommandsWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizeOptionsWithAccountProvider(
            allocator,
            tx_request_builder.optionsFromCommandSource(source, config),
            provider,
        );
    }

    pub fn authorizeCommandsWithChallengeResponseWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizePlanWithChallengeResponse(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            response,
        );
    }

    pub fn authorizeCommandsOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) !AuthorizeOrChallengePromptResult {
        return try self.authorizePlanOrChallengePrompt(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
        );
    }

    pub fn buildCommandsArtifactWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildPlanArtifact(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            kind,
        );
    }

    pub fn buildCommandsArtifactOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        return try self.buildPlanArtifactOrChallengePrompt(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            kind,
        );
    }

    pub fn runCommandsWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runPlan(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            action,
        );
    }

    pub fn runCommandsOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        return try self.runPlanOrChallengePrompt(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            action,
        );
    }

    pub fn authorizeCommandsFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
    ) !tx_request_builder.AuthorizedPreparedRequest {
        return try self.authorizeCommandsWithAccountProvider(allocator, source, config, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn authorizeCommandsOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
    ) !AuthorizeOrChallengePromptResult {
        return try self.authorizeCommandsOrChallengePromptWithAccountProvider(allocator, source, config, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn inspectOptions(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
    ) ![]u8 {
        var prepared = try tx_request_builder.prepareRequest(allocator, options);
        defer prepared.deinit(allocator);
        return try self.inspectPreparedRequest(allocator, &prepared);
    }

    pub fn executeOptions(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
    ) ![]u8 {
        var prepared = try tx_request_builder.prepareRequest(allocator, options);
        defer prepared.deinit(allocator);
        return try self.executePreparedRequest(allocator, &prepared);
    }

    pub fn inspectOptionsWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        var prepared = try self.authorizeOptionsWithAccountProvider(allocator, options, provider);
        defer prepared.deinit(allocator);
        return try self.inspectAuthorizedPreparedRequest(allocator, &prepared);
    }

    pub fn executeOptionsWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        var prepared = try self.authorizeOptionsWithAccountProvider(allocator, options, provider);
        defer prepared.deinit(allocator);
        return try self.executeAuthorizedPreparedRequest(allocator, &prepared);
    }

    pub fn getSessionChallengeRequest(
        self: *const SuiRpcClient,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) ?tx_request_builder.SessionChallengeRequest {
        _ = self;
        return tx_request_builder.sessionChallengeRequest(options, provider);
    }

    pub fn buildSessionChallengeText(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) !?[]u8 {
        const request = self.getSessionChallengeRequest(options, provider) orelse return null;
        return try tx_request_builder.buildSessionChallengeText(allocator, request);
    }

    pub fn getOwnedSessionChallengePrompt(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        provider: tx_request_builder.AccountProvider,
    ) !?OwnedSessionChallengePrompt {
        const request = self.getSessionChallengeRequest(options, provider) orelse return null;
        const text = (try tx_request_builder.buildSessionChallengeText(allocator, request)).?;
        return try buildOwnedSessionChallengePrompt(allocator, request, text);
    }

    pub fn applySessionChallengeResponse(
        self: *const SuiRpcClient,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) !tx_request_builder.AccountProvider {
        _ = self;
        return try tx_request_builder.applySessionChallengeResponse(provider, response);
    }

    pub fn inspectOptionsFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
    ) ![]u8 {
        return try self.inspectOptionsWithAccountProvider(allocator, options, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn executeOptionsFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        options: tx_request_builder.ProgrammaticRequestOptions,
        preparation: keystore.SignerPreparation,
    ) ![]u8 {
        return try self.executeOptionsWithAccountProvider(allocator, options, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn inspectRequestWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        return try self.inspectOptionsWithAccountProvider(
            allocator,
            tx_request_builder.optionsFromRequest(request),
            provider,
        );
    }

    pub fn executeRequestWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        return try self.executeOptionsWithAccountProvider(
            allocator,
            tx_request_builder.optionsFromRequest(request),
            provider,
        );
    }

    pub fn inspectRequestFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
    ) ![]u8 {
        return try self.inspectRequestWithAccountProvider(
            allocator,
            request,
            .{ .default_keystore = .{ .preparation = preparation } },
        );
    }

    pub fn executeRequestFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        request: tx_builder.ProgrammaticTxRequest,
        preparation: keystore.SignerPreparation,
    ) ![]u8 {
        return try self.executeRequestWithAccountProvider(
            allocator,
            request,
            .{ .default_keystore = .{ .preparation = preparation } },
        );
    }

    pub fn inspectCommands(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        sender: ?[]const u8,
        gas_budget: ?u64,
        gas_price: ?u64,
        options_json: ?[]const u8,
    ) ![]u8 {
        return try self.inspectOptions(allocator, tx_request_builder.optionsFromCommandSource(source, .{
            .sender = sender,
            .gas_budget = gas_budget,
            .gas_price = gas_price,
            .options_json = options_json,
        }));
    }

    pub fn inspectCommandsFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        sender: ?[]const u8,
        gas_budget: ?u64,
        gas_price: ?u64,
        options_json: ?[]const u8,
        preparation: keystore.SignerPreparation,
    ) ![]u8 {
        return try self.inspectOptionsFromDefaultKeystore(allocator, tx_request_builder.optionsFromCommandSource(source, .{
            .sender = sender,
            .gas_budget = gas_budget,
            .gas_price = gas_price,
            .options_json = options_json,
        }), preparation);
    }

    pub fn inspectCommandsWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        return try self.inspectOptionsWithAccountProvider(
            allocator,
            tx_request_builder.optionsFromCommandSource(source, config),
            provider,
        );
    }

    pub fn executeCommands(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        sender: ?[]const u8,
        gas_budget: ?u64,
        gas_price: ?u64,
        signatures: []const []const u8,
        options_json: ?[]const u8,
    ) ![]u8 {
        return try self.executeOptions(allocator, tx_request_builder.optionsFromCommandSource(source, .{
            .sender = sender,
            .gas_budget = gas_budget,
            .gas_price = gas_price,
            .signatures = signatures,
            .options_json = options_json,
        }));
    }

    pub fn executeCommandsFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        sender: ?[]const u8,
        gas_budget: ?u64,
        gas_price: ?u64,
        options_json: ?[]const u8,
        preparation: keystore.SignerPreparation,
    ) ![]u8 {
        return try self.executeOptionsFromDefaultKeystore(allocator, tx_request_builder.optionsFromCommandSource(source, .{
            .sender = sender,
            .gas_budget = gas_budget,
            .gas_price = gas_price,
            .options_json = options_json,
        }), preparation);
    }

    pub fn executeCommandsWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        return try self.executeOptionsWithAccountProvider(
            allocator,
            tx_request_builder.optionsFromCommandSource(source, config),
            provider,
        );
    }

    pub fn executeCommandsAndConfirm(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        sender: ?[]const u8,
        gas_budget: ?u64,
        gas_price: ?u64,
        signatures: []const []const u8,
        options_json: ?[]const u8,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        return try self.executeOptions(allocator, tx_request_builder.optionsFromCommandSource(source, .{
            .sender = sender,
            .gas_budget = gas_budget,
            .gas_price = gas_price,
            .signatures = signatures,
            .options_json = options_json,
            .wait_for_confirmation = true,
            .confirm_timeout_ms = timeout_ms,
            .confirm_poll_ms = poll_ms,
        }));
    }

    pub fn executeCommandsAndConfirmFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        sender: ?[]const u8,
        gas_budget: ?u64,
        gas_price: ?u64,
        options_json: ?[]const u8,
        timeout_ms: u64,
        poll_ms: u64,
        preparation: keystore.SignerPreparation,
    ) ![]u8 {
        return try self.executeOptionsFromDefaultKeystore(allocator, tx_request_builder.optionsFromCommandSource(source, .{
            .sender = sender,
            .gas_budget = gas_budget,
            .gas_price = gas_price,
            .options_json = options_json,
            .wait_for_confirmation = true,
            .confirm_timeout_ms = timeout_ms,
            .confirm_poll_ms = poll_ms,
        }), preparation);
    }

    pub fn executeCommandsAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) ![]u8 {
        var confirmed_config = config;
        confirmed_config.wait_for_confirmation = true;
        return try self.executeOptionsWithAccountProvider(
            allocator,
            tx_request_builder.optionsFromCommandSource(source, confirmed_config),
            provider,
        );
    }

    pub fn inspectCommandsOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) !InspectOrChallengePromptResult {
        return try self.inspectPlanOrChallengePrompt(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
        );
    }

    pub fn inspectCommandsWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        return try self.inspectPlanWithChallengeResponse(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            response,
        );
    }

    pub fn buildCommandsArtifactWithChallengeResponseWithAccountProvider(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildPlanArtifactWithChallengeResponse(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            response,
            kind,
        );
    }

    pub fn runCommandsWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runPlanWithChallengeResponse(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            response,
            action,
        );
    }

    pub fn buildCommandsArtifactFromDefaultKeystore(
        self: *const SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.buildCommandsArtifactWithAccountProvider(
            allocator,
            source,
            config,
            .{ .default_keystore = .{ .preparation = preparation } },
            kind,
        );
    }

    pub fn buildCommandsArtifactOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
        kind: tx_request_builder.ProgrammaticArtifactKind,
    ) !ArtifactOrChallengePromptResult {
        return try self.buildCommandsArtifactOrChallengePromptWithAccountProvider(
            allocator,
            source,
            config,
            .{ .default_keystore = .{ .preparation = preparation } },
            kind,
        );
    }

    pub fn runCommandsFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionResult {
        return try self.runCommandsWithAccountProvider(
            allocator,
            source,
            config,
            .{ .default_keystore = .{ .preparation = preparation } },
            action,
        );
    }

    pub fn runCommandsOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
        action: ProgrammaticClientAction,
    ) !ProgrammaticClientActionOrChallengePromptResult {
        return try self.runCommandsOrChallengePromptWithAccountProvider(
            allocator,
            source,
            config,
            .{ .default_keystore = .{ .preparation = preparation } },
            action,
        );
    }

    pub fn inspectCommandsOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
    ) !InspectOrChallengePromptResult {
        return try self.inspectCommandsOrChallengePromptWithAccountProvider(allocator, source, config, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn executeCommandsOrChallengePromptWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
    ) !ExecuteOrChallengePromptResult {
        return try self.executePlanOrChallengePrompt(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
        );
    }

    pub fn executeCommandsOrChallengePromptFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
    ) !ExecuteOrChallengePromptResult {
        return try self.executeCommandsOrChallengePromptWithAccountProvider(allocator, source, config, .{
            .default_keystore = .{ .preparation = preparation },
        });
    }

    pub fn executeCommandsOrChallengePromptAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        return try self.executePlanOrChallengePromptAndConfirm(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeCommandsWithChallengeResponseWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
    ) ![]u8 {
        return try self.executePlanWithChallengeResponse(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            response,
        );
    }

    pub fn executeCommandsWithChallengeResponseAndConfirmWithAccountProvider(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        provider: tx_request_builder.AccountProvider,
        response: tx_request_builder.SessionChallengeResponse,
        timeout_ms: u64,
        poll_ms: u64,
    ) ![]u8 {
        return try self.executePlanWithChallengeResponseAndConfirm(
            allocator,
            self.planCommandsWithAccountProvider(source, config, provider),
            response,
            timeout_ms,
            poll_ms,
        );
    }

    pub fn executeCommandsOrChallengePromptAndConfirmFromDefaultKeystore(
        self: *SuiRpcClient,
        allocator: std.mem.Allocator,
        source: tx_builder.CommandSource,
        config: tx_request_builder.CommandRequestConfig,
        preparation: keystore.SignerPreparation,
        timeout_ms: u64,
        poll_ms: u64,
    ) !ExecuteOrChallengePromptResult {
        return try self.executeCommandsOrChallengePromptAndConfirmWithAccountProvider(
            allocator,
            source,
            config,
            .{ .default_keystore = .{ .preparation = preparation } },
            timeout_ms,
            poll_ms,
        );
    }
};

// Keep compatibility for external code that expects this helper name.
pub fn sendRequestFrom(self: *SuiRpcClient, method: []const u8, params_json: []const u8) ![]u8 {
    return try self.call(method, params_json);
}

test "sendRequestFrom uses request_sender callback and validates request payload" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_match = false;
    var params_match = false;
    var body_match = false;
    var request_id: u64 = 0;

    const MockContext = struct {
        saw_request: *bool,
        method_match: *bool,
        params_match: *bool,
        body_match: *bool,
        request_id: *u64,
        method: []const u8,
        params: []const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: struct {
            id: u64,
            method: []const u8,
            params_json: []const u8,
            request_body: []const u8,
        }) ![]u8 {
            const mock_ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            mock_ctx.saw_request.* = true;
            mock_ctx.method_match.* = std.mem.eql(u8, req.method, mock_ctx.method);
            mock_ctx.params_match.* = std.mem.eql(u8, req.params_json, mock_ctx.params);
            mock_ctx.body_match.* = std.mem.eql(u8, req.request_body, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"rpc.method\",\"params\":[1,2]}");
            mock_ctx.request_id.* = req.id;
            return alloc.dupe(u8, "{\"result\":{\"ok\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_match = &method_match,
        .params_match = &params_match,
        .body_match = &body_match,
        .request_id = &request_id,
        .method = "rpc.method",
        .params = "[1,2]",
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try sendRequestFrom(&client_instance, "rpc.method", "[1,2]");
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_match);
    try testing.expect(params_match);
    try testing.expect(body_match);
    try testing.expectEqual(@as(u64, 1), request_id);
    try testing.expectEqualStrings("{\"result\":{\"ok\":true}}", response);
}

test "call stores rpc error details when rpc returns error object" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: struct {
            id: u64,
            method: []const u8,
            params_json: []const u8,
            request_body: []const u8,
        }) ![]u8 {
            _ = context;
            _ = req;
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"internal error\"},\"id\":99}");
        }
    }.call;

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = undefined,
        .callback = callback,
    };

    try testing.expectError(error.RpcError, client_instance.call("rpc.failure", "[]"));

    const last_error = client_instance.getLastError() orelse return error.TestExpectedError;
    try testing.expectEqual(@as(i64, -32603), last_error.code orelse 0);
    try testing.expectEqualStrings("internal error", last_error.message);
}

test "inspectCommands builds inspect payload from command source" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.inspectCommands(
        allocator,
        .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        "0xabc",
        1000,
        7,
        "{\"skipChecks\":true}",
    );
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);

    const params = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expectEqual(@as(usize, 2), params.value.array.items.len);
}

test "inspectOptions builds inspect payload from generic request options" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.inspectOptions(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .sender = "0xabc",
        .gas_budget = 1000,
        .gas_price = 7,
        .options_json = "{\"skipChecks\":true}",
    });
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);

    const params = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expectEqual(@as(usize, 2), params.value.array.items.len);
}

test "inspectOptionsWithAccountProvider supports zklogin-like sessions for inspect" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.inspectOptionsWithAccountProvider(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .zklogin = .{
            .address = "0xzk",
            .session = .{ .kind = .zklogin, .session_id = "oauth-session", .user_id = "user-1" },
        },
    });
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xzk") != null);
}

test "planCommandsWithAccountProvider returns challenge-ready authorization plans" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{
            .gas_budget = 55,
        },
        .{
            .zklogin = .{
                .address = "0xzk",
                .session = .{ .kind = .zklogin, .session_id = "oauth-session" },
                .session_challenge = .{
                    .zklogin_nonce = .{
                        .nonce = "nonce-456",
                        .provider = "google",
                    },
                },
                .session_action = .cloud_agent_access,
            },
        },
    );

    const request = plan.challengeRequest() orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("0xzk", request.account_address.?);
    try testing.expectEqual(@as(?u64, 55), request.options.gas_budget);
    try testing.expectEqual(tx_request_builder.SessionChallengeAction.cloud_agent_access, request.action);

    const text = try plan.challengeText(allocator);
    defer if (text) |value| allocator.free(value);
    try testing.expect(text != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "zkLogin nonce challenge") != null);
}

test "authorizeOptionsWithAccountProvider returns executable prepared requests for passkey providers" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("0xpasskey", req.account_address.?);
            try testing.expectEqualStrings("session-1", req.account_session.session_id.?);
            return .{
                .sender = "0xprepared",
                .signatures = &.{"sig-prepared"},
                .session = req.account_session,
            };
        }
    }.call;

    var prepared = try client_instance.authorizeOptionsWithAccountProvider(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .passkey = .{
            .address = "0xpasskey",
            .session = .{ .kind = .passkey, .session_id = "session-1" },
            .authorizer = .{
                .context = undefined,
                .callback = authorizer,
            },
            .session_supports_execute = true,
        },
    });
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xprepared", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-prepared", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(tx_request_builder.AccountSessionKind.passkey, prepared.session.kind);
    try testing.expect(prepared.supports_execute);
}

test "authorizeOptionsWithChallengeResponseWithAccountProvider applies challenge response before authorization" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("approved-passkey-session", req.account_session.session_id.?);
            return .{
                .sender = "0xapproved-passkey",
                .signatures = &.{"sig-approved-passkey"},
                .session = req.account_session,
            };
        }
    }.call;

    var prepared = try client_instance.authorizeOptionsWithChallengeResponseWithAccountProvider(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{
            .passkey = .{
                .address = "0xpasskey",
                .session = .{ .kind = .passkey, .session_id = "pending-passkey-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .passkey, .session_id = "approved-passkey-session" },
            .supports_execute = true,
        },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xapproved-passkey", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-approved-passkey", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(tx_request_builder.AccountSessionKind.passkey, prepared.session.kind);
    try testing.expect(prepared.supports_execute);
}

test "authorizePlanOrChallengePrompt returns structured prompt without authorization" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    var result = try client_instance.authorizePlanOrChallengePrompt(allocator, plan);
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.execute, prompt.action);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "buildPlanArtifactOrChallengePrompt returns structured prompt without artifact generation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    var result = try client_instance.buildPlanArtifactOrChallengePrompt(
        allocator,
        plan,
        .execute_payload,
    );
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.execute, prompt.action);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "runPlanOrChallengePrompt returns structured prompts for authorize actions" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    var result = try client_instance.runPlanOrChallengePrompt(allocator, plan, .authorize);
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.execute, prompt.action);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "inspectPlan sends inspect payload from authorization plans" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const plan = client_instance.planOptionsWithAccountProvider(.{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .zklogin = .{
            .address = "0xzk",
            .session = .{ .kind = .zklogin, .session_id = "oauth-session", .user_id = "user-1" },
        },
    });

    const response = try client_instance.inspectPlan(allocator, plan);
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xzk") != null);
}

test "inspectOwnedPlan sends inspect payload from owned authorization plans" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var owned_plan = try builder.finishAuthorizationPlan(.{
        .zklogin = .{
            .address = "0xzk",
            .session = .{ .kind = .zklogin, .session_id = "oauth-session" },
            .session_action = .inspect,
        },
    });
    defer owned_plan.deinit(allocator);

    const response = try client_instance.inspectOwnedPlan(allocator, &owned_plan);
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xzk") != null);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xreceiver") != null);
}

test "inspectPlanOrChallengePrompt returns structured prompt without sending inspect rpc" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;

    const MockContext = struct {
        saw_request: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            return alloc.dupe(u8, "{\"result\":{\"unexpected\":true}}");
        }
    }.call;

    var ctx = MockContext{ .saw_request = &saw_request };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
    );

    var result = try client_instance.inspectPlanOrChallengePrompt(allocator, plan);
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.inspect, prompt.action);
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(!saw_request);
}

test "inspectDslBuilderOrChallengePrompt inspects immediately when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var result = try client_instance.inspectDslBuilderOrChallengePrompt(
        allocator,
        &builder,
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
    );
    defer result.deinit(allocator);

    switch (result) {
        .inspected => |response| {
            try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xabc") != null);
}

test "inspectOptionsOrChallengePromptWithAccountProvider returns structured prompt without sending inspect rpc" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;

    const MockContext = struct {
        saw_request: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            return alloc.dupe(u8, "{\"result\":{\"unexpected\":true}}");
        }
    }.call;

    var ctx = MockContext{ .saw_request = &saw_request };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.inspectOptionsOrChallengePromptWithAccountProvider(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
    );
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.inspect, prompt.action);
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(!saw_request);
}

test "inspectRequestOrChallengePromptWithAccountProvider inspects immediately when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.inspectRequestOrChallengePromptWithAccountProvider(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
    );
    defer result.deinit(allocator);

    switch (result) {
        .inspected => |response| {
            try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xabc") != null);
}

test "inspectCommandsOrChallengePromptWithAccountProvider returns structured prompt without sending inspect rpc" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;

    const MockContext = struct {
        saw_request: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            return alloc.dupe(u8, "{\"result\":{\"unexpected\":true}}");
        }
    }.call;

    var ctx = MockContext{ .saw_request = &saw_request };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.inspectCommandsOrChallengePromptWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
    );
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.inspect, prompt.action);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(!saw_request);
}

test "inspectOptionsOrChallengePromptFromDefaultKeystore inspects immediately when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_inspect_options_prompt_keystore_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.inspectOptionsOrChallengePromptFromDefaultKeystore(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{ .signer_selectors = &.{"builder"} },
    );
    defer result.deinit(allocator);

    switch (result) {
        .inspected => |response| {
            try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xbuilder") != null);
}

test "buildOptionsArtifactFromDefaultKeystore builds execute payloads immediately" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_build_options_artifact_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const payload = try client_instance.buildOptionsArtifactFromDefaultKeystore(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{ .signer_selectors = &.{"builder"} },
        .execute_payload,
    );
    defer allocator.free(payload);

    try testing.expect(std.mem.indexOf(u8, payload, "0xbuilder") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "sig-builder") != null);
}

test "runOptionsFromDefaultKeystore completes authorize actions immediately" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_run_options_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    var result = try client_instance.runOptionsFromDefaultKeystore(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{ .signer_selectors = &.{"builder"} },
        .authorize,
    );
    defer result.deinit(allocator);

    switch (result) {
        .authorized => |prepared| {
            try testing.expectEqualStrings("0xbuilder", prepared.prepared.request.sender.?);
            try testing.expectEqualStrings("sig-builder", prepared.prepared.request.signatures[0]);
            try testing.expect(prepared.supports_execute);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ownedPlanCommandsWithAccountProvider returns owned plans with structured challenge prompts" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    var plan = try client_instance.ownedPlanCommandsWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );
    defer plan.deinit(allocator);

    var result = try client_instance.executeOwnedPlanOrChallengePromptAndConfirm(allocator, &plan, 5_000, 1);
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
            switch (prompt.challenge) {
                .passkey => |value| {
                    try testing.expectEqualStrings("wallet.example", value.rp_id);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ownedPlanRequestWithAccountProvider executes confirmed flows" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"owned-plan-request\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"owned-plan-request\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var plan = try client_instance.ownedPlanRequestWithAccountProvider(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
    );
    defer plan.deinit(allocator);

    const response = try client_instance.executeOwnedPlanAndConfirm(allocator, &plan, 5_000, 1);
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"owned-plan-request\"}}", response);
}

test "ownedPlanOptionsFromDefaultKeystore executes confirmed flows" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_owned_plan_options_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var execute_seen = false;
    var confirm_seen = false;
    var execute_params: ?[]const u8 = null;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
        execute_params: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                ctx.execute_params.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"owned-plan-options\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"owned-plan-options\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
        .execute_params = &execute_params,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var plan = try client_instance.ownedPlanOptionsFromDefaultKeystore(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{ .signer_selectors = &.{"builder"} },
    );
    defer plan.deinit(allocator);

    const response = try client_instance.executeOwnedPlanAndConfirm(allocator, &plan, 5_000, 1);
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"owned-plan-options\"}}", response);
    try testing.expect(execute_params != null);
    defer allocator.free(execute_params.?);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "0xbuilder") != null);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "sig-builder") != null);
}

test "ownedPlanCommandsFromDefaultKeystore returns executed prompt result without challenge" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_owned_plan_commands_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"owned-plan-commands\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"owned-plan-commands\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var plan = try client_instance.ownedPlanCommandsFromDefaultKeystore(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{ .signer_selectors = &.{"builder"} },
    );
    defer plan.deinit(allocator);

    var result = try client_instance.executeOwnedPlanOrChallengePromptAndConfirm(allocator, &plan, 5_000, 1);
    defer result.deinit(allocator);

    switch (result) {
        .executed => |response| {
            try testing.expectEqualStrings("{\"result\":{\"digest\":\"owned-plan-commands\"}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
}

test "buildCommandsArtifactOrChallengePromptFromDefaultKeystore returns artifacts immediately" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_build_commands_artifact_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    var result = try client_instance.buildCommandsArtifactOrChallengePromptFromDefaultKeystore(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{ .signer_selectors = &.{"builder"} },
        .execute_payload,
    );
    defer result.deinit(allocator);

    switch (result) {
        .artifact => |payload| {
            try testing.expect(std.mem.indexOf(u8, payload, "0xbuilder") != null);
            try testing.expect(std.mem.indexOf(u8, payload, "sig-builder") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "runCommandsOrChallengePromptFromDefaultKeystore completes execute-confirm actions immediately" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_run_commands_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"run-commands-default-keystore\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"run-commands-default-keystore\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.runCommandsOrChallengePromptFromDefaultKeystore(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{ .signer_selectors = &.{"builder"} },
        .{ .execute_confirm = .{ .timeout_ms = 5_000, .poll_ms = 1 } },
    );
    defer result.deinit(allocator);

    switch (result) {
        .completed => |completed| switch (completed) {
            .executed => |response| try testing.expectEqualStrings("{\"result\":{\"digest\":\"run-commands-default-keystore\"}}", response),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
}

test "executeOptionsWithAccountProvider uses direct signature accounts" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"abc123\"}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.executeOptionsWithAccountProvider(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .direct_signatures = .{
            .sender = "0xabc",
            .signatures = &.{"sig-a"},
            .session = .{ .kind = .remote_signer, .session_id = "session-1" },
        },
    });
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"abc123\"}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xabc") != null);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "sig-a") != null);
}

test "authorizeCommandsWithAccountProvider maps command config into prepared requests" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    var prepared = try client_instance.authorizeCommandsWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{
            .gas_budget = 42,
            .gas_price = 7,
            .options_json = "{\"showEffects\":true}",
            .wait_for_confirmation = true,
            .confirm_timeout_ms = 9000,
            .confirm_poll_ms = 250,
        },
        .{
            .direct_signatures = .{
                .sender = "0xcli",
                .signatures = &.{"sig-cli"},
                .session = .{ .kind = .remote_signer, .session_id = "session-cli" },
            },
        },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xcli", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-cli", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(@as(?u64, 42), prepared.prepared.request.gas_budget);
    try testing.expectEqual(@as(?u64, 7), prepared.prepared.request.gas_price);
    try testing.expect(prepared.prepared.request.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 9000), prepared.prepared.request.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 250), prepared.prepared.request.confirm_poll_ms);
    try testing.expectEqualStrings("{\"showEffects\":true}", prepared.prepared.request.options_json.?);
    try testing.expectEqual(tx_request_builder.AccountSessionKind.remote_signer, prepared.session.kind);
    try testing.expect(prepared.supports_execute);
}

test "authorizeCommandsWithChallengeResponseWithAccountProvider applies challenge response before authorization" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("commands-approved-session", req.account_session.session_id.?);
            return .{
                .sender = "0xcommands-approved",
                .signatures = &.{"sig-commands-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    var prepared = try client_instance.authorizeCommandsWithChallengeResponseWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{
            .gas_budget = 42,
            .gas_price = 7,
            .options_json = "{\"showEffects\":true}",
            .wait_for_confirmation = true,
            .confirm_timeout_ms = 9000,
            .confirm_poll_ms = 250,
        },
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .remote_signer, .session_id = "commands-approved-session" },
            .supports_execute = true,
        },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xcommands-approved", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-commands-approved", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(@as(?u64, 42), prepared.prepared.request.gas_budget);
    try testing.expectEqual(@as(?u64, 7), prepared.prepared.request.gas_price);
    try testing.expect(prepared.prepared.request.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 9000), prepared.prepared.request.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 250), prepared.prepared.request.confirm_poll_ms);
    try testing.expectEqualStrings("{\"showEffects\":true}", prepared.prepared.request.options_json.?);
    try testing.expectEqual(tx_request_builder.AccountSessionKind.remote_signer, prepared.session.kind);
    try testing.expect(prepared.supports_execute);
}

test "buildSessionChallengeText returns signPersonalMessage prompt for remote signer accounts" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const noop_challenger = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.SessionChallengeRequest) !tx_request_builder.SessionChallengeResponse {
            return .{};
        }
    }.call;

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const text = try client_instance.buildSessionChallengeText(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .remote_signer = .{
            .address = "0xwallet",
            .authorizer = .{
                .context = undefined,
                .callback = struct {
                    fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                        return .{};
                    }
                }.call,
            },
            .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
            .session_challenger = .{
                .context = undefined,
                .callback = noop_challenger,
            },
            .session_challenge = .{
                .sign_personal_message = .{
                    .domain = "wallet.example",
                    .statement = "Sign in to the agent cloud",
                    .nonce = "nonce-123",
                    .address = "0xwallet",
                },
            },
            .session_action = .cloud_agent_access,
            .session_supports_execute = false,
        },
    });
    defer if (text) |value| allocator.free(value);

    try testing.expect(text != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "wallet.example wants you to sign in") != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "0xwallet") != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "Sign in to the agent cloud") != null);
}

test "buildSessionChallengeText returns zklogin prompt for future wallet account providers" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const text = try client_instance.buildSessionChallengeText(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .zklogin = .{
            .address = "0xzk",
            .session = .{ .kind = .zklogin, .session_id = "oauth-session" },
            .session_challenge = .{
                .zklogin_nonce = .{
                    .nonce = "nonce-456",
                    .provider = "google",
                },
            },
            .session_action = .cloud_agent_access,
        },
    });
    defer if (text) |value| allocator.free(value);

    try testing.expect(text != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "zkLogin nonce challenge") != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "google") != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "cloud_agent_access") != null);
}

test "executeOptionsWithAccountProvider supports remote signer authorizers" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"remote123\"}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("0xcloud", req.account_address.?);
            return .{
                .sender = "0xremote",
                .signatures = &.{"sig-remote"},
                .session = .{ .kind = .remote_signer, .session_id = "remote-session" },
            };
        }
    }.call;

    const response = try client_instance.executeOptionsWithAccountProvider(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .remote_signer = .{
            .address = "0xcloud",
            .authorizer = .{
                .context = undefined,
                .callback = authorizer,
            },
        },
    });
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"remote123\"}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xremote") != null);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "sig-remote") != null);
}

test "executePlan authorizes and executes passkey-backed authorization plans" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"plan123\"}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("0xpasskey", req.account_address.?);
            try testing.expectEqualStrings("passkey-session", req.account_session.session_id.?);
            return .{
                .sender = "0xplan-sender",
                .signatures = &.{"sig-plan"},
                .session = req.account_session,
            };
        }
    }.call;

    const plan = client_instance.planOptionsWithAccountProvider(.{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .passkey = .{
            .address = "0xpasskey",
            .session = .{ .kind = .passkey, .session_id = "passkey-session" },
            .authorizer = .{
                .context = undefined,
                .callback = authorizer,
            },
            .session_supports_execute = true,
        },
    });

    const response = try client_instance.executePlan(allocator, plan);
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"plan123\"}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xplan-sender") != null);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "sig-plan") != null);
}

test "executePlanAndConfirm waits for confirmed transaction result" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xplan-confirm\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xplan-confirm\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .direct_signatures = .{
                .sender = "0xplan-sender",
                .signatures = &.{"sig-plan"},
            },
        },
    );

    const response = try client_instance.executePlanAndConfirm(allocator, plan, 5_000, 1);
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xplan-confirm\"}}", response);
    try testing.expect(!plan.options.wait_for_confirmation);
}

test "executePlanOrChallengeTextAndConfirm returns challenge text without executing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;

    const MockContext = struct {
        saw_request: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{ .saw_request = &saw_request };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    var result = try client_instance.executePlanOrChallengeTextAndConfirm(allocator, plan, 5_000, 1);
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |text| {
            try testing.expect(std.mem.indexOf(u8, text, "Passkey challenge for wallet.example") != null);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(!saw_request);
    try testing.expect(!plan.options.wait_for_confirmation);
}

test "executePlanOrChallengePromptAndConfirm returns structured prompt without executing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;

    const MockContext = struct {
        saw_request: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{ .saw_request = &saw_request };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                        .user_name = "alice",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    var result = try client_instance.executePlanOrChallengePromptAndConfirm(allocator, plan, 5_000, 1);
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.execute, prompt.action);
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
            try testing.expectEqual(tx_request_builder.AccountSessionKind.remote_signer, prompt.current_session.kind);
            try testing.expectEqualStrings("pending-session", prompt.current_session.session_id.?);
            try testing.expect(std.mem.indexOf(u8, prompt.text, "Passkey challenge for wallet.example") != null);
            switch (prompt.challenge) {
                .passkey => |value| {
                    try testing.expectEqualStrings("wallet.example", value.rp_id);
                    try testing.expectEqualStrings("challenge-xyz", value.challenge_b64url);
                    try testing.expectEqualStrings("alice", value.user_name.?);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(!saw_request);
    try testing.expect(!plan.options.wait_for_confirmation);
}

test "executeOptionsOrChallengePromptAndConfirmWithAccountProvider returns structured prompt without executing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;

    const MockContext = struct {
        saw_request: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{ .saw_request = &saw_request };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.executeOptionsOrChallengePromptAndConfirmWithAccountProvider(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        5_000,
        1,
    );
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
            switch (prompt.challenge) {
                .passkey => |value| {
                    try testing.expectEqualStrings("wallet.example", value.rp_id);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(!saw_request);
}

test "executePlanWithChallengeResponseAndConfirm applies challenge response before confirmed execution" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;
    var execute_params: ?[]const u8 = null;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
        execute_params: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                ctx.execute_params.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"challenged-confirm\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"challenged-confirm\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
        .execute_params = &execute_params,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("approved-session", req.account_session.session_id.?);
            return .{
                .sender = "0xapproved",
                .signatures = &.{"sig-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
    );

    const response = try client_instance.executePlanWithChallengeResponseAndConfirm(
        allocator,
        plan,
        .{
            .session = .{ .kind = .remote_signer, .session_id = "approved-session" },
            .supports_execute = true,
        },
        5_000,
        1,
    );
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"challenged-confirm\"}}", response);
    try testing.expect(execute_params != null);
    defer allocator.free(execute_params.?);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "0xapproved") != null);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "sig-approved") != null);
}

test "inspectPlanWithChallengeResponse applies challenge response before inspect" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("approved-session", req.account_session.session_id.?);
            return .{
                .sender = "0xapproved",
                .signatures = &.{"sig-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    const plan = client_instance.planCommandsWithAccountProvider(
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
    );

    const response = try client_instance.inspectPlanWithChallengeResponse(
        allocator,
        plan,
        .{
            .session = .{ .kind = .remote_signer, .session_id = "approved-session" },
            .supports_execute = false,
        },
    );
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xapproved") != null);
}

test "executeOptionsWithChallengeResponseWithAccountProvider applies challenge response before execute" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"options-approved\"}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("options-approved-session", req.account_session.session_id.?);
            return .{
                .sender = "0xoptions-approved",
                .signatures = &.{"sig-options-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    const response = try client_instance.executeOptionsWithChallengeResponseWithAccountProvider(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .remote_signer, .session_id = "options-approved-session" },
            .supports_execute = true,
        },
    );
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"options-approved\"}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xoptions-approved") != null);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "sig-options-approved") != null);
}

test "executeDslBuilder authorizes and executes builder pipelines directly" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"builder123\"}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    const response = try client_instance.executeDslBuilder(allocator, &builder, .{
        .direct_signatures = .{
            .sender = "0xabc",
            .signatures = &.{"sig-a"},
        },
    });
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"builder123\"}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xabc") != null);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "sig-a") != null);
}

test "authorizeDslBuilderOrChallengePrompt authorizes immediately when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var result = try client_instance.authorizeDslBuilderOrChallengePrompt(
        allocator,
        &builder,
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
    );
    defer result.deinit(allocator);

    switch (result) {
        .authorized => |prepared| {
            try testing.expectEqualStrings("0xabc", prepared.prepared.request.sender.?);
            try testing.expectEqualStrings("sig-a", prepared.prepared.request.signatures[0]);
            try testing.expect(prepared.supports_execute);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "buildDslBuilderArtifactOrChallengePrompt builds execute payload when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var result = try client_instance.buildDslBuilderArtifactOrChallengePrompt(
        allocator,
        &builder,
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
        .execute_payload,
    );
    defer result.deinit(allocator);

    switch (result) {
        .artifact => |payload| {
            try testing.expect(std.mem.indexOf(u8, payload, "0xabc") != null);
            try testing.expect(std.mem.indexOf(u8, payload, "sig-a") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "runDslBuilderOrChallengePrompt completes execute-confirm actions immediately" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"run-builder-confirm\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"run-builder-confirm\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var result = try client_instance.runDslBuilderOrChallengePrompt(
        allocator,
        &builder,
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
        .{ .execute_confirm = .{ .timeout_ms = 5_000, .poll_ms = 1 } },
    );
    defer result.deinit(allocator);

    switch (result) {
        .completed => |completed| switch (completed) {
            .executed => |response| try testing.expectEqualStrings("{\"result\":{\"digest\":\"run-builder-confirm\"}}", response),
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
}

test "executeDslBuilderAndConfirm waits for confirmed transaction result" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xbuilder-confirm\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xbuilder-confirm\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    const response = try client_instance.executeDslBuilderAndConfirm(
        allocator,
        &builder,
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
        5_000,
        1,
    );
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xbuilder-confirm\"}}", response);
}

test "executeDslBuilderWithChallengeResponseAndConfirm applies challenge response before confirmed execution" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;
    var execute_params: ?[]const u8 = null;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
        execute_params: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                ctx.execute_params.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"builder-challenged-confirm\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"builder-challenged-confirm\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
        .execute_params = &execute_params,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("builder-approved", req.account_session.session_id.?);
            return .{
                .sender = "0xbuilder-approved",
                .signatures = &.{"sig-builder-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    const response = try client_instance.executeDslBuilderWithChallengeResponseAndConfirm(
        allocator,
        &builder,
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .remote_signer, .session_id = "builder-approved" },
            .supports_execute = true,
        },
        5_000,
        1,
    );
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"builder-challenged-confirm\"}}", response);
    try testing.expect(execute_params != null);
    defer allocator.free(execute_params.?);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "0xbuilder-approved") != null);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "sig-builder-approved") != null);
}

test "authorizeDslBuilderWithChallengeResponse applies challenge response before authorization" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("builder-authorized", req.account_session.session_id.?);
            return .{
                .sender = "0xbuilder-authorized",
                .signatures = &.{"sig-builder-authorized"},
                .session = req.account_session,
            };
        }
    }.call;

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var prepared = try client_instance.authorizeDslBuilderWithChallengeResponse(
        allocator,
        &builder,
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .remote_signer, .session_id = "builder-authorized" },
            .supports_execute = true,
        },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xbuilder-authorized", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-builder-authorized", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(tx_request_builder.AccountSessionKind.remote_signer, prepared.session.kind);
    try testing.expect(prepared.supports_execute);
}

test "buildCommandsArtifactWithChallengeResponseWithAccountProvider applies challenge response before artifact build" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("artifact-approved", req.account_session.session_id.?);
            return .{
                .sender = "0xartifact-approved",
                .signatures = &.{"sig-artifact-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    const payload = try client_instance.buildCommandsArtifactWithChallengeResponseWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .remote_signer, .session_id = "artifact-approved" },
            .supports_execute = true,
        },
        .execute_payload,
    );
    defer allocator.free(payload);

    try testing.expect(std.mem.indexOf(u8, payload, "0xartifact-approved") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "sig-artifact-approved") != null);
}

test "runCommandsWithChallengeResponseWithAccountProvider completes authorize actions after approval" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("run-authorized", req.account_session.session_id.?);
            return .{
                .sender = "0xrun-authorized",
                .signatures = &.{"sig-run-authorized"},
                .session = req.account_session,
            };
        }
    }.call;

    var result = try client_instance.runCommandsWithChallengeResponseWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .remote_signer, .session_id = "run-authorized" },
            .supports_execute = true,
        },
        .authorize,
    );
    defer result.deinit(allocator);

    switch (result) {
        .authorized => |prepared| {
            try testing.expectEqualStrings("0xrun-authorized", prepared.prepared.request.sender.?);
            try testing.expectEqualStrings("sig-run-authorized", prepared.prepared.request.signatures[0]);
            try testing.expect(prepared.supports_execute);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "inspectCommandsWithChallengeResponseWithAccountProvider applies challenge response before inspect" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("cmd-approved", req.account_session.session_id.?);
            return .{
                .sender = "0xcmd-approved",
                .signatures = &.{"sig-cmd-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    const response = try client_instance.inspectCommandsWithChallengeResponseWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .inspect,
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .remote_signer, .session_id = "cmd-approved" },
            .supports_execute = false,
        },
    );
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xcmd-approved") != null);
}

test "executeCommandsWithChallengeResponseAndConfirmWithAccountProvider applies challenge response before confirmed execution" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;
    var execute_params: ?[]const u8 = null;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
        execute_params: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                ctx.execute_params.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"commands-approved-confirm\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"commands-approved-confirm\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
        .execute_params = &execute_params,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("commands-approved-session", req.account_session.session_id.?);
            return .{
                .sender = "0xcommands-approved",
                .signatures = &.{"sig-commands-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    const response = try client_instance.executeCommandsWithChallengeResponseAndConfirmWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        .{
            .session = .{ .kind = .remote_signer, .session_id = "commands-approved-session" },
            .supports_execute = true,
        },
        5_000,
        1,
    );
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"commands-approved-confirm\"}}", response);
    try testing.expect(execute_params != null);
    defer allocator.free(execute_params.?);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "0xcommands-approved") != null);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "sig-commands-approved") != null);
}

test "executeDslBuilderOrChallengeTextAndConfirm executes confirmed flows when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"builder-or-challenge\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"builder-or-challenge\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var result = try client_instance.executeDslBuilderOrChallengeTextAndConfirm(
        allocator,
        &builder,
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
        5_000,
        1,
    );
    defer result.deinit(allocator);

    switch (result) {
        .executed => |response| {
            try testing.expectEqualStrings("{\"result\":{\"digest\":\"builder-or-challenge\"}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
}

test "executeDslBuilderOrChallengePromptAndConfirm executes confirmed flows when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"builder-or-prompt\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"builder-or-prompt\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var builder = tx_request_builder.ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var result = try client_instance.executeDslBuilderOrChallengePromptAndConfirm(
        allocator,
        &builder,
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
        5_000,
        1,
    );
    defer result.deinit(allocator);

    switch (result) {
        .executed => |response| {
            try testing.expectEqualStrings("{\"result\":{\"digest\":\"builder-or-prompt\"}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
}

test "executeRequestOrChallengePromptAndConfirmWithAccountProvider executes confirmed flows when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"request-or-prompt\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"request-or-prompt\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.executeRequestOrChallengePromptAndConfirmWithAccountProvider(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
        5_000,
        1,
    );
    defer result.deinit(allocator);

    switch (result) {
        .executed => |response| {
            try testing.expectEqualStrings("{\"result\":{\"digest\":\"request-or-prompt\"}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
}

test "executeOptionsAndConfirmWithAccountProvider waits for confirmed transaction result" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;
    var execute_params: ?[]const u8 = null;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
        execute_params: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                ctx.execute_params.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xopt-confirm\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xopt-confirm\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
        .execute_params = &execute_params,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.executeOptionsAndConfirmWithAccountProvider(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        .{
            .direct_signatures = .{
                .sender = "0xopt-sender",
                .signatures = &.{"sig-opt"},
            },
        },
        5_000,
        1,
    );
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xopt-confirm\"}}", response);
    try testing.expect(execute_params != null);
    defer allocator.free(execute_params.?);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "0xopt-sender") != null);
    try testing.expect(std.mem.indexOf(u8, execute_params.?, "sig-opt") != null);
}

test "executeCommandsAndConfirmWithAccountProvider forces confirmation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xcmd-confirm\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xcmd-confirm\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.executeCommandsAndConfirmWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{
            .confirm_timeout_ms = 5_000,
            .confirm_poll_ms = 1,
        },
        .{
            .direct_signatures = .{
                .sender = "0xcmd-sender",
                .signatures = &.{"sig-cmd"},
            },
        },
    );
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xcmd-confirm\"}}", response);
}

test "executeCommandsOrChallengePromptAndConfirmWithAccountProvider returns structured prompt without executing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;

    const MockContext = struct {
        saw_request: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.method;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{ .saw_request = &saw_request };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.executeCommandsOrChallengePromptAndConfirmWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .remote_signer = .{
                .address = "0xcloud",
                .authorizer = .{
                    .context = undefined,
                    .callback = struct {
                        fn call(_: *anyopaque, _: std.mem.Allocator, _: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
                            return .{};
                        }
                    }.call,
                },
                .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
                .session_challenge = .{
                    .passkey = .{
                        .rp_id = "wallet.example",
                        .challenge_b64url = "challenge-xyz",
                    },
                },
                .session_action = .execute,
                .session_supports_execute = false,
            },
        },
        5_000,
        1,
    );
    defer result.deinit(allocator);

    switch (result) {
        .challenge_required => |prompt| {
            try testing.expectEqualStrings("0xcloud", prompt.account_address.?);
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.execute, prompt.action);
            switch (prompt.challenge) {
                .passkey => |value| {
                    try testing.expectEqualStrings("wallet.example", value.rp_id);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(!saw_request);
}

test "executeCommandsOrChallengePromptWithAccountProvider executes immediately when no challenge is needed" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"cmd-or-prompt\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.executeCommandsOrChallengePromptWithAccountProvider(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{
            .direct_signatures = .{
                .sender = "0xabc",
                .signatures = &.{"sig-a"},
            },
        },
    );
    defer result.deinit(allocator);

    switch (result) {
        .executed => |response| {
            try testing.expectEqualStrings("{\"result\":{\"digest\":\"cmd-or-prompt\"}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(execute_seen);
}

test "executeCommandsOrChallengePromptAndConfirmFromDefaultKeystore executes confirmed flows" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_execute_commands_prompt_keystore_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"cmd-prompt-keystore\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"cmd-prompt-keystore\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    var result = try client_instance.executeCommandsOrChallengePromptAndConfirmFromDefaultKeystore(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .{},
        .{ .signer_selectors = &.{"builder"} },
        5_000,
        1,
    );
    defer result.deinit(allocator);

    switch (result) {
        .executed => |response| {
            try testing.expectEqualStrings("{\"result\":{\"digest\":\"cmd-prompt-keystore\"}}", response);
        },
        else => return error.TestUnexpectedResult,
    }

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
}

test "executeOptionsWithAccountProvider supports passkey account authorizers" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"passkey123\"}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("0xpasskey", req.account_address.?);
            try testing.expectEqualStrings("passkey-session", req.account_session.session_id.?);
            return .{
                .sender = "0xpasskey-sender",
                .signatures = &.{"sig-passkey"},
                .session = req.account_session,
            };
        }
    }.call;

    const response = try client_instance.executeOptionsWithAccountProvider(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .passkey = .{
            .address = "0xpasskey",
            .session = .{ .kind = .passkey, .session_id = "passkey-session" },
            .authorizer = .{
                .context = undefined,
                .callback = authorizer,
            },
            .session_supports_execute = true,
        },
    });
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"passkey123\"}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xpasskey-sender") != null);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "sig-passkey") != null);
}

test "applySessionChallengeResponse updates remote signer providers for later execute" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var saw_request = false;
    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        saw_request: *bool,
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const rpc_callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.saw_request.* = true;
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"challenged123\"}}");
        }
    }.call;

    var ctx = MockContext{
        .saw_request = &saw_request,
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = rpc_callback,
    };

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.RemoteAuthorizationRequest) !tx_request_builder.RemoteAuthorizationResult {
            try testing.expectEqualStrings("approved-session", req.account_session.session_id.?);
            return .{
                .sender = "0xapproved",
                .signatures = &.{"sig-approved"},
                .session = req.account_session,
            };
        }
    }.call;

    const challenger = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: tx_request_builder.SessionChallengeRequest) !tx_request_builder.SessionChallengeResponse {
            try testing.expectEqual(tx_request_builder.SessionChallengeAction.execute, req.action);
            return .{
                .session = .{ .kind = .remote_signer, .session_id = "approved-session" },
                .supports_execute = true,
            };
        }
    }.call;

    const initial_provider: tx_request_builder.AccountProvider = .{
        .remote_signer = .{
            .address = "0xcloud",
            .authorizer = .{
                .context = undefined,
                .callback = authorizer,
            },
            .session = .{ .kind = .remote_signer, .session_id = "pending-session" },
            .session_challenger = .{
                .context = undefined,
                .callback = challenger,
            },
            .session_challenge = .{
                .passkey = .{
                    .rp_id = "wallet.example",
                    .challenge_b64url = "challenge-xyz",
                },
            },
            .session_action = .execute,
            .session_supports_execute = false,
        },
    };

    const challenge_text = try client_instance.buildSessionChallengeText(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, initial_provider);
    defer if (challenge_text) |value| allocator.free(value);

    try testing.expect(challenge_text != null);
    try testing.expect(std.mem.indexOf(u8, challenge_text.?, "Passkey challenge for wallet.example") != null);

    const updated_provider = try client_instance.applySessionChallengeResponse(initial_provider, .{
        .session = .{ .kind = .remote_signer, .session_id = "approved-session" },
        .supports_execute = true,
    });

    switch (updated_provider) {
        .remote_signer => |account| {
            try testing.expect(account.session_challenger == null);
            try testing.expect(account.session_challenge == null);
            try testing.expect(account.session_supports_execute);
            try testing.expectEqualStrings("approved-session", account.session.session_id.?);
        },
        else => return error.TestUnexpectedResult,
    }

    const response = try client_instance.executeOptionsWithAccountProvider(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, updated_provider);
    defer allocator.free(response);

    try testing.expect(saw_request);
    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"challenged123\"}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "0xapproved") != null);
    try testing.expect(std.mem.indexOf(u8, params_text.?, "sig-approved") != null);
}

test "executeOptionsWithAccountProvider rejects unsupported future wallet execution" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();

    try testing.expectError(error.UnsupportedAccountProvider, client_instance.executeOptionsWithAccountProvider(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .passkey = .{
            .address = "0xpasskey",
            .session = .{ .kind = .passkey, .session_id = "passkey-session" },
        },
    }));
}

test "executeRequest honors confirmation settings" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.executeRequest(allocator, .{
        .source = .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        .sender = "0xabc",
        .gas_budget = 1000,
        .gas_price = 7,
        .signatures = &.{"sig-a"},
        .wait_for_confirmation = true,
        .confirm_timeout_ms = 5_000,
        .confirm_poll_ms = 1,
    });
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\"}}", response);
}

test "executeRequestFromDefaultKeystore resolves signer-backed sender and signature" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_keystore_exec_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
        }
    }.call;

    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.executeRequestFromDefaultKeystore(
        allocator,
        .{
            .source = .{
                .move_call = .{
                    .package_id = "0x2",
                    .module = "counter",
                    .function_name = "increment",
                    .type_args = "[]",
                    .arguments = "[\"0xabc\"]",
                },
            },
        },
        .{ .signer_selectors = &.{"builder"} },
    );
    defer allocator.free(response);

    try testing.expect(method_ok);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer payload.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, payload.value.array.items[0].string, .{});
    defer tx_block.deinit();

    try testing.expectEqualStrings("0xbuilder", tx_block.value.object.get("sender").?.string);
    try testing.expectEqualStrings("sig-builder", payload.value.array.items[1].array.items[0].string);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\"}}", response);
}

test "executeOptionsFromDefaultKeystore resolves signer-backed sender and signature" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_keystore_exec_options_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
        }
    }.call;

    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.executeOptionsFromDefaultKeystore(
        allocator,
        .{
            .source = .{
                .move_call = .{
                    .package_id = "0x2",
                    .module = "counter",
                    .function_name = "increment",
                    .type_args = "[]",
                    .arguments = "[\"0xabc\"]",
                },
            },
        },
        .{ .signer_selectors = &.{"builder"} },
    );
    defer allocator.free(response);

    try testing.expect(method_ok);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer payload.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, payload.value.array.items[0].string, .{});
    defer tx_block.deinit();

    try testing.expectEqualStrings("0xbuilder", tx_block.value.object.get("sender").?.string);
    try testing.expectEqualStrings("sig-builder", payload.value.array.items[1].array.items[0].string);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\"}}", response);
}

test "inspectCommandsFromDefaultKeystore resolves signer-backed sender" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_keystore_inspect_cmd_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_devInspectTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"inspected\":true}}");
        }
    }.call;

    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.inspectCommandsFromDefaultKeystore(
        allocator,
        .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        null,
        1000,
        7,
        "{\"skipChecks\":true}",
        .{ .signer_selectors = &.{"builder"} },
    );
    defer allocator.free(response);

    try testing.expect(method_ok);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer payload.deinit();
    try testing.expect(payload.value == .array);
    try testing.expectEqual(@as(usize, 2), payload.value.array.items.len);
    try testing.expectEqualStrings("0xbuilder", payload.value.array.items[1].object.get("sender").?.string);
    try testing.expectEqualStrings("{\"result\":{\"inspected\":true}}", response);
}

test "executeProgrammaticTransaction builds execute payload from context" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var method_ok = false;
    var params_text: ?[]const u8 = null;

    const MockContext = struct {
        method_ok: *bool,
        params_text: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;
            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            ctx.method_ok.* = std.mem.eql(u8, req.method, "sui_executeTransactionBlock");
            ctx.params_text.* = try alloc.dupe(u8, req.params_json);
            return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
        }
    }.call;

    var ctx = MockContext{
        .method_ok = &method_ok,
        .params_text = &params_text,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    var programmatic_context = try tx_builder.ProgrammaticTxContext.initResolved(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        "0xsender",
        900,
        5,
        null,
    );
    defer programmatic_context.deinit(allocator);

    const response = try client_instance.executeProgrammaticTransaction(
        allocator,
        &programmatic_context,
        &.{"sig-a"},
    );
    defer allocator.free(response);

    try testing.expect(method_ok);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\"}}", response);
    try testing.expect(params_text != null);
    defer allocator.free(params_text.?);

    const params = try std.json.parseFromSlice(std.json.Value, allocator, params_text.?, .{});
    defer params.deinit();
    try testing.expect(params.value == .array);
    try testing.expectEqual(@as(usize, 2), params.value.array.items.len);
    try testing.expectEqual(@as(usize, 1), params.value.array.items[1].array.items.len);
}

test "executeCommandsAndConfirm waits for confirmed transaction result" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_seen = false;
    var confirm_seen = false;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.params_json;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.executeCommandsAndConfirm(
        allocator,
        .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        "0xabc",
        1000,
        7,
        &.{"sig-a"},
        null,
        5_000,
        1,
    );
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\"}}", response);
}

test "executeCommandsAndConfirmFromDefaultKeystore waits with signer-backed payload" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keystore_path = try std.fmt.allocPrint(allocator, "tmp_client_keystore_exec_cmd_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(keystore_path);

    const old_override = keystore.test_keystore_path_override;
    keystore.test_keystore_path_override = keystore_path;
    defer keystore.test_keystore_path_override = old_override;

    var file = try std.fs.cwd().createFile(keystore_path, .{ .truncate = true });
    defer file.close();
    defer _ = std.fs.cwd().deleteFile(keystore_path) catch {};
    try file.writeAll("[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]");

    var execute_seen = false;
    var confirm_seen = false;
    var execute_params: ?[]const u8 = null;

    const MockContext = struct {
        execute_seen: *bool,
        confirm_seen: *bool,
        execute_params: *?[]const u8,
    };

    const callback = struct {
        fn call(context: *anyopaque, alloc: std.mem.Allocator, req: RpcRequest) ![]u8 {
            _ = req.id;
            _ = req.request_body;

            const ctx = @as(*MockContext, @ptrCast(@alignCast(context)));
            if (std.mem.eql(u8, req.method, "sui_executeTransactionBlock")) {
                ctx.execute_seen.* = true;
                ctx.execute_params.* = try alloc.dupe(u8, req.params_json);
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            if (std.mem.eql(u8, req.method, "sui_getTransactionBlock")) {
                ctx.confirm_seen.* = true;
                return alloc.dupe(u8, "{\"result\":{\"digest\":\"0xabc\"}}");
            }
            return alloc.dupe(u8, "{\"error\":{\"code\":-32603,\"message\":\"unexpected\"}}");
        }
    }.call;

    var ctx = MockContext{
        .execute_seen = &execute_seen,
        .confirm_seen = &confirm_seen,
        .execute_params = &execute_params,
    };

    var client_instance = try SuiRpcClient.init(allocator, "http://localhost:1234");
    defer client_instance.deinit();
    client_instance.request_sender = .{
        .context = &ctx,
        .callback = callback,
    };

    const response = try client_instance.executeCommandsAndConfirmFromDefaultKeystore(
        allocator,
        .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        null,
        900,
        5,
        null,
        5_000,
        1,
        .{ .signer_selectors = &.{"builder"} },
    );
    defer allocator.free(response);

    try testing.expect(execute_seen);
    try testing.expect(confirm_seen);
    try testing.expect(execute_params != null);
    defer allocator.free(execute_params.?);

    const payload = try std.json.parseFromSlice(std.json.Value, allocator, execute_params.?, .{});
    defer payload.deinit();
    const tx_block = try std.json.parseFromSlice(std.json.Value, allocator, payload.value.array.items[0].string, .{});
    defer tx_block.deinit();

    try testing.expectEqualStrings("0xbuilder", tx_block.value.object.get("sender").?.string);
    try testing.expectEqualStrings("sig-builder", payload.value.array.items[1].array.items[0].string);
    try testing.expectEqualStrings("{\"result\":{\"digest\":\"0xabc\"}}", response);
}
