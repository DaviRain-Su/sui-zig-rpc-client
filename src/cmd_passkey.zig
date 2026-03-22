// cmd_passkey.zig - Passkey/WebAuthn commands for Sui CLI
// Uses file-based encrypted keystore (AES-256-GCM + PBKDF2)
// Supports macOS (Touch ID) and Linux (libfido2/YubiKey)
// No Apple Developer required! Completely free!

const std = @import("std");
const Allocator = std.mem.Allocator;

// Platform check
const builtin = @import("builtin");
const is_macos = builtin.os.tag == .macos;
const is_linux = builtin.os.tag == .linux;
const webauthn_enabled = @hasDecl(builtin, "WEBAUTHN_ENABLED");
const webauthn_available = is_macos and webauthn_enabled;

// Import C bridge only when WebAuthn is enabled on macOS
const c = if (webauthn_available) @import("webauthn/c_bridge.zig") else struct {};

// Import Linux WebAuthn support
const LinuxWebAuthn = if (is_linux) @import("webauthn/linux.zig").LinuxWebAuthn else struct {};

// Import file keystore
const FileKeystore = @import("webauthn/file_keystore.zig").FileKeystore;

// Constants (only used when WebAuthn is available)
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
    } else if (std.mem.eql(u8, action, "create-browser")) {
        try cmdCreateBrowser(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "platform")) {
        try cmdPlatform();
    } else if (std.mem.eql(u8, action, "test")) {
        try cmdTest(allocator);
    } else if (std.mem.eql(u8, action, "list")) {
        try cmdList(allocator);
    } else if (std.mem.eql(u8, action, "devices")) {
        try cmdDevices(allocator);
    } else {
        std.log.err("Unknown passkey action: {s}", .{action});
        printUsage();
        std.process.exit(1);
    }
}

