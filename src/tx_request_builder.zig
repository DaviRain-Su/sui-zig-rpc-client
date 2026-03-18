const std = @import("std");
const tx_builder = @import("./tx_builder.zig");
const keystore = @import("./keystore.zig");
const package_preset = @import("./package_preset.zig");

pub const CommandResultAliases = std.StringHashMapUnmanaged(u16);

pub const ResolvedCommandValue = struct {
    value: []const u8,
    owned: ?[]const u8 = null,

    pub fn deinit(self: *ResolvedCommandValue, allocator: std.mem.Allocator) void {
        if (self.owned) |value| allocator.free(value);
    }
};

pub const ResolvedCommandValues = struct {
    items: std.ArrayListUnmanaged([]const u8) = .{},
    owned_items: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *ResolvedCommandValues, allocator: std.mem.Allocator) void {
        for (self.owned_items.items) |value| allocator.free(value);
        self.items.deinit(allocator);
        self.owned_items.deinit(allocator);
    }
};

pub const ResolvedPtbArgumentSpec = struct {
    spec: PtbArgumentSpec,
    owned_json: ?[]const u8 = null,

    pub fn deinit(self: *ResolvedPtbArgumentSpec, allocator: std.mem.Allocator) void {
        if (self.owned_json) |value| allocator.free(value);
    }
};

pub const ResolvedPtbArgumentSpecs = struct {
    items: std.ArrayListUnmanaged(PtbArgumentSpec) = .{},
    owned_json_items: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *ResolvedPtbArgumentSpecs, allocator: std.mem.Allocator) void {
        for (self.owned_json_items.items) |value| allocator.free(value);
        self.items.deinit(allocator);
        self.owned_json_items.deinit(allocator);
    }
};

pub const NestedResultSpec = struct {
    command_index: u16,
    result_index: u16,
};

pub const CommandOutputHandle = struct {
    command_index: u16,
    result_index: u16,

    pub fn asSpec(self: CommandOutputHandle) PtbArgumentSpec {
        return .{
            .nested_result = .{
                .command_index = self.command_index,
                .result_index = self.result_index,
            },
        };
    }

    pub fn asValue(self: CommandOutputHandle) ArgumentValue {
        return .{ .output = self };
    }
};

pub const CommandResultHandle = struct {
    command_index: u16,

    pub fn asSpec(self: CommandResultHandle) PtbArgumentSpec {
        return .{ .result = self.command_index };
    }

    pub fn asValue(self: CommandResultHandle) ArgumentValue {
        return .{ .result = self };
    }

    pub fn output(self: CommandResultHandle, result_index: u16) CommandOutputHandle {
        return .{
            .command_index = self.command_index,
            .result_index = result_index,
        };
    }

    pub fn outputValue(self: CommandResultHandle, result_index: u16) ArgumentValue {
        return self.output(result_index).asValue();
    }
};

pub const ArgumentVectorValue = struct {
    items: []const ArgumentValue,
};

pub const ArgumentOptionValue = union(enum) {
    none,
    some: *const ArgumentValue,
};

pub const ArgumentValue = union(enum) {
    gas_coin,
    input: u16,
    result: CommandResultHandle,
    output: CommandOutputHandle,
    address: []const u8,
    object_id: []const u8,
    bytes: []const u8,
    raw_json: []const u8,
    string: []const u8,
    boolean: bool,
    u8: u8,
    u16: u16,
    u32: u32,
    u64: u64,
    u128: u128,
    u256: u256,
    i64: i64,
    null,
    vector: ArgumentVectorValue,
    option: ArgumentOptionValue,
};

pub const OwnedCommandResultHandles = struct {
    items: std.ArrayListUnmanaged(CommandResultHandle) = .{},

    pub fn deinit(self: *OwnedCommandResultHandles, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }
};

pub const OwnedArgumentValues = struct {
    items: std.ArrayListUnmanaged(ArgumentValue) = .{},
    owned_json_items: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *OwnedArgumentValues, allocator: std.mem.Allocator) void {
        for (self.owned_json_items.items) |value| allocator.free(value);
        self.items.deinit(allocator);
        self.owned_json_items.deinit(allocator);
    }
};

pub const ResolvedArgumentValue = struct {
    value: ArgumentValue,
    owned_json: ?[]const u8 = null,

    pub fn deinit(self: *ResolvedArgumentValue, allocator: std.mem.Allocator) void {
        if (self.owned_json) |value| allocator.free(value);
    }
};

pub const PtbArgumentSpec = union(enum) {
    gas_coin,
    input: u16,
    result: u16,
    nested_result: NestedResultSpec,
    json: []const u8,
};

pub const ProgrammaticRequestOptions = struct {
    source: tx_builder.CommandSource,
    sender: ?[]const u8 = null,
    gas_budget: ?u64 = null,
    gas_price: ?u64 = null,
    gas_payment_json: ?[]const u8 = null,
    signatures: []const []const u8 = &.{},
    options_json: ?[]const u8 = null,
    wait_for_confirmation: bool = false,
    confirm_timeout_ms: u64 = std.math.maxInt(u64),
    confirm_poll_ms: u64 = 2_000,
};

pub const CommandRequestConfig = struct {
    sender: ?[]const u8 = null,
    gas_budget: ?u64 = null,
    gas_price: ?u64 = null,
    gas_payment_json: ?[]const u8 = null,
    signatures: []const []const u8 = &.{},
    options_json: ?[]const u8 = null,
    wait_for_confirmation: bool = false,
    confirm_timeout_ms: u64 = std.math.maxInt(u64),
    confirm_poll_ms: u64 = 2_000,
};

pub const ProgrammaticArtifactKind = enum {
    transaction_block,
    inspect_payload,
    execute_payload,
};

pub const AccountSessionKind = enum {
    none,
    local_keystore,
    zklogin,
    passkey,
    multisig,
    remote_signer,
};

pub const AccountSession = struct {
    kind: AccountSessionKind = .none,
    session_id: ?[]const u8 = null,
    user_id: ?[]const u8 = null,
    expires_at_ms: ?u64 = null,
};

pub const SessionChallengeAction = enum {
    inspect,
    execute,
    cloud_agent_access,
};

pub const SignPersonalMessageChallenge = struct {
    domain: []const u8,
    statement: []const u8,
    nonce: []const u8,
    address: ?[]const u8 = null,
    uri: ?[]const u8 = null,
    chain: []const u8 = "sui",
    issued_at_ms: ?u64 = null,
    expires_at_ms: ?u64 = null,
    resources: []const []const u8 = &.{},
};

pub const PasskeyChallenge = struct {
    rp_id: []const u8,
    challenge_b64url: []const u8,
    user_name: ?[]const u8 = null,
    user_display_name: ?[]const u8 = null,
    timeout_ms: ?u64 = null,
};

pub const ZkLoginNonceChallenge = struct {
    nonce: []const u8,
    provider: ?[]const u8 = null,
    max_epoch: ?u64 = null,
};

pub const SessionChallenge = union(enum) {
    sign_personal_message: SignPersonalMessageChallenge,
    passkey: PasskeyChallenge,
    zklogin_nonce: ZkLoginNonceChallenge,
};

pub const SessionChallengeRequest = struct {
    options: ProgrammaticRequestOptions,
    account_address: ?[]const u8 = null,
    current_session: AccountSession = .{},
    action: SessionChallengeAction = .execute,
    challenge: SessionChallenge,
};

pub const SessionChallengeResponse = struct {
    session: ?AccountSession = null,
    supports_execute: bool = true,
};

pub const SessionChallenger = struct {
    context: *anyopaque,
    callback: *const fn (*anyopaque, std.mem.Allocator, SessionChallengeRequest) anyerror!SessionChallengeResponse,
};

pub const DirectSignatureAccount = struct {
    sender: ?[]const u8 = null,
    signatures: []const []const u8 = &.{},
    session: AccountSession = .{},
};

pub const KeystoreContentsAccount = struct {
    contents: []const u8,
    preparation: keystore.SignerPreparation,
    session: AccountSession = .{ .kind = .local_keystore },
};

pub const DefaultKeystoreAccount = struct {
    preparation: keystore.SignerPreparation,
    session: AccountSession = .{ .kind = .local_keystore },
};

pub const RemoteAuthorizationRequest = struct {
    options: ProgrammaticRequestOptions,
    account_address: ?[]const u8 = null,
    account_session: AccountSession = .{},
    tx_bytes_base64: ?[]const u8 = null,
};

pub const RemoteAuthorizationResult = struct {
    sender: ?[]const u8 = null,
    signatures: []const []const u8 = &.{},
    session: ?AccountSession = null,
    supports_execute: bool = true,
};

pub const RemoteAuthorizer = struct {
    context: *anyopaque,
    callback: *const fn (*anyopaque, std.mem.Allocator, RemoteAuthorizationRequest) anyerror!RemoteAuthorizationResult,
};

pub const RemoteSignerAccount = struct {
    address: ?[]const u8 = null,
    authorizer: RemoteAuthorizer,
    session: AccountSession = .{ .kind = .remote_signer },
    session_challenger: ?SessionChallenger = null,
    session_challenge: ?SessionChallenge = null,
    session_action: SessionChallengeAction = .execute,
    session_supports_execute: bool = true,
};

pub const FutureWalletAccount = struct {
    address: ?[]const u8 = null,
    session: AccountSession,
    authorizer: ?RemoteAuthorizer = null,
    session_challenge: ?SessionChallenge = null,
    session_action: SessionChallengeAction = .execute,
    session_supports_execute: bool = false,
};

pub const AccountProvider = union(enum) {
    none,
    direct_signatures: DirectSignatureAccount,
    keystore_contents: KeystoreContentsAccount,
    default_keystore: DefaultKeystoreAccount,
    remote_signer: RemoteSignerAccount,
    zklogin: FutureWalletAccount,
    passkey: FutureWalletAccount,
    multisig: FutureWalletAccount,
};

pub fn accountProviderCanExecute(provider: AccountProvider) bool {
    return switch (provider) {
        .none => false,
        .direct_signatures => |account| account.signatures.len != 0,
        .keystore_contents => |account| account.preparation.signer_selectors.len != 0 or account.preparation.from_keystore,
        .default_keystore => |account| account.preparation.signer_selectors.len != 0 or account.preparation.from_keystore,
        .remote_signer => |account| account.session_supports_execute,
        .zklogin => |account| account.authorizer != null and account.session_supports_execute,
        .passkey => |account| account.authorizer != null and account.session_supports_execute,
        .multisig => |account| account.authorizer != null and account.session_supports_execute,
    };
}

pub const AuthorizedPreparedRequest = struct {
    prepared: tx_builder.PreparedProgrammaticTxRequest,
    session: AccountSession = .{},
    supports_execute: bool = true,

    pub fn deinit(self: *AuthorizedPreparedRequest, allocator: std.mem.Allocator) void {
        self.prepared.deinit(allocator);
    }

    pub fn buildInspectPayload(
        self: *AuthorizedPreparedRequest,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.prepared.buildInspectPayload(allocator);
    }

    pub fn buildExecutePayload(
        self: *AuthorizedPreparedRequest,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        if (!self.supports_execute) return error.UnsupportedAccountProvider;
        return try self.prepared.buildExecutePayload(allocator);
    }

    pub fn buildTransactionBlock(
        self: *AuthorizedPreparedRequest,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const commands_json = self.prepared.request.source.commands_json orelse return error.InvalidCli;
        var out = std.ArrayList(u8){};
        errdefer out.deinit(allocator);
        try tx_builder.writeProgrammableTransaction(
            allocator,
            out.writer(allocator),
            commands_json,
            self.prepared.request.sender,
            self.prepared.request.gas_budget,
            self.prepared.request.gas_price,
            self.prepared.request.gas_payment_json,
        );
        return try out.toOwnedSlice(allocator);
    }

    pub fn buildArtifact(
        self: *AuthorizedPreparedRequest,
        allocator: std.mem.Allocator,
        kind: ProgrammaticArtifactKind,
    ) ![]u8 {
        return switch (kind) {
            .transaction_block => try self.buildTransactionBlock(allocator),
            .inspect_payload => try self.buildInspectPayload(allocator),
            .execute_payload => try self.buildExecutePayload(allocator),
        };
    }
};

pub const AuthorizationPlan = struct {
    options: ProgrammaticRequestOptions,
    provider: AccountProvider = .none,

    pub fn challengeRequest(self: AuthorizationPlan) ?SessionChallengeRequest {
        return sessionChallengeRequest(self.options, self.provider);
    }

    pub fn challengeText(
        self: AuthorizationPlan,
        allocator: std.mem.Allocator,
    ) !?[]u8 {
        const request = self.challengeRequest() orelse return null;
        return try buildSessionChallengeText(allocator, request);
    }

    pub fn withChallengeResponse(
        self: AuthorizationPlan,
        response: SessionChallengeResponse,
    ) !AuthorizationPlan {
        return .{
            .options = self.options,
            .provider = try applySessionChallengeResponse(self.provider, response),
        };
    }

    pub fn authorize(
        self: AuthorizationPlan,
        allocator: std.mem.Allocator,
    ) !AuthorizedPreparedRequest {
        return try prepareAuthorizedRequest(allocator, self.options, self.provider);
    }

    pub fn buildAuthorizedInspectPayload(
        self: AuthorizationPlan,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.buildArtifact(allocator, .inspect_payload);
    }

    pub fn buildAuthorizedExecutePayload(
        self: AuthorizationPlan,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.buildArtifact(allocator, .execute_payload);
    }

    pub fn buildArtifact(
        self: AuthorizationPlan,
        allocator: std.mem.Allocator,
        kind: ProgrammaticArtifactKind,
    ) ![]u8 {
        var prepared = try self.authorize(allocator);
        defer prepared.deinit(allocator);
        return try prepared.buildArtifact(allocator, kind);
    }

    pub fn buildTransactionBlock(
        self: AuthorizationPlan,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.buildArtifact(allocator, .transaction_block);
    }
};

pub fn authorizationPlan(
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) AuthorizationPlan {
    return .{
        .options = options,
        .provider = provider,
    };
}

pub fn authorizationPlanFromRequest(
    request: tx_builder.ProgrammaticTxRequest,
    provider: AccountProvider,
) AuthorizationPlan {
    return authorizationPlan(optionsFromRequest(request), provider);
}

pub fn authorizationPlanFromCommandSource(
    source: tx_builder.CommandSource,
    config: CommandRequestConfig,
    provider: AccountProvider,
) AuthorizationPlan {
    return authorizationPlan(optionsFromCommandSource(source, config), provider);
}

pub const OwnedAuthorizationPlan = struct {
    owned_options: OwnedProgrammaticRequestOptions,
    provider: AccountProvider = .none,

    pub fn deinit(self: *OwnedAuthorizationPlan, allocator: std.mem.Allocator) void {
        self.owned_options.deinit(allocator);
    }

    pub fn plan(self: *const OwnedAuthorizationPlan) AuthorizationPlan {
        return authorizationPlan(self.owned_options.options, self.provider);
    }

    pub fn challengeRequest(self: *const OwnedAuthorizationPlan) ?SessionChallengeRequest {
        return self.plan().challengeRequest();
    }

    pub fn challengeText(
        self: *const OwnedAuthorizationPlan,
        allocator: std.mem.Allocator,
    ) !?[]u8 {
        return try self.plan().challengeText(allocator);
    }

    pub fn withChallengeResponse(
        self: *OwnedAuthorizationPlan,
        response: SessionChallengeResponse,
    ) !void {
        self.provider = try applySessionChallengeResponse(self.provider, response);
    }

    pub fn authorize(
        self: *const OwnedAuthorizationPlan,
        allocator: std.mem.Allocator,
    ) !AuthorizedPreparedRequest {
        return try self.plan().authorize(allocator);
    }

    pub fn buildAuthorizedInspectPayload(
        self: *const OwnedAuthorizationPlan,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.plan().buildAuthorizedInspectPayload(allocator);
    }

    pub fn buildAuthorizedExecutePayload(
        self: *const OwnedAuthorizationPlan,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.plan().buildAuthorizedExecutePayload(allocator);
    }

    pub fn buildTransactionBlock(
        self: *const OwnedAuthorizationPlan,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.plan().buildTransactionBlock(allocator);
    }

    pub fn buildArtifact(
        self: *const OwnedAuthorizationPlan,
        allocator: std.mem.Allocator,
        kind: ProgrammaticArtifactKind,
    ) ![]u8 {
        return try self.plan().buildArtifact(allocator, kind);
    }
};

pub const OwnedProgrammaticRequestOptions = struct {
    options: ProgrammaticRequestOptions,
    owned_commands_json: ?[]u8 = null,
    owned_sender: ?[]u8 = null,
    owned_gas_payment_json: ?[]u8 = null,
    owned_options_json: ?[]u8 = null,
    owned_signatures: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *OwnedProgrammaticRequestOptions, allocator: std.mem.Allocator) void {
        if (self.owned_commands_json) |value| allocator.free(value);
        self.owned_commands_json = null;
        if (self.owned_sender) |value| allocator.free(value);
        self.owned_sender = null;
        if (self.owned_gas_payment_json) |value| allocator.free(value);
        self.owned_gas_payment_json = null;
        if (self.owned_options_json) |value| allocator.free(value);
        self.owned_options_json = null;
        for (self.owned_signatures.items) |value| allocator.free(value);
        self.owned_signatures.deinit(allocator);
    }

    pub fn takeCommandsJson(self: *OwnedProgrammaticRequestOptions) ?[]u8 {
        const value = self.owned_commands_json orelse return null;
        self.owned_commands_json = null;
        self.options.source.commands_json = null;
        return value;
    }

    pub fn request(self: *const OwnedProgrammaticRequestOptions) tx_builder.ProgrammaticTxRequest {
        return requestFromOptions(self.options);
    }

    pub fn prepare(
        self: *const OwnedProgrammaticRequestOptions,
        allocator: std.mem.Allocator,
    ) !tx_builder.PreparedProgrammaticTxRequest {
        return try prepareRequest(allocator, self.options);
    }

    pub fn buildInspectPayload(
        self: *const OwnedProgrammaticRequestOptions,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var prepared = try prepareRequest(allocator, self.options);
        defer prepared.deinit(allocator);
        return try prepared.buildInspectPayload(allocator);
    }

    pub fn buildExecutePayload(
        self: *const OwnedProgrammaticRequestOptions,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var prepared = try prepareRequest(allocator, self.options);
        defer prepared.deinit(allocator);
        return try prepared.buildExecutePayload(allocator);
    }

    pub fn authorizationPlan(
        self: OwnedProgrammaticRequestOptions,
        provider: AccountProvider,
    ) OwnedAuthorizationPlan {
        return .{
            .owned_options = self,
            .provider = provider,
        };
    }
};

pub fn ownOptions(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
) !OwnedProgrammaticRequestOptions {
    var prepared = try prepareRequest(allocator, options);
    defer prepared.deinit(allocator);

    var owned = OwnedProgrammaticRequestOptions{
        .options = .{
            .source = .{},
            .sender = null,
            .gas_budget = prepared.request.gas_budget,
            .gas_price = prepared.request.gas_price,
            .gas_payment_json = null,
            .signatures = &.{},
            .options_json = null,
            .wait_for_confirmation = prepared.request.wait_for_confirmation,
            .confirm_timeout_ms = prepared.request.confirm_timeout_ms,
            .confirm_poll_ms = prepared.request.confirm_poll_ms,
        },
    };
    errdefer owned.deinit(allocator);

    owned.owned_commands_json = try allocator.dupe(u8, prepared.owned_commands_json);
    owned.options.source = .{ .commands_json = owned.owned_commands_json };

    if (prepared.request.sender) |value| {
        owned.owned_sender = try allocator.dupe(u8, value);
        owned.options.sender = owned.owned_sender;
    }

    if (prepared.request.gas_payment_json) |value| {
        owned.owned_gas_payment_json = try allocator.dupe(u8, value);
        owned.options.gas_payment_json = owned.owned_gas_payment_json;
    }

    if (prepared.request.options_json) |value| {
        owned.owned_options_json = try allocator.dupe(u8, value);
        owned.options.options_json = owned.owned_options_json;
    }

    for (prepared.request.signatures) |value| {
        try owned.owned_signatures.append(allocator, try allocator.dupe(u8, value));
    }
    owned.options.signatures = owned.owned_signatures.items;

    return owned;
}

pub fn ownRequest(
    allocator: std.mem.Allocator,
    request: tx_builder.ProgrammaticTxRequest,
) !OwnedProgrammaticRequestOptions {
    return try ownOptions(allocator, optionsFromRequest(request));
}

pub fn ownOptionsFromCommandSource(
    allocator: std.mem.Allocator,
    source: tx_builder.CommandSource,
    config: CommandRequestConfig,
) !OwnedProgrammaticRequestOptions {
    return try ownOptions(allocator, optionsFromCommandSource(source, config));
}

pub const OwnedCommandItems = struct {
    items: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *OwnedCommandItems, allocator: std.mem.Allocator) void {
        for (self.items.items) |value| allocator.free(value);
        self.items.deinit(allocator);
    }

    pub fn appendToOwnedLists(
        self: *OwnedCommandItems,
        allocator: std.mem.Allocator,
        items: *std.ArrayListUnmanaged([]const u8),
        owned_items: *std.ArrayListUnmanaged([]const u8),
    ) !void {
        try items.appendSlice(allocator, self.items.items);
        try owned_items.appendSlice(allocator, self.items.items);
        self.items.deinit(allocator);
        self.items = .{};
    }
};

pub fn deinitCommandResultAliases(
    allocator: std.mem.Allocator,
    aliases: *CommandResultAliases,
) void {
    var iterator = aliases.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
    aliases.deinit(allocator);
}

pub fn cloneCommandResultAliases(
    allocator: std.mem.Allocator,
    aliases: *const CommandResultAliases,
) !CommandResultAliases {
    var cloned = CommandResultAliases{};
    errdefer deinitCommandResultAliases(allocator, &cloned);

    var iterator = aliases.iterator();
    while (iterator.next()) |entry| {
        const owned_name = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(owned_name);
        try cloned.put(allocator, owned_name, entry.value_ptr.*);
    }

    return cloned;
}

pub fn assignCommandResultAlias(
    allocator: std.mem.Allocator,
    aliases: *CommandResultAliases,
    raw_name: []const u8,
    command_index: usize,
) !void {
    const name = std.mem.trim(u8, raw_name, " \n\r\t");
    if (name.len == 0) return error.InvalidCli;
    if (std.mem.indexOfScalar(u8, name, ':') != null) return error.InvalidCli;
    if (aliases.contains(name)) return error.InvalidCli;

    const cast_index = std.math.cast(u16, command_index) orelse return error.InvalidCli;
    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);
    try aliases.put(allocator, owned_name, cast_index);
}

pub fn resolveNamedResultReferenceToken(
    allocator: std.mem.Allocator,
    aliases: *const CommandResultAliases,
    raw: []const u8,
) !?[]u8 {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (!std.mem.startsWith(u8, trimmed, "ptb:name:")) return null;

    const spec = trimmed["ptb:name:".len..];
    if (spec.len == 0) return error.InvalidCli;

    const separator = std.mem.indexOfScalar(u8, spec, ':');
    const alias_name = if (separator) |index| spec[0..index] else spec;
    if (alias_name.len == 0) return error.InvalidCli;

    const command_index = aliases.get(alias_name) orelse return error.InvalidCli;
    if (separator) |index| {
        const result_index = try std.fmt.parseInt(u16, spec[index + 1 ..], 10);
        return try std.fmt.allocPrint(allocator, "ptb:nested:{}:{}", .{ command_index, result_index });
    }

    return try std.fmt.allocPrint(allocator, "ptb:result:{}", .{command_index});
}

fn applyCommandIndexOffset(
    value: ArgumentValue,
    command_index_offset: u16,
) !ArgumentValue {
    return switch (value) {
        .result => |result| .{
            .result = .{
                .command_index = try std.math.add(u16, result.command_index, command_index_offset),
            },
        },
        .output => |output| .{
            .output = .{
                .command_index = try std.math.add(u16, output.command_index, command_index_offset),
                .result_index = output.result_index,
            },
        },
        else => value,
    };
}

