const std = @import("std");
const shared = @import("../shared.zig");

const log = std.log.scoped(.metal_renderer);
const log_objc = std.log.scoped(.metal_renderer_objc);

pub const Renderer = struct {
    allocator: *std.mem.Allocator,
    lib: *std.DynLib,
    params: *shared.Parameters,

    objc_init: fn (cb: @TypeOf(objc_log_callback), vst_path: [*:0]u8, ptr: **c_void) callconv(.C) void,
    editor_open: fn (ref: *c_void, view: *c_void) callconv(.C) void,
    editor_close: fn (ref: *c_void) callconv(.C) void,
    update_buffer: fn (ref: *c_void, ptr: [*]f32, len: usize) callconv(.C) void,

    objc_ref: *c_void = undefined,

    pub fn init(allocator: *std.mem.Allocator, params: *shared.Parameters) !Renderer {
        var self: Renderer = undefined;
        self.allocator = allocator;
        self.params = params;

        const vst_path = try resolveVSTPath(allocator);
        defer allocator.free(vst_path);

        const dynlib_name = "za-renderer.dynlib";
        const dynlib_path = try std.fs.path.join(allocator, &[_][]const u8{
            vst_path,
            dynlib_name,
        });

        self.lib = try allocator.create(std.DynLib);
        self.lib.* = try std.DynLib.open(dynlib_path);

        const lookup_names = &[_][]const u8{
            "editor_open",
            "editor_close",
            "objc_init",
            "update_buffer",
        };

        inline for (lookup_names) |name| {
            const idx = std.meta.fieldIndex(Renderer, name).?;
            const info = std.meta.fields(Renderer)[idx];

            @field(self, name) = self.lib.lookup(info.field_type, name ++ "\x00") orelse return error.MissingExport;
        }

        const c_str = try allocator.allocSentinel(u8, vst_path.len, 0);
        std.mem.copy(u8, c_str, vst_path);
        self.objc_init(objc_log_callback, c_str, &self.objc_ref);

        return self;
    }

    pub fn editorOpen(self: *Renderer, view_ptr: *c_void) anyerror!void {
        self.editor_open(self.objc_ref, view_ptr);
    }

    pub fn editorClose(self: *Renderer) void {
        self.editor_close(self.objc_ref);
    }

    pub fn update(self: *Renderer, buffer: []f32) void {
        self.update_buffer(self.objc_ref, buffer.ptr, buffer.len);
    }

    fn objc_log_callback(data: [*c]const u8) callconv(.C) void {
        log_objc.debug("{s}", .{data});
    }
};

export fn __analyzer_macos_dummy_export() void {}

fn resolveVSTPath(allocator: *std.mem.Allocator) ![]const u8 {
    const dlfcn = @cImport({
        @cInclude("dlfcn.h");
    });

    var info: dlfcn.Dl_info = undefined;
    const success = dlfcn.dladdr(__analyzer_macos_dummy_export, &info);

    if (success == 1) {
        const name = @ptrCast([*:0]const u8, info.dli_fname);
        var name_slice = try allocator.alloc(u8, std.mem.len(name));
        @memcpy(name_slice.ptr, name, name_slice.len);
        return std.fs.path.dirname(name_slice) orelse return error.DirnameFailed;
    } else {
        std.log.err("dladdr returned {}", .{success});
        return error.dladdrFailed;
    }
}
