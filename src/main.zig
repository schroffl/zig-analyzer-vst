const std = @import("std");
const known_folders = @import("known-folders");
const api = @import("./api.zig");

const allocator = std.heap.page_allocator;
var log_file: ?std.fs.File = null;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = switch (message_level) {
        .emerg => "emergency",
        .alert => "alert",
        .crit => "critical",
        .err => "error",
        .warn => "warning",
        .notice => "notice",
        .info => "info",
        .debug => "debug",
    };
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    if (log_file) |file| {
        var writer = file.writer();
        writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    }
}

pub fn panic(err: []const u8, maybe_trace: ?*std.builtin.StackTrace) noreturn {
    if (log_file) |file| {
        var writer = file.writer();
        writer.writeAll("Panic: ") catch unreachable;
        writer.writeAll(err) catch unreachable;

        if (maybe_trace) |trace| writer.print("{}\n", .{trace}) catch unreachable;
    }

    while (true) {
        @breakpoint();
    }
}

export fn VSTPluginMain(callback: api.HostCallback) ?*api.AEffect {
    var effect = allocator.create(api.AEffect) catch unreachable;

    effect.* = .{
        .dispatcher = onDispatch,
        .setParameter = setParameter,
        .getParameter = getParameter,
        .processReplacing = processReplacing,
        .processReplacingF64 = processReplacingF64,

        .unique_id = 0x93843,
        .initial_delay = 0,
        .version = 0,

        .num_programs = 0,
        .num_params = 1,
        .num_inputs = 2,
        .num_outputs = 2,
        .flags = api.Plugin.Flag.toBitmask(&[_]api.Plugin.Flag{
            .CanReplacing, .HasEditor,
        }),
    };

    const cwd = std.fs.cwd();

    const desktop_path = (known_folders.getPath(allocator, .desktop) catch unreachable).?;
    const log_path = std.fs.path.join(allocator, &[_][]const u8{
        desktop_path,
        "zig-analyzer-log.txt",
    }) catch unreachable;

    log_file = cwd.createFile(log_path, .{}) catch unreachable;

    std.log.debug("\n\n===============\nCreated log file", .{});

    return effect;
}

var params = [_]f32{0};

fn onDispatch(
    effect: *api.AEffect,
    opcode: i32,
    index: i32,
    value: isize,
    ptr: ?*c_void,
    opt: f32,
) callconv(.C) isize {
    const code = api.Codes.HostToPlugin.fromInt(opcode) catch {
        std.log.warn("Unknown opcode: {}", .{opcode});
        return 0;
    };

    switch (code) {
        .GetProductName => _ = setData(u8, ptr.?, "Zig Analyzer", api.ProductNameMaxLength),
        .GetVendorName => _ = setData(u8, ptr.?, "schroffl", api.VendorNameMaxLength),
        .GetPresetName => _ = setData(u8, ptr.?, "Default", api.ProductNameMaxLength),
        .GetApiVersion => return 2400,
        .GetCategory => return api.Plugin.Category.Analysis.toI32(),
        .Initialize => {
            var plugin_ptr = allocator.create(Plugin) catch {
                std.log.crit("Failed to allocate Plugin", .{});
                return 0;
            };

            plugin_ptr.* = Plugin.init() catch |err| {
                std.log.crit("Plugin.init failed: {}", .{err});
                return 0;
            };

            effect.user = plugin_ptr;
        },
        .SetSampleRate => {
            if (Plugin.fromEffect(effect)) |plugin| plugin.sample_rate = opt;
        },
        .SetBufferSize => {
            if (Plugin.fromEffect(effect)) |plugin| {
                plugin.buffer_size = value;
                plugin.sample_buffer = allocator.alloc(f32, @intCast(usize, value * 2)) catch {
                    std.log.crit("Failed to allocate sample buffer", .{});
                    return 0;
                };
            }
        },
        .GetCurrentPresetNum => return 0,
        .GetMidiKeyName => _ = setData(u8, ptr.?, "what is this?", api.ProductNameMaxLength),
        .GetTailSize => return 1,
        .CanDo => {
            const can_do = @ptrCast([*:0]u8, ptr.?);
            std.log.debug("CanDo: {s}", .{can_do});
            return -1;
        },
        .EditorGetRect => {
            var rect = allocator.create(api.Rect) catch |err| {
                std.log.err("Failed to allocate editor rect: {}", .{err});
                return 0;
            };

            rect.top = 0;
            rect.left = 0;
            rect.right = 500;
            rect.bottom = 500;

            var rect_ptr = @ptrCast(**c_void, @alignCast(@alignOf(**c_void), ptr.?));

            rect_ptr.* = rect;

            std.log.debug("Rect: {}", .{rect});

            return 1;
        },
        .EditorOpen => {
            std.log.debug("EditorOpen: {}", .{ptr.?});

            if (Plugin.fromEffect(effect)) |plugin| {
                plugin.renderer.editorOpen(ptr.?);
            }

            return 1;
        },
        .EditorClose => {
            std.log.debug("EditorClose", .{});

            if (Plugin.fromEffect(effect)) |plugin| {
                plugin.renderer.editorClose();
            }

            return 1;
        },
        .GetParameterDisplay => {
            const val = params[@intCast(usize, index)];
            const str = std.fmt.allocPrint(allocator, "{d:.5}", .{val}) catch unreachable;
            defer allocator.free(str);
            _ = setData(u8, ptr.?, str, 64);
        },
        .GetParameterName => {
            _ = setData(u8, ptr.?, "Graph Scale", 64);
        },
        .GetParameterLabel => {
            _ = setData(u8, ptr.?, "Yo", 64);
        },
        .CanBeAutomated => return 1,
        .EditorIdle => {},
        else => {
            const t = std.time.milliTimestamp();
            std.log.debug("{d:.} Unhandled opcode: {} {} {} {} {}", .{ t, code, index, value, ptr, opt });
        },
    }

    return 0;
}

