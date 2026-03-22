/// Linux WebAuthn Implementation
/// Uses libfido2 for FIDO2/CTAP2 authenticator support

const std = @import("std");
const Allocator = std.mem.Allocator;

// libfido2 C bindings
const fido2 = @cImport({
    @cInclude("fido.h");
});

pub const LinuxWebAuthn = struct {
    allocator: Allocator,
    initialized: bool,

    pub fn init(allocator: Allocator) !LinuxWebAuthn {
        // Initialize libfido2
        fido2.fido_init(0);

        return .{
            .allocator = allocator,
            .initialized = true,
        };
    }

    pub fn deinit(self: *LinuxWebAuthn) void {
        _ = self;
    }

    /// Check if any FIDO2 authenticator is available
    pub fn isAvailable(self: *const LinuxWebAuthn) bool {
        _ = self;

        // Try to find any FIDO device
        var path: [256]u8 = undefined;
        const found = fido2.fido_dev_info_manifest(
            @ptrCast(&path),
            1,
            null,
        );

        return found > 0;
    }

    /// List available authenticators
    pub fn listAuthenticators(self: *LinuxWebAuthn) ![]AuthenticatorInfo {

        var infos: [10]fido2.fido_dev_info_t = undefined;
        var n_found: usize = 0;

        const result = fido2.fido_dev_info_manifest(
            @ptrCast(&infos),
            infos.len,
            &n_found,
        );

        if (result != fido2.FIDO_OK) {
            return error.DeviceEnumerationFailed;
        }

        var list = try self.allocator.alloc(AuthenticatorInfo, n_found);
        errdefer self.allocator.free(list);

        for (0..n_found) |i| {
            const path = fido2.fido_dev_info_path(&infos[i]);
            const manufacturer = fido2.fido_dev_info_manufacturer_string(&infos[i]);
            const product = fido2.fido_dev_info_product_string(&infos[i]);

            list[i] = .{
                .path = try self.allocator.dupe(u8, std.mem.span(path)),
                .manufacturer = try self.allocator.dupe(u8, std.mem.span(manufacturer)),
                .product = try self.allocator.dupe(u8, std.mem.span(product)),
            };
        }

        return list;
    }

    /// Create a new credential on authenticator
    pub fn makeCredential(
        self: *LinuxWebAuthn,
        rp_id: []const u8,
        user_name: []const u8,
        challenge: []const u8,
    ) !Credential {
        // Open first available device
        const dev = try self.openDevice();
        defer fido2.fido_dev_close(dev);

        // Create credential
        const cred = fido2.fido_cred_new() orelse return error.CredentialCreationFailed;
        defer fido2.fido_cred_free(&cred);

        // Set RP
        if (fido2.fido_cred_set_rp(cred, rp_id.ptr, "Sui Wallet") != fido2.FIDO_OK) {
            return error.SetRPFailed;
        }

        // Set user
        const user_id = generateUserId();
        if (fido2.fido_cred_set_user(
            cred,
            &user_id,
            user_id.len,
            user_name.ptr,
            null, // display_name
            null, // icon
        ) != fido2.FIDO_OK) {
            return error.SetUserFailed;
        }

        // Set challenge
        if (fido2.fido_cred_set_clientdata_hash(cred, challenge.ptr, challenge.len) != fido2.FIDO_OK) {
            return error.SetChallengeFailed;
        }

        // Set algorithms (ES256 for P-256)
        if (fido2.fido_cred_set_type(cred, fido2.COSE_ES256) != fido2.FIDO_OK) {
            return error.SetAlgorithmFailed;
        }

        // Make credential (user touches authenticator)
        std.log.info("Please touch your authenticator...", .{});

        if (fido2.fido_dev_make_cred(dev, cred, null) != fido2.FIDO_OK) {
            return error.MakeCredentialFailed;
        }

        // Extract credential ID
        const cred_id_ptr = fido2.fido_cred_id_ptr(cred);
        const cred_id_len = fido2.fido_cred_id_len(cred);
        const cred_id = try self.allocator.dupe(u8, cred_id_ptr[0..cred_id_len]);

        // Extract public key
        const pubkey_ptr = fido2.fido_cred_pubkey_ptr(cred);
        const pubkey_len = fido2.fido_cred_pubkey_len(cred);
        const pubkey = try self.allocator.dupe(u8, pubkey_ptr[0..pubkey_len]);

        return .{
            .id = cred_id,
            .public_key = pubkey,
            .rp_id = try self.allocator.dupe(u8, rp_id),
            .user_name = try self.allocator.dupe(u8, user_name),
        };
    }

    /// Get assertion (sign challenge)
    pub fn getAssertion(
        self: *LinuxWebAuthn,
        rp_id: []const u8,
        challenge: []const u8,
        credential_id: []const u8,
    ) !Assertion {
        // Open device
        const dev = try self.openDevice();
        defer fido2.fido_dev_close(dev);

        // Create assertion
        const assert = fido2.fido_assert_new() orelse return error.AssertionCreationFailed;
        defer fido2.fido_assert_free(&assert);

        // Set RP
        if (fido2.fido_assert_set_rp(assert, rp_id.ptr) != fido2.FIDO_OK) {
            return error.SetRPFailed;
        }

        // Set challenge
        if (fido2.fido_assert_set_clientdata_hash(assert, challenge.ptr, challenge.len) != fido2.FIDO_OK) {
            return error.SetChallengeFailed;
        }

        // Allow credential
        if (fido2.fido_assert_allow_cred(assert, credential_id.ptr, credential_id.len) != fido2.FIDO_OK) {
            return error.SetCredentialFailed;
        }

        // Get assertion (user touches authenticator)
        std.log.info("Please touch your authenticator to sign...", .{});

        if (fido2.fido_dev_get_assert(dev, assert, null) != fido2.FIDO_OK) {
            return error.GetAssertionFailed;
        }

        // Extract signature
        const sig_ptr = fido2.fido_assert_sig_ptr(assert, 0);
        const sig_len = fido2.fido_assert_sig_len(assert, 0);
        const signature = try self.allocator.dupe(u8, sig_ptr[0..sig_len]);

        // Extract authenticator data
        const authdata_ptr = fido2.fido_assert_authdata_ptr(assert, 0);
        const authdata_len = fido2.fido_assert_authdata_len(assert, 0);
        const auth_data = try self.allocator.dupe(u8, authdata_ptr[0..authdata_len]);

        return .{
            .signature = signature,
            .authenticator_data = auth_data,
        };
    }

    fn openDevice(self: *LinuxWebAuthn) !*fido2.fido_dev_t {
        _ = self;

        const dev = fido2.fido_dev_new() orelse return error.DeviceCreationFailed;
        errdefer fido2.fido_dev_free(&dev);

        // Try to open first device at /dev/hidraw0
        if (fido2.fido_dev_open(dev, "/dev/hidraw0") != fido2.FIDO_OK) {
            // Try other common paths
            const paths = [_][]const u8{
                "/dev/hidraw1",
                "/dev/hidraw2",
            };

            for (paths) |path| {
                if (fido2.fido_dev_open(dev, path) == fido2.FIDO_OK) {
                    return dev;
                }
            }

            return error.NoDeviceFound;
        }

        return dev;
    }

    fn generateUserId() [32]u8 {
        var id: [32]u8 = undefined;
        std.crypto.random.bytes(&id);
        return id;
    }
};