fn tokenUsesRelativeCommandIndex(raw: []const u8) bool {
    return std.mem.startsWith(u8, raw, "result:") or
        std.mem.startsWith(u8, raw, "ptb:result:") or
        std.mem.startsWith(u8, raw, "output:") or
        std.mem.startsWith(u8, raw, "nested:") or
        std.mem.startsWith(u8, raw, "ptb:nested:");
}

fn writeArgumentValueJsonFromJsonValueWithOffset(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    command_index_offset: u16,
    writer: anytype,
    value: std.json.Value,
) anyerror!void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool, .integer, .float, .number_string => try writer.print("{f}", .{std.json.fmt(value, .{})}),
        .string => {
            var resolved = try parseArgumentValueToken(allocator, aliases, value.string);
            defer resolved.deinit(allocator);
            const offset_value = if (command_index_offset != 0 and tokenUsesRelativeCommandIndex(value.string))
                try applyCommandIndexOffset(resolved.value, command_index_offset)
            else
                resolved.value;
            const rendered = try buildArgumentValueJson(allocator, offset_value);
            defer allocator.free(rendered);
            try writer.writeAll(rendered);
        },
        .array => |array| {
            try writer.writeAll("[");
            for (array.items, 0..) |item, index| {
                if (index != 0) try writer.writeAll(",");
                try writeArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, writer, item);
            }
            try writer.writeAll("]");
        },
        .object => |object| {
            try writer.writeAll("{");
            var iterator = object.iterator();
            var index: usize = 0;
            while (iterator.next()) |entry| : (index += 1) {
                if (index != 0) try writer.writeAll(",");
                try writer.print("{f}:", .{std.json.fmt(entry.key_ptr.*, .{})});
                try writeArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, writer, entry.value_ptr.*);
            }
            try writer.writeAll("}");
        },
    }
}

fn writeArgumentValueJsonFromJsonValue(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    writer: anytype,
    value: std.json.Value,
) anyerror!void {
    try writeArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, 0, writer, value);
}

fn buildArgumentValueJsonFromJsonValueWithOffset(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    command_index_offset: u16,
    value: std.json.Value,
) anyerror![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    try writeArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, out.writer(allocator), value);
    return try out.toOwnedSlice(allocator);
}

fn buildArgumentValueJsonFromJsonValue(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    value: std.json.Value,
) anyerror![]u8 {
    return try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, 0, value);
}

fn splitTopLevelArgumentTokens(
    allocator: std.mem.Allocator,
    raw: []const u8,
) !std.ArrayList([]const u8) {
    var items = std.ArrayList([]const u8){};
    errdefer items.deinit(allocator);

    if (std.mem.trim(u8, raw, " \n\r\t").len == 0) return items;

    var start: usize = 0;
    var bracket_depth: usize = 0;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var in_string = false;
    var escaped = false;

    for (raw, 0..) |ch, index| {
        if (in_string) {
            if (escaped) {
                escaped = false;
                continue;
            }
            switch (ch) {
                '\\' => escaped = true,
                '"' => in_string = false,
                else => {},
            }
            continue;
        }

        switch (ch) {
            '"' => in_string = true,
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth == 0) return error.InvalidCli;
                bracket_depth -= 1;
            },
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth == 0) return error.InvalidCli;
                paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth == 0) return error.InvalidCli;
                brace_depth -= 1;
            },
            ',' => {
                if (bracket_depth == 0 and paren_depth == 0 and brace_depth == 0) {
                    const item = std.mem.trim(u8, raw[start..index], " \n\r\t");
                    if (item.len == 0) return error.InvalidCli;
                    try items.append(allocator, item);
                    start = index + 1;
                }
            },
            else => {},
        }
    }

    if (in_string or bracket_depth != 0 or paren_depth != 0 or brace_depth != 0) {
        return error.InvalidCli;
    }

    const tail = std.mem.trim(u8, raw[start..], " \n\r\t");
    if (tail.len == 0) return error.InvalidCli;
    try items.append(allocator, tail);
    return items;
}

fn resolveAliasReferenceToken(
    aliases: *const CommandResultAliases,
    raw: []const u8,
) !?ArgumentValue {
    if (aliases.get(raw)) |command_index| {
        return .{ .result = .{ .command_index = command_index } };
    }

    const separator = std.mem.lastIndexOfScalar(u8, raw, '.') orelse return null;
    const alias_name = raw[0..separator];
    const output_spec = raw[separator + 1 ..];
    if (alias_name.len == 0 or output_spec.len == 0) return error.InvalidCli;

    const command_index = aliases.get(alias_name) orelse return null;
    return .{
        .output = .{
            .command_index = command_index,
            .result_index = try std.fmt.parseInt(u16, output_spec, 10),
        },
    };
}

pub fn parseArgumentValueToken(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    raw: []const u8,
) anyerror!ResolvedArgumentValue {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    if (aliases) |value_aliases| {
        if (try resolveAliasReferenceToken(value_aliases, trimmed)) |resolved_alias| {
            return .{ .value = resolved_alias };
        }

        if (std.mem.startsWith(u8, trimmed, "ptb:name:")) {
            const spec = trimmed["ptb:name:".len..];
            if (spec.len == 0) return error.InvalidCli;

            const separator = std.mem.indexOfScalar(u8, spec, ':');
            const alias_name = if (separator) |index| spec[0..index] else spec;
            if (alias_name.len == 0) return error.InvalidCli;

            const command_index = value_aliases.get(alias_name) orelse return error.InvalidCli;
            if (separator) |index| {
                const result_index = try std.fmt.parseInt(u16, spec[index + 1 ..], 10);
                return .{ .value = .{
                    .output = .{
                        .command_index = command_index,
                        .result_index = result_index,
                    },
                } };
            }
            return .{ .value = .{ .result = .{ .command_index = command_index } } };
        }
    }

    if (std.mem.eql(u8, trimmed, "gas") or std.mem.eql(u8, trimmed, "ptb:gas")) {
        return .{ .value = .gas_coin };
    }
    if (std.mem.startsWith(u8, trimmed, "input:")) {
        return .{ .value = .{ .input = try std.fmt.parseInt(u16, trimmed["input:".len..], 10) } };
    }
    if (std.mem.startsWith(u8, trimmed, "ptb:input:")) {
        return .{ .value = .{ .input = try std.fmt.parseInt(u16, trimmed["ptb:input:".len..], 10) } };
    }
    if (std.mem.startsWith(u8, trimmed, "result:")) {
        return .{ .value = .{ .result = .{ .command_index = try std.fmt.parseInt(u16, trimmed["result:".len..], 10) } } };
    }
    if (std.mem.startsWith(u8, trimmed, "ptb:result:")) {
        return .{ .value = .{ .result = .{ .command_index = try std.fmt.parseInt(u16, trimmed["ptb:result:".len..], 10) } } };
    }
    if (std.mem.startsWith(u8, trimmed, "output:") or std.mem.startsWith(u8, trimmed, "nested:") or std.mem.startsWith(u8, trimmed, "ptb:nested:")) {
        const prefix_len: usize = if (std.mem.startsWith(u8, trimmed, "output:"))
            "output:".len
        else if (std.mem.startsWith(u8, trimmed, "nested:"))
            "nested:".len
        else
            "ptb:nested:".len;
        const rest = trimmed[prefix_len..];
        const separator = std.mem.indexOfScalar(u8, rest, ':') orelse return error.InvalidCli;
        return .{ .value = .{
            .output = .{
                .command_index = try std.fmt.parseInt(u16, rest[0..separator], 10),
                .result_index = try std.fmt.parseInt(u16, rest[separator + 1 ..], 10),
            },
        } };
    }

    if (trimmed[0] == '@') {
        if (trimmed.len == 1) return error.InvalidCli;
        return .{ .value = .{ .address = trimmed[1..] } };
    }
    if (std.mem.startsWith(u8, trimmed, "addr:")) return .{ .value = .{ .address = trimmed["addr:".len..] } };
    if (std.mem.startsWith(u8, trimmed, "obj:")) return .{ .value = .{ .object_id = trimmed["obj:".len..] } };
    if (std.mem.startsWith(u8, trimmed, "bytes:")) return .{ .value = .{ .bytes = trimmed["bytes:".len..] } };
    if (std.mem.startsWith(u8, trimmed, "str:")) return .{ .value = .{ .string = trimmed["str:".len..] } };
    if (std.mem.startsWith(u8, trimmed, "bool:")) {
        const value = trimmed["bool:".len..];
        if (std.mem.eql(u8, value, "true")) return .{ .value = .{ .boolean = true } };
        if (std.mem.eql(u8, value, "false")) return .{ .value = .{ .boolean = false } };
        return error.InvalidCli;
    }
    if (std.mem.startsWith(u8, trimmed, "u8:")) return .{ .value = .{ .u8 = try std.fmt.parseInt(u8, trimmed["u8:".len..], 10) } };
    if (std.mem.startsWith(u8, trimmed, "u16:")) return .{ .value = .{ .u16 = try std.fmt.parseInt(u16, trimmed["u16:".len..], 10) } };
    if (std.mem.startsWith(u8, trimmed, "u32:")) return .{ .value = .{ .u32 = try std.fmt.parseInt(u32, trimmed["u32:".len..], 10) } };
    if (std.mem.startsWith(u8, trimmed, "u64:")) return .{ .value = .{ .u64 = try std.fmt.parseInt(u64, trimmed["u64:".len..], 10) } };
    if (std.mem.startsWith(u8, trimmed, "u128:")) return .{ .value = .{ .u128 = try std.fmt.parseInt(u128, trimmed["u128:".len..], 10) } };
    if (std.mem.startsWith(u8, trimmed, "u256:")) return .{ .value = .{ .u256 = try std.fmt.parseInt(u256, trimmed["u256:".len..], 10) } };
    if (std.mem.startsWith(u8, trimmed, "i64:")) return .{ .value = .{ .i64 = try std.fmt.parseInt(i64, trimmed["i64:".len..], 10) } };
    if (std.mem.eql(u8, trimmed, "none") or std.mem.eql(u8, trimmed, "option:none")) return .{ .value = .null };
    if (std.mem.startsWith(u8, trimmed, "vector[")) {
        if (!std.mem.endsWith(u8, trimmed, "]")) return error.InvalidCli;
        const inner = trimmed["vector[".len .. trimmed.len - 1];
        var inner_tokens = try splitTopLevelArgumentTokens(allocator, inner);
        defer inner_tokens.deinit(allocator);
        var values = try parseArgumentValueTokens(allocator, aliases, inner_tokens.items);
        defer values.deinit(allocator);
        const owned_json = try buildArgumentValueArray(allocator, values.items.items);
        return .{
            .value = .{ .raw_json = owned_json },
            .owned_json = owned_json,
        };
    }
    if (std.mem.startsWith(u8, trimmed, "vec:")) {
        const raw_json = trimmed["vec:".len..];
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_json, .{});
        defer parsed.deinit();
        if (parsed.value != .array) return error.InvalidCli;
        const owned_json = try buildArgumentValueJsonFromJsonValue(allocator, aliases, parsed.value);
        return .{
            .value = .{ .raw_json = owned_json },
            .owned_json = owned_json,
        };
    }
    if (std.mem.startsWith(u8, trimmed, "some(")) {
        if (!std.mem.endsWith(u8, trimmed, ")")) return error.InvalidCli;
        const inner = std.mem.trim(u8, trimmed["some(".len .. trimmed.len - 1], " \n\r\t");
        if (inner.len == 0) return error.InvalidCli;
        var value = try parseArgumentValueToken(allocator, aliases, inner);
        defer value.deinit(allocator);
        const owned_json = try buildArgumentValueJson(allocator, value.value);
        return .{
            .value = .{ .raw_json = owned_json },
            .owned_json = owned_json,
        };
    }
    if (std.mem.startsWith(u8, trimmed, "some:") or std.mem.startsWith(u8, trimmed, "option:some:")) {
        const prefix_len: usize = if (std.mem.startsWith(u8, trimmed, "some:"))
            "some:".len
        else
            "option:some:".len;
        const raw_json = trimmed[prefix_len..];
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_json, .{});
        defer parsed.deinit();
        const owned_json = try buildArgumentValueJsonFromJsonValue(allocator, aliases, parsed.value);
        return .{
            .value = .{ .raw_json = owned_json },
            .owned_json = owned_json,
        };
    }
    if (std.mem.eql(u8, trimmed, "null")) return .{ .value = .null };

    if (std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{})) |parsed| {
        defer parsed.deinit();
        const owned_json = try buildArgumentValueJsonFromJsonValue(allocator, aliases, parsed.value);
        return .{
            .value = .{ .raw_json = owned_json },
            .owned_json = owned_json,
        };
    } else |_| {}

    return .{ .value = .{ .string = trimmed } };
}

pub fn parseArgumentValueTokens(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    raws: []const []const u8,
) anyerror!OwnedArgumentValues {
    var values = OwnedArgumentValues{};
    errdefer values.deinit(allocator);

    for (raws) |raw| {
        var value = try parseArgumentValueToken(allocator, aliases, raw);
        errdefer value.deinit(allocator);
        try values.items.append(allocator, value.value);
        if (value.owned_json) |owned_json| {
            try values.owned_json_items.append(allocator, owned_json);
            value.owned_json = null;
        }
    }

    return values;
}

pub fn resolveCommandValue(
    allocator: std.mem.Allocator,
    aliases: *const CommandResultAliases,
    raw: []const u8,
) !ResolvedCommandValue {
    if (try resolveNamedResultReferenceToken(allocator, aliases, raw)) |resolved| {
        return .{ .value = resolved, .owned = resolved };
    }
    return .{ .value = raw };
}

pub fn resolveCommandValues(
    allocator: std.mem.Allocator,
    aliases: *const CommandResultAliases,
    raw_items: []const []const u8,
) !ResolvedCommandValues {
    var resolved = ResolvedCommandValues{};
    errdefer resolved.deinit(allocator);

    for (raw_items) |raw| {
        if (try resolveNamedResultReferenceToken(allocator, aliases, raw)) |value| {
            try resolved.items.append(allocator, value);
            try resolved.owned_items.append(allocator, value);
        } else {
            try resolved.items.append(allocator, raw);
        }
    }

    return resolved;
}

fn parsePtbArgumentSpecToken(raw: []const u8) !?PtbArgumentSpec {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (!std.mem.startsWith(u8, trimmed, "ptb:")) return null;

    const spec = trimmed["ptb:".len..];
    if (spec.len == 0) return error.InvalidCli;

    if (std.mem.eql(u8, spec, "gas") or std.mem.eql(u8, spec, "gascoin")) {
        return .gas_coin;
    }
    if (std.mem.startsWith(u8, spec, "input:")) {
        return .{ .input = try std.fmt.parseInt(u16, spec["input:".len..], 10) };
    }
    if (std.mem.startsWith(u8, spec, "result:")) {
        return .{ .result = try std.fmt.parseInt(u16, spec["result:".len..], 10) };
    }
    if (std.mem.startsWith(u8, spec, "nested:")) {
        const rest = spec["nested:".len..];
        const sep = std.mem.indexOfScalar(u8, rest, ':') orelse return error.InvalidCli;
        return .{ .nested_result = .{
            .command_index = try std.fmt.parseInt(u16, rest[0..sep], 10),
            .result_index = try std.fmt.parseInt(u16, rest[sep + 1 ..], 10),
        } };
    }

    return error.InvalidCli;
}

pub fn resolvePtbArgumentSpec(
    allocator: std.mem.Allocator,
    aliases: *const CommandResultAliases,
    raw: []const u8,
) !ResolvedPtbArgumentSpec {
    const resolved_named = try resolveNamedResultReferenceToken(allocator, aliases, raw);
    defer if (resolved_named) |value| allocator.free(value);

    const value = if (resolved_named) |named| named else raw;
    if (try parsePtbArgumentSpecToken(value)) |spec| {
        return .{ .spec = spec };
    }

    const json = try tx_builder.buildCliValueJson(allocator, value);
    return .{
        .spec = .{ .json = json },
        .owned_json = json,
    };
}

pub fn resolvePtbArgumentSpecs(
    allocator: std.mem.Allocator,
    aliases: *const CommandResultAliases,
    raw_items: []const []const u8,
) !ResolvedPtbArgumentSpecs {
    var resolved = ResolvedPtbArgumentSpecs{};
    errdefer resolved.deinit(allocator);

    for (raw_items) |raw| {
        var item = try resolvePtbArgumentSpec(allocator, aliases, raw);
        errdefer item.deinit(allocator);

        try resolved.items.append(allocator, item.spec);
        if (item.owned_json) |value| {
            try resolved.owned_json_items.append(allocator, value);
            item.owned_json = null;
        }
    }

    return resolved;
}

fn writeCanonicalJsonValue(
    allocator: std.mem.Allocator,
    writer: anytype,
    raw: []const u8,
) !void {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
}

fn buildCanonicalJsonValue(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    try writeCanonicalJsonValue(allocator, out.writer(allocator), raw);
    return try out.toOwnedSlice(allocator);
}

fn writePtbArgumentSpecJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    spec: PtbArgumentSpec,
) !void {
    switch (spec) {
        .gas_coin => try writer.writeAll("\"GasCoin\""),
        .input => |index| try writer.print("{{\"Input\":{}}}", .{index}),
        .result => |index| try writer.print("{{\"Result\":{}}}", .{index}),
        .nested_result => |nested| try writer.print(
            "{{\"NestedResult\":[{},{}]}}",
            .{ nested.command_index, nested.result_index },
        ),
        .json => |raw| try writeCanonicalJsonValue(allocator, writer, raw),
    }
}

pub fn buildPtbArgumentJson(
    allocator: std.mem.Allocator,
    spec: PtbArgumentSpec,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    try writePtbArgumentSpecJson(allocator, out.writer(allocator), spec);
    return try out.toOwnedSlice(allocator);
}

pub fn buildPtbArgumentArray(
    allocator: std.mem.Allocator,
    specs: []const PtbArgumentSpec,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("[");
    for (specs, 0..) |spec, index| {
        if (index != 0) try writer.writeAll(",");
        try writePtbArgumentSpecJson(allocator, writer, spec);
    }
    try writer.writeAll("]");

    return try out.toOwnedSlice(allocator);
}

pub fn buildArgumentValueJson(
    allocator: std.mem.Allocator,
    value: ArgumentValue,
) ![]u8 {
    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    var resolved = try builder.argumentValueToSpec(value);
    defer resolved.deinit(allocator);

    return try buildPtbArgumentJson(allocator, resolved.spec);
}

pub fn buildArgumentValueArray(
    allocator: std.mem.Allocator,
    values: []const ArgumentValue,
) ![]u8 {
    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    var resolved = try builder.argumentValuesToSpecs(values);
    defer resolved.deinit(allocator);

    return try buildPtbArgumentArray(allocator, resolved.items.items);
}

pub fn buildArgumentValueTokenArray(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    raws: []const []const u8,
) ![]u8 {
    var values = try parseArgumentValueTokens(allocator, aliases, raws);
    defer values.deinit(allocator);

    return try buildArgumentValueArray(allocator, values.items.items);
}

pub fn normalizeArgumentValueJsonArray(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    raw_json: []const u8,
) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidCli;
    return try buildArgumentValueJsonFromJsonValue(allocator, aliases, parsed.value);
}

fn stringifyJsonValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    try out.writer(allocator).print("{f}", .{std.json.fmt(value, .{})});
    return try out.toOwnedSlice(allocator);
}

fn resolvePackageIdAliasOrRaw(raw: []const u8) []const u8 {
    return package_preset.resolvePackageIdAlias(raw) orelse raw;
}

fn normalizeRawCommandJson(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    command_index_offset: u16,
    commands_json: []const u8,
) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    var builder = ProgrammaticRequestOptionsBuilder.init(allocator);
    defer builder.deinit();

    var single_item: [1]std.json.Value = undefined;
    const items = switch (parsed.value) {
        .array => parsed.value.array.items,
        .object => blk: {
            single_item[0] = parsed.value;
            break :blk single_item[0..];
        },
        else => return error.InvalidCli,
    };

    for (items) |entry| {
        if (entry != .object) return error.InvalidCli;
        const kind_value = entry.object.get("kind") orelse return error.InvalidCli;
        if (kind_value != .string) return error.InvalidCli;

        if (std.mem.eql(u8, kind_value.string, "MoveCall")) {
            const package_id = entry.object.get("package") orelse return error.InvalidCli;
            const module = entry.object.get("module") orelse return error.InvalidCli;
            const function_name = entry.object.get("function") orelse return error.InvalidCli;
            if (package_id != .string or module != .string or function_name != .string) return error.InvalidCli;
            const resolved_package_id = resolvePackageIdAliasOrRaw(package_id.string);

            var type_args_json: ?[]u8 = null;
            defer if (type_args_json) |value| allocator.free(value);
            if (entry.object.get("typeArguments")) |value| {
                if (value != .null) type_args_json = try stringifyJsonValue(allocator, value);
            }

            var arguments_json: ?[]u8 = null;
            defer if (arguments_json) |value| allocator.free(value);
            if (entry.object.get("arguments")) |value| {
                if (value != .null) arguments_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, value);
            }

            try builder.appendMoveCall(.{
                .package_id = resolved_package_id,
                .module = module.string,
                .function_name = function_name.string,
                .type_args = if (type_args_json) |value| value else null,
                .arguments = if (arguments_json) |value| value else null,
            });
            continue;
        }

        if (std.mem.eql(u8, kind_value.string, "TransferObjects")) {
            const objects = entry.object.get("objects") orelse return error.InvalidCli;
            const address = entry.object.get("address") orelse return error.InvalidCli;
            const objects_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, objects);
            defer allocator.free(objects_json);
            const address_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, address);
            defer allocator.free(address_json);
            try builder.appendTransferObjects(.{
                .objects_json = objects_json,
                .address_json = address_json,
            });
            continue;
        }

        if (std.mem.eql(u8, kind_value.string, "SplitCoins")) {
            const coin = entry.object.get("coin") orelse return error.InvalidCli;
            const amounts = entry.object.get("amounts") orelse return error.InvalidCli;
            const coin_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, coin);
            defer allocator.free(coin_json);
            const amounts_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, amounts);
            defer allocator.free(amounts_json);
            try builder.appendSplitCoins(.{
                .coin_json = coin_json,
                .amounts_json = amounts_json,
            });
            continue;
        }

        if (std.mem.eql(u8, kind_value.string, "MergeCoins")) {
            const destination = entry.object.get("destination") orelse return error.InvalidCli;
            const sources = entry.object.get("sources") orelse return error.InvalidCli;
            const destination_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, destination);
            defer allocator.free(destination_json);
            const sources_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, sources);
            defer allocator.free(sources_json);
            try builder.appendMergeCoins(.{
                .destination_json = destination_json,
                .sources_json = sources_json,
            });
            continue;
        }

        if (std.mem.eql(u8, kind_value.string, "MakeMoveVec")) {
            const elements = entry.object.get("elements") orelse return error.InvalidCli;
            const elements_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, elements);
            defer allocator.free(elements_json);

            var type_json: ?[]u8 = null;
            defer if (type_json) |value| allocator.free(value);
            if (entry.object.get("type")) |value| {
                if (value != .null) type_json = try stringifyJsonValue(allocator, value);
            }

            try builder.appendMakeMoveVec(.{
                .type_json = if (type_json) |value| value else null,
                .elements_json = elements_json,
            });
            continue;
        }

        if (std.mem.eql(u8, kind_value.string, "Publish")) {
            const modules = entry.object.get("modules") orelse return error.InvalidCli;
            const dependencies = entry.object.get("dependencies") orelse return error.InvalidCli;
            const modules_json = try stringifyJsonValue(allocator, modules);
            defer allocator.free(modules_json);
            const dependencies_json = try stringifyJsonValue(allocator, dependencies);
            defer allocator.free(dependencies_json);
            try builder.appendPublish(.{
                .modules_json = modules_json,
                .dependencies_json = dependencies_json,
            });
            continue;
        }

        if (std.mem.eql(u8, kind_value.string, "Upgrade")) {
            const modules = entry.object.get("modules") orelse return error.InvalidCli;
            const dependencies = entry.object.get("dependencies") orelse return error.InvalidCli;
            const package_id = entry.object.get("package") orelse return error.InvalidCli;
            const ticket = entry.object.get("ticket") orelse return error.InvalidCli;
            if (package_id != .string) return error.InvalidCli;
            const resolved_package_id = resolvePackageIdAliasOrRaw(package_id.string);

            const modules_json = try stringifyJsonValue(allocator, modules);
            defer allocator.free(modules_json);
            const dependencies_json = try stringifyJsonValue(allocator, dependencies);
            defer allocator.free(dependencies_json);
            const ticket_json = try buildArgumentValueJsonFromJsonValueWithOffset(allocator, aliases, command_index_offset, ticket);
            defer allocator.free(ticket_json);
            try builder.appendUpgrade(.{
                .modules_json = modules_json,
                .dependencies_json = dependencies_json,
                .package_id = resolved_package_id,
                .ticket_json = ticket_json,
            });
            continue;
        }

        const raw_entry = try stringifyJsonValue(allocator, entry);
        defer allocator.free(raw_entry);
        try builder.commands.appendRawJson(raw_entry);
    }

    var owned = try builder.finish();
    errdefer owned.deinit(allocator);
    return owned.takeCommandsJson() orelse error.InvalidCli;
}

