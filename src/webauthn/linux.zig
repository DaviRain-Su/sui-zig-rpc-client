// Linux WebAuthn Implementation
// Uses libfido2 for hardware key support (YubiKey, etc.)

const std = @import("std");
const Allocator = std.mem.Allocator;

// Platform detection
const is_linux = @import("builtin").os.tag == .linux;

// C library imports (libfido2)
const c = if (is_linux) @cImport({
    @cInclude("fido.h");
    @cInclude("stddef.h");
}) else struct {};

pub const LinuxWebAuthnError = error{
    NotSupported,
    DeviceNotFound,
    DeviceOpenFailed,
    CredentialCreationFailed,
    AssertionFailed,
    InvalidResponse,
    LibraryNotAvailable,
};

/// Linux WebAuthn implementation using libfido2
pub const LinuxWebAuthn = struct {
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Check if WebAuthn is available on Linux
    pub fn isAvailable(self: *Self) bool {
        _ = self;

        if (!is_linux) return false;

        // Try to initialize libfido2
        const version = c.fido_strerr(0); // Dummy call to check if library is linked
        _ = version;

        // Check if any FIDO devices are available
        const dev_list = c.fido_dev_info_new(1);
        if (dev_list == null) return false;
        defer c.fido_dev_info_free(&dev_list, 1);

        var n_devices: usize = 0;
        const result = c.fido_dev_info_manifest(dev_list, 1, &n_devices);

        return result == c.FIDO_OK and n_devices > 0;
    }

    /// Get information about connected devices
    pub fn listDevices(self: *Self) ![]DeviceInfo {
        if (!is_linux) return LinuxWebAuthnError.NotSupported;

        const max_devices = 8;
        const dev_list = c.fido_dev_info_new(max_devices);
        if (dev_list == null) return LinuxWebAuthnError.LibraryNotAvailable;
        defer c.fido_dev_info_free(&dev_list, max_devices);

        var n_devices: usize = 0;
        const result = c.fido_dev_info_manifest(dev_list, max_devices, &n_devices);

        if (result != c.FIDO_OK) {
            return LinuxWebAuthnError.DeviceNotFound;
        }

        var devices = try self.allocator.alloc(DeviceInfo, n_devices);
        errdefer self.allocator.free(devices);

        for (0..n_devices) |i| {
            const info = c.fido_dev_info_ptr(dev_list, i);
            const path = c.fido_dev_info_path(info);
            const manufacturer = c.fido_dev_info_manufacturer_string(info);
            const product = c.fido_dev_info_product_string(info);

            devices[i] = .{
                .path = try self.allocator.dupe(u8, std.mem.span(path)),
                .manufacturer = try self.allocator.dupe(u8, std.mem.span(manufacturer)),
                .product = try self.allocator.dupe(u8, std.mem.span(product)),
            };
        }

        return devices;
    }

    /// Create a new credential (register)
    pub fn createCredential(
        self: *Self,
        rp_id: []const u8,
        user_name: []const u8,
    ) !Credential {
        if (!is_linux) return LinuxWebAuthnError.NotSupported;

        // Find first available device
        const devices = try self.listDevices();
        defer {
            for (devices) |dev| {
                self.allocator.free(dev.path);
                self.allocator.free(dev.manufacturer);
                self.allocator.free(dev.product);
            }
            self.allocator.free(devices);
        }

        if (devices.len == 0) {
            return LinuxWebAuthnError.DeviceNotFound;
        }

        // Open the device
        const dev = c.fido_dev_new();
        if (dev == null) return LinuxWebAuthnError.DeviceOpenFailed;
        defer c.fido_dev_free(&dev);

        const open_result = c.fido_dev_open(dev, devices[0].path.ptr);
        if (open_result != c.FIDO_OK) {
            return LinuxWebAuthnError.DeviceOpenFailed;
        }
        defer _ = c.fido_dev_close(dev);

        // Create credential
        const cred = c.fido_cred_new();
        if (cred == null) return LinuxWebAuthnError.CredentialCreationFailed;
        defer c.fido_cred_free(&cred);

        // Set RP
        const rp_result = c.fido_cred_set_rp(cred, rp_id.ptr, rp_id.ptr);
        if (rp_result != c.FIDO_OK) {
            return LinuxWebAuthnError.CredentialCreationFailed;
        }

        // Set user
        var user_id: [32]u8 = undefined;
        std.crypto.random.bytes(&user_id);

        const user_result = c.fido_cred_set_user(
            cred,
            &user_id,
            user_id.len,
            user_name.ptr,
            null, // display_name
            null, // icon
        );
        if (user_result != c.FIDO_OK) {
            return LinuxWebAuthnError.CredentialCreationFailed;
        }

        // Set type (ES256 for compatibility)
        const type_result = c.fido_cred_set_type(cred, c.COSE_ES256);
        if (type_result != c.FIDO_OK) {
            return LinuxWebAuthnError.CredentialCreationFailed;
        }

        // Generate and set challenge
        var challenge: [32]u8 = undefined;
        std.crypto.random.bytes(&challenge);

        const challenge_result = c.fido_cred_set_clientdata_hash(cred, &challenge, challenge.len);
        if (challenge_result != c.FIDO_OK) {
            return LinuxWebAuthnError.CredentialCreationFailed;
        }

        // Make credential (this will prompt user to touch the key)
        std.log.info("Please touch your security key to create credential...", .{});

        const make_result = c.fido_dev_make_cred(dev, cred, null);
        if (make_result != c.FIDO_OK) {
            std.log.err("Failed to create credential: {s}", .{c.fido_strerr(make_result)});
            return LinuxWebAuthnError.CredentialCreationFailed;
        }

        // Extract credential ID
        const cred_id_ptr = c.fido_cred_id_ptr(cred);
        const cred_id_len = c.fido_cred_id_len(cred);
        const cred_id = try self.allocator.dupe(u8, cred_id_ptr[0..cred_id_len]);
        errdefer self.allocator.free(cred_id);

        // Extract public key
        const pubkey_ptr = c.fido_cred_pubkey_ptr(cred);
        const pubkey_len = c.fido_cred_pubkey_len(cred);

        if (pubkey_len != 65) { // Uncompressed P-256 key
            return LinuxWebAuthnError.InvalidResponse;
        }

        var public_key: [65]u8 = undefined;
        @memcpy(&public_key, pubkey_ptr[0..65]);

        return Credential{
            .id = cred_id,
            .public_key = public_key,
            .rp_id = try self.allocator.dupe(u8, rp_id),
            .user_name = try self.allocator.dupe(u8, user_name),
        };
    }

    /// Sign data using credential (authenticate)
    pub fn sign(
        self: *Self,
        credential_id: []const u8,
        rp_id: []const u8,
        data: []const u8,
    ) !Signature {
        if (!is_linux) return LinuxWebAuthnError.NotSupported;

        // Find device
        const devices = try self.listDevices();
        defer {
            for (devices) |dev| {
                self.allocator.free(dev.path);
                self.allocator.free(dev.manufacturer);
                self.allocator.free(dev.product);
            }
            self.allocator.free(devices);
        }

        if (devices.len == 0) {
            return LinuxWebAuthnError.DeviceNotFound;
        }

        // Open device
        const dev = c.fido_dev_new();
        if (dev == null) return LinuxWebAuthnError.DeviceOpenFailed;
        defer c.fido_dev_free(&dev);

        const open_result = c.fido_dev_open(dev, devices[0].path.ptr);
        if (open_result != c.FIDO_OK) {
            return LinuxWebAuthnError.DeviceOpenFailed;
        }
        defer _ = c.fido_dev_close(dev);

        // Create assertion
        const assert = c.fido_assert_new();
        if (assert == null) return LinuxWebAuthnError.AssertionFailed;
        defer c.fido_assert_free(&assert);

        // Set RP
        const rp_result = c.fido_assert_set_rp(assert, rp_id.ptr);
        if (rp_result != c.FIDO_OK) {
            return LinuxWebAuthnError.AssertionFailed;
        }

        // Set challenge (hash of data)
        var challenge: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &challenge, .{});

        const challenge_result = c.fido_assert_set_clientdata_hash(assert, &challenge, challenge.len);
        if (challenge_result != c.FIDO_OK) {
            return LinuxWebAuthnError.AssertionFailed;
        }

        // Allow specific credential
        const allow_result = c.fido_assert_allow_cred(assert, credential_id.ptr, credential_id.len);
        if (allow_result != c.FIDO_OK) {
            return LinuxWebAuthnError.AssertionFailed;
        }

        // Get assertion (prompts user to touch key)
        std.log.info("Please touch your security key to sign...", .{});

        const assert_result = c.fido_dev_get_assert(dev, assert, null);
        if (assert_result != c.FIDO_OK) {
            std.log.err("Failed to get assertion: {s}", .{c.fido_strerr(assert_result)});
            return LinuxWebAuthnError.AssertionFailed;
        }

        // Extract signature
        const sig_ptr = c.fido_assert_sig_ptr(assert, 0);
        const sig_len = c.fido_assert_sig_len(assert, 0);

        var signature: [64]u8 = undefined; // ECDSA P-256 signature
        if (sig_len > 64) {
            return LinuxWebAuthnError.InvalidResponse;
        }
        @memset(&signature, 0);
        @memcpy(signature[0..sig_len], sig_ptr[0..sig_len]);

        // Extract authenticator data
        const authdata_ptr = c.fido_assert_authdata_ptr(assert, 0);
        const authdata_len = c.fido_assert_authdata_len(assert, 0);
        const auth_data = try self.allocator.dupe(u8, authdata_ptr[0..authdata_len]);

        return Signature{
            .signature = signature,
            .authenticator_data = auth_data,
        };
    }
};

pub const DeviceInfo = struct {
    path: []const u8,
    manufacturer: []const u8,
    product: []const u8,
};

pub const Credential = struct {
    id: []const u8,
    public_key: [65]u8, // Uncompressed P-256 public key
    rp_id: []const u8,
    user_name: []const u8,

    pub fn deinit(self: *Credential, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.rp_id);
        allocator.free(self.user_name);
    }
};

pub const Signature = struct {
    signature: [64]u8,
    authenticator_data: []const u8,

    pub fn deinit(self: *Signature, allocator: Allocator) void {
        allocator.free(self.authenticator_data);
    }
};

// Test functions
test "LinuxWebAuthn availability check" {
    const allocator = std.testing.allocator;

    var webauthn = LinuxWebAuthn.init(allocator);
    defer webauthn.deinit();

    // This will return false if no hardware key is connected
    _ = webauthn.isAvailable();
}

// Build instructions for Linux:
// 1. Install libfido2-dev: sudo apt-get install libfido2-dev
// 2. Link with: -lfido2 -lcrypto
