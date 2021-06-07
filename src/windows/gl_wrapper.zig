const std = @import("std");
const GL = @import("../util/opengl.zig");
const Ring = @import("../util/ring.zig");
const shared = @import("../shared.zig");
const zigimg = @import("zigimg");
const UI = @import("../util/ui.zig");
const GLRenderer = @import("../gl_renderer.zig");
const Editor = @import("../editor.zig");

usingnamespace std.os.windows;

const ProcedureData = struct {
    var wndproc_atom_ptr: ?LPCSTR = null;

    msg_queue: *MessageQueue,
    old_wnd_proc: LONG_PTR,
};

const Message = union(enum) {
    MouseMove: UI.MousePos,
    MouseDown: void,
    MouseUp: void,
    KeyDown: usize,
    KeyUp: usize,
};

const DraggingInfo = struct {
    start: UI.MousePos,
    current: UI.MousePos,
    ui_id: u32,
};

const MessageQueue = std.fifo.LinearFifo(Message, .Dynamic);

pub const Renderer = struct {
    allocator: *std.mem.Allocator,
    thread: ?*std.Thread = null,
    should_close: bool = false,
    ring: Ring,
    images: ?GLRenderer.Images = null,
    editor: *Editor,
    msg_queue: MessageQueue,

    pub fn init(allocator: *std.mem.Allocator, editor: *Editor) !Renderer {
        return Renderer{
            .allocator = allocator,
            .ring = try Ring.init(allocator, 65536),
            .msg_queue = MessageQueue.init(allocator),
            .editor = editor,
        };
    }

    pub fn editorOpen(self: *Renderer, ptr: *c_void) !void {
        const hwnd = @ptrCast(HWND, ptr);
        self.thread = try std.Thread.spawn(renderLoop, .{
            .self = self,
            .hwnd = hwnd,
        });
    }

    pub fn editorClose(self: *Renderer) void {
        if (self.thread) |thread| {
            self.should_close = true;
            thread.wait();
            self.thread = null;
            self.should_close = false;
        }
    }

    pub fn update(self: *Renderer, buffer: []f32) void {
        self.ring.write(buffer);
    }

    const RenderArgs = struct {
        self: *Renderer,
        hwnd: HWND,
    };

    fn renderLoop(args: RenderArgs) !void {
        const self = args.self;
        const hwnd = args.hwnd;

        var proc_data = ProcedureData{
            .msg_queue = &self.msg_queue,
            .old_wnd_proc = GetWindowLongPtrA(hwnd, GWLP_WNDPROC),
        };

        if (ProcedureData.wndproc_atom_ptr == null) {
            const atom = GlobalAddAtomA("zig-analyzer-wndproc-storage");

            // High word needs to be all 0 and the low word needs to be the atom identifier.
            const atom_ptr_int = @as(usize, atom & 0xffff);
            ProcedureData.wndproc_atom_ptr = @intToPtr([*:0]const CHAR, atom_ptr_int);
        }

        if (SetPropA(hwnd, ProcedureData.wndproc_atom_ptr.?, @ptrCast(*c_void, &proc_data)) != TRUE) {
            std.log.crit("SetPropA failed", .{});
        }

        const proc_ptr = @intCast(isize, @ptrToInt(customWindowProcedure));
        if (SetWindowLongPtrA(hwnd, GWLP_WNDPROC, proc_ptr) == 0) {
            std.log.crit("Failed to set the custom window procedure: {}", .{GetLastError()});
        }

        defer {
            if (SetWindowLongPtrA(hwnd, GWLP_WNDPROC, proc_data.old_wnd_proc) == 0) {
                std.log.debug("Failed to reset the window procedure: {}", .{GetLastError()});
            }
        }

        var instance = try wglSetup(self.allocator, hwnd);
        defer instance.deinit();
        _ = instance.makeCurrent();

        var opengl = try instance.loadFunctions();
        self.images = self.images orelse try self.loadImages();

        var gl_renderer = try GLRenderer.init(self.allocator, &opengl, &self.ring, self.images.?);
        defer gl_renderer.deinit();

        const viewport = GLRenderer.Viewport{ .width = 900, .height = 900 };
        gl_renderer.resize(viewport);

        const time_ms = 800;
        const frame_count = 48_000 * (time_ms / @as(f64, 1000.0));
        gl_renderer.gpu_ring.resize(@floatToInt(usize, frame_count) * 2);

        var mouse_pos: UI.MousePos = .{ .x = 0, .y = 0 };
        var mouse_down: bool = false;
        var dragging: ?DraggingInfo = null;

        while (!self.should_close) {
            var mouse_moved_this_frame = false;
            var mouse_down_this_frame = false;

            while (self.msg_queue.readItem()) |msg| switch (msg) {
                .KeyDown => |code| switch (code) {
                    84 => {
                        const mode = self.editor.lissajous_mode;
                        const mode_int = @enumToInt(mode);
                        var new_int = mode_int + 1;

                        if (new_int >= comptime std.meta.fields(Editor.LissajousMode).len) {
                            new_int = 0;
                        }

                        self.editor.lissajous_mode = @intToEnum(Editor.LissajousMode, new_int);
                    },
                    else => {},
                },
                .MouseMove => |move_pos| {
                    mouse_pos = move_pos;
                    mouse_moved_this_frame = true;
                },
                .MouseDown => {
                    mouse_down = true;
                    mouse_down_this_frame = true;
                },
                .MouseUp => {
                    mouse_down = false;
                    dragging = null;
                },
                else => {},
            };

            const picked_id = gl_renderer.render(self.editor.*, viewport, mouse_pos);

            if (dragging) |*drag_info| {
                drag_info.current = mouse_pos;
                std.log.debug("{}", .{drag_info});
            } else if (mouse_down and mouse_moved_this_frame and picked_id != null) {
                dragging = DraggingInfo{
                    .start = mouse_pos,
                    .current = mouse_pos,
                    .ui_id = picked_id.?,
                };
            } else if (mouse_down_this_frame and picked_id != null) {
                std.log.debug("Clicked {}", .{picked_id.?});
            }

            _ = instance.swapBuffers();
        }

        std.log.debug("Cleanup", .{});
    }

    fn loadImages(self: *Renderer) !GLRenderer.Images {
        var img = try zigimg.Image.fromMemory(self.allocator, @embedFile("../../resources/scale.png"));
        var pixels = img.pixels orelse return error.ImageNoPixels;
        var buffer = try self.allocator.alloc(u8, pixels.len() * 4);
        var it = img.iterator();

        var i: usize = 0;

        while (it.next()) |value| {
            buffer[i] = @floatToInt(u8, std.math.floor(value.R * 255));
            buffer[i + 1] = @floatToInt(u8, std.math.floor(value.G * 255));
            buffer[i + 2] = @floatToInt(u8, std.math.floor(value.B * 255));
            buffer[i + 3] = @floatToInt(u8, std.math.floor(value.A * 255));
            i += 4;
        }

        return GLRenderer.Images{
            .scale = buffer,
        };
    }
};