fn setParameter(effect: *api.AEffect, index: i32, parameter: f32) callconv(.C) void {
    std.log.debug("setParameter: {}", .{parameter});
    params[@intCast(usize, index)] = parameter;
}

fn getParameter(effect: *api.AEffect, index: i32) callconv(.C) f32 {
    return params[@intCast(usize, index)];
}

fn processReplacing(effect: *api.AEffect, inputs: [*][*]f32, outputs: [*][*]f32, num_frames: i32) callconv(.C) void {
    const channels = @intCast(usize, std.math.min(effect.num_inputs, effect.num_outputs));
    const frames = @intCast(usize, num_frames);

    const plugin = Plugin.fromEffect(effect).?;
    var sample_buffer = plugin.sample_buffer.?;

    var channel_i: usize = 0;

    while (channel_i < channels) : (channel_i += 1) {
        const in = inputs[channel_i][0..frames];
        var out = outputs[channel_i][0..frames];

        for (in) |v, i| {
            sample_buffer[i * channels + channel_i] = v;
            out[i] = v;
        }
    }

    plugin.renderer.update(sample_buffer);
}

fn processReplacingF64(effect: *api.AEffect, inputs: [*][*]f64, outputs: [*][*]f64, frames: i32) callconv(.C) void {
    std.log.warn("processReplacingF64 called", .{});
}

fn setData(comptime T: type, ptr: *c_void, data: []const T, max_length: usize) usize {
    const buf_ptr = @ptrCast([*]T, ptr);
    const copy_len = std.math.min(max_length - 1, data.len);

    @memcpy(buf_ptr, data.ptr, copy_len);
    std.mem.set(u8, buf_ptr[copy_len..max_length], 0);

    return copy_len;
}

const Plugin = struct {
    sample_rate: ?f32 = null,
    buffer_size: ?isize = null,

    sample_buffer: ?[]f32 = null,
    renderer: switch (std.Target.current.os.tag) {
        .macos => @import("./macos/renderer.zig").Renderer,
        else => @compileError("No renderer for target OS"),
    },

    fn init() !Plugin {
        var plugin: Plugin = undefined;

        const vst_path = try resolveVSTPath(allocator);

        plugin.renderer = try @TypeOf(plugin.renderer).init(allocator, vst_path);
        plugin.sample_rate = null;
        plugin.buffer_size = null;

        return plugin;
    }

    fn fromEffect(effect: *api.AEffect) ?*Plugin {
        const aligned = @alignCast(@alignOf(Plugin), effect.user);
        const ptr = @ptrCast(?*Plugin, aligned);

        return ptr;
    }
};

fn resolveVSTPath(alloc: *std.mem.Allocator) ![]const u8 {
    const dlfcn = @cImport({
        @cInclude("dlfcn.h");
    });

    var info: dlfcn.Dl_info = undefined;
    const success = dlfcn.dladdr(VSTPluginMain, &info);

    if (success == 1) {
        const name = @ptrCast([*:0]const u8, info.dli_fname);
        var name_slice = try alloc.alloc(u8, std.mem.len(name));
        @memcpy(name_slice.ptr, name, name_slice.len);
        return std.fs.path.dirname(name_slice) orelse return error.DirnameFailed;
    } else {
        std.log.err("dladdr returned {}", .{success});
        return error.dladdrFailed;
    }
}
