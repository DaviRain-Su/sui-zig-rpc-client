/// Transaction signing module for Sui
/// Implements Ed25519 signing for Sui transactions

const std = @import("std");
const Allocator = std.mem.Allocator;

// Use Zig's standard library Ed25519 implementation
const Ed25519 = std.crypto.sign.Ed25519;

// Ed25519 constants
pub const ED25519_PUBLIC_KEY_LEN: usize = 32;
pub const ED25519_SECRET_KEY_LEN: usize = 32;
pub const ED25519_SIGNATURE_LEN: usize = 64;
pub const SUI_SIGNATURE_SCHEME_LEN: usize = 1;
pub const SUI_PUBLIC_KEY_LEN: usize = SUI_SIGNATURE_SCHEME_LEN + ED25519_PUBLIC_KEY_LEN;
pub const SUI_SIGNATURE_LEN: usize = SUI_SIGNATURE_SCHEME_LEN + ED25519_SIGNATURE_LEN + ED25519_PUBLIC_KEY_LEN;

// Signature scheme flag
pub const SIGNATURE_SCHEME_ED25519: u8 = 0x00;

/// Key pair for signing
pub const KeyPair = struct {
    public_key: [ED25519_PUBLIC_KEY_LEN]u8,
    secret_key: [ED25519_SECRET_KEY_LEN]u8,

    pub fn fromSecretKey(secret_key: [ED25519_SECRET_KEY_LEN]u8) !KeyPair {
        // Derive public key from secret key using Ed25519
        // Ed25519 secret key is the seed, we need to expand it
        const seed = secret_key;
        
        // Use Ed25519 key pair generation from seed
        const kp = try Ed25519.KeyPair.generateDeterministic(seed);
        
        var public_key: [ED25519_PUBLIC_KEY_LEN]u8 = undefined;
        @memcpy(&public_key, &kp.public_key.bytes);
        
        return KeyPair{
            .public_key = public_key,
            .secret_key = secret_key,
        };
    }

    pub fn generateRandom() !KeyPair {
        var secret_key: [ED25519_SECRET_KEY_LEN]u8 = undefined;
        std.crypto.random.bytes(&secret_key);
        
        return try fromSecretKey(secret_key);
    }
};

/// Transaction signer
pub const TransactionSigner = struct {
    allocator: Allocator,
    keypair: KeyPair,

    pub fn init(allocator: Allocator, keypair: KeyPair) TransactionSigner {
        return .{
            .allocator = allocator,
            .keypair = keypair,
        };
    }

    /// Sign transaction data
    /// Returns a Sui-compatible signature
    pub fn signTransaction(self: *const TransactionSigner, tx_data: []const u8) ![SUI_SIGNATURE_LEN]u8 {
        var signature: [SUI_SIGNATURE_LEN]u8 = undefined;
        
        // Signature scheme flag
        signature[0] = SIGNATURE_SCHEME_ED25519;
        
        // Create Ed25519 key pair from our secret key
        const seed = self.keypair.secret_key;
        const kp = try Ed25519.KeyPair.generateDeterministic(seed);
        
        // Sign the transaction data
        const sig = try kp.sign(tx_data, null);
        
        // Copy signature bytes (64 bytes)
        @memcpy(signature[1..65], &sig.toBytes());
        
        // Copy public key (32 bytes)
        @memcpy(signature[65..97], &self.keypair.public_key);
        
        return signature;
    }

    /// Get the Sui address from the public key
    pub fn getAddress(self: *const TransactionSigner, allocator: Allocator) ![]const u8 {
        // Sui address is derived from public key using Blake2b-256 hash
        // Address = 0x + hex(first 20 bytes of hash)
        
        // Create public key with scheme flag
        var pk_with_scheme: [SUI_PUBLIC_KEY_LEN]u8 = undefined;
        pk_with_scheme[0] = SIGNATURE_SCHEME_ED25519;
        @memcpy(pk_with_scheme[1..], &self.keypair.public_key);
        
        // Blake2b-256 hash
        var hash: [32]u8 = undefined;
        std.crypto.hash.blake2.Blake2b256.hash(&pk_with_scheme, &hash, .{});
        
        // Format address: 0x + hex(first 20 bytes)
        const address = try allocator.alloc(u8, 42);
        errdefer allocator.free(address);
        
        @memcpy(address[0..2], "0x");
        
        const hex_chars = "0123456789abcdef";
        for (0..20) |i| {
            const byte = hash[i];
            address[2 + i * 2] = hex_chars[byte >> 4];
            address[2 + i * 2 + 1] = hex_chars[byte & 0x0F];
        }
        
        return address;
    }
};