pub const AuthenticatorInfo = struct {
    path: []const u8,
    manufacturer: []const u8,
    product: []const u8,

    pub fn deinit(self: *AuthenticatorInfo, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.manufacturer);
        allocator.free(self.product);
    }
};

pub const Credential = struct {
    id: []const u8,
    public_key: []const u8,
    rp_id: []const u8,
    user_name: []const u8,

    pub fn deinit(self: *Credential, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.public_key);
        allocator.free(self.rp_id);
        allocator.free(self.user_name);
    }
};

pub const Assertion = struct {
    signature: []const u8,
    authenticator_data: []const u8,

    pub fn deinit(self: *Assertion, allocator: Allocator) void {
        allocator.free(self.signature);
        allocator.free(self.authenticator_data);
    }
};

// Error mapping
fn fidoErrorToZig(err: c_int) error{
    DeviceCreationFailed,
    DeviceEnumerationFailed,
    CredentialCreationFailed,
    SetRPFailed,
    SetUserFailed,
    SetChallengeFailed,
    SetAlgorithmFailed,
    MakeCredentialFailed,
    AssertionCreationFailed,
    SetCredentialFailed,
    GetAssertionFailed,
    NoDeviceFound,
} {
    _ = err;
    return error.DeviceCreationFailed;
}
