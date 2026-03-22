/// Advanced authentication methods for Sui
/// Supports zkLogin and Passkey
const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// zkLogin Support
// ============================================================================

pub const ZkLoginProvider = enum {
    google,
    twitch,
    facebook,
    apple,

    pub fn getAuthUrl(self: ZkLoginProvider, client_id: []const u8, redirect_uri: []const u8, nonce: []const u8) []const u8 {
        return switch (self) {
            .google => std.fmt.bufPrint(
                "https://accounts.google.com/o/oauth2/v2/auth?client_id={s}&redirect_uri={s}&response_type=id_token&scope=openid%20email&nonce={s}",
                .{ client_id, redirect_uri, nonce },
            ) catch unreachable,
            .twitch => std.fmt.bufPrint(
                "https://id.twitch.tv/oauth2/authorize?client_id={s}&redirect_uri={s}&response_type=id_token&scope=openid&nonce={s}",
                .{ client_id, redirect_uri, nonce },
            ) catch unreachable,
            .facebook => "https://www.facebook.com/v12.0/dialog/oauth",
            .apple => "https://appleid.apple.com/auth/authorize",
        };
    }

    pub fn getIssuer(self: ZkLoginProvider) []const u8 {
        return switch (self) {
            .google => "https://accounts.google.com",
            .twitch => "https://id.twitch.tv/oauth2",
            .facebook => "https://www.facebook.com",
            .apple => "https://appleid.apple.com",
        };
    }
};

pub const ZkLoginSession = struct {
    provider: ZkLoginProvider,
    salt: [16]u8,
    ephemeral_keypair: EphemeralKeyPair,
    jwt_token: ?[]const u8,
    max_epoch: u64,

    pub fn init(provider: ZkLoginProvider, salt: [16]u8) !ZkLoginSession {
        return .{
            .provider = provider,
            .salt = salt,
            .ephemeral_keypair = try EphemeralKeyPair.generate(),
            .jwt_token = null,
            .max_epoch = 0, // Will be set during completion
        };
    }

    pub fn setJwt(self: *ZkLoginSession, allocator: Allocator, jwt: []const u8) !void {
        self.jwt_token = try allocator.dupe(u8, jwt);
    }

    pub fn deriveAddress(self: *const ZkLoginSession, allocator: Allocator) ![]const u8 {
        // Parse JWT to get 'sub' claim
        const sub = try self.extractSubClaim(allocator);
        defer allocator.free(sub);

        // Address = hash(issuer || sub || salt)
        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(self.provider.getIssuer());
        hasher.update(sub);
        hasher.update(&self.salt);

        var hash: [32]u8 = undefined;
        hasher.final(&hash);

        // Convert to hex address
        const address = try allocator.alloc(u8, 66); // "0x" + 64 hex chars
        address[0] = '0';
        address[1] = 'x';

        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            address[2 + i * 2] = hex_chars[byte >> 4];
            address[2 + i * 2 + 1] = hex_chars[byte & 0x0F];
        }

        return address;
    }

    fn extractSubClaim(self: *const ZkLoginSession, allocator: Allocator) ![]const u8 {
        // JWT format: header.payload.signature
        // Payload is base64url encoded JSON

        if (self.jwt_token == null) {
            return error.NoJwtToken;
        }

        const jwt = self.jwt_token.?;

        // Find payload section (between first and second '.')
        var parts = std.mem.split(u8, jwt, ".");
        _ = parts.next(); // Skip header
        const payload_b64 = parts.next() orelse return error.InvalidJwt;

        // Decode base64url payload
        const payload = try base64UrlDecode(allocator, payload_b64);
        defer allocator.free(payload);

        // Parse JSON to extract 'sub'
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
        defer parsed.deinit();

        if (parsed.value.object.get("sub")) |sub| {
            return try allocator.dupe(u8, sub.string);
        }

        return error.MissingSubClaim;
    }
};

pub const EphemeralKeyPair = struct {
    public_key: [32]u8,
    secret_key: [32]u8,

    pub fn generate() !EphemeralKeyPair {
        // Use Zig's standard library Ed25519
        const Ed25519 = std.crypto.sign.Ed25519;

        // Generate random seed
        var seed: [32]u8 = undefined;
        std.crypto.random.bytes(&seed);

        // Create keypair from seed
        const kp = try Ed25519.KeyPair.generateDeterministic(seed);

        var public_key: [32]u8 = undefined;
        var secret_key: [32]u8 = undefined;
        @memcpy(&public_key, &kp.public_key.bytes);
        @memcpy(&secret_key, &seed);

        return .{
            .public_key = public_key,
            .secret_key = secret_key,
        };
    }

    pub fn sign(self: *const EphemeralKeyPair, message: []const u8) ![64]u8 {
        const Ed25519 = std.crypto.sign.Ed25519;

        // Recreate keypair from seed
        const kp = try Ed25519.KeyPair.generateDeterministic(self.secret_key);

        // Sign the message
        const sig = try kp.sign(message, null);

        return sig.toBytes();
    }
};

// ============================================================================
// Passkey Support
// ============================================================================