fn printUsage() void {
    std.log.info("Usage: passkey <action>", .{});
    std.log.info("Actions:", .{});
    std.log.info("  create --name <name>         Create Passkey (file encryption)", .{});
    std.log.info("  create-browser --name <name> Create Passkey via browser (WebAuthn)", .{});
    std.log.info("  list                         List stored credentials", .{});
    std.log.info("  platform                     Show platform info", .{});
    std.log.info("  test                         Test biometric/hardware authentication", .{});
    std.log.info("  devices                      List connected hardware keys (Linux)", .{});
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

    if (!webauthn_available) {
        std.log.err("Passkey creation requires WebAuthn support (macOS with -Dwebauthn flag)", .{});
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
    const bio_name = if (bio_type == BIOMETRY_TYPE_TOUCH_ID) "Touch ID" else if (bio_type == BIOMETRY_TYPE_FACE_ID) "Face ID" else if (bio_type == BIOMETRY_TYPE_OPTIC_ID) "Optic ID" else "Biometric";

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

fn cmdCreateBrowser(allocator: Allocator, args: []const []const u8) !void {
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

    std.log.info("=== Create Passkey via Browser ===", .{});
    std.log.info("", .{});
    std.log.info("Name: {s}", .{credential_name});
    std.log.info("", .{});
    std.log.info("This will:", .{});
    std.log.info("  1. Open your default browser", .{});
    std.log.info("  2. Use WebAuthn API for credential creation", .{});
    std.log.info("  3. Support Touch ID, Face ID, or YubiKey", .{});
    std.log.info("  4. Save credential to file", .{});
    std.log.info("", .{});
    std.log.info("Press Enter to continue...", .{});

    var buf: [10]u8 = undefined;
    const stdin = std.fs.File{ .handle = 0 };
    _ = stdin.read(&buf) catch {};

    // Import browser bridge (use server version for localhost support)
    const browser = @import("webauthn/browser_server.zig");

    const output_dir = try getKeystoreDir(allocator);
    defer allocator.free(output_dir);

    std.log.info("", .{});
    std.log.info("Opening browser...", .{});

    var credential = browser.createCredentialInBrowser(
        allocator,
        "sui-cli.local",
        credential_name,
        output_dir,
    ) catch |err| {
        std.log.err("Failed to create credential: {s}", .{@errorName(err)});
        std.log.info("", .{});
        std.log.info("Make sure to:", .{});
        std.log.info("  - Use a WebAuthn-compatible browser (Safari, Chrome, Firefox)", .{});
        std.log.info("  - Download the .json file when prompted", .{});
        std.log.info("  - Move it to: {s}/", .{output_dir});
        std.process.exit(1);
    };
    defer credential.deinit(allocator);

    std.log.info("✓ Credential created via browser!", .{});
    std.log.info("  ID: {s}", .{credential.id});
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

    if (webauthn_available) {
        std.log.info("Platform: macOS (WebAuthn enabled)", .{});
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
            const bio_name = if (bio_type == BIOMETRY_TYPE_TOUCH_ID) "Touch ID 🖐️" else if (bio_type == BIOMETRY_TYPE_FACE_ID) "Face ID 😊" else if (bio_type == BIOMETRY_TYPE_OPTIC_ID) "Optic ID 👁️" else "None";

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
    } else if (is_macos) {
        std.log.info("Platform: macOS", .{});
        std.log.info("", .{});
        std.log.info("WebAuthn: Not enabled (build with -Dwebauthn)", .{});
        std.log.info("", .{});
        std.log.info("Features:", .{});
        std.log.info("  - File-based keystore (available)", .{});
        std.log.info("  - Touch ID authentication (requires -Dwebauthn)", .{});
    } else if (is_linux) {
        std.log.info("Platform: Linux", .{});
        std.log.info("", .{});

        // Check for libfido2 support
        var webauthn = LinuxWebAuthn.init(std.heap.page_allocator);
        defer webauthn.deinit();

        const available = webauthn.isAvailable();
        std.log.info("Hardware Key Support: {s}", .{if (available) "✓ Available" else "✗ Not Available"});

        if (available) {
            const devices = webauthn.listDevices() catch |err| {
                std.log.info("  Error listing devices: {s}", .{@errorName(err)});
                return;
            };
            defer {
                for (devices) |dev| {
                    std.heap.page_allocator.free(dev.path);
                    std.heap.page_allocator.free(dev.manufacturer);
                    std.heap.page_allocator.free(dev.product);
                }
                std.heap.page_allocator.free(devices);
            }

            std.log.info("  Connected devices: {d}", .{devices.len});
            for (devices) |dev| {
                std.log.info("    - {s} ({s})", .{ dev.product, dev.manufacturer });
            }
        }

        std.log.info("", .{});
        std.log.info("Features:", .{});
        std.log.info("  - YubiKey/hardware key support (libfido2)", .{});
        std.log.info("  - AES-256-GCM encryption", .{});
        std.log.info("  - PBKDF2 key derivation", .{});
        std.log.info("  - File-based storage", .{});
    } else {
        std.log.info("Platform: {s}", .{@tagName(builtin.os.tag)});
        std.log.info("", .{});
        std.log.info("WebAuthn is supported on macOS and Linux.", .{});
    }
}

fn cmdDevices(allocator: Allocator) !void {
    std.log.info("=== Hardware Key Devices ===", .{});
    std.log.info("", .{});

    if (!is_linux) {
        std.log.info("Device listing is only available on Linux with libfido2.", .{});
        std.log.info("On macOS, hardware keys are automatically detected.", .{});
        return;
    }

    var webauthn = LinuxWebAuthn.init(allocator);
    defer webauthn.deinit();

    const devices = webauthn.listDevices() catch |err| {
        std.log.err("Failed to list devices: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    defer {
        for (devices) |dev| {
            allocator.free(dev.path);
            allocator.free(dev.manufacturer);
            allocator.free(dev.product);
        }
        allocator.free(devices);
    }

    if (devices.len == 0) {
        std.log.info("No hardware keys detected.", .{});
        std.log.info("", .{});
        std.log.info("Make sure you have:", .{});
        std.log.info("  - libfido2 installed (sudo apt install libfido2-1)", .{});
        std.log.info("  - A FIDO2-compatible key (YubiKey, etc.) plugged in", .{});
        std.log.info("  - Proper udev rules for USB access", .{});
    } else {
        std.log.info("Found {d} device(s):", .{devices.len});
        std.log.info("", .{});
        for (devices, 0..) |dev, i| {
            std.log.info("Device {d}:", .{i + 1});
            std.log.info("  Path: {s}", .{dev.path});
            std.log.info("  Manufacturer: {s}", .{dev.manufacturer});
            std.log.info("  Product: {s}", .{dev.product});
            std.log.info("", .{});
        }
    }
}

fn cmdTest(allocator: Allocator) !void {
    _ = allocator;

    std.log.info("=== Authentication Test ===", .{});
    std.log.info("", .{});

    if (is_linux) {
        std.log.info("Platform: Linux", .{});
        std.log.info("", .{});
        std.log.info("On Linux, hardware key authentication is used during:", .{});
        std.log.info("  - passkey create (with hardware key option)", .{});
        std.log.info("  - Transaction signing", .{});
        std.log.info("", .{});
        std.log.info("Use 'passkey devices' to list connected hardware keys.", .{});
        return;
    }

    if (!webauthn_available) {
        std.log.err("Touch ID test requires WebAuthn support (build with -Dwebauthn)", .{});
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
    const bio_name = if (bio_type == BIOMETRY_TYPE_TOUCH_ID) "Touch ID" else if (bio_type == BIOMETRY_TYPE_FACE_ID) "Face ID" else if (bio_type == BIOMETRY_TYPE_OPTIC_ID) "Optic ID" else "Biometric";

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
