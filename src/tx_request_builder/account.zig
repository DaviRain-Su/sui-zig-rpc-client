/// tx_request_builder/account.zig - Account providers for signing
const std = @import("std");

/// Account provider union for different signing methods
pub const AccountProvider = union(enum) {
    /// Direct signature with private key
    direct: DirectSignatureAccount,
    /// Keystore contents account
    keystore_contents: KeystoreContentsAccount,
    /// Default keystore account
    default_keystore: DefaultKeystoreAccount,
    /// Remote signer with callback
    remote_signer: RemoteSignerAccount,
    /// Future wallet (session-based)
    future_wallet: FutureWalletAccount,

    pub fn deinit(self: *AccountProvider, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .direct => |*d| d.deinit(allocator),
            .keystore_contents => |*k| k.deinit(allocator),
            .default_keystore => |*d| d.deinit(allocator),
            .remote_signer => |*r| r.deinit(allocator),
            .future_wallet => |*f| f.deinit(allocator),
        }
    }
};

/// Direct signature account with private key
pub const DirectSignatureAccount = struct {
    /// Private key bytes
    private_key: []const u8,
    /// Public key/address
    address: []const u8,
    /// Key scheme (ed25519, secp256k1, etc.)
    key_scheme: []const u8,

    pub fn deinit(self: *DirectSignatureAccount, allocator: std.mem.Allocator) void {
        allocator.free(self.private_key);
        allocator.free(self.address);
        allocator.free(self.key_scheme);
    }
};

/// Keystore contents account
pub const KeystoreContentsAccount = struct {
    /// Keystore JSON contents
    contents: []const u8,
    /// Address to use from keystore
    address: []const u8,

    pub fn deinit(self: *KeystoreContentsAccount, allocator: std.mem.Allocator) void {
        allocator.free(self.contents);
        allocator.free(self.address);
    }
};

/// Default keystore account
pub const DefaultKeystoreAccount = struct {
    /// Address to use (optional, uses active address if null)
    address: ?[]const u8 = null,
    /// Keystore path override
    keystore_path: ?[]const u8 = null,

    pub fn deinit(self: *DefaultKeystoreAccount, allocator: std.mem.Allocator) void {
        if (self.address) |a| allocator.free(a);
        if (self.keystore_path) |p| allocator.free(p);
    }
};

/// Remote signer account with callback
pub const RemoteSignerAccount = struct {
    /// Remote signer URL or identifier
    signer_id: []const u8,
    /// Authorization callback
    authorize_callback: ?*const fn ([]const u8) anyerror![]const u8 = null,
    /// Expected address
    expected_address: ?[]const u8 = null,

    pub fn deinit(self: *RemoteSignerAccount, allocator: std.mem.Allocator) void {
        allocator.free(self.signer_id);
        if (self.expected_address) |a| allocator.free(a);
    }
};

/// Future wallet account for session-based signing
pub const FutureWalletAccount = struct {
    /// Wallet identifier
    id: []const u8,
    /// Wallet type (passkey, zklogin, etc.)
    wallet_type: []const u8,
    /// Expected address
    expected_address: ?[]const u8 = null,
    /// Session challenge
    session_challenge: ?[]const u8 = null,

    pub fn deinit(self: *FutureWalletAccount, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.wallet_type);
        if (self.expected_address) |a| allocator.free(a);
        if (self.session_challenge) |c| allocator.free(c);
    }
};

/// Check if account provider can execute transactions
pub fn accountProviderCanExecute(provider: AccountProvider) bool {
    return switch (provider) {
        .direct => true,
        .keystore_contents => true,
        .default_keystore => true,
        .remote_signer => |r| r.authorize_callback != null,
        .future_wallet => |f| f.session_challenge != null,
    };
}

/// Remote authorization request
pub const RemoteAuthorizationRequest = struct {
    /// Transaction bytes to sign
    tx_bytes: []const u8,
    /// Sender address
    sender: []const u8,
    /// Intent message
    intent: ?[]const u8 = null,

    pub fn deinit(self: *RemoteAuthorizationRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.tx_bytes);
        allocator.free(self.sender);
        if (self.intent) |i| allocator.free(i);
    }
};

/// Remote authorization result
pub const RemoteAuthorizationResult = struct {
    /// Signature bytes
    signature: []const u8,
    /// Public key
    public_key: []const u8,

    pub fn deinit(self: *RemoteAuthorizationResult, allocator: std.mem.Allocator) void {
        allocator.free(self.signature);
        allocator.free(self.public_key);
    }
};