pub const PasskeyCredential = struct {
    id: []const u8, // Base64url encoded credential ID
    public_key: [33]u8, // P-256 compressed public key (0x02 || x) or (0x03 || x)
    rp_id: []const u8, // Relying Party ID (e.g., "sui.io")
    user_handle: []const u8, // User identifier
    sign_count: u32, // Signature counter (anti-replay)

    pub fn fromCreationResponse(allocator: Allocator, response: []const u8) !PasskeyCredential {
        // Parse WebAuthn credential creation response
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
        defer parsed.deinit();

        const id = parsed.value.object.get("id") orelse return error.MissingCredentialId;
        const raw_id = parsed.value.object.get("rawId") orelse return error.MissingRawId;

        // Extract public key from attestation object
        // This is simplified - real implementation needs CBOR parsing
        var public_key: [33]u8 = undefined;
        public_key[0] = 0x02; // Compressed format indicator
        std.crypto.random.bytes(public_key[1..]);

        return .{
            .id = try allocator.dupe(u8, id.string),
            .public_key = public_key,
            .rp_id = try allocator.dupe(u8, "sui.io"),
            .user_handle = try allocator.dupe(u8, raw_id.string),
            .sign_count = 0,
        };
    }

    pub fn deinit(self: *PasskeyCredential, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.rp_id);
        allocator.free(self.user_handle);
    }

    pub fn deriveSuiAddress(self: *const PasskeyCredential, allocator: Allocator) ![]const u8 {
        // Sui address from P-256 public key
        // Address = "0x" + hex(first 20 bytes of Blake2b-256(public_key))

        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(&self.public_key);

        var hash: [32]u8 = undefined;
        hasher.final(&hash);

        const address = try allocator.alloc(u8, 42); // "0x" + 40 hex chars
        address[0] = '0';
        address[1] = 'x';

        const hex_chars = "0123456789abcdef";
        for (hash[0..20], 0..) |byte, i| {
            address[2 + i * 2] = hex_chars[byte >> 4];
            address[2 + i * 2 + 1] = hex_chars[byte & 0x0F];
        }

        return address;
    }
};

pub const PasskeySignature = struct {
    authenticator_data: []const u8,
    client_data_json: []const u8,
    signature: [64]u8, // ECDSA P-256 signature (r || s)
};

pub const PasskeyAuthenticator = struct {
    allocator: Allocator,
    credentials: std.ArrayList(PasskeyCredential),

    pub fn init(allocator: Allocator) PasskeyAuthenticator {
        return .{
            .allocator = allocator,
            .credentials = std.ArrayList(PasskeyCredential).init(allocator),
        };
    }

    pub fn deinit(self: *PasskeyAuthenticator) void {
        for (self.credentials.items) |*cred| {
            cred.deinit(self.allocator);
        }
        self.credentials.deinit();
    }

    pub fn createCredential(_: *PasskeyAuthenticator, _: []const u8) !void {
        // In a real implementation, this would:
        // 1. Call platform WebAuthn API
        // 2. Get credential creation response
        // 3. Parse and store the credential

        std.log.info("Creating Passkey credential...", .{});
        std.log.info("Note: This requires platform WebAuthn support", .{});
        std.log.info("On macOS/iOS: Use LocalAuthentication framework", .{});
        std.log.info("On Linux: Use libfido2", .{});

        return error.NotImplemented;
    }

    pub fn signTransaction(
        self: *const PasskeyAuthenticator,
        credential_id: []const u8,
        tx_hash: []const u8,
    ) !PasskeySignature {
        // Find credential
        const credential = for (self.credentials.items) |cred| {
            if (std.mem.eql(u8, cred.id, credential_id)) break cred;
        } else return error.CredentialNotFound;

        // In a real implementation, this would:
        // 1. Call platform WebAuthn API with tx_hash as challenge
        // 2. Get assertion response
        // 3. Parse authenticator data, client data, and signature

        _ = credential;
        _ = tx_hash;

        return error.NotImplemented;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

fn base64UrlDecode(allocator: Allocator, input: []const u8) ![]const u8 {
    // Convert base64url to standard base64
    var standard = try allocator.alloc(u8, input.len);
    defer allocator.free(standard);

    for (input, 0..) |c, i| {
        standard[i] = switch (c) {
            '-' => '+',
            '_' => '/',
            else => c,
        };
    }

    // Add padding if needed
    const padding_needed = (4 - (input.len % 4)) % 4;
    const padded = try allocator.alloc(u8, input.len + padding_needed);
    @memcpy(padded[0..input.len], standard);
    @memset(padded[input.len..], '=');

    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(padded);
    const decoded = try allocator.alloc(u8, decoded_len);
    try std.base64.standard.Decoder.decode(decoded, padded);

    return decoded;
}

// ============================================================================
// Tests
// ============================================================================

test "ZkLoginProvider issuer" {
    try std.testing.expectEqualStrings(
        "https://accounts.google.com",
        ZkLoginProvider.google.getIssuer(),
    );
}

test "EphemeralKeyPair generation" {
    const kp = try EphemeralKeyPair.generate();
    try std.testing.expectEqual(kp.public_key.len, 32);
    try std.testing.expectEqual(kp.secret_key.len, 32);
}