pub const ProgrammaticRequestOptionsBuilder = struct {
    commands: tx_builder.CommandBuilder,
    config: CommandRequestConfig = .{},

    pub fn init(allocator: std.mem.Allocator) ProgrammaticRequestOptionsBuilder {
        return .{ .commands = tx_builder.CommandBuilder.init(allocator) };
    }

    pub fn deinit(self: *ProgrammaticRequestOptionsBuilder) void {
        self.commands.deinit();
    }

    pub fn appendRawJson(self: *ProgrammaticRequestOptionsBuilder, commands_json: []const u8) !void {
        const normalized = try normalizeRawCommandJson(self.commands.allocator, null, 0, commands_json);
        defer self.commands.allocator.free(normalized);
        try self.commands.appendRawJson(normalized);
    }

    pub fn appendRawJsonWithAliases(
        self: *ProgrammaticRequestOptionsBuilder,
        aliases: ?*const CommandResultAliases,
        commands_json: []const u8,
    ) !void {
        const normalized = try normalizeRawCommandJson(self.commands.allocator, aliases, 0, commands_json);
        defer self.commands.allocator.free(normalized);
        try self.commands.appendRawJson(normalized);
    }

    pub fn appendMoveCall(self: *ProgrammaticRequestOptionsBuilder, spec: tx_builder.MoveCallSpec) !void {
        try self.commands.appendMoveCall(spec);
    }

    pub fn appendMoveCallFromSpecs(
        self: *ProgrammaticRequestOptionsBuilder,
        spec: struct {
            package_id: []const u8,
            module: []const u8,
            function_name: []const u8,
            type_arg_items: []const []const u8 = &.{},
            arguments: []const PtbArgumentSpec = &.{},
        },
    ) !void {
        var type_args_json: ?[]u8 = null;
        defer if (type_args_json) |value| self.commands.allocator.free(value);
        if (spec.type_arg_items.len > 0) {
            type_args_json = try tx_builder.buildJsonStringArray(self.commands.allocator, spec.type_arg_items);
        }

        var args_json: ?[]u8 = null;
        defer if (args_json) |value| self.commands.allocator.free(value);
        if (spec.arguments.len > 0) {
            args_json = try buildPtbArgumentArray(self.commands.allocator, spec.arguments);
        }

        try self.appendMoveCall(.{
            .package_id = spec.package_id,
            .module = spec.module,
            .function_name = spec.function_name,
            .type_args = if (type_args_json) |value| value else null,
            .arguments = if (args_json) |value| value else null,
        });
    }

    pub fn appendMoveCallFromCliValues(
        self: *ProgrammaticRequestOptionsBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arg_items: []const []const u8,
    ) !void {
        var type_args_json: ?[]u8 = null;
        defer if (type_args_json) |value| self.commands.allocator.free(value);
        if (type_arg_items.len > 0) {
            type_args_json = try tx_builder.buildJsonStringArray(self.commands.allocator, type_arg_items);
        }

        var args_json: ?[]u8 = null;
        defer if (args_json) |value| self.commands.allocator.free(value);
        if (arg_items.len > 0) {
            args_json = try tx_builder.buildCliPtbArgumentArray(self.commands.allocator, arg_items);
        }

        try self.appendMoveCall(.{
            .package_id = package_id,
            .module = module,
            .function_name = function_name,
            .type_args = if (type_args_json) |value| value else null,
            .arguments = if (args_json) |value| value else null,
        });
    }

    pub fn appendMakeMoveVec(
        self: *ProgrammaticRequestOptionsBuilder,
        spec: struct {
            type_json: ?[]const u8 = null,
            elements_json: []const u8,
        },
    ) !void {
        try self.commands.appendMakeMoveVec(.{
            .type_json = spec.type_json,
            .elements_json = spec.elements_json,
        });
    }

    pub fn appendMakeMoveVecFromSpecs(
        self: *ProgrammaticRequestOptionsBuilder,
        spec: struct {
            type_json: ?[]const u8 = null,
            elements: []const PtbArgumentSpec,
        },
    ) !void {
        var type_json: ?[]u8 = null;
        defer if (type_json) |value| self.commands.allocator.free(value);
        if (spec.type_json) |value| {
            type_json = try tx_builder.buildCliValueJson(self.commands.allocator, value);
        }

        const elements_json = try buildPtbArgumentArray(self.commands.allocator, spec.elements);
        defer self.commands.allocator.free(elements_json);

        try self.appendMakeMoveVec(.{
            .type_json = if (type_json) |value| value else null,
            .elements_json = elements_json,
        });
    }

    pub fn appendMakeMoveVecFromCliValues(
        self: *ProgrammaticRequestOptionsBuilder,
        type_value: ?[]const u8,
        element_items: []const []const u8,
    ) !void {
        var type_json: ?[]u8 = null;
        defer if (type_json) |value| self.commands.allocator.free(value);
        if (type_value) |value| {
            type_json = try tx_builder.buildCliValueJson(self.commands.allocator, value);
        }

        const elements_json = try tx_builder.buildCliPtbArgumentArray(self.commands.allocator, element_items);
        defer self.commands.allocator.free(elements_json);

        try self.appendMakeMoveVec(.{
            .type_json = if (type_json) |value| value else null,
            .elements_json = elements_json,
        });
    }

    pub fn appendTransferObjects(self: *ProgrammaticRequestOptionsBuilder, spec: tx_builder.TransferObjectsSpec) !void {
        try self.commands.appendTransferObjects(spec);
    }

    pub fn appendTransferObjectsFromSpecs(
        self: *ProgrammaticRequestOptionsBuilder,
        spec: struct {
            objects: []const PtbArgumentSpec,
            address: PtbArgumentSpec,
        },
    ) !void {
        const objects_json = try buildPtbArgumentArray(self.commands.allocator, spec.objects);
        defer self.commands.allocator.free(objects_json);
        const address_json = try buildPtbArgumentJson(self.commands.allocator, spec.address);
        defer self.commands.allocator.free(address_json);

        try self.appendTransferObjects(.{
            .objects_json = objects_json,
            .address_json = address_json,
        });
    }

    pub fn appendTransferObjectsFromCliValues(
        self: *ProgrammaticRequestOptionsBuilder,
        object_items: []const []const u8,
        address: []const u8,
    ) !void {
        const objects_json = try tx_builder.buildCliPtbArgumentArray(self.commands.allocator, object_items);
        defer self.commands.allocator.free(objects_json);
        const address_json = try tx_builder.buildCliPtbArgumentJson(self.commands.allocator, address);
        defer self.commands.allocator.free(address_json);

        try self.appendTransferObjects(.{
            .objects_json = objects_json,
            .address_json = address_json,
        });
    }

    pub fn appendSplitCoins(self: *ProgrammaticRequestOptionsBuilder, spec: tx_builder.SplitCoinsSpec) !void {
        try self.commands.appendSplitCoins(spec);
    }

    pub fn appendSplitCoinsFromSpecs(
        self: *ProgrammaticRequestOptionsBuilder,
        spec: struct {
            coin: PtbArgumentSpec,
            amounts: []const PtbArgumentSpec,
        },
    ) !void {
        const coin_json = try buildPtbArgumentJson(self.commands.allocator, spec.coin);
        defer self.commands.allocator.free(coin_json);
        const amounts_json = try buildPtbArgumentArray(self.commands.allocator, spec.amounts);
        defer self.commands.allocator.free(amounts_json);

        try self.appendSplitCoins(.{
            .coin_json = coin_json,
            .amounts_json = amounts_json,
        });
    }

    pub fn appendSplitCoinsFromCliValues(
        self: *ProgrammaticRequestOptionsBuilder,
        coin: []const u8,
        amount_items: []const []const u8,
    ) !void {
        const coin_json = try tx_builder.buildCliPtbArgumentJson(self.commands.allocator, coin);
        defer self.commands.allocator.free(coin_json);
        const amounts_json = try tx_builder.buildCliPtbArgumentArray(self.commands.allocator, amount_items);
        defer self.commands.allocator.free(amounts_json);

        try self.appendSplitCoins(.{
            .coin_json = coin_json,
            .amounts_json = amounts_json,
        });
    }

    pub fn appendMergeCoins(self: *ProgrammaticRequestOptionsBuilder, spec: tx_builder.MergeCoinsSpec) !void {
        try self.commands.appendMergeCoins(spec);
    }

    pub fn appendMergeCoinsFromSpecs(
        self: *ProgrammaticRequestOptionsBuilder,
        spec: struct {
            destination: PtbArgumentSpec,
            sources: []const PtbArgumentSpec,
        },
    ) !void {
        const destination_json = try buildPtbArgumentJson(self.commands.allocator, spec.destination);
        defer self.commands.allocator.free(destination_json);
        const sources_json = try buildPtbArgumentArray(self.commands.allocator, spec.sources);
        defer self.commands.allocator.free(sources_json);

        try self.appendMergeCoins(.{
            .destination_json = destination_json,
            .sources_json = sources_json,
        });
    }

    pub fn appendMergeCoinsFromCliValues(
        self: *ProgrammaticRequestOptionsBuilder,
        destination: []const u8,
        source_items: []const []const u8,
    ) !void {
        const destination_json = try tx_builder.buildCliPtbArgumentJson(self.commands.allocator, destination);
        defer self.commands.allocator.free(destination_json);
        const sources_json = try tx_builder.buildCliPtbArgumentArray(self.commands.allocator, source_items);
        defer self.commands.allocator.free(sources_json);

        try self.appendMergeCoins(.{
            .destination_json = destination_json,
            .sources_json = sources_json,
        });
    }

    pub fn appendPublish(self: *ProgrammaticRequestOptionsBuilder, spec: tx_builder.PublishSpec) !void {
        try self.commands.appendPublish(spec);
    }

    pub fn appendPublishFromCliValues(
        self: *ProgrammaticRequestOptionsBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
    ) !void {
        try self.appendPublish(.{
            .modules_json = modules_json,
            .dependencies_json = dependencies_json,
        });
    }

    pub fn appendUpgrade(self: *ProgrammaticRequestOptionsBuilder, spec: tx_builder.UpgradeSpec) !void {
        try self.commands.appendUpgrade(spec);
    }

    pub fn appendUpgradeFromSpecs(
        self: *ProgrammaticRequestOptionsBuilder,
        spec: struct {
            modules_json: []const u8,
            dependencies_json: []const u8,
            package_id: []const u8,
            ticket: PtbArgumentSpec,
        },
    ) !void {
        const ticket_json = try buildPtbArgumentJson(self.commands.allocator, spec.ticket);
        defer self.commands.allocator.free(ticket_json);

        try self.appendUpgrade(.{
            .modules_json = spec.modules_json,
            .dependencies_json = spec.dependencies_json,
            .package_id = spec.package_id,
            .ticket_json = ticket_json,
        });
    }

    pub fn appendUpgradeFromCliValues(
        self: *ProgrammaticRequestOptionsBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: []const u8,
    ) !void {
        const ticket_json = try tx_builder.buildCliPtbArgumentJson(self.commands.allocator, ticket);
        defer self.commands.allocator.free(ticket_json);

        try self.appendUpgrade(.{
            .modules_json = modules_json,
            .dependencies_json = dependencies_json,
            .package_id = package_id,
            .ticket_json = ticket_json,
        });
    }

    pub fn setSender(self: *ProgrammaticRequestOptionsBuilder, sender: ?[]const u8) void {
        self.config.sender = sender;
    }

    pub fn setGasBudget(self: *ProgrammaticRequestOptionsBuilder, gas_budget: ?u64) void {
        self.config.gas_budget = gas_budget;
    }

    pub fn setGasPrice(self: *ProgrammaticRequestOptionsBuilder, gas_price: ?u64) void {
        self.config.gas_price = gas_price;
    }

    pub fn setGasPaymentJson(self: *ProgrammaticRequestOptionsBuilder, gas_payment_json: ?[]const u8) void {
        self.config.gas_payment_json = gas_payment_json;
    }

    pub fn setSignatures(self: *ProgrammaticRequestOptionsBuilder, signatures: []const []const u8) void {
        self.config.signatures = signatures;
    }

    pub fn setOptionsJson(self: *ProgrammaticRequestOptionsBuilder, options_json: ?[]const u8) void {
        self.config.options_json = options_json;
    }

    pub fn setConfirmation(
        self: *ProgrammaticRequestOptionsBuilder,
        timeout_ms: u64,
        poll_ms: u64,
    ) void {
        self.config.wait_for_confirmation = true;
        self.config.confirm_timeout_ms = timeout_ms;
        self.config.confirm_poll_ms = poll_ms;
    }

    pub fn finish(self: *ProgrammaticRequestOptionsBuilder) !OwnedProgrammaticRequestOptions {
        const commands_json = try self.commands.finish();
        return .{
            .options = optionsFromCommandSource(.{ .commands_json = commands_json }, self.config),
            .owned_commands_json = commands_json,
        };
    }
};