/// Remote authorizer callback type
pub const RemoteAuthorizer = struct {
    context: *anyopaque,
    callback: *const fn (*anyopaque, RemoteAuthorizationRequest) anyerror!RemoteAuthorizationResult,
};

// ============================================================
// Tests
// ============================================================

test "DirectSignatureAccount lifecycle" {
    const testing = std.testing;

    var account = DirectSignatureAccount{
        .private_key = try testing.allocator.dupe(u8, "secret_key"),
        .address = try testing.allocator.dupe(u8, "0x123"),
        .key_scheme = try testing.allocator.dupe(u8, "ed25519"),
    };
    defer account.deinit(testing.allocator);

    try testing.expectEqualStrings("secret_key", account.private_key);
    try testing.expectEqualStrings("0x123", account.address);
}

test "KeystoreContentsAccount lifecycle" {
    const testing = std.testing;

    var account = KeystoreContentsAccount{
        .contents = try testing.allocator.dupe(u8, "[]"),
        .address = try testing.allocator.dupe(u8, "0x456"),
    };
    defer account.deinit(testing.allocator);

    try testing.expectEqualStrings("[]", account.contents);
}

test "DefaultKeystoreAccount lifecycle" {
    const testing = std.testing;

    var account = DefaultKeystoreAccount{
        .address = try testing.allocator.dupe(u8, "0x789"),
        .keystore_path = try testing.allocator.dupe(u8, "/path/to/keystore"),
    };
    defer account.deinit(testing.allocator);

    try testing.expectEqualStrings("0x789", account.address.?);
}

test "RemoteSignerAccount lifecycle" {
    const testing = std.testing;

    var account = RemoteSignerAccount{
        .signer_id = try testing.allocator.dupe(u8, "signer_1"),
        .expected_address = try testing.allocator.dupe(u8, "0xabc"),
    };
    defer account.deinit(testing.allocator);

    try testing.expectEqualStrings("signer_1", account.signer_id);
}

test "FutureWalletAccount lifecycle" {
    const testing = std.testing;

    var account = FutureWalletAccount{
        .id = try testing.allocator.dupe(u8, "wallet_1"),
        .wallet_type = try testing.allocator.dupe(u8, "passkey"),
        .session_challenge = try testing.allocator.dupe(u8, "challenge_123"),
    };
    defer account.deinit(testing.allocator);

    try testing.expectEqualStrings("wallet_1", account.id);
    try testing.expectEqualStrings("passkey", account.wallet_type);
}

test "AccountProvider lifecycle" {
    const testing = std.testing;

    var provider = AccountProvider{
        .direct = .{
            .private_key = try testing.allocator.dupe(u8, "key"),
            .address = try testing.allocator.dupe(u8, "0x123"),
            .key_scheme = try testing.allocator.dupe(u8, "ed25519"),
        },
    };
    defer provider.deinit(testing.allocator);

    try testing.expectEqualStrings("key", provider.direct.private_key);
}

test "accountProviderCanExecute" {
    const testing = std.testing;

    const direct = AccountProvider{
        .direct = .{
            .private_key = "key",
            .address = "0x123",
            .key_scheme = "ed25519",
        },
    };
    try testing.expect(accountProviderCanExecute(direct));

    const remote_no_callback = AccountProvider{
        .remote_signer = .{
            .signer_id = "signer",
            .authorize_callback = null,
        },
    };
    try testing.expect(!accountProviderCanExecute(remote_no_callback));
}

test "RemoteAuthorizationRequest lifecycle" {
    const testing = std.testing;

    var request = RemoteAuthorizationRequest{
        .tx_bytes = try testing.allocator.dupe(u8, "0xabc"),
        .sender = try testing.allocator.dupe(u8, "0x123"),
        .intent = try testing.allocator.dupe(u8, "transfer"),
    };
    defer request.deinit(testing.allocator);

    try testing.expectEqualStrings("0xabc", request.tx_bytes);
    try testing.expectEqualStrings("transfer", request.intent.?);
}

test "RemoteAuthorizationResult lifecycle" {
    const testing = std.testing;

    var result = RemoteAuthorizationResult{
        .signature = try testing.allocator.dupe(u8, "sig"),
        .public_key = try testing.allocator.dupe(u8, "pk"),
    };
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("sig", result.signature);
}
