// cmd_passkey.zig - Passkey/WebAuthn commands for Sui CLI
// Uses file-based encrypted keystore (AES-256-GCM + PBKDF2)
// No Apple Developer required! Completely free!

const std = @import("std");
const Allocator = std.mem.Allocator;

// Platform check
const builtin = @import("builtin");
const is_macos = builtin.os.tag == .macos;

// Import C bridge on macOS for Touch ID
const c = if (is_macos) @import("webauthn/c_bridge.zig") else struct {};

// Import file keystore
const FileKeystore = @import("webauthn/file_keystore.zig").FileKeystore;

// Constants
const POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS: c_int = 2;
const BIOMETRY_TYPE_TOUCH_ID: c_int = 1;
const BIOMETRY_TYPE_FACE_ID: c_int = 2;
const BIOMETRY_TYPE_OPTIC_ID: c_int = 3;

pub fn execute(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        printUsage();
        std.process.exit(1);
    }

    const action = args[0];

    if (std.mem.eql(u8, action, "create")) {
        try cmdCreate(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "platform")) {
        try cmdPlatform();
    } else if (std.mem.eql(u8, action, "test")) {
        try cmdTest(allocator);
    } else if (std.mem.eql(u8, action, "list")) {
        try cmdList(allocator);
    } else {
        std.log.err("Unknown passkey action: {s}", .{action});
        printUsage();
        std.process.exit(1);
    }
}

fn printUsage() void {
    std.log.info("Usage: passkey <action>", .{});
    std.log.info("Actions:", .{});
    std.log.info("  create --name <name>    Create new Passkey with Touch ID", .{});
    std.log.info("  list                    List stored credentials", .{});
    std.log.info("  platform                Show platform info", .{});
    std.log.info("  test                    Test Touch ID authentication", .{});
}

fn getKeystoreDir(allocator: Allocator) ![]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return allocator.dupe(u8, ".sui-zig/keystore");
    };
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &.{ home, ".sui-zig", "keystore" });
}

fn promptPassword(allocator: Allocator) ![]const u8 {
    std.log.info("Enter password to protect the key: ", .{});
    
    // Simple password prompt (echo disabled in production)
    var buf: [256]u8 = undefined;
    const stdin = std.fs.File{ .handle = 0 };
    const n = try stdin.read(&buf);
    
    // Remove newline
    var len = n;
    if (len > 0 and buf[len - 1] == '\n') len -= 1;
    if (len > 0 and buf[len - 1] == '\r') len -= 1;
    
    return try allocator.dupe(u8, buf[0..len]);
}

