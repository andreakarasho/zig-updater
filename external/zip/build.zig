const builtin = @import("builtin");
const std = @import("std");

pub fn build(_: *std.Build) !void {}

pub const Package = struct {
    module: *std.Build.Module,
    lib: *std.Build.CompileStep,
};

pub fn package(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
    _: struct {},
) Package {
    const module = b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/zip.zig" },
    });

    const zip_lib = b.addStaticLibrary(.{
        .name = "zip",
        .target = target,
        .optimize = optimize,
    });

    const c_flags = [_][]const u8{ "-std=c99", "-fno-sanitize=undefined" };
    zip_lib.addCSourceFile(.{ .file = .{ .path = "external/zip/src/zip.c" }, .flags = &c_flags });
    zip_lib.linkLibC();
    zip_lib.addIncludePath(.{ .path = "external/zip/src" });

    return .{ .module = module, .lib = zip_lib };
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