fn customWindowProcedure(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) LRESULT {
    var proc_data = getProcDataProp(hwnd);
    var msg_queue = proc_data.msg_queue;

    switch (msg) {
        0x100 => {
            msg_queue.writeItem(.{ .KeyDown = wparam }) catch unreachable;
        },
        0x101 => {
            msg_queue.writeItem(.{ .KeyUp = wparam }) catch unreachable;
        },
        512 => {
            const lo = @bitCast(i16, @intCast(u16, lparam & 0xffff));
            const hi = @bitCast(i16, @intCast(u16, (lparam >> 16) & 0xffff));

            const mouse_pos = UI.MousePos{ .x = lo, .y = hi };
            msg_queue.writeItem(.{ .MouseMove = mouse_pos }) catch unreachable;
        },
        513 => {
            msg_queue.writeItem(.{ .MouseDown = {} }) catch unreachable;
        },
        514 => {
            msg_queue.writeItem(.{ .MouseUp = {} }) catch unreachable;
        },
        else => {},
    }

    const old_proc = @intToPtr(WNDPROC, @intCast(usize, proc_data.old_wnd_proc));
    return CallWindowProcA(old_proc, hwnd, msg, wparam, lparam);
}

fn getProcDataProp(hwnd: HWND) *ProcedureData {
    const handle = GetPropA(hwnd, ProcedureData.wndproc_atom_ptr.?);
    const aligned_ptr = @alignCast(@alignOf(ProcedureData), handle);

    return @ptrCast(*ProcedureData, aligned_ptr);
}