/// Load keypair from keystore file
pub fn loadKeypairFromKeystore(allocator: Allocator, keystore_path: []const u8, _: []const u8) !KeyPair {
    // Read keystore file
    const file = try std.fs.cwd().openFile(keystore_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Parse JSON keystore
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    // Try array format first: ["base64key1", "base64key2", ...]
    if (parsed.value == .array) {
        if (parsed.value.array.items.len > 0) {
            const key_b64 = parsed.value.array.items[0].string;
            
            // Decode base64 key
            const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(key_b64);
            var decoded = try allocator.alloc(u8, decoded_len);
            defer allocator.free(decoded);
            
            try std.base64.standard.Decoder.decode(decoded, key_b64);
            
            // Extract secret key (last 32 bytes for Ed25519)
            var secret_key: [ED25519_SECRET_KEY_LEN]u8 = undefined;
            @memcpy(&secret_key, decoded[decoded_len - 32 ..]);
            
            return try KeyPair.fromSecretKey(secret_key);
        }
    }

    // Try object format: {"addresses": [...], "keys": [...]}
    if (parsed.value == .object) {
        if (parsed.value.object.get("keys")) |keys| {
            if (keys == .array and keys.array.items.len > 0) {
                const key_b64 = keys.array.items[0].string;
                
                // Decode base64 key
                const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(key_b64);
                var decoded = try allocator.alloc(u8, decoded_len);
                defer allocator.free(decoded);
                
                try std.base64.standard.Decoder.decode(decoded, key_b64);
                
                // Extract secret key (last 32 bytes)
                var secret_key: [ED25519_SECRET_KEY_LEN]u8 = undefined;
                @memcpy(&secret_key, decoded[decoded_len - 32 ..]);
                
                return try KeyPair.fromSecretKey(secret_key);
            }
        }
    }

    return error.KeyNotFound;
}

/// Load keypair from mnemonic phrase (BIP-39)
pub fn loadKeypairFromMnemonic(allocator: Allocator, mnemonic: []const u8) !KeyPair {
    const bip39 = @import("bip39.zig");
    
    // Validate mnemonic
    if (!bip39.validateMnemonic(mnemonic)) {
        return error.InvalidMnemonic;
    }
    
    // Convert mnemonic to seed
    const seed = try bip39.mnemonicToSeed(allocator, mnemonic, null);
    
    // Derive Ed25519 key from seed (SLIP-0010)
    const secret_key = try bip39.deriveEd25519Key(seed, "m/44'/784'/0'/0'/0'");
    
    return try KeyPair.fromSecretKey(secret_key);
}

/// Load keypair from private key file
pub fn loadKeypairFromFile(allocator: Allocator, path: []const u8) !KeyPair {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    // Parse private key (hex or base64)
    var secret_key: [ED25519_SECRET_KEY_LEN]u8 = undefined;
    
    if (content.len == 64) {
        // Hex encoded
        for (0..32) |i| {
            secret_key[i] = try std.fmt.parseInt(u8, content[i * 2 .. i * 2 + 2], 16);
        }
    } else if (content.len == 44) {
        // Base64 encoded
        var decoded: [32]u8 = undefined;
        try std.base64.standard.Decoder.decode(&decoded, content);
        secret_key = decoded;
    } else {
        return error.InvalidKeyFormat;
    }

    return try KeyPair.fromSecretKey(secret_key);
}

/// Create a signed transaction
pub fn createSignedTransaction(
    allocator: Allocator,
    signer: *const TransactionSigner,
    tx_bytes: []const u8,
) ![]const u8 {
    // Sign the transaction
    const signature = try signer.signTransaction(tx_bytes);
    
    // Create signed transaction JSON
    const signed_tx = try std.fmt.allocPrint(allocator, 
        "{{\"transactionBytes\":\"{s}\",\"signature\":\"{s}\"}}",
        .{
            try std.base64.standard.Encoder.encode(allocator, tx_bytes),
            try std.base64.standard.Encoder.encode(allocator, &signature),
        },
    );
    
    return signed_tx;
}

// Test functions
test "KeyPair generation" {
    const keypair = try KeyPair.generateRandom();
    try std.testing.expectEqual(keypair.public_key.len, ED25519_PUBLIC_KEY_LEN);
    try std.testing.expectEqual(keypair.secret_key.len, ED25519_SECRET_KEY_LEN);
}

test "TransactionSigner init" {
    const keypair = try KeyPair.generateRandom();
    const signer = TransactionSigner.init(std.testing.allocator, keypair);
    try std.testing.expectEqual(signer.keypair.public_key.len, ED25519_PUBLIC_KEY_LEN);
}

test "Address generation" {
    const keypair = try KeyPair.generateRandom();
    const signer = TransactionSigner.init(std.testing.allocator, keypair);
    const address = try signer.getAddress(std.testing.allocator);
    defer std.testing.allocator.free(address);
    
    try std.testing.expectEqual(address.len, 42);
    try std.testing.expectEqual(address[0..2], "0x");
}

test "Transaction signing" {
    const keypair = try KeyPair.generateRandom();
    const signer = TransactionSigner.init(std.testing.allocator, keypair);
    
    const tx_data = "test transaction data";
    const signature = try signer.signTransaction(tx_data);
    
    // Verify signature structure
    try std.testing.expectEqual(signature[0], SIGNATURE_SCHEME_ED25519);
    try std.testing.expectEqual(signature.len, SUI_SIGNATURE_LEN);
}

test "Ed25519 signature verification" {
    const keypair = try KeyPair.generateRandom();
    const signer = TransactionSigner.init(std.testing.allocator, keypair);
    
    const tx_data = "test transaction data";
    const signature = try signer.signTransaction(tx_data);
    
    // Extract signature components
    const sig_bytes = signature[1..65];
    const pk_bytes = signature[65..97];
    
    // Verify the signature
    const pk = try Ed25519.PublicKey.fromBytes(pk_bytes.*);
    const sig = try Ed25519.Signature.fromBytes(sig_bytes.*);
    
    try sig.verify(&pk, tx_data);
}
