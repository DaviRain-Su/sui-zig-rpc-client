const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
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
}