pub const ProgrammaticDslBuilder = struct {
    allocator: std.mem.Allocator,
    options_builder: ProgrammaticRequestOptionsBuilder,
    aliases: CommandResultAliases = .{},
    command_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) ProgrammaticDslBuilder {
        return .{
            .allocator = allocator,
            .options_builder = ProgrammaticRequestOptionsBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *ProgrammaticDslBuilder) void {
        deinitCommandResultAliases(self.allocator, &self.aliases);
        self.options_builder.deinit();
    }

    pub fn setSender(self: *ProgrammaticDslBuilder, sender: ?[]const u8) void {
        self.options_builder.setSender(sender);
    }

    pub fn setGasBudget(self: *ProgrammaticDslBuilder, gas_budget: ?u64) void {
        self.options_builder.setGasBudget(gas_budget);
    }

    pub fn setGasPrice(self: *ProgrammaticDslBuilder, gas_price: ?u64) void {
        self.options_builder.setGasPrice(gas_price);
    }

    pub fn setGasPaymentJson(self: *ProgrammaticDslBuilder, gas_payment_json: ?[]const u8) void {
        self.options_builder.setGasPaymentJson(gas_payment_json);
    }

    pub fn setSignatures(self: *ProgrammaticDslBuilder, signatures: []const []const u8) void {
        self.options_builder.setSignatures(signatures);
    }

    pub fn setOptionsJson(self: *ProgrammaticDslBuilder, options_json: ?[]const u8) void {
        self.options_builder.setOptionsJson(options_json);
    }

    pub fn setConfirmation(
        self: *ProgrammaticDslBuilder,
        timeout_ms: u64,
        poll_ms: u64,
    ) void {
        self.options_builder.setConfirmation(timeout_ms, poll_ms);
    }

    pub fn importAliases(self: *ProgrammaticDslBuilder, aliases: *const CommandResultAliases) !void {
        deinitCommandResultAliases(self.allocator, &self.aliases);
        self.aliases = try cloneCommandResultAliases(self.allocator, aliases);
    }

    pub fn appendRawJson(self: *ProgrammaticDslBuilder, commands_json: []const u8) !void {
        var normalized = try normalizeCommandItemsFromRawJsonWithContext(
            self.allocator,
            &self.aliases,
            self.command_count,
            commands_json,
        );
        defer normalized.deinit(self.allocator);

        const offset = std.math.cast(u16, self.command_count) orelse return error.InvalidCli;
        const normalized_json = try normalizeRawCommandJson(self.allocator, &self.aliases, offset, commands_json);
        defer self.allocator.free(normalized_json);
        try self.options_builder.commands.appendRawJson(normalized_json);
        self.command_count += normalized.items.items.len;
    }

    fn lastHandleAfterAppend(self: *ProgrammaticDslBuilder) !CommandResultHandle {
        return try self.lastResultHandle();
    }

    fn lastValueAfterAppend(self: *ProgrammaticDslBuilder) !ArgumentValue {
        return (try self.lastHandleAfterAppend()).asValue();
    }

    fn handlesForAppendedRange(
        self: *ProgrammaticDslBuilder,
        start_index: usize,
        count: usize,
    ) !OwnedCommandResultHandles {
        var handles = OwnedCommandResultHandles{};
        errdefer handles.deinit(self.allocator);

        var offset: usize = 0;
        while (offset < count) : (offset += 1) {
            const command_index = std.math.cast(u16, start_index + offset) orelse return error.InvalidCli;
            try handles.items.append(self.allocator, .{ .command_index = command_index });
        }

        return handles;
    }

    fn valuesForHandles(
        self: *ProgrammaticDslBuilder,
        handles: []const CommandResultHandle,
    ) !OwnedArgumentValues {
        var values = OwnedArgumentValues{};
        errdefer values.deinit(self.allocator);

        for (handles) |handle| {
            try values.items.append(self.allocator, handle.asValue());
        }

        return values;
    }

    fn validateHexIdentifier(raw: []const u8) ![]const u8 {
        const trimmed = std.mem.trim(u8, raw, " \n\r\t");
        if (trimmed.len < 3) return error.InvalidCli;
        if (!std.mem.startsWith(u8, trimmed, "0x")) return error.InvalidCli;
        for (trimmed[2..]) |char| {
            if (!std.ascii.isHex(char)) return error.InvalidCli;
        }
        return trimmed;
    }

    fn validateEvenLengthHex(raw: []const u8) ![]const u8 {
        const trimmed = try validateHexIdentifier(raw);
        if (((trimmed.len - 2) % 2) != 0) return error.InvalidCli;
        return trimmed;
    }

    fn argumentValueToSpec(
        self: *ProgrammaticDslBuilder,
        value: ArgumentValue,
    ) !ResolvedPtbArgumentSpec {
        return switch (value) {
            .gas_coin => .{ .spec = .gas_coin },
            .input => |index| .{ .spec = .{ .input = index } },
            .result => |handle| .{ .spec = handle.asSpec() },
            .output => |handle| .{ .spec = handle.asSpec() },
            else => blk: {
                const owned_json = try self.argumentValueToOwnedJson(value);
                break :blk .{
                    .spec = .{ .json = owned_json },
                    .owned_json = owned_json,
                };
            },
        };
    }

    fn encodeJsonValue(
        self: *ProgrammaticDslBuilder,
        value: anytype,
    ) ![]u8 {
        var out = std.ArrayList(u8){};
        errdefer out.deinit(self.allocator);
        try out.writer(self.allocator).print("{f}", .{std.json.fmt(value, .{})});
        return try out.toOwnedSlice(self.allocator);
    }

    fn writeArgumentValueJson(
        self: *ProgrammaticDslBuilder,
        writer: anytype,
        value: ArgumentValue,
    ) !void {
        switch (value) {
            .gas_coin => try writePtbArgumentSpecJson(self.allocator, writer, .gas_coin),
            .input => |index| try writePtbArgumentSpecJson(self.allocator, writer, .{ .input = index }),
            .result => |handle| try writePtbArgumentSpecJson(self.allocator, writer, handle.asSpec()),
            .output => |handle| try writePtbArgumentSpecJson(self.allocator, writer, handle.asSpec()),
            .address => |raw| {
                const validated = try validateHexIdentifier(raw);
                const encoded = try self.encodeJsonValue(validated);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .object_id => |raw| {
                const validated = try validateHexIdentifier(raw);
                const encoded = try self.encodeJsonValue(validated);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .bytes => |raw| {
                const validated = try validateEvenLengthHex(raw);
                const encoded = try self.encodeJsonValue(validated);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .raw_json => |json| try writeCanonicalJsonValue(self.allocator, writer, json),
            .string => |raw| {
                const encoded = try self.encodeJsonValue(raw);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .boolean => |flag| {
                const encoded = try self.encodeJsonValue(flag);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .u8 => |number| {
                const encoded = try self.encodeJsonValue(number);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .u16 => |number| {
                const encoded = try self.encodeJsonValue(number);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .u32 => |number| {
                const encoded = try self.encodeJsonValue(number);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .u64 => |number| {
                const encoded = try self.encodeJsonValue(number);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .u128 => |number| {
                const encoded = try self.encodeJsonValue(number);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .u256 => |number| {
                const encoded = try self.encodeJsonValue(number);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .i64 => |number| {
                const encoded = try self.encodeJsonValue(number);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
            },
            .null => try writer.writeAll("null"),
            .vector => |vector| {
                try writer.writeAll("[");
                for (vector.items, 0..) |item, index| {
                    if (index != 0) try writer.writeAll(",");
                    try self.writeArgumentValueJson(writer, item);
                }
                try writer.writeAll("]");
            },
            .option => |option_value| switch (option_value) {
                .none => try writer.writeAll("null"),
                .some => |item| try self.writeArgumentValueJson(writer, item.*),
            },
        }
    }

    fn argumentValueToOwnedJson(
        self: *ProgrammaticDslBuilder,
        value: ArgumentValue,
    ) ![]u8 {
        var out = std.ArrayList(u8){};
        errdefer out.deinit(self.allocator);
        try self.writeArgumentValueJson(out.writer(self.allocator), value);
        return try out.toOwnedSlice(self.allocator);
    }

    fn argumentValuesToSpecs(
        self: *ProgrammaticDslBuilder,
        values: []const ArgumentValue,
    ) !ResolvedPtbArgumentSpecs {
        var resolved = ResolvedPtbArgumentSpecs{};
        errdefer resolved.deinit(self.allocator);

        for (values) |value| {
            var item = try self.argumentValueToSpec(value);
            errdefer item.deinit(self.allocator);

            try resolved.items.append(self.allocator, item.spec);
            if (item.owned_json) |owned_json| {
                try resolved.owned_json_items.append(self.allocator, owned_json);
                item.owned_json = null;
            }
        }

        return resolved;
    }

    pub fn appendRawJsonAndGetHandles(
        self: *ProgrammaticDslBuilder,
        commands_json: []const u8,
    ) !OwnedCommandResultHandles {
        var normalized = try normalizeCommandItemsFromRawJsonWithContext(
            self.allocator,
            &self.aliases,
            self.command_count,
            commands_json,
        );
        defer normalized.deinit(self.allocator);

        const start_index = self.command_count;
        const offset = std.math.cast(u16, self.command_count) orelse return error.InvalidCli;
        const normalized_json = try normalizeRawCommandJson(self.allocator, &self.aliases, offset, commands_json);
        defer self.allocator.free(normalized_json);
        try self.options_builder.commands.appendRawJson(normalized_json);
        self.command_count += normalized.items.items.len;
        return try self.handlesForAppendedRange(start_index, normalized.items.items.len);
    }

    pub fn appendRawJsonAndGetValues(
        self: *ProgrammaticDslBuilder,
        commands_json: []const u8,
    ) !OwnedArgumentValues {
        var handles = try self.appendRawJsonAndGetHandles(commands_json);
        defer handles.deinit(self.allocator);
        return try self.valuesForHandles(handles.items.items);
    }

    pub fn lastResultHandle(self: *const ProgrammaticDslBuilder) !CommandResultHandle {
        if (self.command_count == 0) return error.InvalidCli;
        const command_index = std.math.cast(u16, self.command_count - 1) orelse return error.InvalidCli;
        return .{ .command_index = command_index };
    }

    pub fn lastResultValue(self: *const ProgrammaticDslBuilder) !ArgumentValue {
        return (try self.lastResultHandle()).asValue();
    }

    pub fn resultHandleForAlias(
        self: *const ProgrammaticDslBuilder,
        raw_name: []const u8,
    ) !CommandResultHandle {
        const name = std.mem.trim(u8, raw_name, " \n\r\t");
        if (name.len == 0) return error.InvalidCli;
        const command_index = self.aliases.get(name) orelse return error.InvalidCli;
        return .{ .command_index = command_index };
    }

    pub fn resultValueForAlias(
        self: *const ProgrammaticDslBuilder,
        raw_name: []const u8,
    ) !ArgumentValue {
        return (try self.resultHandleForAlias(raw_name)).asValue();
    }

    pub fn appendMoveCallFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arg_items: []const []const u8,
    ) !void {
        var resolved_args = try resolvePtbArgumentSpecs(self.allocator, &self.aliases, arg_items);
        defer resolved_args.deinit(self.allocator);

        try self.appendMoveCallFromSpecs(
            package_id,
            module,
            function_name,
            type_arg_items,
            resolved_args.items.items,
        );
    }

    pub fn appendMoveCallAndGetHandleFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arg_items: []const []const u8,
    ) !CommandResultHandle {
        try self.appendMoveCallFromNamedCliValues(package_id, module, function_name, type_arg_items, arg_items);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMoveCallAndGetValueFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arg_items: []const []const u8,
    ) !ArgumentValue {
        try self.appendMoveCallFromNamedCliValues(package_id, module, function_name, type_arg_items, arg_items);
        return try self.lastValueAfterAppend();
    }

    pub fn appendMoveCallFromSpecs(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arguments: []const PtbArgumentSpec,
    ) !void {
        try self.options_builder.appendMoveCallFromSpecs(.{
            .package_id = package_id,
            .module = module,
            .function_name = function_name,
            .type_arg_items = type_arg_items,
            .arguments = arguments,
        });
        self.command_count += 1;
    }

    pub fn appendMoveCallFromValues(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arguments: []const ArgumentValue,
    ) !void {
        var resolved_arguments = try self.argumentValuesToSpecs(arguments);
        defer resolved_arguments.deinit(self.allocator);

        try self.appendMoveCallFromSpecs(
            package_id,
            module,
            function_name,
            type_arg_items,
            resolved_arguments.items.items,
        );
    }

    pub fn appendMoveCallFromValueTokens(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arguments: []const []const u8,
    ) !void {
        var parsed_arguments = try parseArgumentValueTokens(self.allocator, &self.aliases, arguments);
        defer parsed_arguments.deinit(self.allocator);
        try self.appendMoveCallFromValues(package_id, module, function_name, type_arg_items, parsed_arguments.items.items);
    }

    pub fn appendMoveCallAndGetHandleFromSpecs(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arguments: []const PtbArgumentSpec,
    ) !CommandResultHandle {
        try self.appendMoveCallFromSpecs(package_id, module, function_name, type_arg_items, arguments);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMoveCallAndGetHandleFromValues(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arguments: []const ArgumentValue,
    ) !CommandResultHandle {
        try self.appendMoveCallFromValues(package_id, module, function_name, type_arg_items, arguments);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMoveCallAndGetValueFromValues(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arguments: []const ArgumentValue,
    ) !ArgumentValue {
        try self.appendMoveCallFromValues(package_id, module, function_name, type_arg_items, arguments);
        return try self.lastValueAfterAppend();
    }

    pub fn appendMoveCallAndGetHandleFromValueTokens(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arguments: []const []const u8,
    ) !CommandResultHandle {
        try self.appendMoveCallFromValueTokens(package_id, module, function_name, type_arg_items, arguments);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMoveCallAndGetValueFromValueTokens(
        self: *ProgrammaticDslBuilder,
        package_id: []const u8,
        module: []const u8,
        function_name: []const u8,
        type_arg_items: []const []const u8,
        arguments: []const []const u8,
    ) !ArgumentValue {
        try self.appendMoveCallFromValueTokens(package_id, module, function_name, type_arg_items, arguments);
        return try self.lastValueAfterAppend();
    }

    pub fn appendMakeMoveVecFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        element_items: []const []const u8,
    ) !void {
        var resolved_elements = try resolvePtbArgumentSpecs(self.allocator, &self.aliases, element_items);
        defer resolved_elements.deinit(self.allocator);

        try self.appendMakeMoveVecFromSpecs(type_value, resolved_elements.items.items);
    }

    pub fn appendMakeMoveVecAndGetHandleFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        element_items: []const []const u8,
    ) !CommandResultHandle {
        try self.appendMakeMoveVecFromNamedCliValues(type_value, element_items);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMakeMoveVecAndGetValueFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        element_items: []const []const u8,
    ) !ArgumentValue {
        try self.appendMakeMoveVecFromNamedCliValues(type_value, element_items);
        return try self.lastValueAfterAppend();
    }

    pub fn appendMakeMoveVecFromSpecs(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        elements: []const PtbArgumentSpec,
    ) !void {
        try self.options_builder.appendMakeMoveVecFromSpecs(.{
            .type_json = type_value,
            .elements = elements,
        });
        self.command_count += 1;
    }

    pub fn appendMakeMoveVecFromValues(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        elements: []const ArgumentValue,
    ) !void {
        var resolved_elements = try self.argumentValuesToSpecs(elements);
        defer resolved_elements.deinit(self.allocator);

        try self.appendMakeMoveVecFromSpecs(type_value, resolved_elements.items.items);
    }

    pub fn appendMakeMoveVecFromValueTokens(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        elements: []const []const u8,
    ) !void {
        var parsed_elements = try parseArgumentValueTokens(self.allocator, &self.aliases, elements);
        defer parsed_elements.deinit(self.allocator);
        try self.appendMakeMoveVecFromValues(type_value, parsed_elements.items.items);
    }

    pub fn appendMakeMoveVecAndGetHandleFromSpecs(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        elements: []const PtbArgumentSpec,
    ) !CommandResultHandle {
        try self.appendMakeMoveVecFromSpecs(type_value, elements);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMakeMoveVecAndGetHandleFromValues(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        elements: []const ArgumentValue,
    ) !CommandResultHandle {
        try self.appendMakeMoveVecFromValues(type_value, elements);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMakeMoveVecAndGetValueFromValues(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        elements: []const ArgumentValue,
    ) !ArgumentValue {
        try self.appendMakeMoveVecFromValues(type_value, elements);
        return try self.lastValueAfterAppend();
    }

    pub fn appendMakeMoveVecAndGetHandleFromValueTokens(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        elements: []const []const u8,
    ) !CommandResultHandle {
        try self.appendMakeMoveVecFromValueTokens(type_value, elements);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMakeMoveVecAndGetValueFromValueTokens(
        self: *ProgrammaticDslBuilder,
        type_value: ?[]const u8,
        elements: []const []const u8,
    ) !ArgumentValue {
        try self.appendMakeMoveVecFromValueTokens(type_value, elements);
        return try self.lastValueAfterAppend();
    }

    pub fn appendTransferObjectsFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        object_items: []const []const u8,
        address: []const u8,
    ) !void {
        var resolved_objects = try resolvePtbArgumentSpecs(self.allocator, &self.aliases, object_items);
        defer resolved_objects.deinit(self.allocator);
        var resolved_address = try resolvePtbArgumentSpec(self.allocator, &self.aliases, address);
        defer resolved_address.deinit(self.allocator);

        try self.appendTransferObjectsFromSpecs(resolved_objects.items.items, resolved_address.spec);
    }

    pub fn appendTransferObjectsAndGetHandleFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        object_items: []const []const u8,
        address: []const u8,
    ) !CommandResultHandle {
        try self.appendTransferObjectsFromNamedCliValues(object_items, address);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendTransferObjectsAndGetValueFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        object_items: []const []const u8,
        address: []const u8,
    ) !ArgumentValue {
        try self.appendTransferObjectsFromNamedCliValues(object_items, address);
        return try self.lastValueAfterAppend();
    }

    pub fn appendTransferObjectsFromSpecs(
        self: *ProgrammaticDslBuilder,
        objects: []const PtbArgumentSpec,
        address: PtbArgumentSpec,
    ) !void {
        try self.options_builder.appendTransferObjectsFromSpecs(.{
            .objects = objects,
            .address = address,
        });
        self.command_count += 1;
    }

    pub fn appendTransferObjectsFromValues(
        self: *ProgrammaticDslBuilder,
        objects: []const ArgumentValue,
        address: ArgumentValue,
    ) !void {
        var resolved_objects = try self.argumentValuesToSpecs(objects);
        defer resolved_objects.deinit(self.allocator);
        var resolved_address = try self.argumentValueToSpec(address);
        defer resolved_address.deinit(self.allocator);

        try self.appendTransferObjectsFromSpecs(resolved_objects.items.items, resolved_address.spec);
    }

    pub fn appendTransferObjectsFromValueTokens(
        self: *ProgrammaticDslBuilder,
        objects: []const []const u8,
        address: []const u8,
    ) !void {
        var parsed_objects = try parseArgumentValueTokens(self.allocator, &self.aliases, objects);
        defer parsed_objects.deinit(self.allocator);
        var parsed_address = try parseArgumentValueToken(self.allocator, &self.aliases, address);
        defer parsed_address.deinit(self.allocator);
        try self.appendTransferObjectsFromValues(parsed_objects.items.items, parsed_address.value);
    }

    pub fn appendTransferObjectsAndGetHandleFromSpecs(
        self: *ProgrammaticDslBuilder,
        objects: []const PtbArgumentSpec,
        address: PtbArgumentSpec,
    ) !CommandResultHandle {
        try self.appendTransferObjectsFromSpecs(objects, address);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendTransferObjectsAndGetHandleFromValues(
        self: *ProgrammaticDslBuilder,
        objects: []const ArgumentValue,
        address: ArgumentValue,
    ) !CommandResultHandle {
        try self.appendTransferObjectsFromValues(objects, address);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendTransferObjectsAndGetValueFromValues(
        self: *ProgrammaticDslBuilder,
        objects: []const ArgumentValue,
        address: ArgumentValue,
    ) !ArgumentValue {
        try self.appendTransferObjectsFromValues(objects, address);
        return try self.lastValueAfterAppend();
    }

    pub fn appendTransferObjectsAndGetHandleFromValueTokens(
        self: *ProgrammaticDslBuilder,
        objects: []const []const u8,
        address: []const u8,
    ) !CommandResultHandle {
        try self.appendTransferObjectsFromValueTokens(objects, address);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendTransferObjectsAndGetValueFromValueTokens(
        self: *ProgrammaticDslBuilder,
        objects: []const []const u8,
        address: []const u8,
    ) !ArgumentValue {
        try self.appendTransferObjectsFromValueTokens(objects, address);
        return try self.lastValueAfterAppend();
    }

    pub fn appendSplitCoinsFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        coin: []const u8,
        amount_items: []const []const u8,
    ) !void {
        var resolved_coin = try resolvePtbArgumentSpec(self.allocator, &self.aliases, coin);
        defer resolved_coin.deinit(self.allocator);
        var resolved_amounts = try resolvePtbArgumentSpecs(self.allocator, &self.aliases, amount_items);
        defer resolved_amounts.deinit(self.allocator);

        try self.appendSplitCoinsFromSpecs(resolved_coin.spec, resolved_amounts.items.items);
    }

    pub fn appendSplitCoinsAndGetHandleFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        coin: []const u8,
        amount_items: []const []const u8,
    ) !CommandResultHandle {
        try self.appendSplitCoinsFromNamedCliValues(coin, amount_items);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendSplitCoinsAndGetValueFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        coin: []const u8,
        amount_items: []const []const u8,
    ) !ArgumentValue {
        try self.appendSplitCoinsFromNamedCliValues(coin, amount_items);
        return try self.lastValueAfterAppend();
    }

    pub fn appendSplitCoinsFromSpecs(
        self: *ProgrammaticDslBuilder,
        coin: PtbArgumentSpec,
        amounts: []const PtbArgumentSpec,
    ) !void {
        try self.options_builder.appendSplitCoinsFromSpecs(.{
            .coin = coin,
            .amounts = amounts,
        });
        self.command_count += 1;
    }

    pub fn appendSplitCoinsFromValues(
        self: *ProgrammaticDslBuilder,
        coin: ArgumentValue,
        amounts: []const ArgumentValue,
    ) !void {
        var resolved_coin = try self.argumentValueToSpec(coin);
        defer resolved_coin.deinit(self.allocator);
        var resolved_amounts = try self.argumentValuesToSpecs(amounts);
        defer resolved_amounts.deinit(self.allocator);

        try self.appendSplitCoinsFromSpecs(resolved_coin.spec, resolved_amounts.items.items);
    }

    pub fn appendSplitCoinsFromValueTokens(
        self: *ProgrammaticDslBuilder,
        coin: []const u8,
        amounts: []const []const u8,
    ) !void {
        var parsed_coin = try parseArgumentValueToken(self.allocator, &self.aliases, coin);
        defer parsed_coin.deinit(self.allocator);
        var parsed_amounts = try parseArgumentValueTokens(self.allocator, &self.aliases, amounts);
        defer parsed_amounts.deinit(self.allocator);
        try self.appendSplitCoinsFromValues(parsed_coin.value, parsed_amounts.items.items);
    }

    pub fn appendSplitCoinsAndGetHandleFromSpecs(
        self: *ProgrammaticDslBuilder,
        coin: PtbArgumentSpec,
        amounts: []const PtbArgumentSpec,
    ) !CommandResultHandle {
        try self.appendSplitCoinsFromSpecs(coin, amounts);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendSplitCoinsAndGetHandleFromValues(
        self: *ProgrammaticDslBuilder,
        coin: ArgumentValue,
        amounts: []const ArgumentValue,
    ) !CommandResultHandle {
        try self.appendSplitCoinsFromValues(coin, amounts);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendSplitCoinsAndGetValueFromValues(
        self: *ProgrammaticDslBuilder,
        coin: ArgumentValue,
        amounts: []const ArgumentValue,
    ) !ArgumentValue {
        try self.appendSplitCoinsFromValues(coin, amounts);
        return try self.lastValueAfterAppend();
    }

    pub fn appendSplitCoinsAndGetHandleFromValueTokens(
        self: *ProgrammaticDslBuilder,
        coin: []const u8,
        amounts: []const []const u8,
    ) !CommandResultHandle {
        try self.appendSplitCoinsFromValueTokens(coin, amounts);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendSplitCoinsAndGetValueFromValueTokens(
        self: *ProgrammaticDslBuilder,
        coin: []const u8,
        amounts: []const []const u8,
    ) !ArgumentValue {
        try self.appendSplitCoinsFromValueTokens(coin, amounts);
        return try self.lastValueAfterAppend();
    }

    pub fn appendMergeCoinsFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        destination: []const u8,
        source_items: []const []const u8,
    ) !void {
        var resolved_destination = try resolvePtbArgumentSpec(self.allocator, &self.aliases, destination);
        defer resolved_destination.deinit(self.allocator);
        var resolved_sources = try resolvePtbArgumentSpecs(self.allocator, &self.aliases, source_items);
        defer resolved_sources.deinit(self.allocator);

        try self.appendMergeCoinsFromSpecs(resolved_destination.spec, resolved_sources.items.items);
    }

    pub fn appendMergeCoinsAndGetHandleFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        destination: []const u8,
        source_items: []const []const u8,
    ) !CommandResultHandle {
        try self.appendMergeCoinsFromNamedCliValues(destination, source_items);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMergeCoinsAndGetValueFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        destination: []const u8,
        source_items: []const []const u8,
    ) !ArgumentValue {
        try self.appendMergeCoinsFromNamedCliValues(destination, source_items);
        return try self.lastValueAfterAppend();
    }

    pub fn appendMergeCoinsFromSpecs(
        self: *ProgrammaticDslBuilder,
        destination: PtbArgumentSpec,
        sources: []const PtbArgumentSpec,
    ) !void {
        try self.options_builder.appendMergeCoinsFromSpecs(.{
            .destination = destination,
            .sources = sources,
        });
        self.command_count += 1;
    }

    pub fn appendMergeCoinsFromValues(
        self: *ProgrammaticDslBuilder,
        destination: ArgumentValue,
        sources: []const ArgumentValue,
    ) !void {
        var resolved_destination = try self.argumentValueToSpec(destination);
        defer resolved_destination.deinit(self.allocator);
        var resolved_sources = try self.argumentValuesToSpecs(sources);
        defer resolved_sources.deinit(self.allocator);

        try self.appendMergeCoinsFromSpecs(resolved_destination.spec, resolved_sources.items.items);
    }

    pub fn appendMergeCoinsFromValueTokens(
        self: *ProgrammaticDslBuilder,
        destination: []const u8,
        sources: []const []const u8,
    ) !void {
        var parsed_destination = try parseArgumentValueToken(self.allocator, &self.aliases, destination);
        defer parsed_destination.deinit(self.allocator);
        var parsed_sources = try parseArgumentValueTokens(self.allocator, &self.aliases, sources);
        defer parsed_sources.deinit(self.allocator);
        try self.appendMergeCoinsFromValues(parsed_destination.value, parsed_sources.items.items);
    }

    pub fn appendMergeCoinsAndGetHandleFromSpecs(
        self: *ProgrammaticDslBuilder,
        destination: PtbArgumentSpec,
        sources: []const PtbArgumentSpec,
    ) !CommandResultHandle {
        try self.appendMergeCoinsFromSpecs(destination, sources);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMergeCoinsAndGetHandleFromValues(
        self: *ProgrammaticDslBuilder,
        destination: ArgumentValue,
        sources: []const ArgumentValue,
    ) !CommandResultHandle {
        try self.appendMergeCoinsFromValues(destination, sources);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMergeCoinsAndGetValueFromValues(
        self: *ProgrammaticDslBuilder,
        destination: ArgumentValue,
        sources: []const ArgumentValue,
    ) !ArgumentValue {
        try self.appendMergeCoinsFromValues(destination, sources);
        return try self.lastValueAfterAppend();
    }

    pub fn appendMergeCoinsAndGetHandleFromValueTokens(
        self: *ProgrammaticDslBuilder,
        destination: []const u8,
        sources: []const []const u8,
    ) !CommandResultHandle {
        try self.appendMergeCoinsFromValueTokens(destination, sources);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendMergeCoinsAndGetValueFromValueTokens(
        self: *ProgrammaticDslBuilder,
        destination: []const u8,
        sources: []const []const u8,
    ) !ArgumentValue {
        try self.appendMergeCoinsFromValueTokens(destination, sources);
        return try self.lastValueAfterAppend();
    }

    pub fn appendPublishFromCliValues(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
    ) !void {
        try self.options_builder.appendPublishFromCliValues(modules_json, dependencies_json);
        self.command_count += 1;
    }

    pub fn appendPublishAndGetHandleFromCliValues(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
    ) !CommandResultHandle {
        try self.appendPublishFromCliValues(modules_json, dependencies_json);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendPublishAndGetValueFromCliValues(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
    ) !ArgumentValue {
        try self.appendPublishFromCliValues(modules_json, dependencies_json);
        return try self.lastValueAfterAppend();
    }

    pub fn appendUpgradeFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: []const u8,
    ) !void {
        var resolved_ticket = try resolvePtbArgumentSpec(self.allocator, &self.aliases, ticket);
        defer resolved_ticket.deinit(self.allocator);

        try self.appendUpgradeFromSpecs(
            modules_json,
            dependencies_json,
            package_id,
            resolved_ticket.spec,
        );
    }

    pub fn appendUpgradeAndGetHandleFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: []const u8,
    ) !CommandResultHandle {
        try self.appendUpgradeFromNamedCliValues(modules_json, dependencies_json, package_id, ticket);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendUpgradeAndGetValueFromNamedCliValues(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: []const u8,
    ) !ArgumentValue {
        try self.appendUpgradeFromNamedCliValues(modules_json, dependencies_json, package_id, ticket);
        return try self.lastValueAfterAppend();
    }

    pub fn appendUpgradeFromSpecs(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: PtbArgumentSpec,
    ) !void {
        try self.options_builder.appendUpgradeFromSpecs(.{
            .modules_json = modules_json,
            .dependencies_json = dependencies_json,
            .package_id = package_id,
            .ticket = ticket,
        });
        self.command_count += 1;
    }

    pub fn appendUpgradeFromValue(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: ArgumentValue,
    ) !void {
        var resolved_ticket = try self.argumentValueToSpec(ticket);
        defer resolved_ticket.deinit(self.allocator);

        try self.appendUpgradeFromSpecs(
            modules_json,
            dependencies_json,
            package_id,
            resolved_ticket.spec,
        );
    }

    pub fn appendUpgradeFromValueToken(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: []const u8,
    ) !void {
        var parsed_ticket = try parseArgumentValueToken(self.allocator, &self.aliases, ticket);
        defer parsed_ticket.deinit(self.allocator);
        try self.appendUpgradeFromValue(modules_json, dependencies_json, package_id, parsed_ticket.value);
    }

    pub fn appendUpgradeAndGetHandleFromSpecs(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: PtbArgumentSpec,
    ) !CommandResultHandle {
        try self.appendUpgradeFromSpecs(modules_json, dependencies_json, package_id, ticket);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendUpgradeAndGetHandleFromValue(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: ArgumentValue,
    ) !CommandResultHandle {
        try self.appendUpgradeFromValue(modules_json, dependencies_json, package_id, ticket);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendUpgradeAndGetValueFromValue(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: ArgumentValue,
    ) !ArgumentValue {
        try self.appendUpgradeFromValue(modules_json, dependencies_json, package_id, ticket);
        return try self.lastValueAfterAppend();
    }

    pub fn appendUpgradeAndGetHandleFromValueToken(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: []const u8,
    ) !CommandResultHandle {
        try self.appendUpgradeFromValueToken(modules_json, dependencies_json, package_id, ticket);
        return try self.lastHandleAfterAppend();
    }

    pub fn appendUpgradeAndGetValueFromValueToken(
        self: *ProgrammaticDslBuilder,
        modules_json: []const u8,
        dependencies_json: []const u8,
        package_id: []const u8,
        ticket: []const u8,
    ) !ArgumentValue {
        try self.appendUpgradeFromValueToken(modules_json, dependencies_json, package_id, ticket);
        return try self.lastValueAfterAppend();
    }

    pub fn assignLastResultAlias(self: *ProgrammaticDslBuilder, raw_name: []const u8) !void {
        try self.assignResultAlias(raw_name, try self.lastResultHandle());
    }

    pub fn assignResultAlias(
        self: *ProgrammaticDslBuilder,
        raw_name: []const u8,
        handle: CommandResultHandle,
    ) !void {
        try assignCommandResultAlias(self.allocator, &self.aliases, raw_name, handle.command_index);
    }

    pub fn finish(self: *ProgrammaticDslBuilder) !OwnedProgrammaticRequestOptions {
        return try self.options_builder.finish();
    }

    pub fn finishAuthorizationPlan(
        self: *ProgrammaticDslBuilder,
        provider: AccountProvider,
    ) !OwnedAuthorizationPlan {
        return (try self.finish()).authorizationPlan(provider);
    }

    pub fn authorize(
        self: *ProgrammaticDslBuilder,
        allocator: std.mem.Allocator,
        provider: AccountProvider,
    ) !AuthorizedPreparedRequest {
        var plan = try self.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try plan.authorize(allocator);
    }

    pub fn buildAuthorizedInspectPayload(
        self: *ProgrammaticDslBuilder,
        allocator: std.mem.Allocator,
        provider: AccountProvider,
    ) ![]u8 {
        var plan = try self.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try plan.buildAuthorizedInspectPayload(allocator);
    }

    pub fn buildAuthorizedExecutePayload(
        self: *ProgrammaticDslBuilder,
        allocator: std.mem.Allocator,
        provider: AccountProvider,
    ) ![]u8 {
        var plan = try self.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try plan.buildAuthorizedExecutePayload(allocator);
    }

    pub fn buildTransactionBlock(
        self: *ProgrammaticDslBuilder,
        allocator: std.mem.Allocator,
        provider: AccountProvider,
    ) ![]u8 {
        var plan = try self.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try plan.buildTransactionBlock(allocator);
    }

    pub fn buildArtifact(
        self: *ProgrammaticDslBuilder,
        allocator: std.mem.Allocator,
        provider: AccountProvider,
        kind: ProgrammaticArtifactKind,
    ) ![]u8 {
        var plan = try self.finishAuthorizationPlan(provider);
        defer plan.deinit(allocator);
        return try plan.buildArtifact(allocator, kind);
    }
};

pub fn normalizeCommandItemsFromRawJson(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
) !OwnedCommandItems {
    return try normalizeCommandItemsFromRawJsonWithContext(allocator, null, 0, commands_json);
}

pub fn normalizeCommandItemsFromRawJsonWithAliases(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    commands_json: []const u8,
) !OwnedCommandItems {
    return try normalizeCommandItemsFromRawJsonWithContext(allocator, aliases, 0, commands_json);
}

pub fn normalizeCommandItemsFromRawJsonWithContext(
    allocator: std.mem.Allocator,
    aliases: ?*const CommandResultAliases,
    command_index_offset: usize,
    commands_json: []const u8,
) !OwnedCommandItems {
    var builder = ProgrammaticRequestOptionsBuilder.init(allocator);
    defer builder.deinit();

    const offset = std.math.cast(u16, command_index_offset) orelse return error.InvalidCli;
    const normalized_json = try normalizeRawCommandJson(allocator, aliases, offset, commands_json);
    defer allocator.free(normalized_json);
    try builder.commands.appendRawJson(normalized_json);

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const normalized = owned.takeCommandsJson() orelse return error.InvalidCli;
    defer allocator.free(normalized);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, normalized, .{});
    defer parsed.deinit();
    if (parsed.value != .array or parsed.value.array.items.len == 0) return error.InvalidCli;

    var out = OwnedCommandItems{};
    errdefer out.deinit(allocator);

    for (parsed.value.array.items) |entry| {
        var item = std.ArrayList(u8){};
        errdefer item.deinit(allocator);
        const writer = item.writer(allocator);
        try writer.print("{f}", .{std.json.fmt(entry, .{})});
        try out.items.append(allocator, try item.toOwnedSlice(allocator));
    }

    return out;
}

pub fn optionsFromCommandSource(
    source: tx_builder.CommandSource,
    config: CommandRequestConfig,
) ProgrammaticRequestOptions {
    return .{
        .source = source,
        .sender = config.sender,
        .gas_budget = config.gas_budget,
        .gas_price = config.gas_price,
        .gas_payment_json = config.gas_payment_json,
        .signatures = config.signatures,
        .options_json = config.options_json,
        .wait_for_confirmation = config.wait_for_confirmation,
        .confirm_timeout_ms = config.confirm_timeout_ms,
        .confirm_poll_ms = config.confirm_poll_ms,
    };
}

fn applyDirectSignatures(
    options: ProgrammaticRequestOptions,
    account: DirectSignatureAccount,
) !ProgrammaticRequestOptions {
    var resolved = options;
    if (account.sender) |sender| {
        if (resolved.sender) |existing| {
            if (!std.mem.eql(u8, existing, sender)) return error.InvalidCli;
        }
        resolved.sender = sender;
    }
    if (account.signatures.len != 0) resolved.signatures = account.signatures;
    return resolved;
}

fn applyFutureWalletAddress(
    options: ProgrammaticRequestOptions,
    account: FutureWalletAccount,
) !ProgrammaticRequestOptions {
    var resolved = options;
    if (account.address) |address| {
        if (resolved.sender) |existing| {
            if (!std.mem.eql(u8, existing, address)) return error.InvalidCli;
        }
        resolved.sender = address;
    }
    return resolved;
}

fn applyRemoteAuthorization(
    options: ProgrammaticRequestOptions,
    account_address: ?[]const u8,
    authorization: RemoteAuthorizationResult,
) !ProgrammaticRequestOptions {
    var resolved = options;
    if (account_address) |address| {
        if (resolved.sender) |existing| {
            if (!std.mem.eql(u8, existing, address)) return error.InvalidCli;
        }
        resolved.sender = address;
    }
    if (authorization.sender) |sender| {
        if (resolved.sender) |existing| {
            if (!std.mem.eql(u8, existing, sender)) return error.InvalidCli;
        }
        resolved.sender = sender;
    }
    if (authorization.signatures.len != 0) resolved.signatures = authorization.signatures;
    return resolved;
}

pub fn sessionChallengeRequest(
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) ?SessionChallengeRequest {
    return switch (provider) {
        .remote_signer => |account| if (account.session_challenger != null and account.session_challenge != null) .{
            .options = options,
            .account_address = account.address,
            .current_session = account.session,
            .action = account.session_action,
            .challenge = account.session_challenge.?,
        } else null,
        .zklogin => |account| if (account.session_challenge != null) .{
            .options = options,
            .account_address = account.address,
            .current_session = account.session,
            .action = account.session_action,
            .challenge = account.session_challenge.?,
        } else null,
        .passkey => |account| if (account.session_challenge != null) .{
            .options = options,
            .account_address = account.address,
            .current_session = account.session,
            .action = account.session_action,
            .challenge = account.session_challenge.?,
        } else null,
        .multisig => |account| if (account.session_challenge != null) .{
            .options = options,
            .account_address = account.address,
            .current_session = account.session,
            .action = account.session_action,
            .challenge = account.session_challenge.?,
        } else null,
        else => null,
    };
}

pub fn applySessionChallengeResponse(
    provider: AccountProvider,
    response: SessionChallengeResponse,
) !AccountProvider {
    return switch (provider) {
        .remote_signer => |account| .{
            .remote_signer = .{
                .address = account.address,
                .authorizer = account.authorizer,
                .session = response.session orelse account.session,
                .session_challenger = null,
                .session_challenge = null,
                .session_action = account.session_action,
                .session_supports_execute = response.supports_execute,
            },
        },
        .zklogin => |account| .{
            .zklogin = .{
                .address = account.address,
                .session = response.session orelse account.session,
                .authorizer = account.authorizer,
                .session_challenge = null,
                .session_action = account.session_action,
                .session_supports_execute = response.supports_execute,
            },
        },
        .passkey => |account| .{
            .passkey = .{
                .address = account.address,
                .session = response.session orelse account.session,
                .authorizer = account.authorizer,
                .session_challenge = null,
                .session_action = account.session_action,
                .session_supports_execute = response.supports_execute,
            },
        },
        .multisig => |account| .{
            .multisig = .{
                .address = account.address,
                .session = response.session orelse account.session,
                .authorizer = account.authorizer,
                .session_challenge = null,
                .session_action = account.session_action,
                .session_supports_execute = response.supports_execute,
            },
        },
        else => error.UnsupportedAccountProvider,
    };
}

pub fn buildSignPersonalMessageChallengeText(
    allocator: std.mem.Allocator,
    challenge: SignPersonalMessageChallenge,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.print("{s} wants you to sign in with your Sui account:\n", .{challenge.domain});
    try writer.print("{s}\n\n", .{challenge.address orelse "<account>"});
    try writer.print("{s}\n", .{challenge.statement});
    try writer.print("\nChain: {s}\n", .{challenge.chain});
    try writer.print("Nonce: {s}\n", .{challenge.nonce});
    if (challenge.uri) |uri| {
        try writer.print("URI: {s}\n", .{uri});
    }
    if (challenge.issued_at_ms) |issued_at_ms| {
        try writer.print("Issued At (ms): {}\n", .{issued_at_ms});
    }
    if (challenge.expires_at_ms) |expires_at_ms| {
        try writer.print("Expires At (ms): {}\n", .{expires_at_ms});
    }
    if (challenge.resources.len != 0) {
        try writer.writeAll("Resources:\n");
        for (challenge.resources) |resource| {
            try writer.print("- {s}\n", .{resource});
        }
    }

    return try out.toOwnedSlice(allocator);
}

pub fn buildSessionChallengeText(
    allocator: std.mem.Allocator,
    request: SessionChallengeRequest,
) ![]u8 {
    return switch (request.challenge) {
        .sign_personal_message => |challenge| try buildSignPersonalMessageChallengeText(allocator, challenge),
        .passkey => |challenge| try std.fmt.allocPrint(
            allocator,
            "Passkey challenge for {s}\nAction: {s}\nChallenge: {s}\n",
            .{ challenge.rp_id, @tagName(request.action), challenge.challenge_b64url },
        ),
        .zklogin_nonce => |challenge| try std.fmt.allocPrint(
            allocator,
            "zkLogin nonce challenge\nAction: {s}\nNonce: {s}\nProvider: {s}\n",
            .{ @tagName(request.action), challenge.nonce, challenge.provider orelse "<unknown>" },
        ),
    };
}

pub fn requestFromOptions(options: ProgrammaticRequestOptions) tx_builder.ProgrammaticTxRequest {
    return .{
        .source = options.source,
        .sender = options.sender,
        .gas_budget = options.gas_budget,
        .gas_price = options.gas_price,
        .gas_payment_json = options.gas_payment_json,
        .signatures = options.signatures,
        .options_json = options.options_json,
        .wait_for_confirmation = options.wait_for_confirmation,
        .confirm_timeout_ms = options.confirm_timeout_ms,
        .confirm_poll_ms = options.confirm_poll_ms,
    };
}

pub fn optionsFromRequest(request: tx_builder.ProgrammaticTxRequest) ProgrammaticRequestOptions {
    return .{
        .source = request.source,
        .sender = request.sender,
        .gas_budget = request.gas_budget,
        .gas_price = request.gas_price,
        .gas_payment_json = request.gas_payment_json,
        .signatures = request.signatures,
        .options_json = request.options_json,
        .wait_for_confirmation = request.wait_for_confirmation,
        .confirm_timeout_ms = request.confirm_timeout_ms,
        .confirm_poll_ms = request.confirm_poll_ms,
    };
}

pub fn prepareRequest(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
) !tx_builder.PreparedProgrammaticTxRequest {
    return try requestFromOptions(options).prepare(allocator);
}

pub fn prepareResolvedRequestFromContents(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    contents: []const u8,
    preparation: keystore.SignerPreparation,
) !tx_builder.PreparedProgrammaticTxRequest {
    return try keystore.prepareResolvedProgrammaticRequestFromContents(
        allocator,
        requestFromOptions(options),
        contents,
        preparation,
    );
}

pub fn prepareResolvedRequestFromDefaultKeystore(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    preparation: keystore.SignerPreparation,
) !tx_builder.PreparedProgrammaticTxRequest {
    return try keystore.prepareResolvedProgrammaticRequestFromDefaultKeystore(
        allocator,
        requestFromOptions(options),
        preparation,
    );
}

pub fn prepareAuthorizedRequest(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) !AuthorizedPreparedRequest {
    switch (provider) {
        .none => {
            return .{
                .prepared = try prepareRequest(allocator, options),
            };
        },
        .direct_signatures => |account| {
            return .{
                .prepared = try prepareRequest(allocator, try applyDirectSignatures(options, account)),
                .session = account.session,
            };
        },
        .keystore_contents => |account| {
            return .{
                .prepared = try prepareResolvedRequestFromContents(
                    allocator,
                    options,
                    account.contents,
                    account.preparation,
                ),
                .session = account.session,
            };
        },
        .default_keystore => |account| {
            return .{
                .prepared = try prepareResolvedRequestFromDefaultKeystore(
                    allocator,
                    options,
                    account.preparation,
                ),
                .session = account.session,
            };
        },
        .remote_signer => |account| {
            var session = account.session;
            var supports_execute = account.session_supports_execute;

            if (account.session_challenger) |challenger| {
                if (account.session_challenge) |challenge| {
                    const challenge_response = try challenger.callback(
                        challenger.context,
                        allocator,
                        .{
                            .options = options,
                            .account_address = account.address,
                            .current_session = session,
                            .action = account.session_action,
                            .challenge = challenge,
                        },
                    );
                    if (challenge_response.session) |updated_session| {
                        session = updated_session;
                    }
                    supports_execute = challenge_response.supports_execute;
                }
            }

            const authorization = try account.authorizer.callback(
                account.authorizer.context,
                allocator,
                .{
                    .options = options,
                    .account_address = account.address,
                    .account_session = session,
                },
            );

            return .{
                .prepared = try prepareRequest(
                    allocator,
                    try applyRemoteAuthorization(options, account.address, authorization),
                ),
                .session = authorization.session orelse session,
                .supports_execute = supports_execute and authorization.supports_execute,
            };
        },
        .zklogin => |account| {
            if (account.authorizer) |authorizer| {
                const authorization = try authorizer.callback(
                    authorizer.context,
                    allocator,
                    .{
                        .options = options,
                        .account_address = account.address,
                        .account_session = account.session,
                    },
                );
                return .{
                    .prepared = try prepareRequest(
                        allocator,
                        try applyRemoteAuthorization(options, account.address, authorization),
                    ),
                    .session = authorization.session orelse account.session,
                    .supports_execute = account.session_supports_execute and authorization.supports_execute,
                };
            }
            return .{
                .prepared = try prepareRequest(allocator, try applyFutureWalletAddress(options, account)),
                .session = account.session,
                .supports_execute = false,
            };
        },
        .passkey => |account| {
            if (account.authorizer) |authorizer| {
                const authorization = try authorizer.callback(
                    authorizer.context,
                    allocator,
                    .{
                        .options = options,
                        .account_address = account.address,
                        .account_session = account.session,
                    },
                );
                return .{
                    .prepared = try prepareRequest(
                        allocator,
                        try applyRemoteAuthorization(options, account.address, authorization),
                    ),
                    .session = authorization.session orelse account.session,
                    .supports_execute = account.session_supports_execute and authorization.supports_execute,
                };
            }
            return .{
                .prepared = try prepareRequest(allocator, try applyFutureWalletAddress(options, account)),
                .session = account.session,
                .supports_execute = false,
            };
        },
        .multisig => |account| {
            if (account.authorizer) |authorizer| {
                const authorization = try authorizer.callback(
                    authorizer.context,
                    allocator,
                    .{
                        .options = options,
                        .account_address = account.address,
                        .account_session = account.session,
                    },
                );
                return .{
                    .prepared = try prepareRequest(
                        allocator,
                        try applyRemoteAuthorization(options, account.address, authorization),
                    ),
                    .session = authorization.session orelse account.session,
                    .supports_execute = account.session_supports_execute and authorization.supports_execute,
                };
            }
            return .{
                .prepared = try prepareRequest(allocator, try applyFutureWalletAddress(options, account)),
                .session = account.session,
                .supports_execute = false,
            };
        },
    }
}

pub fn buildAuthorizedInspectPayload(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) ![]u8 {
    var prepared = try prepareAuthorizedRequest(allocator, options, provider);
    defer prepared.deinit(allocator);
    return try prepared.buildInspectPayload(allocator);
}

pub fn buildAuthorizedExecutePayload(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) ![]u8 {
    var prepared = try prepareAuthorizedRequest(allocator, options, provider);
    defer prepared.deinit(allocator);
    return try prepared.buildExecutePayload(allocator);
}

pub fn buildAuthorizedArtifact(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
    kind: ProgrammaticArtifactKind,
) ![]u8 {
    var prepared = try prepareAuthorizedRequest(allocator, options, provider);
    defer prepared.deinit(allocator);
    return try prepared.buildArtifact(allocator, kind);
}

pub fn buildAuthorizedTransactionBlock(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    provider: AccountProvider,
) ![]u8 {
    return try buildAuthorizedArtifact(allocator, options, provider, .transaction_block);
}

pub fn buildTransactionBlock(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
) ![]u8 {
    return try buildArtifact(allocator, options, .transaction_block);
}

pub fn buildArtifact(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    kind: ProgrammaticArtifactKind,
) ![]u8 {
    var prepared = try prepareRequest(allocator, options);
    defer prepared.deinit(allocator);
    var authorized = AuthorizedPreparedRequest{
        .prepared = prepared,
    };
    return try authorized.buildArtifact(allocator, kind);
}

pub fn buildTransactionBlockFromCommandSource(
    allocator: std.mem.Allocator,
    source: tx_builder.CommandSource,
    config: CommandRequestConfig,
) ![]u8 {
    return try buildArtifactFromCommandSource(allocator, source, config, .transaction_block);
}

pub fn buildInstruction(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
) ![]u8 {
    return try buildInstructionFromCommandSource(allocator, options.source);
}

pub fn buildInstructionFromCommandSource(
    allocator: std.mem.Allocator,
    source: tx_builder.CommandSource,
) ![]u8 {
    if (source.commands_json != null or source.command_items.len > 0) return error.InvalidCli;
    const move_call = source.move_call orelse return error.InvalidCli;

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    try tx_builder.writeMoveCallInstruction(
        allocator,
        out.writer(allocator),
        move_call.package_id,
        move_call.module,
        move_call.function_name,
        move_call.type_args,
        move_call.arguments,
    );
    return try out.toOwnedSlice(allocator);
}

pub fn buildArtifactFromCommandSource(
    allocator: std.mem.Allocator,
    source: tx_builder.CommandSource,
    config: CommandRequestConfig,
    kind: ProgrammaticArtifactKind,
) ![]u8 {
    return try buildArtifact(allocator, optionsFromCommandSource(source, config), kind);
}

pub fn buildInspectPayload(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
) ![]u8 {
    return try buildArtifact(allocator, options, .inspect_payload);
}

pub fn buildExecutePayload(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
) ![]u8 {
    return try buildArtifact(allocator, options, .execute_payload);
}

pub fn buildResolvedInspectPayloadFromContents(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    contents: []const u8,
    preparation: keystore.SignerPreparation,
) ![]u8 {
    var prepared = try prepareResolvedRequestFromContents(allocator, options, contents, preparation);
    defer prepared.deinit(allocator);
    return try prepared.buildInspectPayload(allocator);
}

pub fn buildResolvedExecutePayloadFromContents(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    contents: []const u8,
    preparation: keystore.SignerPreparation,
) ![]u8 {
    var prepared = try prepareResolvedRequestFromContents(allocator, options, contents, preparation);
    defer prepared.deinit(allocator);
    return try prepared.buildExecutePayload(allocator);
}

pub fn buildResolvedInspectPayloadFromDefaultKeystore(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    preparation: keystore.SignerPreparation,
) ![]u8 {
    var prepared = try prepareResolvedRequestFromDefaultKeystore(allocator, options, preparation);
    defer prepared.deinit(allocator);
    return try prepared.buildInspectPayload(allocator);
}

pub fn buildResolvedExecutePayloadFromDefaultKeystore(
    allocator: std.mem.Allocator,
    options: ProgrammaticRequestOptions,
    preparation: keystore.SignerPreparation,
) ![]u8 {
    var prepared = try prepareResolvedRequestFromDefaultKeystore(allocator, options, preparation);
    defer prepared.deinit(allocator);
    return try prepared.buildExecutePayload(allocator);
}

test "requestFromOptions maps arbitrary programmatic request settings" {
    const testing = std.testing;

    const request = requestFromOptions(.{
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
        .gas_budget = 800,
        .gas_price = 6,
        .gas_payment_json = "[{\"objectId\":\"0xgas\",\"version\":\"7\",\"digest\":\"digest-gas\"}]",
        .signatures = &.{"sig-a"},
        .options_json = "{\"showEffects\":true}",
        .wait_for_confirmation = true,
        .confirm_timeout_ms = 5_000,
        .confirm_poll_ms = 25,
    });

    try testing.expect(request.source.move_call != null);
    try testing.expectEqualStrings("0xabc", request.sender.?);
    try testing.expectEqual(@as(u64, 800), request.gas_budget.?);
    try testing.expectEqual(@as(u64, 6), request.gas_price.?);
    try testing.expectEqualStrings("[{\"objectId\":\"0xgas\",\"version\":\"7\",\"digest\":\"digest-gas\"}]", request.gas_payment_json.?);
    try testing.expectEqualStrings("sig-a", request.signatures[0]);
    try testing.expectEqualStrings("{\"showEffects\":true}", request.options_json.?);
    try testing.expect(request.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 5_000), request.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 25), request.confirm_poll_ms);
}

test "prepareAuthorizedRequest supports direct signatures and execute payloads" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareAuthorizedRequest(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .direct_signatures = .{
            .sender = "0xabc",
            .signatures = &.{"sig-a"},
            .session = .{ .kind = .remote_signer, .session_id = "session-1", .expires_at_ms = 1_234 },
        },
    });
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xabc", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-a", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(AccountSessionKind.remote_signer, prepared.session.kind);
    try testing.expect(prepared.supports_execute);

    const payload = try prepared.buildExecutePayload(allocator);
    defer allocator.free(payload);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
}

test "buildSignPersonalMessageChallengeText formats reusable session prompts" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const text = try buildSignPersonalMessageChallengeText(allocator, .{
        .domain = "agent.example.com",
        .statement = "Authorize cloud agent execution",
        .nonce = "nonce-123",
        .address = "0xabc",
        .uri = "https://agent.example.com/session",
        .issued_at_ms = 1_000,
        .expires_at_ms = 2_000,
        .resources = &.{ "urn:agent:project:demo", "urn:agent:scope:execute" },
    });
    defer allocator.free(text);

    try testing.expect(std.mem.indexOf(u8, text, "agent.example.com wants you to sign in") != null);
    try testing.expect(std.mem.indexOf(u8, text, "0xabc") != null);
    try testing.expect(std.mem.indexOf(u8, text, "Nonce: nonce-123") != null);
    try testing.expect(std.mem.indexOf(u8, text, "Resources:") != null);
}

test "sessionChallengeRequest exposes configured remote signer challenges" {
    const testing = std.testing;

    const maybe_request = sessionChallengeRequest(.{
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
                .callback = struct {
                    fn call(_: *anyopaque, _: std.mem.Allocator, _: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
                        return .{};
                    }
                }.call,
            },
            .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
            .session_challenger = .{
                .context = undefined,
                .callback = struct {
                    fn call(_: *anyopaque, _: std.mem.Allocator, _: SessionChallengeRequest) !SessionChallengeResponse {
                        return .{};
                    }
                }.call,
            },
            .session_challenge = .{
                .sign_personal_message = .{
                    .domain = "agent.example.com",
                    .statement = "Authorize cloud agent execution",
                    .nonce = "nonce-123",
                },
            },
            .session_action = .cloud_agent_access,
        },
    });

    try testing.expect(maybe_request != null);
    try testing.expectEqualStrings("0xcloud", maybe_request.?.account_address.?);
    try testing.expectEqual(AccountSessionKind.remote_signer, maybe_request.?.current_session.kind);
    try testing.expectEqual(SessionChallengeAction.cloud_agent_access, maybe_request.?.action);
    try testing.expect(maybe_request.?.challenge == .sign_personal_message);
}

test "sessionChallengeRequest exposes configured future wallet challenges" {
    const testing = std.testing;

    const maybe_request = sessionChallengeRequest(.{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .passkey = .{
            .address = "0xpasskey",
            .session = .{ .kind = .passkey, .session_id = "webauthn-session", .user_id = "user-2" },
            .session_challenge = .{
                .passkey = .{
                    .rp_id = "wallet.example",
                    .challenge_b64url = "challenge-123",
                },
            },
            .session_action = .cloud_agent_access,
        },
    });

    try testing.expect(maybe_request != null);
    try testing.expectEqualStrings("0xpasskey", maybe_request.?.account_address.?);
    try testing.expectEqual(AccountSessionKind.passkey, maybe_request.?.current_session.kind);
    try testing.expectEqual(SessionChallengeAction.cloud_agent_access, maybe_request.?.action);
    try testing.expect(maybe_request.?.challenge == .passkey);
}

test "authorizationPlan carries session challenges and applied responses" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const initial = authorizationPlan(.{
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

    const request = initial.challengeRequest() orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("0xzk", request.account_address.?);
    try testing.expectEqual(SessionChallengeAction.cloud_agent_access, request.action);

    const text = try initial.challengeText(allocator);
    defer if (text) |value| allocator.free(value);
    try testing.expect(text != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "zkLogin nonce challenge") != null);
    try testing.expect(std.mem.indexOf(u8, text.?, "google") != null);

    const updated = try initial.withChallengeResponse(.{
        .session = .{ .kind = .zklogin, .session_id = "approved-session" },
        .supports_execute = false,
    });

    try testing.expect(updated.challengeRequest() == null);
    switch (updated.provider) {
        .zklogin => |account| {
            try testing.expectEqualStrings("approved-session", account.session.session_id.?);
            try testing.expect(account.session_challenge == null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "accountProviderCanExecute reflects configured signer and session sources" {
    const testing = std.testing;

    try testing.expect(!accountProviderCanExecute(.none));
    try testing.expect(accountProviderCanExecute(.{
        .direct_signatures = .{
            .signatures = &.{"sig-a"},
        },
    }));
    try testing.expect(accountProviderCanExecute(.{
        .default_keystore = .{
            .preparation = .{ .signer_selectors = &.{"builder"} },
        },
    }));
    try testing.expect(!accountProviderCanExecute(.{
        .default_keystore = .{
            .preparation = .{},
        },
    }));
    try testing.expect(accountProviderCanExecute(.{
        .passkey = .{
            .session = .{ .kind = .passkey, .session_id = "session-1" },
            .authorizer = .{
                .context = undefined,
                .callback = struct {
                    fn call(_: *anyopaque, _: std.mem.Allocator, _: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
                        return .{};
                    }
                }.call,
            },
            .session_supports_execute = true,
        },
    }));
    try testing.expect(!accountProviderCanExecute(.{
        .zklogin = .{
            .session = .{ .kind = .zklogin, .session_id = "session-1" },
        },
    }));
}

test "buildSessionChallengeText formats passkey and zklogin challenge summaries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const passkey_text = try buildSessionChallengeText(allocator, .{
        .options = .{ .source = .{ .command_items = &.{} } },
        .action = .execute,
        .challenge = .{
            .passkey = .{
                .rp_id = "agent.example.com",
                .challenge_b64url = "abc123",
            },
        },
    });
    defer allocator.free(passkey_text);
    try testing.expect(std.mem.indexOf(u8, passkey_text, "Passkey challenge") != null);

    const zklogin_text = try buildSessionChallengeText(allocator, .{
        .options = .{ .source = .{ .command_items = &.{} } },
        .action = .inspect,
        .challenge = .{
            .zklogin_nonce = .{
                .nonce = "nonce-456",
                .provider = "google",
            },
        },
    });
    defer allocator.free(zklogin_text);
    try testing.expect(std.mem.indexOf(u8, zklogin_text, "zkLogin nonce challenge") != null);
    try testing.expect(std.mem.indexOf(u8, zklogin_text, "google") != null);
}

test "prepareAuthorizedRequest supports remote signer authorization callbacks" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
            try testing.expectEqualStrings("0xcloud", req.account_address.?);
            try testing.expectEqual(AccountSessionKind.remote_signer, req.account_session.kind);
            return .{
                .sender = "0xremote",
                .signatures = &.{"sig-remote"},
                .session = .{ .kind = .remote_signer, .session_id = "remote-session", .user_id = "user-1" },
            };
        }
    }.call;

    var prepared = try prepareAuthorizedRequest(allocator, .{
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
                .callback = callback,
            },
        },
    });
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xremote", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-remote", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(AccountSessionKind.remote_signer, prepared.session.kind);
    try testing.expect(prepared.supports_execute);
}

test "prepareAuthorizedRequest rejects conflicting direct signature sender overrides" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, prepareAuthorizedRequest(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
            .sender = "0xexpected",
        },
        .{
            .direct_signatures = .{
                .sender = "0xother",
                .signatures = &.{"sig-a"},
            },
        },
    ));
}

test "prepareAuthorizedRequest supports session challengers before remote authorization" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const State = struct {
        challenge_seen: bool = false,
    };

    var state = State{};

    const challenge_callback = struct {
        fn call(context: *anyopaque, _: std.mem.Allocator, req: SessionChallengeRequest) !SessionChallengeResponse {
            const state_ptr = @as(*State, @ptrCast(@alignCast(context)));
            state_ptr.challenge_seen = true;
            try testing.expectEqual(AccountSessionKind.remote_signer, req.current_session.kind);
            try testing.expect(req.challenge == .sign_personal_message);
            return .{
                .session = .{ .kind = .remote_signer, .session_id = "session-after-challenge", .user_id = "user-1" },
            };
        }
    }.call;

    const authorizer_callback = struct {
        fn call(context: *anyopaque, _: std.mem.Allocator, req: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
            const state_ptr = @as(*State, @ptrCast(@alignCast(context)));
            try testing.expect(state_ptr.challenge_seen);
            try testing.expectEqualStrings("session-after-challenge", req.account_session.session_id.?);
            return .{
                .sender = "0xremote",
                .signatures = &.{"sig-remote"},
            };
        }
    }.call;

    var prepared = try prepareAuthorizedRequest(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .remote_signer = .{
            .address = "0xcloud",
            .authorizer = .{
                .context = &state,
                .callback = authorizer_callback,
            },
            .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
            .session_challenger = .{
                .context = &state,
                .callback = challenge_callback,
            },
            .session_challenge = .{
                .sign_personal_message = .{
                    .domain = "agent.example.com",
                    .statement = "Authorize cloud agent execution",
                    .nonce = "nonce-123",
                },
            },
            .session_action = .cloud_agent_access,
        },
    });
    defer prepared.deinit(allocator);

    try testing.expect(state.challenge_seen);
    try testing.expectEqualStrings("0xremote", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-remote", prepared.prepared.request.signatures[0]);
    try testing.expectEqualStrings("session-after-challenge", prepared.session.session_id.?);
}

test "prepareAuthorizedRequest resolves keystore-backed accounts from provided contents" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareAuthorizedRequest(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .gas_budget = 900,
    }, .{
        .keystore_contents = .{
            .contents = "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
            .preparation = .{ .signer_selectors = &.{"builder"} },
        },
    });
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xbuilder", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-builder", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(AccountSessionKind.local_keystore, prepared.session.kind);
    try testing.expect(prepared.supports_execute);
}