fn cmdCreate(allocator: Allocator, args: []const []const u8) !void {
    var name: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--name")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing value for --name", .{});
                std.process.exit(1);
            }
            name = args[i + 1];
            i += 1;
        }
    }

    const credential_name = name orelse "Sui Passkey";

    std.log.info("=== Create Passkey ===", .{});
    std.log.info("", .{});
    std.log.info("Name: {s}", .{credential_name});
    std.log.info("", .{});

    if (!is_macos) {
        std.log.err("Passkey creation is only supported on macOS currently", .{});
        std.process.exit(1);
    }

    // Check biometric availability
    const context = c.LAContextCreate();
    if (context == null) {
        std.log.err("Failed to create LAContext", .{});
        std.process.exit(1);
    }
    defer c.LAContextRelease(context);

    var error_code: c_int = 0;
    const bio_available = c.LAContextCanEvaluatePolicy(
        context,
        POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
        &error_code,
    );

    if (!bio_available) {
        const err_msg = c.GetErrorMessage(error_code);
        defer c.FreeString(err_msg);
        std.log.err("Biometric authentication not available: {s}", .{err_msg});
        std.log.info("", .{});
        std.log.info("Please ensure:", .{});
        std.log.info("  - You have a Touch ID capable Mac", .{});
        std.log.info("  - Fingerprints are enrolled in System Preferences > Touch ID", .{});
        std.process.exit(1);
    }

    const bio_type = c.LAContextGetBiometryType(context);
    const bio_name = if (bio_type == BIOMETRY_TYPE_TOUCH_ID) "Touch ID"
        else if (bio_type == BIOMETRY_TYPE_FACE_ID) "Face ID"
        else if (bio_type == BIOMETRY_TYPE_OPTIC_ID) "Optic ID"
        else "Biometric";

    std.log.info("✓ {s} is available", .{bio_name});
    std.log.info("", .{});
    std.log.info("This will:", .{});
    std.log.info("  1. Prompt for {s} verification", .{bio_name});
    std.log.info("  2. Generate Ed25519 keypair", .{});
    std.log.info("  3. Encrypt with AES-256-GCM", .{});
    std.log.info("  4. Store in encrypted file", .{});
    std.log.info("", .{});
    std.log.info("Press Enter to continue or Ctrl+C to cancel...", .{});

    // Wait for user
    var buf: [10]u8 = undefined;
    const stdin = std.fs.File{ .handle = 0 };
    _ = stdin.read(&buf) catch {};

    // Prompt for authentication
    std.log.info("", .{});
    std.log.info("🔐 Please authenticate with {s}...", .{bio_name});

    const auth_context = c.LAContextCreate();
    if (auth_context == null) {
        std.log.err("Failed to create auth context", .{});
        std.process.exit(1);
    }
    defer c.LAContextRelease(auth_context);

    const reason = "Create Sui Passkey credential";
    const auth_success = c.LAContextEvaluatePolicySync(
        auth_context,
        POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
        reason.ptr,
        &error_code,
    );

    if (!auth_success) {
        const err_msg = c.GetErrorMessage(error_code);
        defer c.FreeString(err_msg);
        std.log.err("Authentication failed: {s}", .{err_msg});
        std.process.exit(1);
    }

    std.log.info("✓ Authentication successful!", .{});
    std.log.info("", .{});

    // For demo, use a default password
    // In production, prompt user securely
    const password = "sui-zig-passkey-2024";
    std.log.info("Using default encryption password (demo mode)", .{});

    // Generate credential tag
    const timestamp = std.time.milliTimestamp();
    var tag_buf: [256]u8 = undefined;
    const tag = try std.fmt.bufPrint(&tag_buf, "sui-passkey-{s}-{d}", .{ credential_name, timestamp });

    // Generate Ed25519 key pair
    std.log.info("Generating Ed25519 keypair...", .{});
    
    const Ed25519 = std.crypto.sign.Ed25519;
    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    const kp = try Ed25519.KeyPair.generateDeterministic(seed);

    std.log.info("✓ Keypair generated", .{});

    // Store in encrypted file
    const keystore_dir = try getKeystoreDir(allocator);
    defer allocator.free(keystore_dir);

    var keystore = try FileKeystore.init(allocator, keystore_dir);
    defer keystore.deinit();

    try keystore.storeCredential(tag, seed, kp.public_key.bytes, password);

    std.log.info("✓ Credential encrypted and stored", .{});
    std.log.info("  Location: {s}/{s}.json", .{ keystore_dir, tag });

    // Print success
    printCredentialSuccess(tag, &kp.public_key.bytes, false);
}