extern "user32" fn GetDC(hwnd: HWND) HDC;
extern "user32" fn GetWindowLongPtrA(HWND, c_int) LONG_PTR;
extern "user32" fn CallWindowProcA(WNDPROC, HWND, UINT, WPARAM, LPARAM) LRESULT;
extern "user32" fn SetWindowLongPtrA(HWND, c_int, LONG_PTR) LONG_PTR;
extern "user32" fn GlobalAddAtomA(LPCSTR) ATOM;
extern "user32" fn SetPropA(HWND, LPCSTR, HANDLE) BOOL;
extern "user32" fn GetPropA(HWND, LPCSTR) HANDLE;

extern "gdi32" fn ChoosePixelFormat(hdc: HDC, ppfd: *const PixelFormatDescriptor) c_int;
extern "gdi32" fn SetPixelFormat(hdc: HDC, format: c_int, ppfd: *const PixelFormatDescriptor) BOOL;

extern "opengl32" fn wglCreateContext(hdc: HDC) ?HGLRC;
extern "opengl32" fn wglDeleteContext(HGLRC) BOOL;
extern "opengl32" fn wglMakeCurrent(hdc: HDC, glrc: ?HGLRC) BOOL;
extern "opengl32" fn wglGetProcAddress(name: LPCSTR) ?*c_void;
extern "opengl32" fn SwapBuffers(hdc: HDC) BOOL;

extern fn SetLastError(DWORD) void;
extern fn GetLastError() DWORD;

const WNDPROC = fn (hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.C) LRESULT;
const GWLP_WNDPROC = -4;

const PixelFormatDescriptor = extern struct {
    Size: WORD,
    Version: WORD,
    wFlags: DWORD,
    PixelType: BYTE,
    ColorBits: BYTE,
    RedBits: BYTE,
    RedShift: BYTE,
    GreenBits: BYTE,
    GreenShift: BYTE,
    BlueBits: BYTE,
    BlueShift: BYTE,
    AlphaBits: BYTE,
    AlphaShift: BYTE,
    AccumBits: BYTE,
    AccumRedBits: BYTE,
    AccumGreenBits: BYTE,
    AccumBlueBits: BYTE,
    AccumAlphaBits: BYTE,
    DepthBits: BYTE,
    StencilBits: BYTE,
    AuxBuffers: BYTE,
    LayerType: BYTE,
    Reserved: BYTE,
    wLayerMask: DWORD,
    wVisibleMask: DWORD,
    wDamageMask: DWORD,
};

const PFD_DRAW_TO_WINDOW: DWORD = 4;
const PFD_SUPPORT_OPENGL: DWORD = 32;
const PFD_DOUBLEBUFFER: DWORD = 1;
const PFD_TYPE_RGBA: DWORD = 0;
const PFD_MAIN_PLANE: DWORD = 1;

const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;
const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;