test "prepareAuthorizedRequest carries future wallet metadata without execute support" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareAuthorizedRequest(allocator, .{
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
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xzk", prepared.prepared.request.sender.?);
    try testing.expectEqual(AccountSessionKind.zklogin, prepared.session.kind);
    try testing.expect(!prepared.supports_execute);

    const inspect_payload = try prepared.buildInspectPayload(allocator);
    defer allocator.free(inspect_payload);
    try testing.expectError(error.UnsupportedAccountProvider, prepared.buildExecutePayload(allocator));
}

test "applySessionChallengeResponse updates future wallet providers" {
    const testing = std.testing;

    const updated = try applySessionChallengeResponse(.{
        .zklogin = .{
            .address = "0xzk",
            .session = .{ .kind = .zklogin, .session_id = "old-session" },
            .session_challenge = .{
                .zklogin_nonce = .{
                    .nonce = "nonce-456",
                    .provider = "google",
                },
            },
            .session_action = .inspect,
        },
    }, .{
        .session = .{ .kind = .zklogin, .session_id = "new-session", .user_id = "user-1" },
        .supports_execute = false,
    });

    switch (updated) {
        .zklogin => |account| {
            try testing.expectEqualStrings("0xzk", account.address.?);
            try testing.expectEqualStrings("new-session", account.session.session_id.?);
            try testing.expect(account.session_challenge == null);
            try testing.expectEqual(SessionChallengeAction.inspect, account.session_action);
            try testing.expect(!account.session_supports_execute);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "prepareAuthorizedRequest supports authorized future wallet execution" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
            try testing.expectEqualStrings("0xpasskey", req.account_address.?);
            try testing.expectEqual(AccountSessionKind.passkey, req.account_session.kind);
            try testing.expectEqualStrings("passkey-session", req.account_session.session_id.?);
            return .{
                .sender = "0xpasskey-sender",
                .signatures = &.{"sig-passkey"},
                .session = .{ .kind = .passkey, .session_id = "passkey-session" },
            };
        }
    }.call;

    var prepared = try prepareAuthorizedRequest(allocator, .{
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
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xpasskey-sender", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-passkey", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(AccountSessionKind.passkey, prepared.session.kind);
    try testing.expect(prepared.supports_execute);
}

test "prepareAuthorizedRequest rejects conflicting remote account senders" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, _: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
            return .{
                .sender = "0xremote-account",
                .signatures = &.{"sig-remote"},
            };
        }
    }.call;

    try testing.expectError(error.InvalidCli, prepareAuthorizedRequest(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
            .sender = "0xexplicit-sender",
        },
        .{
            .remote_signer = .{
                .address = "0xremote-account",
                .authorizer = .{
                    .context = undefined,
                    .callback = authorizer,
                },
                .session_supports_execute = true,
            },
        },
    ));
}

