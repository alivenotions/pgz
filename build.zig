const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ==========================================================================
    // Library Module
    // ==========================================================================

    const lib_mod = b.addModule("pgz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ==========================================================================
    // CLI Executable
    // ==========================================================================

    const exe = b.addExecutable(.{
        .name = "pgz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    // Run command: `zig build run -- <args>`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the pgz CLI");
    run_step.dependOn(&run_cmd.step);

    // ==========================================================================
    // Tests
    // ==========================================================================

    // Library tests
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Executable tests
    const exe_unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // Individual module tests for faster iteration
    const types_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/types.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_types_tests = b.addRunArtifact(types_tests);
    const test_types_step = b.step("test-types", "Run types.zig tests");
    test_types_step.dependOn(&run_types_tests.step);

    const crc_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/crc32c.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_crc_tests = b.addRunArtifact(crc_tests);
    const test_crc_step = b.step("test-crc", "Run crc32c.zig tests");
    test_crc_step.dependOn(&run_crc_tests.step);

    // ==========================================================================
    // Formatting
    // ==========================================================================

    const fmt_step = b.step("fmt", "Format source code");
    const fmt = b.addFmt(.{
        .paths = &.{"src"},
    });
    fmt_step.dependOn(&fmt.step);

    const fmt_check_step = b.step("fmt-check", "Check source code formatting");
    const fmt_check = b.addFmt(.{
        .paths = &.{"src"},
        .check = true,
    });
    fmt_check_step.dependOn(&fmt_check.step);
}
