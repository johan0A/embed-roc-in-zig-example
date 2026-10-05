const std = @import("std");
const zon = @import("build.zig.zon");

const RocTarget = enum {
    x64mac,
    x64win,
    x64musl,
    arm64mac,
    arm64musl,

    fn toZigTarget(self: RocTarget) std.Target.Query {
        return switch (self) {
            .x64mac => .{ .cpu_arch = .x86_64, .os_tag = .macos },
            .x64win => .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
            .x64musl => .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
            .arm64mac => .{ .cpu_arch = .aarch64, .os_tag = .macos },
            .arm64musl => .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        };
    }

    fn appLibName(self: RocTarget) []const u8 {
        return switch (self) {
            .x64win => "app.lib",
            else => "libapp.a",
        };
    }

    fn fromZigTarget(target: std.Target) !RocTarget {
        return switch (target.os.tag) {
            .macos => switch (target.cpu.arch) {
                .x86_64 => .x64mac,
                .aarch64 => .arm64mac,
                else => error.UnsupportedTarget,
            },
            .linux => switch (target.cpu.arch) {
                .x86_64 => .x64musl,
                .aarch64 => .arm64musl,
                else => error.UnsupportedTarget,
            },
            .windows => switch (target.cpu.arch) {
                .x86_64 => .x64win,
                else => error.UnsupportedTarget,
            },
            else => error.UnsupportedTarget,
        };
    }
};

pub fn build(b: *std.Build) !void {
    const target_option = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const roc_exe = b.option([]const u8, "roc", "Path to the roc compiler") orelse "roc";

    const roc_target = try RocTarget.fromZigTarget(target_option.result);

    const roc_build = b.addSystemCommand(&.{ roc_exe, "build" });
    roc_build.addFileArg(b.path("src/main.roc"));
    roc_build.addArg(b.fmt("--target={s}", .{@tagName(roc_target)}));
    const app_lib = roc_build.addPrefixedOutputFileArg("--output=", roc_target.appLibName());
    for ([_][]const u8{
        "src/platform/main.roc",
        "src/platform/Host.roc",
        "src/platform/Stdout.roc",
        "src/platform/Stderr.roc",
        "src/platform/Stdin.roc",
    }) |path| roc_build.addFileInput(b.path(path));

    const exe = b.addExecutable(.{
        .name = @tagName(zon.name),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(roc_target.toZigTarget()),
            .optimize = optimize,
        }),
    });
    exe.root_module.addObjectFile(app_lib);
    b.installArtifact(exe);

    {
        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());
        if (b.args) |args| run.addArgs(args);
        b.step("run", "").dependOn(&run.step);
    }
}