test "authorizationPlan authorizes command-source configs into executable payloads" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
            try testing.expectEqualStrings("0xpasskey", req.account_address.?);
            try testing.expectEqualStrings("session-1", req.account_session.session_id.?);
            try testing.expectEqual(@as(?u64, 77), req.options.gas_budget);
            return .{
                .sender = "0xauthorized",
                .signatures = &.{"sig-authorized"},
                .session = req.account_session,
            };
        }
    }.call;

    const plan = authorizationPlanFromCommandSource(.{
        .command_items = &.{
            "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
        },
    }, .{
        .gas_budget = 77,
        .gas_price = 9,
        .wait_for_confirmation = true,
        .confirm_timeout_ms = 3333,
        .confirm_poll_ms = 444,
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

    var prepared = try plan.authorize(allocator);
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xauthorized", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-authorized", prepared.prepared.request.signatures[0]);
    try testing.expectEqual(@as(?u64, 77), prepared.prepared.request.gas_budget);
    try testing.expectEqual(@as(?u64, 9), prepared.prepared.request.gas_price);
    try testing.expect(prepared.prepared.request.wait_for_confirmation);
    try testing.expect(prepared.supports_execute);

    const payload = try plan.buildAuthorizedExecutePayload(allocator);
    defer allocator.free(payload);
    try testing.expect(std.mem.indexOf(u8, payload, "sig-authorized") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "0xauthorized") != null);
}

test "buildTransactionBlockFromCommandSource normalizes move-call sources into programmable tx blocks" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const tx_block = try buildTransactionBlockFromCommandSource(allocator, .{
        .move_call = .{
            .package_id = "0x2",
            .module = "counter",
            .function_name = "increment",
            .type_args = "[]",
            .arguments = "[\"0xabc\"]",
        },
    }, .{
        .sender = "0xsender",
        .gas_budget = 123,
        .gas_price = 9,
    });
    defer allocator.free(tx_block);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, tx_block, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .object);
    try testing.expectEqualStrings("ProgrammableTransaction", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xsender", parsed.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 123), parsed.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 9), parsed.value.object.get("gasPrice").?.integer);
}

test "buildArtifact routes shared programmatic artifact kinds" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options: ProgrammaticRequestOptions = .{
        .source = .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        .sender = "0xsender",
        .gas_budget = 77,
        .gas_price = 5,
        .signatures = &.{"sig-a"},
    };

    const tx_block = try buildArtifact(allocator, options, .transaction_block);
    defer allocator.free(tx_block);

    const parsed_tx_block = try std.json.parseFromSlice(std.json.Value, allocator, tx_block, .{});
    defer parsed_tx_block.deinit();
    try testing.expect(parsed_tx_block.value == .object);
    try testing.expectEqualStrings("ProgrammableTransaction", parsed_tx_block.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0xsender", parsed_tx_block.value.object.get("sender").?.string);

    var prepared = try prepareRequest(allocator, options);
    defer prepared.deinit(allocator);

    const inspect_payload = try buildArtifact(allocator, options, .inspect_payload);
    defer allocator.free(inspect_payload);
    const expected_inspect_payload = try prepared.buildInspectPayload(allocator);
    defer allocator.free(expected_inspect_payload);
    try testing.expectEqualStrings(expected_inspect_payload, inspect_payload);

    const execute_payload = try buildArtifact(allocator, options, .execute_payload);
    defer allocator.free(execute_payload);
    const expected_execute_payload = try prepared.buildExecutePayload(allocator);
    defer allocator.free(expected_execute_payload);
    try testing.expectEqualStrings(expected_execute_payload, execute_payload);
}

test "buildInstructionFromCommandSource renders move-call instruction artifacts" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const instruction = try buildInstructionFromCommandSource(allocator, .{
        .move_call = .{
            .package_id = "0x2",
            .module = "counter",
            .function_name = "increment",
            .type_args = "[\"u64\"]",
            .arguments = "[7]",
        },
    });
    defer allocator.free(instruction);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, instruction, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .object);
    try testing.expectEqualStrings("MoveCall", parsed.value.object.get("kind").?.string);
    try testing.expectEqualStrings("0x2", parsed.value.object.get("package").?.string);
    try testing.expectEqualStrings("counter", parsed.value.object.get("module").?.string);
}

test "AuthorizationPlan can build transaction blocks through authorized sender resolution" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const authorizer = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, req: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
            try testing.expectEqualStrings("0xpasskey", req.account_address.?);
            return .{
                .sender = "0xauthorized",
                .signatures = &.{"sig-authorized"},
                .session = req.account_session,
            };
        }
    }.call;

    const tx_block = try authorizationPlan(.{
        .source = .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        .gas_budget = 321,
        .gas_price = 11,
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
    }).buildTransactionBlock(allocator);
    defer allocator.free(tx_block);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, tx_block, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("0xauthorized", parsed.value.object.get("sender").?.string);
    try testing.expectEqual(@as(i64, 321), parsed.value.object.get("gasBudget").?.integer);
    try testing.expectEqual(@as(i64, 11), parsed.value.object.get("gasPrice").?.integer);
}

test "prepareAuthorizedRequest can mark remote signer accounts as inspect-only" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const callback = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, _: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
            return .{
                .sender = "0xinspect-only",
                .supports_execute = false,
            };
        }
    }.call;

    var prepared = try prepareAuthorizedRequest(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .remote_signer = .{
            .authorizer = .{
                .context = undefined,
                .callback = callback,
            },
        },
    });
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xinspect-only", prepared.prepared.request.sender.?);
    try testing.expect(!prepared.supports_execute);
    try testing.expectError(error.UnsupportedAccountProvider, prepared.buildExecutePayload(allocator));
}

test "prepareAuthorizedRequest can mark challenged remote signer accounts as inspect-only" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const challenge_callback = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, _: SessionChallengeRequest) !SessionChallengeResponse {
            return .{ .supports_execute = false };
        }
    }.call;

    const authorizer_callback = struct {
        fn call(_: *anyopaque, _: std.mem.Allocator, _: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
            return .{
                .sender = "0xinspect-only",
            };
        }
    }.call;

    var prepared = try prepareAuthorizedRequest(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
        .remote_signer = .{
            .authorizer = .{
                .context = undefined,
                .callback = authorizer_callback,
            },
            .session_challenger = .{
                .context = undefined,
                .callback = challenge_callback,
            },
            .session_challenge = .{
                .passkey = .{
                    .rp_id = "agent.example.com",
                    .challenge_b64url = "abc123",
                },
            },
        },
    });
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xinspect-only", prepared.prepared.request.sender.?);
    try testing.expect(!prepared.supports_execute);
    try testing.expectError(error.UnsupportedAccountProvider, prepared.buildExecutePayload(allocator));
}

test "applySessionChallengeResponse updates remote signer providers for later execution" {
    const testing = std.testing;

    const authorizer = RemoteAuthorizer{
        .context = undefined,
        .callback = struct {
            fn call(_: *anyopaque, _: std.mem.Allocator, _: RemoteAuthorizationRequest) !RemoteAuthorizationResult {
                return .{};
            }
        }.call,
    };

    const updated = try applySessionChallengeResponse(.{
        .remote_signer = .{
            .address = "0xcloud",
            .authorizer = authorizer,
            .session = .{ .kind = .remote_signer, .session_id = "bootstrap-session" },
            .session_challenger = .{
                .context = undefined,
                .callback = struct {
                    fn call(_: *anyopaque, _: std.mem.Allocator, _: SessionChallengeRequest) !SessionChallengeResponse {
                        return .{};
                    }
                }.call,
            },
            .session_challenge = .{
                .passkey = .{
                    .rp_id = "agent.example.com",
                    .challenge_b64url = "abc123",
                },
            },
        },
    }, .{
        .session = .{ .kind = .remote_signer, .session_id = "session-after-challenge" },
        .supports_execute = false,
    });

    try testing.expect(updated == .remote_signer);
    try testing.expectEqualStrings("session-after-challenge", updated.remote_signer.session.session_id.?);
    try testing.expect(updated.remote_signer.session_challenger == null);
    try testing.expect(updated.remote_signer.session_challenge == null);
    try testing.expect(!updated.remote_signer.session_supports_execute);
}

test "optionsFromCommandSource maps arbitrary command-source settings" {
    const testing = std.testing;

    const options = optionsFromCommandSource(.{
        .command_items = &.{
            "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
        },
    }, .{
        .sender = "0xabc",
        .gas_budget = 900,
        .gas_price = 8,
        .signatures = &.{"sig-a"},
        .options_json = "{\"showEffects\":true}",
        .wait_for_confirmation = true,
        .confirm_timeout_ms = 6_000,
        .confirm_poll_ms = 30,
    });

    try testing.expectEqual(@as(usize, 1), options.source.command_items.len);
    try testing.expectEqualStrings("0xabc", options.sender.?);
    try testing.expectEqual(@as(u64, 900), options.gas_budget.?);
    try testing.expectEqual(@as(u64, 8), options.gas_price.?);
    try testing.expectEqualStrings("sig-a", options.signatures[0]);
    try testing.expectEqualStrings("{\"showEffects\":true}", options.options_json.?);
    try testing.expect(options.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 6_000), options.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 30), options.confirm_poll_ms);
}

test "ProgrammaticRequestOptionsBuilder builds owned options from typed commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticRequestOptionsBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendMoveCall(.{
        .package_id = "0x2",
        .module = "counter",
        .function_name = "increment",
        .type_args = "[]",
        .arguments = "[\"0xabc\"]",
    });
    try builder.appendTransferObjects(.{
        .objects_json = "[\"0xcoin\"]",
        .address_json = "\"0xreceiver\"",
    });
    try builder.appendPublish(.{
        .modules_json = "[\"AQID\"]",
        .dependencies_json = "[\"0x2\"]",
    });
    builder.setSender("0xabc");
    builder.setGasBudget(900);
    builder.setGasPrice(8);
    builder.setSignatures(&.{"sig-a"});
    builder.setOptionsJson("{\"showEffects\":true}");
    builder.setConfirmation(6_000, 30);

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    try testing.expect(owned.options.source.commands_json != null);
    try testing.expectEqualStrings("0xabc", owned.options.sender.?);
    try testing.expectEqual(@as(u64, 900), owned.options.gas_budget.?);
    try testing.expectEqual(@as(u64, 8), owned.options.gas_price.?);
    try testing.expectEqualStrings("sig-a", owned.options.signatures[0]);
    try testing.expectEqualStrings("{\"showEffects\":true}", owned.options.options_json.?);
    try testing.expect(owned.options.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 6_000), owned.options.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 30), owned.options.confirm_poll_ms);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, owned.options.source.commands_json.?, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
}

test "OwnedProgrammaticRequestOptions can produce owned authorization plans" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticRequestOptionsBuilder.init(allocator);
    defer builder.deinit();
    try builder.appendTransferObjects(.{
        .objects_json = "[\"0xcoin\"]",
        .address_json = "\"0xreceiver\"",
    });

    var owned = try builder.finish();
    var plan = owned.authorizationPlan(.{
        .direct_signatures = .{
            .sender = "0xabc",
            .signatures = &.{"sig-a"},
        },
    });
    defer plan.deinit(allocator);

    const payload = try plan.buildAuthorizedExecutePayload(allocator);
    defer allocator.free(payload);

    try testing.expect(std.mem.indexOf(u8, payload, "sig-a") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "0xabc") != null);
}

test "ownOptions normalizes and owns programmatic request fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var owned = try ownOptions(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .sender = "0xsender",
        .gas_budget = 1000,
        .gas_price = 7,
        .signatures = &.{"sig-a"},
        .options_json = "{\"showEffects\":true}",
        .wait_for_confirmation = true,
        .confirm_timeout_ms = 5_000,
        .confirm_poll_ms = 25,
    });
    defer owned.deinit(allocator);

    try testing.expect(owned.options.source.commands_json != null);
    try testing.expectEqualStrings("0xsender", owned.options.sender.?);
    try testing.expectEqual(@as(usize, 1), owned.options.signatures.len);
    try testing.expectEqualStrings("sig-a", owned.options.signatures[0]);
    try testing.expectEqualStrings("{\"showEffects\":true}", owned.options.options_json.?);
    try testing.expect(owned.options.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 5_000), owned.options.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 25), owned.options.confirm_poll_ms);
}

test "AuthorizationPlan withChallengeResponse clears consumed future-wallet challenges" {
    const testing = std.testing;

    const plan = authorizationPlan(.{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, .{
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
            .session_supports_execute = false,
        },
    });

    try testing.expect(plan.challengeRequest() != null);

    const updated = try plan.withChallengeResponse(.{
        .session = .{ .kind = .passkey, .session_id = "approved-passkey-session" },
        .supports_execute = false,
    });

    try testing.expect(updated.challengeRequest() == null);
    switch (updated.provider) {
        .passkey => |account| {
            try testing.expectEqualStrings("approved-passkey-session", account.session.session_id.?);
            try testing.expect(!account.session_supports_execute);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "applySessionChallengeResponse does not make authorizer-free passkey accounts executable" {
    const testing = std.testing;

    const updated = try applySessionChallengeResponse(.{
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
            .session_supports_execute = false,
        },
    }, .{
        .session = .{ .kind = .passkey, .session_id = "approved-passkey-session" },
        .supports_execute = true,
    });

    try testing.expect(!accountProviderCanExecute(updated));
}

test "prepareAuthorizedRequest keeps authorizer-free passkey accounts inspect-only after approval" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const updated = try applySessionChallengeResponse(.{
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
            .session_supports_execute = false,
        },
    }, .{
        .session = .{ .kind = .passkey, .session_id = "approved-passkey-session" },
        .supports_execute = true,
    });

    var prepared = try prepareAuthorizedRequest(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
    }, updated);
    defer prepared.deinit(allocator);

    try testing.expect(!prepared.supports_execute);
    try testing.expectEqualStrings("0xpasskey", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("approved-passkey-session", prepared.session.session_id.?);
    try testing.expectError(error.UnsupportedAccountProvider, prepared.buildExecutePayload(allocator));
}

test "ProgrammaticDslBuilder can finish directly into owned authorization plans" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendSplitCoinsAndGetValueFromValues(.gas_coin, &.{.{ .u64 = 7 }});

    var plan = try builder.finishAuthorizationPlan(.{
        .zklogin = .{
            .address = "0xzk",
            .session = .{ .kind = .zklogin, .session_id = "oauth-session" },
            .session_challenge = .{
                .zklogin_nonce = .{
                    .nonce = "nonce-456",
                    .provider = "google",
                },
            },
            .session_action = .inspect,
        },
    });
    defer plan.deinit(allocator);

    const request = plan.challengeRequest() orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("0xzk", request.account_address.?);

    const text = try plan.challengeText(allocator);
    defer if (text) |value| allocator.free(value);
    try testing.expect(text != null);

    try plan.withChallengeResponse(.{
        .session = .{ .kind = .zklogin, .session_id = "approved-session" },
        .supports_execute = false,
    });

    try testing.expect(plan.challengeRequest() == null);
    switch (plan.provider) {
        .zklogin => |account| {
            try testing.expectEqualStrings("approved-session", account.session.session_id.?);
            try testing.expect(account.session_challenge == null);
            try testing.expect(!account.session_supports_execute);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ProgrammaticDslBuilder can authorize directly with an account provider" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    _ = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    var prepared = try builder.authorize(allocator, .{
        .direct_signatures = .{
            .sender = "0xabc",
            .signatures = &.{"sig-a"},
        },
    });
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xabc", prepared.prepared.request.sender.?);
    try testing.expectEqualStrings("sig-a", prepared.prepared.request.signatures[0]);
    try testing.expect(prepared.supports_execute);
}