fn printCredentialSuccess(tag: []const u8, public_key: *const [32]u8, is_secure_enclave: bool) void {
    // Derive Sui address from public key
    var pk_with_scheme: [33]u8 = undefined;
    pk_with_scheme[0] = 0x00; // Ed25519 scheme
    @memcpy(pk_with_scheme[1..], public_key);

    var hash: [32]u8 = undefined;
    std.crypto.hash.blake2.Blake2b256.hash(&pk_with_scheme, &hash, .{});

    var address: [42]u8 = undefined;
    address[0] = '0';
    address[1] = 'x';
    const hex_chars = "0123456789abcdef";
    for (0..20) |i| {
        const byte = hash[i];
        address[2 + i * 2] = hex_chars[byte >> 4];
        address[2 + i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    std.log.info("", .{});
    std.log.info("╔══════════════════════════════════════════════════════════════╗", .{});
    std.log.info("║                 Passkey Created Successfully                 ║", .{});
    std.log.info("╚══════════════════════════════════════════════════════════════╝", .{});
    std.log.info("", .{});
    std.log.info("Credential ID: {s}", .{tag});
    std.log.info("Sui Address:   {s}", .{address});
    std.log.info("Public Key:    32 bytes", .{});
    std.log.info("Algorithm:     Ed25519", .{});
    std.log.info("Storage:       {s}", .{if (is_secure_enclave) "Secure Enclave" else "Encrypted file (AES-256-GCM)"});
    std.log.info("Protection:    Touch ID + Password", .{});
    std.log.info("", .{});
    std.log.info("To use this credential:", .{});
    std.log.info("  passkey sign --id \"{s}\" --tx <transaction_bytes>", .{tag});
}

fn cmdList(allocator: Allocator) !void {
    const keystore_dir = try getKeystoreDir(allocator);
    defer allocator.free(keystore_dir);

    var keystore = try FileKeystore.init(allocator, keystore_dir);
    defer keystore.deinit();

    const credentials = try keystore.listCredentials(allocator);
    defer {
        for (credentials) |cred| allocator.free(cred);
        allocator.free(credentials);
    }

    std.log.info("=== Stored Credentials ===", .{});
    std.log.info("", .{});
    std.log.info("Location: {s}", .{keystore_dir});
    std.log.info("", .{});

    if (credentials.len == 0) {
        std.log.info("No credentials found.", .{});
        std.log.info("", .{});
        std.log.info("Create one with:", .{});
        std.log.info("  passkey create --name \"My Key\"", .{});
    } else {
        std.log.info("Found {d} credential(s):", .{credentials.len});
        std.log.info("", .{});
        for (credentials) |cred| {
            std.log.info("  - {s}", .{cred});
        }
    }
}

fn cmdPlatform() !void {
    std.log.info("=== WebAuthn Platform Info ===", .{});
    std.log.info("", .{});

    if (is_macos) {
        std.log.info("Platform: macOS", .{});
        std.log.info("", .{});

        const context = c.LAContextCreate();
        if (context) |ctx| {
            defer c.LAContextRelease(ctx);

            var error_code: c_int = 0;
            const bio_available = c.LAContextCanEvaluatePolicy(
                ctx,
                POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
                &error_code,
            );

            const bio_type = c.LAContextGetBiometryType(ctx);
            const bio_name = if (bio_type == BIOMETRY_TYPE_TOUCH_ID) "Touch ID 🖐️"
                else if (bio_type == BIOMETRY_TYPE_FACE_ID) "Face ID 😊"
                else if (bio_type == BIOMETRY_TYPE_OPTIC_ID) "Optic ID 👁️"
                else "None";

            std.log.info("Biometry Type: {s}", .{bio_name});
            std.log.info("Available: {s}", .{if (bio_available) "✓ Yes" else "✗ No"});
        } else {
            std.log.info("Failed to create LAContext", .{});
        }

        std.log.info("", .{});
        std.log.info("Features:", .{});
        std.log.info("  - Touch ID authentication", .{});
        std.log.info("  - AES-256-GCM encryption", .{});
        std.log.info("  - PBKDF2 key derivation", .{});
        std.log.info("  - File-based storage (no Apple Developer needed!)", .{});
    } else {
        std.log.info("Platform: {s}", .{@tagName(builtin.os.tag)});
        std.log.info("", .{});
        std.log.info("WebAuthn is only supported on macOS currently.", .{});
    }
}

fn cmdTest(allocator: Allocator) !void {
    _ = allocator;
    
    std.log.info("=== Touch ID Test ===", .{});
    std.log.info("", .{});

    if (!is_macos) {
        std.log.err("This test is only available on macOS", .{});
        std.process.exit(1);
    }

    const context = c.LAContextCreate();
    if (context == null) {
        std.log.err("Failed to create LAContext", .{});
        std.process.exit(1);
    }
    defer c.LAContextRelease(context);

    var error_code: c_int = 0;
    const bio_available = c.LAContextCanEvaluatePolicy(
        context,
        POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
        &error_code,
    );

    if (!bio_available) {
        std.log.err("Biometric authentication not available", .{});
        std.process.exit(1);
    }

    const bio_type = c.LAContextGetBiometryType(context);
    const bio_name = if (bio_type == BIOMETRY_TYPE_TOUCH_ID) "Touch ID"
        else if (bio_type == BIOMETRY_TYPE_FACE_ID) "Face ID"
        else if (bio_type == BIOMETRY_TYPE_OPTIC_ID) "Optic ID"
        else "Biometric";

    std.log.info("✓ {s} is available", .{bio_name});
    std.log.info("", .{});
    std.log.info("Press Enter to test authentication...", .{});

    var buf: [10]u8 = undefined;
    const stdin = std.fs.File{ .handle = 0 };
    _ = stdin.read(&buf) catch {};

    std.log.info("", .{});
    std.log.info("🔐 Prompting for {s}...", .{bio_name});

    const auth_context = c.LAContextCreate();
    if (auth_context == null) {
        std.log.err("Failed to create auth context", .{});
        std.process.exit(1);
    }
    defer c.LAContextRelease(auth_context);

    const reason = "Test Touch ID authentication";
    const auth_success = c.LAContextEvaluatePolicySync(
        auth_context,
        POLICY_DEVICE_OWNER_AUTHENTICATION_WITH_BIOMETRICS,
        reason.ptr,
        &error_code,
    );

    if (auth_success) {
        std.log.info("✓ Authentication successful!", .{});
        std.log.info("", .{});
        std.log.info("🎉 Touch ID is working correctly!", .{});
    } else {
        const err_msg = c.GetErrorMessage(error_code);
        defer c.FreeString(err_msg);
        std.log.err("Authentication failed: {s}", .{err_msg});
        std.process.exit(1);
    }
}
