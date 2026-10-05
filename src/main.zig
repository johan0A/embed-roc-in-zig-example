const std = @import("std");
const builtin = @import("builtin");
const abi = @import("roc_platform_abi.zig");

pub const std_options: std.Options = .{ .allow_stack_tracing = false };

/// All host state. Global because the exported `roc_*` symbols receive no context.
const Host = struct {
    gpa: std.heap.DebugAllocator(.{}),
    stdin_buffer: [4096]u8,
    stdin_reader: std.Io.File.Reader,
    roc_env: abi.RocEnv,
    roc_host: abi.RocHost,
};

var host: Host = undefined;

fn okResult(comptime Result: type) Result {
    return std.mem.zeroInit(Result, .{ .tag = .Ok });
}

fn errResult(comptime Result: type, err: anyerror) Result {
    var r = std.mem.zeroInit(Result, .{ .tag = .Err });
    r.payload = .{ .err = abi.RocStr.fromSlice(@errorName(err), &host.roc_host) };
    return r;
}

fn writeLine(comptime Result: type, file: std.Io.File, str: abi.RocStr) Result {
    defer str.decref(&host.roc_host);
    const io = std.Io.Threaded.global_single_threaded.io();
    file.writeStreamingAll(io, str.asSlice()) catch |e| return errResult(Result, e);
    file.writeStreamingAll(io, "\n") catch |e| return errResult(Result, e);
    return okResult(Result);
}

fn hostedStdoutLine(str: abi.RocStr) callconv(.c) abi.HostStdout_lineResult {
    return writeLine(abi.HostStdout_lineResult, std.Io.File.stdout(), str);
}

fn hostedStderrLine(str: abi.RocStr) callconv(.c) abi.HostStderr_lineResult {
    return writeLine(abi.HostStderr_lineResult, std.Io.File.stderr(), str);
}

fn hostedStdinLine() callconv(.c) abi.HostStdin_lineResult {
    const Result = abi.HostStdin_lineResult;
    const reader = &host.stdin_reader.interface;

    const line = while (true) {
        break reader.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                // Skip the overlong line so the next call starts fresh.
                _ = reader.discardDelimiterInclusive('\n') catch |e| switch (e) {
                    error.EndOfStream => break "",
                    else => return errResult(Result, e),
                };
                continue;
            },
            else => return errResult(Result, err),
        } orelse "";
    };

    const trimmed = if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;

    var r = okResult(Result);
    r.payload = .{ .ok = abi.RocStr.fromSlice(trimmed, &host.roc_host) };
    return r;
}

fn hostAlloc(len: usize, alignment: usize) callconv(.c) ?*anyopaque {
    return abi.DefaultAllocators.rocAlloc(&host.roc_host, len, alignment);
}

fn hostDealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    abi.DefaultAllocators.rocDealloc(&host.roc_host, ptr, alignment);
}

fn hostRealloc(ptr: *anyopaque, len: usize, alignment: usize) callconv(.c) ?*anyopaque {
    return abi.DefaultAllocators.rocRealloc(&host.roc_host, ptr, len, alignment);
}

fn hostDbg(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocDbg(&host.roc_host, bytes, len);
}

fn hostExpectFailed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocExpectFailed(&host.roc_host, bytes, len);
}

fn hostCrashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocCrashed(&host.roc_host, bytes, len);
}

comptime {
    if (!builtin.is_test) {
        @export(&hostedStderrLine, .{ .name = "roc_stderr_line", .visibility = .hidden });
        @export(&hostedStdinLine, .{ .name = "roc_stdin_line", .visibility = .hidden });
        @export(&hostedStdoutLine, .{ .name = "roc_stdout_line", .visibility = .hidden });

        @export(&hostAlloc, .{ .name = "roc_alloc", .visibility = .hidden });
        @export(&hostDealloc, .{ .name = "roc_dealloc", .visibility = .hidden });
        @export(&hostRealloc, .{ .name = "roc_realloc", .visibility = .hidden });
        @export(&hostDbg, .{ .name = "roc_dbg", .visibility = .hidden });
        @export(&hostExpectFailed, .{ .name = "roc_expect_failed", .visibility = .hidden });
        @export(&hostCrashed, .{ .name = "roc_crashed", .visibility = .hidden });
    }
}

pub fn main(init: std.process.Init) !u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    host = .{
        .gpa = .init,
        .stdin_buffer = undefined,
        .stdin_reader = std.Io.File.stdin().readerStreaming(io, &host.stdin_buffer),
        .roc_env = .{
            .allocator = host.gpa.allocator(),
            .roc_io = abi.RocIo.default(),
        },
        .roc_host = abi.makeRocHost(&host.roc_env),
    };

    const args_list = abi.RocList(abi.RocStr).allocate(args.len, &host.roc_host);
    if (args_list.elements_ptr) |ptr| {
        for (args, ptr[0..args.len]) |arg, *slot| slot.* = abi.RocStr.fromSlice(arg, &host.roc_host);
    }

    const exit_code = abi.roc_main(args_list);

    if (host.gpa.deinit() == .leak) {
        std.log.err("\x1b[33mMemory leak detected!\x1b[0m", .{});
        return 1;
    }
    return @intCast(exit_code);
}