test "ProgrammaticDslBuilder can build authorized artifacts directly" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var execute_builder = ProgrammaticDslBuilder.init(allocator);
    defer execute_builder.deinit();
    _ = try execute_builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    const payload = try execute_builder.buildAuthorizedExecutePayload(allocator, .{
        .direct_signatures = .{
            .sender = "0xabc",
            .signatures = &.{"sig-a"},
        },
    });
    defer allocator.free(payload);
    try testing.expect(std.mem.indexOf(u8, payload, "sig-a") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "0xabc") != null);

    var tx_block_builder = ProgrammaticDslBuilder.init(allocator);
    defer tx_block_builder.deinit();
    _ = try tx_block_builder.appendTransferObjectsAndGetValueFromValues(
        &.{.{ .object_id = "0xcoin" }},
        .{ .address = "0xreceiver" },
    );

    const tx_block = try tx_block_builder.buildTransactionBlock(allocator, .{
        .direct_signatures = .{
            .sender = "0xabc",
            .signatures = &.{"sig-a"},
        },
    });
    defer allocator.free(tx_block);
    try testing.expect(std.mem.indexOf(u8, tx_block, "\"sender\":\"0xabc\"") != null);
}

test "CommandResultAliases assign and resolve named references" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);

    try assignCommandResultAlias(allocator, &aliases, "coin_split", 3);

    const result = try resolveNamedResultReferenceToken(allocator, &aliases, "ptb:name:coin_split");
    defer allocator.free(result.?);
    try testing.expectEqualStrings("ptb:result:3", result.?);

    const nested = try resolveNamedResultReferenceToken(allocator, &aliases, "ptb:name:coin_split:0");
    defer allocator.free(nested.?);
    try testing.expectEqualStrings("ptb:nested:3:0", nested.?);

    try testing.expectError(error.InvalidCli, assignCommandResultAlias(allocator, &aliases, "coin_split", 4));
    try testing.expectError(error.InvalidCli, resolveNamedResultReferenceToken(allocator, &aliases, "ptb:name:missing"));
}

test "cloneCommandResultAliases duplicates alias mappings" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);
    try assignCommandResultAlias(allocator, &aliases, "coin_split", 3);

    var cloned = try cloneCommandResultAliases(allocator, &aliases);
    defer deinitCommandResultAliases(allocator, &cloned);

    try testing.expectEqual(@as(?u16, 3), cloned.get("coin_split"));
}

test "resolveCommandValue and resolveCommandValues expand named references" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);
    try assignCommandResultAlias(allocator, &aliases, "coin_split", 2);

    var single = try resolveCommandValue(allocator, &aliases, "ptb:name:coin_split:0");
    defer single.deinit(allocator);
    try testing.expectEqualStrings("ptb:nested:2:0", single.value);

    var many = try resolveCommandValues(allocator, &aliases, &.{ "ptb:name:coin_split", "0xabc" });
    defer many.deinit(allocator);
    try testing.expectEqual(@as(usize, 2), many.items.items.len);
    try testing.expectEqualStrings("ptb:result:2", many.items.items[0]);
    try testing.expectEqualStrings("0xabc", many.items.items[1]);
}

test "resolvePtbArgumentSpec and resolvePtbArgumentSpecs expand named refs and canonicalize json" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);
    try assignCommandResultAlias(allocator, &aliases, "coin_split", 2);

    var single = try resolvePtbArgumentSpec(allocator, &aliases, "ptb:name:coin_split:0");
    defer single.deinit(allocator);
    try testing.expect(single.spec == .nested_result);
    try testing.expectEqual(@as(u16, 2), single.spec.nested_result.command_index);
    try testing.expectEqual(@as(u16, 0), single.spec.nested_result.result_index);

    var plain = try resolvePtbArgumentSpec(allocator, &aliases, "0xabc");
    defer plain.deinit(allocator);
    try testing.expect(plain.spec == .json);
    try testing.expectEqualStrings("\"0xabc\"", plain.spec.json);

    var many = try resolvePtbArgumentSpecs(allocator, &aliases, &.{ "ptb:gas", "ptb:name:coin_split", "7" });
    defer many.deinit(allocator);
    try testing.expectEqual(@as(usize, 3), many.items.items.len);
    try testing.expect(many.items.items[0] == .gas_coin);
    try testing.expect(many.items.items[1] == .result);
    try testing.expectEqual(@as(u16, 2), many.items.items[1].result);
    try testing.expect(many.items.items[2] == .json);
    try testing.expectEqualStrings("7", many.items.items[2].json);
}

test "buildPtbArgumentJson and buildPtbArgumentArray encode structured PTB specs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const gas = try buildPtbArgumentJson(allocator, .gas_coin);
    defer allocator.free(gas);
    try testing.expectEqualStrings("\"GasCoin\"", gas);

    const nested = try buildPtbArgumentJson(allocator, .{
        .nested_result = .{ .command_index = 4, .result_index = 5 },
    });
    defer allocator.free(nested);
    try testing.expectEqualStrings("{\"NestedResult\":[4,5]}", nested);

    const json = try buildPtbArgumentArray(allocator, &.{
        .gas_coin,
        .{ .input = 0 },
        .{ .result = 1 },
        .{ .nested_result = .{ .command_index = 2, .result_index = 3 } },
        .{ .json = "\"0xabc\"" },
        .{ .json = "7" },
    });
    defer allocator.free(json);
    try testing.expectEqualStrings("[\"GasCoin\",{\"Input\":0},{\"Result\":1},{\"NestedResult\":[2,3]},\"0xabc\",7]", json);
}

test "buildArgumentValueArray and buildArgumentValueTokenArray encode typed argument values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const values_json = try buildArgumentValueArray(allocator, &.{
        .{ .address = "0xabc123" },
        .{ .u128 = 18446744073709551616 },
        .{ .boolean = true },
    });
    defer allocator.free(values_json);
    try testing.expectEqualStrings("[\"0xabc123\",18446744073709551616,true]", values_json);

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);
    try assignCommandResultAlias(allocator, &aliases, "coin_split", 2);

    const tokens_json = try buildArgumentValueTokenArray(allocator, &aliases, &.{
        "addr:0xabc123",
        "u8:7",
        "ptb:name:coin_split:0",
    });
    defer allocator.free(tokens_json);
    try testing.expectEqualStrings("[\"0xabc123\",7,{\"NestedResult\":[2,0]}]", tokens_json);
}

test "normalizeArgumentValueJsonArray resolves typed tokens inside JSON arrays recursively" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = try normalizeArgumentValueJsonArray(
        allocator,
        null,
        "[\"addr:0xabc123\",{\"owner\":\"obj:0xdef456\"},[\"bytes:0x0a0b\"]]",
    );
    defer allocator.free(json);

    try testing.expectEqualStrings("[\"0xabc123\",{\"owner\":\"0xdef456\"},[\"0x0a0b\"]]", json);
}

test "OwnedProgrammaticRequestOptions can transfer owned commands json" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticRequestOptionsBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendMoveCall(.{
        .package_id = "0x2",
        .module = "counter",
        .function_name = "increment",
        .type_args = "[]",
        .arguments = "[\"0xabc\"]",
    });

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.takeCommandsJson() orelse return error.TestExpectedEqual;
    defer allocator.free(commands_json);

    try testing.expect(owned.owned_commands_json == null);
    try testing.expect(owned.options.source.commands_json == null);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
}

test "ProgrammaticRequestOptionsBuilder supports cli-like fragment values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticRequestOptionsBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendMoveCallFromCliValues(
        "0x2",
        "counter",
        "increment",
        &.{"0x2::sui::SUI"},
        &.{"ptb:gas", "ptb:result:0", "true"},
    );
    try builder.appendMakeMoveVecFromCliValues("0x2::sui::SUI", &.{"ptb:input:0"});
    try builder.appendTransferObjectsFromCliValues(&.{"ptb:gas"}, "0xreceiver");
    try builder.appendSplitCoinsFromCliValues("ptb:gas", &.{"7", "8"});
    try builder.appendMergeCoinsFromCliValues("ptb:result:1", &.{"ptb:nested:2:0"});
    try builder.appendPublishFromCliValues("[\"AQID\"]", "[\"0x2\"]");
    try builder.appendUpgradeFromCliValues("[\"BAUG\"]", "[\"0x2\",\"0x3\"]", "0x42", "ptb:result:0");

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 7), parsed.value.array.items.len);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("MakeMoveVec", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[2].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", parsed.value.array.items[3].object.get("kind").?.string);
    try testing.expectEqualStrings("MergeCoins", parsed.value.array.items[4].object.get("kind").?.string);
    try testing.expectEqualStrings("Publish", parsed.value.array.items[5].object.get("kind").?.string);
    try testing.expectEqualStrings("Upgrade", parsed.value.array.items[6].object.get("kind").?.string);
    try testing.expectEqualStrings("GasCoin", parsed.value.array.items[0].object.get("arguments").?.array.items[0].string);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[0].object.get("arguments").?.array.items[1].object.get("Result").?.integer);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("elements").?.array.items[0].object.get("Input").?.integer);
    try testing.expectEqualStrings("GasCoin", parsed.value.array.items[2].object.get("objects").?.array.items[0].string);
    try testing.expectEqualStrings("GasCoin", parsed.value.array.items[3].object.get("coin").?.string);
    try testing.expectEqual(@as(i64, 1), parsed.value.array.items[4].object.get("destination").?.object.get("Result").?.integer);
    try testing.expectEqualStrings("0x42", parsed.value.array.items[6].object.get("package").?.string);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[6].object.get("ticket").?.object.get("Result").?.integer);
}

test "ProgrammaticRequestOptionsBuilder supports structured PTB argument specs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticRequestOptionsBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendMoveCallFromSpecs(.{
        .package_id = "0x2",
        .module = "counter",
        .function_name = "increment",
        .type_arg_items = &.{"0x2::sui::SUI"},
        .arguments = &.{
            .gas_coin,
            .{ .result = 0 },
            .{ .json = "true" },
        },
    });
    try builder.appendMakeMoveVecFromSpecs(.{
        .type_json = "\"0x2::sui::SUI\"",
        .elements = &.{
            .{ .input = 0 },
        },
    });
    try builder.appendTransferObjectsFromSpecs(.{
        .objects = &.{
            .gas_coin,
        },
        .address = .{ .json = "\"0xreceiver\"" },
    });
    try builder.appendSplitCoinsFromSpecs(.{
        .coin = .gas_coin,
        .amounts = &.{
            .{ .json = "7" },
            .{ .json = "8" },
        },
    });
    try builder.appendMergeCoinsFromSpecs(.{
        .destination = .{ .result = 1 },
        .sources = &.{
            .{ .nested_result = .{ .command_index = 2, .result_index = 0 } },
        },
    });
    try builder.appendPublish(.{
        .modules_json = "[\"AQID\"]",
        .dependencies_json = "[\"0x2\"]",
    });
    try builder.appendUpgradeFromSpecs(.{
        .modules_json = "[\"BAUG\"]",
        .dependencies_json = "[\"0x2\",\"0x3\"]",
        .package_id = "0x42",
        .ticket = .{ .result = 1 },
    });

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 7), parsed.value.array.items.len);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("MakeMoveVec", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[2].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", parsed.value.array.items[3].object.get("kind").?.string);
    try testing.expectEqualStrings("MergeCoins", parsed.value.array.items[4].object.get("kind").?.string);
    try testing.expectEqualStrings("Publish", parsed.value.array.items[5].object.get("kind").?.string);
    try testing.expectEqualStrings("Upgrade", parsed.value.array.items[6].object.get("kind").?.string);
    try testing.expectEqualStrings("GasCoin", parsed.value.array.items[0].object.get("arguments").?.array.items[0].string);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[0].object.get("arguments").?.array.items[1].object.get("Result").?.integer);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("elements").?.array.items[0].object.get("Input").?.integer);
    try testing.expectEqualStrings("GasCoin", parsed.value.array.items[2].object.get("objects").?.array.items[0].string);
    try testing.expectEqualStrings("0xreceiver", parsed.value.array.items[2].object.get("address").?.string);
    try testing.expectEqualStrings("GasCoin", parsed.value.array.items[3].object.get("coin").?.string);
    try testing.expectEqual(@as(i64, 1), parsed.value.array.items[4].object.get("destination").?.object.get("Result").?.integer);
    try testing.expectEqualStrings("0x42", parsed.value.array.items[6].object.get("package").?.string);
    try testing.expectEqual(@as(i64, 1), parsed.value.array.items[6].object.get("ticket").?.object.get("Result").?.integer);
}

test "ProgrammaticDslBuilder supports named result aliases across typed commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendSplitCoinsFromNamedCliValues("ptb:gas", &.{"7"});
    try builder.assignLastResultAlias("coin_split");
    try builder.appendTransferObjectsFromNamedCliValues(&.{"ptb:name:coin_split:0"}, "0xreceiver");

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[1].integer);
}

test "ProgrammaticDslBuilder counts raw command batches for alias assignment" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendRawJson("[{\"kind\":\"SplitCoins\",\"coin\":\"GasCoin\",\"amounts\":[7]}]");
    try builder.assignLastResultAlias("coin_split");
    try builder.appendTransferObjectsFromNamedCliValues(&.{"ptb:name:coin_split:0"}, "0xreceiver");

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[0].integer);
}

test "ProgrammaticDslBuilder can import existing aliases for named references" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);
    try assignCommandResultAlias(allocator, &aliases, "coin_split", 2);

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();
    try builder.importAliases(&aliases);
    try builder.appendTransferObjectsFromNamedCliValues(&.{"ptb:name:coin_split:0"}, "0xreceiver");

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
    try testing.expectEqual(@as(i64, 2), parsed.value.array.items[0].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[0].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[1].integer);
}

test "ProgrammaticDslBuilder supports publish and upgrade with named ticket refs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendPublishFromCliValues("[\"AQID\"]", "[\"0x2\"]");
    try builder.appendSplitCoinsFromNamedCliValues("ptb:gas", &.{"7"});
    try builder.assignLastResultAlias("ticket");
    try builder.appendUpgradeFromNamedCliValues("[\"BAUG\"]", "[\"0x2\",\"0x3\"]", "0x42", "ptb:name:ticket");

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
    try testing.expectEqualStrings("Publish", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("Upgrade", parsed.value.array.items[2].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 1), parsed.value.array.items[2].object.get("ticket").?.object.get("Result").?.integer);
}

test "bootcamp C3 split and transfer scenario stays stable across typed and raw surfaces" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var typed_builder = ProgrammaticDslBuilder.init(allocator);
    defer typed_builder.deinit();

    const split_value = try typed_builder.appendSplitCoinsAndGetValueFromValueTokens("gas", &.{"u64:7"});
    try typed_builder.assignResultAlias("coin_split", split_value.result);
    _ = try typed_builder.appendTransferObjectsAndGetValueFromValueTokens(
        &.{"coin_split.0"},
        "@0xdef456",
    );

    var typed_owned = try typed_builder.finish();
    defer typed_owned.deinit(allocator);

    var raw_builder = ProgrammaticDslBuilder.init(allocator);
    defer raw_builder.deinit();

    _ = try raw_builder.appendRawJsonAndGetValues(
        "[{\"kind\":\"SplitCoins\",\"coin\":\"GasCoin\",\"amounts\":[7]},{\"kind\":\"TransferObjects\",\"objects\":[\"output:0:0\"],\"address\":\"@0xdef456\"}]",
    );

    var raw_owned = try raw_builder.finish();
    defer raw_owned.deinit(allocator);

    const typed_commands = typed_owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const raw_commands = raw_owned.options.source.commands_json orelse return error.TestExpectedEqual;

    const typed = try std.json.parseFromSlice(std.json.Value, allocator, typed_commands, .{});
    defer typed.deinit();
    const raw = try std.json.parseFromSlice(std.json.Value, allocator, raw_commands, .{});
    defer raw.deinit();

    try testing.expectEqual(@as(usize, 2), typed.value.array.items.len);
    try testing.expectEqual(@as(usize, 2), raw.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", typed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", raw.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 7), typed.value.array.items[0].object.get("amounts").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 7), raw.value.array.items[0].object.get("amounts").?.array.items[0].integer);

    const typed_object = typed.value.array.items[1].object.get("objects").?.array.items[0];
    const raw_object = raw.value.array.items[1].object.get("objects").?.array.items[0];
    try testing.expectEqualStrings("TransferObjects", typed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", raw.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("0xdef456", typed.value.array.items[1].object.get("address").?.string);
    try testing.expectEqualStrings("0xdef456", raw.value.array.items[1].object.get("address").?.string);
    try testing.expectEqual(@as(i64, 0), typed_object.object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), typed_object.object.get("NestedResult").?.array.items[1].integer);
    try testing.expectEqual(@as(i64, 0), raw_object.object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), raw_object.object.get("NestedResult").?.array.items[1].integer);
}

test "bootcamp C3 move-call alias shorthand feeds later move-call arguments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const created = try builder.appendMoveCallAndGetValueFromValueTokens(
        "0x2",
        "counter",
        "create",
        &.{},
        &.{"str:seed"},
    );
    try builder.assignResultAlias("created", created.result);

    _ = try builder.appendMoveCallAndGetHandleFromValueTokens(
        "0x2",
        "counter",
        "consume",
        &.{},
        &.{
            "created.0",
            "vector[@0xabc123, none, some(@0xdef456)]",
        },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    const args_json = parsed.value.array.items[1].object.get("arguments").?.array.items;
    try testing.expect(args_json[0] == .object);
    try testing.expectEqual(@as(i64, 0), args_json[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), args_json[0].object.get("NestedResult").?.array.items[1].integer);
    try testing.expect(args_json[1] == .array);
    try testing.expectEqualStrings("0xabc123", args_json[1].array.items[0].string);
    try testing.expect(args_json[1].array.items[1] == .null);
    try testing.expectEqualStrings("0xdef456", args_json[1].array.items[2].string);
}

test "bootcamp C3 make-move-vec supports mixed result references and shorthand tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const split_value = try builder.appendSplitCoinsAndGetValueFromValueTokens("gas", &.{"u64:7"});
    try builder.assignResultAlias("coin_split", split_value.result);

    _ = try builder.appendMakeMoveVecAndGetValueFromValueTokens(
        "0x2::sui::SUI",
        &.{
            "@0xabc123",
            "ptb:name:coin_split:0",
            "vector[@0xdef456, none]",
        },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expectEqualStrings("MakeMoveVec", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("0x2::sui::SUI", parsed.value.array.items[1].object.get("type").?.string);

    const elements = parsed.value.array.items[1].object.get("elements").?.array.items;
    try testing.expectEqual(@as(usize, 3), elements.len);
    try testing.expectEqualStrings("0xabc123", elements[0].string);
    try testing.expect(elements[1] == .object);
    try testing.expectEqual(@as(i64, 0), elements[1].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), elements[1].object.get("NestedResult").?.array.items[1].integer);
    try testing.expect(elements[2] == .array);
    try testing.expectEqualStrings("0xdef456", elements[2].array.items[0].string);
    try testing.expect(elements[2].array.items[1] == .null);
}

test "bootcamp H1 publish and upgrade flow can build execute payloads" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.appendPublishAndGetValueFromCliValues("[\"AQID\"]", "[\"0x2\"]");
    const ticket = try builder.appendSplitCoinsAndGetValueFromValueTokens("gas", &.{"u64:7"});
    try builder.assignResultAlias("upgrade_ticket", ticket.result);
    _ = try builder.appendUpgradeAndGetValueFromNamedCliValues(
        "[\"BAUG\"]",
        "[\"0x2\",\"0x3\"]",
        "0x42",
        "upgrade_ticket",
    );

    const payload = try builder.buildAuthorizedExecutePayload(allocator, .{
        .direct_signatures = .{
            .sender = "0xabc",
            .signatures = &.{"sig-a"},
        },
    });
    defer allocator.free(payload);

    try testing.expect(std.mem.indexOf(u8, payload, "Publish") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "Upgrade") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "sig-a") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "0xabc") != null);
}

test "ProgrammaticDslBuilder supports structured PTB specs without CLI tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendSplitCoinsFromSpecs(.gas_coin, &.{.{ .json = "7" }});
    try builder.appendTransferObjectsFromSpecs(
        &.{.{ .nested_result = .{ .command_index = 0, .result_index = 0 } }},
        .{ .json = "\"0xreceiver\"" },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[1].integer);
}

test "ProgrammaticDslBuilder exposes typed result handles for command chaining" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendSplitCoinsFromSpecs(.gas_coin, &.{.{ .json = "7" }});
    const split_coin = try builder.lastResultHandle();
    try testing.expectEqual(@as(u16, 0), split_coin.command_index);

    try builder.assignResultAlias("coin_split", split_coin);
    const aliased_split_coin = try builder.resultHandleForAlias("coin_split");
    try testing.expectEqual(@as(u16, 0), aliased_split_coin.command_index);

    try builder.appendTransferObjectsFromSpecs(
        &.{aliased_split_coin.output(0).asSpec()},
        .{ .json = "\"0xreceiver\"" },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[1].object.get("objects").?.array.items[0].object.get("NestedResult").?.array.items[1].integer);
}

test "ProgrammaticDslBuilder exposes typed result values for value-based chaining" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.appendSplitCoinsAndGetHandleFromValues(.gas_coin, &.{.{ .u64 = 7 }});

    const last_value = try builder.lastResultValue();
    try testing.expect(last_value == .result);
    try testing.expectEqual(@as(u16, 0), last_value.result.command_index);

    try builder.assignLastResultAlias("coin_split");
    const aliased_value = try builder.resultValueForAlias("coin_split");
    try testing.expect(aliased_value == .result);
    try testing.expectEqual(@as(u16, 0), aliased_value.result.command_index);

    _ = try builder.appendTransferObjectsAndGetHandleFromValues(
        &.{aliased_value.result.outputValue(0)},
        .{ .address = "0xreceiver" },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    const object_arg = parsed.value.array.items[1].object.get("objects").?.array.items[0];
    try testing.expect(object_arg == .object);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[1].integer);
}

test "ProgrammaticDslBuilder append helpers can return result values directly" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const split_value = try builder.appendSplitCoinsAndGetValueFromValues(.gas_coin, &.{.{ .u64 = 7 }});
    try testing.expect(split_value == .result);
    try testing.expectEqual(@as(u16, 0), split_value.result.command_index);

    const transfer_value = try builder.appendTransferObjectsAndGetValueFromValues(
        &.{split_value.result.outputValue(0)},
        .{ .address = "0xreceiver" },
    );
    try testing.expect(transfer_value == .result);
    try testing.expectEqual(@as(u16, 1), transfer_value.result.command_index);

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    const object_arg = parsed.value.array.items[1].object.get("objects").?.array.items[0];
    try testing.expect(object_arg == .object);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[1].integer);
}

test "ProgrammaticDslBuilder named and token helpers can return result values directly" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const split_value = try builder.appendSplitCoinsAndGetValueFromNamedCliValues("ptb:gas", &.{"7"});
    try testing.expect(split_value == .result);
    try builder.assignResultAlias("coin_split", split_value.result);

    const transfer_value = try builder.appendTransferObjectsAndGetValueFromValueTokens(
        &.{"coin_split.0"},
        "@0xdef456",
    );
    try testing.expect(transfer_value == .result);
    try testing.expectEqual(@as(u16, 1), transfer_value.result.command_index);

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    const object_arg = parsed.value.array.items[1].object.get("objects").?.array.items[0];
    try testing.expect(object_arg == .object);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[1].integer);
}

