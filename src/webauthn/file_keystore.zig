// File-based encrypted keystore for Passkey credentials
// Uses AES-256-GCM for encryption, keys protected by user password
// Completely free, no Apple Developer required!

const std = @import("std");
const Allocator = std.mem.Allocator;

// AES-256-GCM constants
const KEY_LEN: usize = 32; // 256 bits
const NONCE_LEN: usize = 12; // 96 bits for GCM
const TAG_LEN: usize = 16; // 128 bits authentication tag
const SALT_LEN: usize = 32; // 256 bits salt for PBKDF2
const ITERATIONS: u32 = 100_000; // PBKDF2 iterations

/// Encrypted credential stored in file
pub const EncryptedCredential = struct {
    tag: []const u8,
    salt: [SALT_LEN]u8,
    nonce: [NONCE_LEN]u8,
    encrypted_seed: []const u8,
    public_key: [32]u8,
    algorithm: []const u8, // "Ed25519"
    created_at: i64,
};

/// Keystore manager
pub const FileKeystore = struct {
    allocator: Allocator,
    keystore_dir: []const u8,

    const Self = @This();

    /// Initialize keystore with directory path
    pub fn init(allocator: Allocator, keystore_dir: []const u8) !Self {
        // Create directory if it doesn't exist
        std.fs.cwd().makePath(keystore_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return Self{
            .allocator = allocator,
            .keystore_dir = try allocator.dupe(u8, keystore_dir),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.keystore_dir);
    }

    /// Derive encryption key from password using PBKDF2-HMAC-SHA256
    fn deriveKey(password: []const u8, salt: [SALT_LEN]u8) ![KEY_LEN]u8 {
        var key: [KEY_LEN]u8 = undefined;

        // Use PBKDF2 to derive key from password
        try std.crypto.pwhash.pbkdf2(
            &key,
            password,
            &salt,
            ITERATIONS,
            std.crypto.auth.hmac.sha2.HmacSha256,
        );

        return key;
    }

    /// Encrypt seed with password using AES-256-GCM
    fn encryptSeed(seed: [32]u8, password: []const u8) !struct { salt: [SALT_LEN]u8, nonce: [NONCE_LEN]u8, ciphertext: [32 + TAG_LEN]u8 } {
        // Generate random salt
        var salt: [SALT_LEN]u8 = undefined;
        std.crypto.random.bytes(&salt);

        // Generate random nonce
        var nonce: [NONCE_LEN]u8 = undefined;
        std.crypto.random.bytes(&nonce);

        // Derive encryption key
        const key = try deriveKey(password, salt);

        // Encrypt using AES-256-GCM
        var ciphertext: [32 + TAG_LEN]u8 = undefined;
        const Aes256Gcm = std.crypto.aead.aes_gcm.Aes256Gcm;
        Aes256Gcm.encrypt(
            ciphertext[0..32], // ciphertext
            ciphertext[32..], // tag
            &seed, // plaintext
            &.{}, // associated data (none)
            nonce, // nonce
            key, // key
        );

        return .{
            .salt = salt,
            .nonce = nonce,
            .ciphertext = ciphertext,
        };
    }

    /// Decrypt seed with password using AES-256-GCM
    fn decryptSeed(encrypted: [32 + TAG_LEN]u8, salt: [SALT_LEN]u8, nonce: [NONCE_LEN]u8, password: []const u8) ![32]u8 {
        // Derive encryption key
        const key = try deriveKey(password, salt);

        // Decrypt using AES-256-GCM
        var seed: [32]u8 = undefined;
        const Aes256Gcm = std.crypto.aead.aes_gcm.Aes256Gcm;
        try Aes256Gcm.decrypt(
            &seed, // plaintext
            encrypted[0..32], // ciphertext
            encrypted[32..], // tag
            nonce, // nonce
            key, // key
            &.{}, // associated data (none)
        );

        return seed;
    }

    /// Store credential in encrypted file
    pub fn storeCredential(
        self: *Self,
        tag: []const u8,
        seed: [32]u8,
        public_key: [32]u8,
        password: []const u8,
    ) !void {
        // Encrypt seed
        const encrypted = try encryptSeed(seed, password);

        // Create credential structure
        const credential = EncryptedCredential{
            .tag = tag,
            .salt = encrypted.salt,
            .nonce = encrypted.nonce,
            .encrypted_seed = &encrypted.ciphertext,
            .public_key = public_key,
            .algorithm = "Ed25519",
            .created_at = std.time.milliTimestamp(),
        };

        // Serialize to JSON
        const json = try self.serializeCredential(credential);
        defer self.allocator.free(json);

        // Write to file
        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.keystore_dir, tag });
        defer self.allocator.free(filename);

        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(json);
    }

    /// Load credential from encrypted file
    pub fn loadCredential(
        self: *Self,
        tag: []const u8,
        password: []const u8,
    ) !struct { seed: [32]u8, public_key: [32]u8 } {
        // Read file
        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.keystore_dir, tag });
        defer self.allocator.free(filename);

        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // Parse JSON
        const credential = try self.parseCredential(content);

        // Decrypt seed
        var encrypted_arr: [32 + TAG_LEN]u8 = undefined;
        @memcpy(&encrypted_arr, credential.encrypted_seed);

        const seed = try decryptSeed(encrypted_arr, credential.salt, credential.nonce, password);

        return .{
            .seed = seed,
            .public_key = credential.public_key,
        };
    }

    /// Delete credential file
    pub fn deleteCredential(self: *Self, tag: []const u8) !void {
        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.keystore_dir, tag });
        defer self.allocator.free(filename);

        try std.fs.cwd().deleteFile(filename);
    }

    /// List all credentials
    pub fn listCredentials(self: *Self, allocator: Allocator) ![][]const u8 {
        var list = try allocator.alloc([]const u8, 100); // Max 100 credentials
        var count: usize = 0;
        errdefer {
            for (0..count) |i| allocator.free(list[i]);
            allocator.free(list);
        }

        var dir = std.fs.cwd().openDir(self.keystore_dir, .{ .iterate = true }) catch return allocator.dupe([]const u8, &[_][]const u8{});
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (count >= 100) break;
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
                const tag = try allocator.dupe(u8, entry.name[0 .. entry.name.len - 5]);
                list[count] = tag;
                count += 1;
            }
        }

        // Resize to actual count
        const result = try allocator.realloc(list, count);
        return result;
    }

    /// Serialize credential to JSON
    fn serializeCredential(self: *Self, cred: EncryptedCredential) ![]const u8 {
        // Manual JSON serialization
        var buf = try self.allocator.alloc(u8, 4096);
        defer self.allocator.free(buf);

        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        try writer.writeAll("{\n");

        // tag
        try writer.print("  \"tag\": \"{s}\",\n", .{cred.tag});

        // salt (hex)
        try writer.writeAll("  \"salt\": \"");
        for (cred.salt) |b| try writer.print("{x:0>2}", .{b});
        try writer.writeAll("\",\n");

        // nonce (hex)
        try writer.writeAll("  \"nonce\": \"");
        for (cred.nonce) |b| try writer.print("{x:0>2}", .{b});
        try writer.writeAll("\",\n");

        // encrypted_seed (hex)
        try writer.writeAll("  \"encrypted_seed\": \"");
        for (cred.encrypted_seed) |b| try writer.print("{x:0>2}", .{b});
        try writer.writeAll("\",\n");

        // public_key (hex)
        try writer.writeAll("  \"public_key\": \"");
        for (cred.public_key) |b| try writer.print("{x:0>2}", .{b});
        try writer.writeAll("\",\n");

        // algorithm
        try writer.print("  \"algorithm\": \"{s}\",\n", .{cred.algorithm});

        // created_at
        try writer.print("  \"created_at\": {d}\n", .{cred.created_at});

        try writer.writeAll("}\n");

        const written = stream.getWritten().len;
        return try self.allocator.dupe(u8, buf[0..written]);
    }

    /// Parse credential from JSON
    fn parseCredential(self: *Self, json: []const u8) !EncryptedCredential {
        // Simple JSON parsing - in production use proper JSON parser
        var result: EncryptedCredential = undefined;
        result.algorithm = "Ed25519";

        // Parse fields manually (simplified)
        // In production, use std.json.parseFromSlice

        // For now, use std.json
        const parsed = try std.json.parseFromSlice(struct {
            tag: []const u8,
            salt: []const u8,
            nonce: []const u8,
            encrypted_seed: []const u8,
            public_key: []const u8,
            algorithm: []const u8,
            created_at: i64,
        }, self.allocator, json, .{});
        defer parsed.deinit();

        result.tag = try self.allocator.dupe(u8, parsed.value.tag);

        // Parse hex strings
        result.salt = try parseHex(parsed.value.salt);
        result.nonce = try parseHex(parsed.value.nonce);
        result.encrypted_seed = try parseHexAlloc(self.allocator, parsed.value.encrypted_seed);
        result.public_key = try parseHex(parsed.value.public_key);
        result.algorithm = try self.allocator.dupe(u8, parsed.value.algorithm);
        result.created_at = parsed.value.created_at;

        return result;
    }
};

