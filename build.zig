const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // WebAuthn option (macOS only)
    const webauthn = b.option(bool, "webauthn", "Enable WebAuthn/Passkey support (macOS only)") orelse false;
    
    const move_fixture_paths = [_][]const u8{
        "fixtures/move/counter_baseline",
        "fixtures/move/shared_state_lab",
        "fixtures/move/generic_vault",
        "fixtures/move/vector_router",
        "fixtures/move/receipt_flow_lab",
        "fixtures/move/dynamic_registry",
        "fixtures/move/admin_upgrade_lab",
        "fixtures/move/pool_like_protocol_lab",
    };

    // Core client module
    const client_module = b.addModule("sui_client_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Executable module (original structure)
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sui_client_zig", .module = client_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "sui-zig-rpc-client",
        .root_module = exe_module,
    });

    b.installArtifact(exe);

    // New v2 executable using new API only
    const exe_v2_module = b.createModule(.{
        .root_source_file = b.path("src/main_v2.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sui_client_zig", .module = client_module },
        },
    });

    const exe_v2 = b.addExecutable(.{
        .name = "sui-zig-rpc-client-v2",
        .root_module = exe_v2_module,
    });

    // Add WebAuthn support on macOS
    if (webauthn and target.result.os.tag == .macos) {
        std.log.info("Building with WebAuthn support for macOS", .{});
        
        // Add the Objective-C object file
        exe_v2.addObjectFile(b.path("macos_bridge.o"));
        
        // Link Apple frameworks
        exe_v2.linkFramework("LocalAuthentication");
        exe_v2.linkFramework("Security");
        exe_v2.linkFramework("Foundation");
        
        // Add include path for headers
        exe_v2.addIncludePath(b.path("src/webauthn"));
        
        // Define WEBAUTHN_ENABLED for conditional compilation
        exe_v2.root_module.addCMacro("WEBAUTHN_ENABLED", "1");
    }

    b.installArtifact(exe_v2);

    // Run v2 command
    const run_v2_step = b.step("run-v2", "Run the v2 app");
    const run_v2_cmd = b.addRunArtifact(exe_v2);
    if (b.args) |args| {
        run_v2_cmd.addArgs(args);
    }
    run_v2_step.dependOn(&run_v2_cmd.step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    const move_fixture_test_step = b.step(
        "move-fixture-test",
        "Run local Move fixture matrix with `sui move test`",
    );
    for (move_fixture_paths) |fixture_path| {
        const move_test = b.addSystemCommand(&.{
            "sui",
            "move",
            "test",
            "--path",
            fixture_path,
        });
        move_fixture_test_step.dependOn(&move_test.step);
    }

    const test_step = b.step("test", "Run project tests");
    
    // Test the main module
    const tests = b.addTest(.{
        .root_module = exe_module,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(move_fixture_test_step);
    
    // WebAuthn test step (macOS only)
    if (target.result.os.tag == .macos) {
        const webauthn_test_step = b.step("test-webauthn", "Test WebAuthn bridge (macOS)");
        const webauthn_test = b.addSystemCommand(&.{
            "./test_bridge",
        });
        webauthn_test_step.dependOn(&webauthn_test.step);
    }
}