test "ProgrammaticDslBuilder append helpers can return result handles directly" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const split_handle = try builder.appendSplitCoinsAndGetHandleFromSpecs(.gas_coin, &.{.{ .json = "7" }});
    try testing.expectEqual(@as(u16, 0), split_handle.command_index);

    const transfer_handle = try builder.appendTransferObjectsAndGetHandleFromSpecs(
        &.{split_handle.output(0).asSpec()},
        .{ .json = "\"0xreceiver\"" },
    );
    try testing.expectEqual(@as(u16, 1), transfer_handle.command_index);

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expectEqualStrings("SplitCoins", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[1].object.get("kind").?.string);
}

test "ProgrammaticDslBuilder appendRawJsonAndGetHandles returns typed handles for raw batches" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    var handles = try builder.appendRawJsonAndGetHandles(
        "[{\"kind\":\"SplitCoins\",\"coin\":\"GasCoin\",\"amounts\":[7]},{\"kind\":\"SplitCoins\",\"coin\":\"GasCoin\",\"amounts\":[8]}]",
    );
    defer handles.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), handles.items.items.len);
    try testing.expectEqual(@as(u16, 0), handles.items.items[0].command_index);
    try testing.expectEqual(@as(u16, 1), handles.items.items[1].command_index);

    _ = try builder.appendTransferObjectsAndGetHandleFromSpecs(
        &.{handles.items.items[1].output(0).asSpec()},
        .{ .json = "\"0xreceiver\"" },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[2].object.get("kind").?.string);
}

test "ProgrammaticDslBuilder appendRawJsonAndGetValues returns typed values for raw batches" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    var values = try builder.appendRawJsonAndGetValues(
        "[{\"kind\":\"SplitCoins\",\"coin\":\"GasCoin\",\"amounts\":[7]},{\"kind\":\"SplitCoins\",\"coin\":\"GasCoin\",\"amounts\":[8]}]",
    );
    defer values.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), values.items.items.len);
    try testing.expect(values.items.items[0] == .result);
    try testing.expect(values.items.items[1] == .result);
    try testing.expectEqual(@as(u16, 0), values.items.items[0].result.command_index);
    try testing.expectEqual(@as(u16, 1), values.items.items[1].result.command_index);
}

test "parseArgumentValueToken parses typed prefixes and named PTB references" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);
    try assignCommandResultAlias(allocator, &aliases, "coin_split", 3);

    var address = try parseArgumentValueToken(allocator, &aliases, "addr:0x1234");
    defer address.deinit(allocator);
    try testing.expect(address.value == .address);
    try testing.expectEqualStrings("0x1234", address.value.address);

    var at_address = try parseArgumentValueToken(allocator, &aliases, "@0x5678");
    defer at_address.deinit(allocator);
    try testing.expect(at_address.value == .address);
    try testing.expectEqualStrings("0x5678", at_address.value.address);

    var nested = try parseArgumentValueToken(allocator, &aliases, "ptb:name:coin_split:0");
    defer nested.deinit(allocator);
    try testing.expect(nested.value == .output);
    try testing.expectEqual(@as(u16, 3), nested.value.output.command_index);
    try testing.expectEqual(@as(u16, 0), nested.value.output.result_index);

    var shorthand_result = try parseArgumentValueToken(allocator, &aliases, "coin_split");
    defer shorthand_result.deinit(allocator);
    try testing.expect(shorthand_result.value == .result);
    try testing.expectEqual(@as(u16, 3), shorthand_result.value.result.command_index);

    var shorthand_output = try parseArgumentValueToken(allocator, &aliases, "coin_split.0");
    defer shorthand_output.deinit(allocator);
    try testing.expect(shorthand_output.value == .output);
    try testing.expectEqual(@as(u16, 3), shorthand_output.value.output.command_index);
    try testing.expectEqual(@as(u16, 0), shorthand_output.value.output.result_index);

    var bigint = try parseArgumentValueToken(allocator, &aliases, "u128:18446744073709551616");
    defer bigint.deinit(allocator);
    try testing.expect(bigint.value == .u128);
    try testing.expectEqual(@as(u128, 18446744073709551616), bigint.value.u128);

    var raw_json = try parseArgumentValueToken(allocator, &aliases, "{\"k\":1}");
    defer raw_json.deinit(allocator);
    try testing.expect(raw_json.value == .raw_json);
    try testing.expectEqualStrings("{\"k\":1}", raw_json.value.raw_json);

    var normalized_object = try parseArgumentValueToken(allocator, &aliases, "{\"owner\":\"obj:0xdef456\"}");
    defer normalized_object.deinit(allocator);
    try testing.expect(normalized_object.value == .raw_json);
    try testing.expectEqualStrings("{\"owner\":\"0xdef456\"}", normalized_object.value.raw_json);

    var normalized_string = try parseArgumentValueToken(allocator, &aliases, "\"ptb:name:coin_split:0\"");
    defer normalized_string.deinit(allocator);
    try testing.expect(normalized_string.value == .raw_json);
    try testing.expectEqualStrings("{\"NestedResult\":[3,0]}", normalized_string.value.raw_json);

    var normalized_shorthand = try parseArgumentValueToken(allocator, &aliases, "\"coin_split.0\"");
    defer normalized_shorthand.deinit(allocator);
    try testing.expect(normalized_shorthand.value == .raw_json);
    try testing.expectEqualStrings("{\"NestedResult\":[3,0]}", normalized_shorthand.value.raw_json);

    var vector_json = try parseArgumentValueToken(allocator, &aliases, "vec:[1,\"addr:0xabc123\",\"ptb:name:coin_split:0\"]");
    defer vector_json.deinit(allocator);
    try testing.expect(vector_json.value == .raw_json);
    try testing.expectEqualStrings("[1,\"0xabc123\",{\"NestedResult\":[3,0]}]", vector_json.value.raw_json);

    var some_json = try parseArgumentValueToken(allocator, &aliases, "option:some:\"addr:0xdef456\"");
    defer some_json.deinit(allocator);
    try testing.expect(some_json.value == .raw_json);
    try testing.expectEqualStrings("\"0xdef456\"", some_json.value.raw_json);

    var some_paren = try parseArgumentValueToken(allocator, &aliases, "some(@0xdef456)");
    defer some_paren.deinit(allocator);
    try testing.expect(some_paren.value == .raw_json);
    try testing.expectEqualStrings("\"0xdef456\"", some_paren.value.raw_json);

    var vector_token = try parseArgumentValueToken(allocator, &aliases, "vector[@0xabc123, none, ptb:name:coin_split:0]");
    defer vector_token.deinit(allocator);
    try testing.expect(vector_token.value == .raw_json);
    try testing.expectEqualStrings("[\"0xabc123\",null,{\"NestedResult\":[3,0]}]", vector_token.value.raw_json);

    var none = try parseArgumentValueToken(allocator, &aliases, "option:none");
    defer none.deinit(allocator);
    try testing.expect(none.value == .null);

    var fallback = try parseArgumentValueToken(allocator, &aliases, "counter-id");
    defer fallback.deinit(allocator);
    try testing.expect(fallback.value == .string);
    try testing.expectEqualStrings("counter-id", fallback.value.string);
}

test "parseArgumentValueToken rejects malformed shorthand tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);

    try testing.expectError(error.InvalidCli, parseArgumentValueToken(allocator, &aliases, "@xyz"));
    try testing.expectError(error.InvalidCli, parseArgumentValueToken(allocator, &aliases, "bytes:0xabc"));
    try testing.expectError(error.InvalidCli, parseArgumentValueToken(allocator, &aliases, "vector[@xyz, none]"));
    try testing.expectError(error.InvalidCli, parseArgumentValueToken(allocator, &aliases, "some(bytes:0xabc)"));
}

test "ProgrammaticDslBuilder named CLI append helpers can return result handles directly" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const split_handle = try builder.appendSplitCoinsAndGetHandleFromNamedCliValues("ptb:gas", &.{"7"});
    try builder.assignResultAlias("coin_split", split_handle);

    const transfer_handle = try builder.appendTransferObjectsAndGetHandleFromNamedCliValues(
        &.{"ptb:name:coin_split:0"},
        "0xreceiver",
    );
    try testing.expectEqual(@as(u16, 1), transfer_handle.command_index);

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[1].object.get("kind").?.string);
}

test "ProgrammaticDslBuilder supports value-token append helpers" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const split_handle = try builder.appendSplitCoinsAndGetHandleFromValueTokens("gas", &.{"u64:7"});
    try builder.assignResultAlias("coin_split", split_handle);

    _ = try builder.appendMoveCallAndGetHandleFromValueTokens(
        "0x2",
        "counter",
        "set_value",
        &.{},
        &.{
            "obj:0xabc123",
            "addr:0x1234",
            "bool:true",
            "u8:7",
            "counter-id",
            "{\"k\":1}",
            "ptb:name:coin_split:0",
        },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    const args_json = parsed.value.array.items[1].object.get("arguments").?.array.items;
    try testing.expectEqualStrings("0xabc123", args_json[0].string);
    try testing.expectEqualStrings("0x1234", args_json[1].string);
    try testing.expectEqual(true, args_json[2].bool);
    try testing.expectEqual(@as(i64, 7), args_json[3].integer);
    try testing.expectEqualStrings("counter-id", args_json[4].string);
    try testing.expect(args_json[5] == .object);
    try testing.expect(args_json[6] == .object);
    try testing.expectEqual(@as(i64, 0), args_json[6].object.get("NestedResult").?.array.items[0].integer);
}

test "ProgrammaticDslBuilder supports typed argument values for DSL construction" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const split_handle = try builder.appendSplitCoinsAndGetHandleFromValues(.gas_coin, &.{.{ .u64 = 7 }});
    const move_call_handle = try builder.appendMoveCallAndGetHandleFromValues(
        "0x2",
        "counter",
        "set_value",
        &.{},
        &.{
            .{ .string = "counter-id" },
            .{ .boolean = true },
            .{ .u64 = 42 },
            .{ .output = split_handle.output(0) },
        },
    );
    try testing.expectEqual(@as(u16, 1), move_call_handle.command_index);

    _ = try builder.appendTransferObjectsAndGetHandleFromValues(
        &.{.{ .output = split_handle.output(0) }},
        .{ .string = "0xreceiver" },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("counter-id", parsed.value.array.items[1].object.get("arguments").?.array.items[0].string);
    try testing.expectEqual(true, parsed.value.array.items[1].object.get("arguments").?.array.items[1].bool);
    try testing.expectEqual(@as(i64, 42), parsed.value.array.items[1].object.get("arguments").?.array.items[2].integer);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[2].object.get("kind").?.string);
    try testing.expectEqualStrings("0xreceiver", parsed.value.array.items[2].object.get("address").?.string);
}

test "ProgrammaticDslBuilder supports vector and option argument containers" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    const split_handle = try builder.appendSplitCoinsAndGetHandleFromValues(.gas_coin, &.{.{ .u64 = 7 }});
    const some_value = ArgumentValue{ .string = "enabled" };
    const vector_items = [_]ArgumentValue{
        .{ .string = "tag" },
        .{ .u64 = 9 },
        .{ .output = split_handle.output(0) },
    };

    _ = try builder.appendMoveCallAndGetHandleFromValues(
        "0x2",
        "counter",
        "set_values",
        &.{},
        &.{
            .{ .vector = .{ .items = &vector_items } },
            .{ .option = .none },
            .{ .option = .{ .some = &some_value } },
        },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    const args_json = parsed.value.array.items[1].object.get("arguments").?.array.items;
    try testing.expect(args_json[0] == .array);
    try testing.expectEqualStrings("tag", args_json[0].array.items[0].string);
    try testing.expectEqual(@as(i64, 9), args_json[0].array.items[1].integer);
    try testing.expect(args_json[0].array.items[2] == .object);
    try testing.expectEqual(@as(i64, 0), args_json[0].array.items[2].object.get("NestedResult").?.array.items[0].integer);
    try testing.expect(args_json[1] == .null);
    try testing.expectEqualStrings("enabled", args_json[2].string);
}

test "ProgrammaticDslBuilder supports explicit address and object-id values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.appendMoveCallAndGetHandleFromValues(
        "0x2",
        "counter",
        "set_owner",
        &.{},
        &.{
            .{ .object_id = "0xabc123" },
            .{ .address = "0xdef456" },
        },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    const args_json = parsed.value.array.items[0].object.get("arguments").?.array.items;
    try testing.expectEqualStrings("0xabc123", args_json[0].string);
    try testing.expectEqualStrings("0xdef456", args_json[1].string);
}

test "ProgrammaticDslBuilder rejects invalid explicit address and object-id values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    try testing.expectError(error.InvalidCli, builder.appendMoveCallFromValues(
        "0x2",
        "counter",
        "set_owner",
        &.{},
        &.{
            .{ .object_id = "abc123" },
            .{ .address = "receiver" },
        },
    ));
}

test "ProgrammaticDslBuilder supports explicit bytes and narrow integer values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.appendMoveCallAndGetHandleFromValues(
        "0x2",
        "counter",
        "set_bytes",
        &.{},
        &.{
            .{ .bytes = "0x0a0b0c" },
            .{ .u8 = 7 },
            .{ .u16 = 512 },
            .{ .u32 = 70000 },
        },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    const args_json = parsed.value.array.items[0].object.get("arguments").?.array.items;
    try testing.expectEqualStrings("0x0a0b0c", args_json[0].string);
    try testing.expectEqual(@as(i64, 7), args_json[1].integer);
    try testing.expectEqual(@as(i64, 512), args_json[2].integer);
    try testing.expectEqual(@as(i64, 70000), args_json[3].integer);
}

test "ProgrammaticDslBuilder rejects invalid explicit bytes values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    try testing.expectError(error.InvalidCli, builder.appendMoveCallFromValues(
        "0x2",
        "counter",
        "set_bytes",
        &.{},
        &.{
            .{ .bytes = "0xabc" },
        },
    ));
}

test "ProgrammaticDslBuilder supports explicit u128 and u256 values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.appendMoveCallAndGetHandleFromValues(
        "0x2",
        "counter",
        "set_bigints",
        &.{},
        &.{
            .{ .u128 = 18446744073709551616 },
            .{ .u256 = 340282366920938463463374607431768211456 },
        },
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    try testing.expect(std.mem.indexOf(u8, commands_json, "\"arguments\":[18446744073709551616,340282366920938463463374607431768211456]") != null);
}

test "normalizeCommandItemsFromRawJson splits normalized command entries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var normalized = try normalizeCommandItemsFromRawJson(
        allocator,
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"},{\"kind\":\"MergeCoins\",\"destination\":\"0xcoin\",\"sources\":[\"0xcoin2\"]}]",
    );
    defer normalized.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), normalized.items.items.len);

    const first = try std.json.parseFromSlice(std.json.Value, allocator, normalized.items.items[0], .{});
    defer first.deinit();
    const second = try std.json.parseFromSlice(std.json.Value, allocator, normalized.items.items[1], .{});
    defer second.deinit();

    try testing.expectEqualStrings("TransferObjects", first.value.object.get("kind").?.string);
    try testing.expectEqualStrings("MergeCoins", second.value.object.get("kind").?.string);
}

test "normalizeCommandItemsFromRawJson resolves typed tokens inside raw command json" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var normalized = try normalizeCommandItemsFromRawJson(
        allocator,
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"set_values\",\"arguments\":[\"vector[@0xabc123, none]\",\"some(@0xdef456)\",\"u64:7\"]},{\"kind\":\"TransferObjects\",\"objects\":[\"@0xaaa111\"],\"address\":\"@0xdef456\"}]",
    );
    defer normalized.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), normalized.items.items.len);

    const move_call = try std.json.parseFromSlice(std.json.Value, allocator, normalized.items.items[0], .{});
    defer move_call.deinit();
    const transfer = try std.json.parseFromSlice(std.json.Value, allocator, normalized.items.items[1], .{});
    defer transfer.deinit();

    const args_json = move_call.value.object.get("arguments").?.array.items;
    try testing.expect(args_json[0] == .array);
    try testing.expectEqualStrings("0xabc123", args_json[0].array.items[0].string);
    try testing.expect(args_json[0].array.items[1] == .null);
    try testing.expectEqualStrings("0xdef456", args_json[1].string);
    try testing.expectEqual(@as(i64, 7), args_json[2].integer);

    try testing.expectEqualStrings("0xaaa111", transfer.value.object.get("objects").?.array.items[0].string);
    try testing.expectEqualStrings("0xdef456", transfer.value.object.get("address").?.string);
}

test "normalizeCommandItemsFromRawJson resolves package aliases inside raw command json" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var normalized = try normalizeCommandItemsFromRawJson(
        allocator,
        "[{\"kind\":\"MoveCall\",\"package\":\"cetus_clmm_mainnet\",\"module\":\"pool\",\"function\":\"swap\",\"arguments\":[]},{\"kind\":\"Upgrade\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"],\"package\":\"pkg:cetus.mainnet.clmm\",\"ticket\":{\"Result\":0}}]",
    );
    defer normalized.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), normalized.items.items.len);

    const move_call = try std.json.parseFromSlice(std.json.Value, allocator, normalized.items.items[0], .{});
    defer move_call.deinit();
    const upgrade = try std.json.parseFromSlice(std.json.Value, allocator, normalized.items.items[1], .{});
    defer upgrade.deinit();

    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, move_call.value.object.get("package").?.string);
    try testing.expectEqualStrings(package_preset.cetus_clmm_mainnet, upgrade.value.object.get("package").?.string);
}

test "normalizeCommandItemsFromRawJson rejects malformed known command fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, normalizeCommandItemsFromRawJson(
        allocator,
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"set_value\",\"typeArguments\":[],\"arguments\":\"bad\"}]",
    ));

    try testing.expectError(error.InvalidCli, normalizeCommandItemsFromRawJson(
        allocator,
        "[{\"kind\":\"MakeMoveVec\",\"type\":\"0x2::sui::SUI\",\"elements\":\"bad\"}]",
    ));

    try testing.expectError(error.InvalidCli, normalizeCommandItemsFromRawJson(
        allocator,
        "[{\"kind\":\"Upgrade\",\"modules\":[\"AQID\"],\"dependencies\":[\"0x2\"],\"package\":\"0x42\",\"ticket\":\"@xyz\"}]",
    ));
}

test "normalizeCommandItemsFromRawJsonWithAliases resolves named result references inside raw command json" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var aliases = CommandResultAliases{};
    defer deinitCommandResultAliases(allocator, &aliases);
    try assignCommandResultAlias(allocator, &aliases, "coin_split", 2);

    var normalized = try normalizeCommandItemsFromRawJsonWithAliases(
        allocator,
        &aliases,
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"coin_split.0\"],\"address\":\"@0xdef456\"}]",
    );
    defer normalized.deinit(allocator);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, normalized.items.items[0], .{});
    defer parsed.deinit();

    const object_arg = parsed.value.object.get("objects").?.array.items[0];
    try testing.expect(object_arg == .object);
    try testing.expectEqual(@as(i64, 2), object_arg.object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[1].integer);
    try testing.expectEqualStrings("0xdef456", parsed.value.object.get("address").?.string);
}

test "ProgrammaticDslBuilder offsets raw command shorthand references by existing command count" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticDslBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.appendSplitCoinsAndGetHandleFromValueTokens("gas", &.{"u64:7"});
    _ = try builder.appendRawJsonAndGetHandles(
        "[{\"kind\":\"TransferObjects\",\"objects\":[\"output:0:0\"],\"address\":\"@0xdef456\"}]",
    );

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const commands_json = owned.options.source.commands_json orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed.deinit();

    const object_arg = parsed.value.array.items[1].object.get("objects").?.array.items[0];
    try testing.expect(object_arg == .object);
    try testing.expectEqual(@as(i64, 1), object_arg.object.get("NestedResult").?.array.items[0].integer);
    try testing.expectEqual(@as(i64, 0), object_arg.object.get("NestedResult").?.array.items[1].integer);
}

test "optionsFromRequest maps programmatic request fields" {
    const testing = std.testing;

    const options = optionsFromRequest(.{
        .source = .{
            .commands_json = "[{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}]",
        },
        .sender = "0xabc",
        .gas_budget = 900,
        .gas_price = 8,
        .gas_payment_json = "[{\"objectId\":\"0xgas\",\"version\":\"8\",\"digest\":\"digest-gas\"}]",
        .signatures = &.{"sig-a"},
        .options_json = "{\"showEffects\":true}",
        .wait_for_confirmation = true,
        .confirm_timeout_ms = 6_000,
        .confirm_poll_ms = 30,
    });

    try testing.expect(options.source.commands_json != null);
    try testing.expectEqualStrings("0xabc", options.sender.?);
    try testing.expectEqual(@as(u64, 900), options.gas_budget.?);
    try testing.expectEqual(@as(u64, 8), options.gas_price.?);
    try testing.expectEqualStrings("[{\"objectId\":\"0xgas\",\"version\":\"8\",\"digest\":\"digest-gas\"}]", options.gas_payment_json.?);
    try testing.expectEqualStrings("sig-a", options.signatures[0]);
    try testing.expectEqualStrings("{\"showEffects\":true}", options.options_json.?);
    try testing.expect(options.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 6_000), options.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 30), options.confirm_poll_ms);
}

test "prepareRequest normalizes command items into a prepared request" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareRequest(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
            },
        },
        .sender = "0xabc",
        .gas_budget = 900,
        .signatures = &.{"sig-a"},
    });
    defer prepared.deinit(allocator);

    try testing.expect(prepared.request.source.commands_json != null);
    try testing.expectEqualStrings("0xabc", prepared.request.sender.?);
    try testing.expectEqualStrings("sig-a", prepared.request.signatures[0]);
}

test "buildExecutePayload builds payloads from generic request options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildExecutePayload(allocator, .{
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
        .gas_payment_json = "[{\"objectId\":\"0xgas\",\"version\":\"9\",\"digest\":\"digest-gas\"}]",
        .signatures = &.{"sig-a"},
    });
    defer allocator.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);

    const tx_block = parsed.value.array.items[0];
    try testing.expect(tx_block == .string);
    const parsed_tx_block = try std.json.parseFromSlice(std.json.Value, allocator, tx_block.string, .{});
    defer parsed_tx_block.deinit();
    try testing.expectEqualStrings("0xgas", parsed_tx_block.value.object.get("gasPayment").?.array.items[0].object.get("objectId").?.string);

}

test "ownOptions preserves explicit gas payment fields in normalized request options" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var owned = try ownOptions(allocator, .{
        .source = .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .arguments = "[\"0xabc\"]",
            },
        },
        .sender = "0xabc",
        .gas_payment_json = "[{\"objectId\":\"0xgas-owned\",\"version\":\"10\",\"digest\":\"digest-gas\"}]",
        .signatures = &.{"sig-a"},
    });
    defer owned.deinit(allocator);

    try testing.expect(owned.options.gas_payment_json != null);
    try testing.expectEqualStrings("[{\"objectId\":\"0xgas-owned\",\"version\":\"10\",\"digest\":\"digest-gas\"}]", owned.options.gas_payment_json.?);
}

test "prepareResolvedRequestFromContents resolves signer-backed sender and normalized commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareResolvedRequestFromContents(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
            .gas_budget = 900,
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .signer_selectors = &.{"builder"} },
    );
    defer prepared.deinit(allocator);

    try testing.expect(prepared.request.source.commands_json != null);
    try testing.expectEqualStrings("0xbuilder", prepared.request.sender.?);
    try testing.expectEqual(@as(usize, 1), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[0]);
}

test "OwnedProgrammaticRequestOptions builds execute payloads" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ProgrammaticRequestOptionsBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendMoveCall(.{
        .package_id = "0x2",
        .module = "counter",
        .function_name = "increment",
        .type_args = "[]",
        .arguments = "[\"0xabc\"]",
    });
    builder.setSender("0xabc");
    builder.setSignatures(&.{"sig-a"});

    var owned = try builder.finish();
    defer owned.deinit(allocator);

    const payload = try owned.buildExecutePayload(allocator);
    defer allocator.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
}