/// Parse hex string to fixed-size array
fn parseHex(hex: []const u8) ![32]u8 {
    var result: [32]u8 = undefined;

    if (hex.len != 64) return error.InvalidHexLength;

    var i: usize = 0;
    while (i < 32) : (i += 1) {
        result[i] = try std.fmt.parseInt(u8, hex[i * 2 .. i * 2 + 2], 16);
    }

    return result;
}

/// Parse hex string to allocated slice
fn parseHexAlloc(allocator: Allocator, hex: []const u8) ![]const u8 {
    if (hex.len % 2 != 0) return error.InvalidHexLength;

    const len = hex.len / 2;
    const result = try allocator.alloc(u8, len);

    var i: usize = 0;
    while (i < len) : (i += 1) {
        result[i] = try std.fmt.parseInt(u8, hex[i * 2 .. i * 2 + 2], 16);
    }

    return result;
}

// Test functions
test "FileKeystore init" {
    const allocator = std.testing.allocator;

    const keystore = try FileKeystore.init(allocator, ".test_keystore");
    defer {
        var k = keystore;
        k.deinit();
        std.fs.cwd().deleteTree(".test_keystore") catch {};
    }
}

test "Encrypt and decrypt seed" {
    const seed: [32]u8 = .{0x01} ** 32;
    const password = "test_password_123";

    // Encrypt
    const encrypted = try FileKeystore.encryptSeed(seed, password);

    // Decrypt
    const decrypted = try FileKeystore.decryptSeed(encrypted.ciphertext, encrypted.salt, encrypted.nonce, password);

    // Verify
    try std.testing.expectEqualSlices(u8, &seed, &decrypted);
}

test "Wrong password fails decryption" {
    const seed: [32]u8 = .{0x01} ** 32;
    const password = "correct_password";
    const wrong_password = "wrong_password";

    // Encrypt
    const encrypted = try FileKeystore.encryptSeed(seed, password);

    // Decrypt with wrong password should fail
    const result = FileKeystore.decryptSeed(encrypted.ciphertext, encrypted.salt, encrypted.nonce, wrong_password);
    try std.testing.expectError(error.AuthenticationFailed, result);
}
