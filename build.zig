const std = @import("std");
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const step_test = b.step("test", "Run All Tests in src/test");
    const this_module = b.addModule("image", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/root.zig"),
    });
    const lib_test = b.addTest(.{
        .target = target,
        .optimize = optimize,
        .root_module = this_module,
    });
    const lib_test_run = b.addRunArtifact(lib_test);
    step_test.dependOn(&lib_test_run.step);
}