fn wglSetup(allocator: *std.mem.Allocator, hwnd: HWND) !Instance {
    const pfd = PixelFormatDescriptor{
        .Size = @sizeOf(PixelFormatDescriptor),
        .Version = 1,
        .wFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
        .PixelType = PFD_TYPE_RGBA,
        .ColorBits = 32,
        .RedBits = 0,
        .RedShift = 0,
        .GreenBits = 0,
        .GreenShift = 0,
        .BlueBits = 0,
        .BlueShift = 0,
        .AlphaBits = 0,
        .AlphaShift = 0,
        .AccumBits = 0,
        .AccumRedBits = 0,
        .AccumGreenBits = 0,
        .AccumBlueBits = 0,
        .AccumAlphaBits = 0,
        .DepthBits = 24,
        .StencilBits = 8,
        .AuxBuffers = 0,
        .LayerType = PFD_MAIN_PLANE,
        .Reserved = 0,
        .wLayerMask = 0,
        .wVisibleMask = 0,
        .wDamageMask = 0,
    };

    const hdc = GetDC(hwnd);
    const pixel_format = ChoosePixelFormat(hdc, &pfd);

    if (pixel_format == 0) {
        return error.PixelFormatIsZero;
    }

    if (SetPixelFormat(hdc, pixel_format, &pfd) == FALSE) {
        return error.SetPixelFormatFailed;
    }

    var gl_lib = try std.DynLib.open("opengl32.dll");
    const gl_ctx = wglCreateContext(hdc) orelse return error.wglCreateContextFailed;
    defer std.debug.assert(wglDeleteContext(gl_ctx) == TRUE);

    if (wglMakeCurrent(hdc, gl_ctx) == FALSE) return error.wglMakeCurrentFailed;

    const wglCreateContextAttribsARB = getOpenGLProc(fn (HDC, ?HGLRC, ?[*:0]const i32) ?HGLRC, "wglCreateContextAttribsARB").?;

    _ = setupSwapInterval(&gl_lib, hdc);

    const attribs = [_]i32{
        WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
        WGL_CONTEXT_MINOR_VERSION_ARB, 3,
        WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
    } ++ [_]i32{0};

    const c_attribs = @ptrCast([*:0]const i32, &attribs);
    const modern_ctx = wglCreateContextAttribsARB(hdc, null, c_attribs) orelse return error.CreateContextARBNull;

    if (wglMakeCurrent(hdc, modern_ctx) == FALSE) return error.wglMakeModernCurrentFailed;

    return Instance{
        .allocator = allocator,
        .hdc = hdc,
        .ctx = modern_ctx,
        .dynlib = gl_lib,
    };
}

fn setupSwapInterval(gl_lib: *std.DynLib, hdc: HDC) bool {
    const glGetString = gl_lib.lookup(fn (GL.Enum) [*:0]GL.char, "glGetString").?;
    const wglGetExtensionsStringARB = getOpenGLProc(fn (HDC) [*:0]u8, "wglGetExtensionsStringARB").?;

    const extensions = std.mem.span(glGetString(GL.EXTENSIONS));
    const wgl_extensions = std.mem.span(wglGetExtensionsStringARB(hdc));

    const ext_supported = std.mem.indexOf(u8, extensions, "WGL_EXT_swap_control") != null;
    const wgl_ext_supported = std.mem.indexOf(u8, wgl_extensions, "WGL_EXT_swap_control") != null;

    if (ext_supported and wgl_ext_supported) {
        const wglSwapIntervalEXT = getOpenGLProc(fn (c_int) BOOL, "wglSwapIntervalEXT").?;
        return wglSwapIntervalEXT(1) == TRUE;
    }

    return false;
}

fn getOpenGLProc(comptime T: type, name: [*:0]const u8) ?T {
    const ptr = wglGetProcAddress(name) orelse return null;
    return @ptrCast(T, ptr);
}

const Instance = struct {
    allocator: *std.mem.Allocator,
    dynlib: std.DynLib,
    hdc: HDC,
    ctx: HGLRC,

    pub fn deinit(self: *Instance) void {
        self.dynlib.close();

        if (wglDeleteContext(self.ctx) != TRUE) std.log.crit("wglDeleteContext failed", .{});
    }

    pub fn makeCurrent(self: *Instance) bool {
        return wglMakeCurrent(self.hdc, self.ctx) == TRUE;
    }

    pub fn swapBuffers(self: *Instance) bool {
        return SwapBuffers(self.hdc) == TRUE;
    }

    pub fn loadFunctions(self: *Instance) !GL {
        var gl: GL = undefined;
        var success: bool = true;

        inline for (std.meta.fields(GL)) |field| {
            const info = @typeInfo(field.field_type);

            switch (info) {
                .Fn => {
                    var buf = try self.allocator.allocSentinel(u8, field.name.len, 0);
                    defer self.allocator.free(buf);
                    std.mem.copy(u8, buf, field.name);
                    buf[buf.len] = 0;

                    if (getOpenGLProc(field.field_type, buf)) |fn_ptr| {
                        @field(gl, field.name) = fn_ptr;
                    } else if (self.dynlib.lookup(field.field_type, buf)) |fn_ptr| {
                        @field(gl, field.name) = fn_ptr;
                    } else {
                        std.log.crit("Unable to get a valid pointer for '{s}'", .{field.name});
                        success = false;
                    }
                },
                else => {},
            }
        }

        return if (success) gl else error.UnableToGetAllFunctions;
    }
};
