const std = @import("std");
const known_folders = @import("known-folders");
const api = @import("./api.zig");
const shared = @import("./shared.zig");

const allocator = std.heap.page_allocator;
var log_file: ?std.fs.File = null;
var log_writer: ?std.fs.File.Writer = null;

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

    if (log_writer) |writer| {
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
        .num_params = shared.Parameters.count,
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
    log_writer = log_file.?.writer();

    std.log.debug("\n\n===============\nCreated log file", .{});

    return effect;
}

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

            Plugin.init(plugin_ptr) catch |err| {
                std.log.crit("Plugin.init failed: {}", .{err});
                return 0;
            };

            effect.user = plugin_ptr;
        },
        .SetSampleRate => {
            std.log.debug("Sample rate: {}", .{opt});
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
            rect.right = 900;
            rect.bottom = 900;

            var rect_ptr = @ptrCast(**c_void, @alignCast(@alignOf(**c_void), ptr.?));
            rect_ptr.* = rect;

            return 1;
        },
        .EditorOpen => {
            std.log.debug("EditorOpen: {}", .{ptr.?});

            if (Plugin.fromEffect(effect)) |plugin| {
                plugin.renderer.editorOpen(ptr.?) catch unreachable;
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
            std.log.debug("GetParameterDisplay for {}", .{index});

            if (Plugin.fromEffect(effect)) |plugin| {
                var out: [api.ParamMaxLength]u8 = undefined;
                const str = plugin.params.displayByIndex(@intCast(usize, index), &out) orelse "Unknown";
                _ = setData(u8, ptr.?, str, out.len);
            } else {
                _ = setData(u8, ptr.?, "Unknown", api.ParamMaxLength);
            }
        },
        .GetParameterName => {
            if (shared.Parameters.getDescription(@intCast(usize, index))) |desc| {
                _ = setData(u8, ptr.?, desc.name, api.ParamMaxLength);
            } else {
                _ = setData(u8, ptr.?, "Unknown", api.ParamMaxLength);
            }
        },
        .GetParameterLabel => {
            if (shared.Parameters.getDescription(@intCast(usize, index))) |desc| {
                _ = setData(u8, ptr.?, desc.label, api.ParamMaxLength);
            } else {
                _ = setData(u8, ptr.?, "Unknown", api.ParamMaxLength);
            }
        },
        .CanBeAutomated => {
            const desc = shared.Parameters.getDescription(@intCast(usize, index)) orelse return 0;
            return if (desc.automatable) 1 else 0;
        },
        .EditorKeyDown, .EditorKeyUp, .EditorIdle => {},
        else => {
            const t = std.time.milliTimestamp();
            std.log.debug("{d:.} Unhandled opcode: {} {} {} {} {}", .{ t, code, index, value, ptr, opt });
        },
    }

    return 0;
}

fn setParameter(effect: *api.AEffect, index: i32, parameter: f32) callconv(.C) void {
    const plugin = Plugin.fromEffect(effect) orelse return;
    plugin.params.setByIndex(@intCast(usize, index), parameter);
}

fn getParameter(effect: *api.AEffect, index: i32) callconv(.C) f32 {
    const plugin = Plugin.fromEffect(effect) orelse return 0;
    return plugin.params.getByIndex(@intCast(usize, index)) orelse 0;
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
    params: shared.Parameters,
    editor: @import("./editor.zig"),

    sample_buffer: ?[]f32 = null,
    renderer: switch (std.Target.current.os.tag) {
        .macos => @import("./macos/renderer.zig").Renderer,
        .windows => @import("./windows/gl_wrapper.zig").Renderer,
        else => @compileError("There's no renderer for the target platform"),
    },

    fn init(plugin: *Plugin) !void {
        plugin.params = shared.Parameters{};
        plugin.sample_rate = null;
        plugin.buffer_size = null;
        plugin.editor = .{
            .params = &plugin.params,
        };

        plugin.renderer = switch (std.Target.current.os.tag) {
            .macos => try @import("./macos/renderer.zig").Renderer.init(allocator, &plugin.editor.params),
            .windows => try @import("./windows/gl_wrapper.zig").Renderer.init(allocator, &plugin.editor),
            else => unreachable,
        };
    }

    fn fromEffect(effect: *api.AEffect) ?*Plugin {
        const aligned = @alignCast(@alignOf(Plugin), effect.user);
        const ptr = @ptrCast(?*Plugin, aligned);

        return ptr;
    }
};

test {
    _ = @import("./util/matrix.zig");
    std.testing.refAllDecls(@This());
}
