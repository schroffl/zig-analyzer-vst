const std = @import("std");
const GL = @import("../util/opengl.zig");
const Ring = @import("../util/ring.zig");
const shared = @import("../shared.zig");

usingnamespace std.os.windows;

const GPURing = struct {
    buffer: GL.uint,
    opengl: GL,
    max_capacity: usize = 0,
    allocated: usize = 0,
    write_index: usize = 0,
    read_index: usize = 0,

    pub fn init(buffer: GL.uint, opengl: GL) GPURing {
        return .{
            .buffer = buffer,
            .opengl = opengl,
        };
    }

    pub fn resize(self: *GPURing, num_samples: usize) void {
        if (num_samples > self.allocated) {
            const byte_size = @intCast(GL.sizei, @sizeOf(f32) * num_samples);

            self.opengl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.buffer });
            self.opengl.callCheckError("glBufferData", .{ GL.ARRAY_BUFFER, byte_size, null, GL.DYNAMIC_DRAW });

            self.allocated = num_samples;
        }

        self.max_capacity = num_samples;
        self.write_index %= self.max_capacity;
        self.read_index %= self.max_capacity;
    }

    pub fn update(self: *GPURing, data: []const f32) void {
        const writable = if (data.len > self.max_capacity) data[data.len - self.max_capacity ..] else data;
        var left = writable;

        self.opengl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.buffer });

        while (left.len > 0) {
            const required = left.len;
            const write_head = self.write_index % self.max_capacity;
            const space_left = self.max_capacity - write_head;

            const actual_length = std.math.min(required, space_left);
            const able_to_write = left[0..actual_length];
            left = left[actual_length..];

            const byte_offset = @intCast(GL.sizei, @sizeOf(f32) * write_head);
            const byte_size = @intCast(GL.sizei, @sizeOf(f32) * able_to_write.len);
            self.opengl.callCheckError("glBufferSubData", .{ GL.ARRAY_BUFFER, byte_offset, byte_size, &able_to_write[0] });

            self.write_index += actual_length;
        }
    }

    pub fn copyFromRing(self: *GPURing, ring: *Ring) void {
        const result = ring.readSlice();

        self.update(result.first);
        if (result.second) |second| self.update(second);
    }
};

pub const Renderer = struct {
    allocator: *std.mem.Allocator,
    thread: ?*std.Thread = null,
    should_close: bool = false,
    ring: Ring,
    params: *shared.Parameters,

    pub fn init(allocator: *std.mem.Allocator, params: *shared.Parameters) !Renderer {
        return Renderer{
            .allocator = allocator,
            .ring = try Ring.init(allocator, 65536),
            .params = params,
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

        var instance = try wglSetup(self.allocator, hwnd);
        defer instance.deinit();
        _ = instance.makeCurrent();

        var opengl = try instance.loadFunctions();

        const program = opengl.glCreateProgram();
        const vsh = try makeShader(self.allocator, opengl, GL.VERTEX_SHADER, vshader);
        const fsh = try makeShader(self.allocator, opengl, GL.FRAGMENT_SHADER, fshader);

        opengl.glAttachShader(program, vsh);
        opengl.glAttachShader(program, fsh);
        opengl.glLinkProgram(program);

        var link_status: GL.int = undefined;
        opengl.glGetProgramiv(program, GL.LINK_STATUS, &link_status);

        if (link_status != GL.GL_TRUE) {
            var log_len: GL.int = undefined;
            opengl.glGetProgramiv(program, GL.INFO_LOG_LENGTH, &log_len);

            var log = try self.allocator.alloc(u8, @intCast(usize, log_len));
            defer self.allocator.free(log);

            var out_len: GL.int = undefined;
            opengl.glGetProgramInfoLog(program, log_len, &out_len, log.ptr);

            std.log.err("Failed to link program: {s}", .{log});
            return error.FailedToLinkProgram;
        }

        opengl.glUseProgram(program);

        const nf_location = opengl.callCheckError("glGetUniformLocation", .{ program, "num_frames" });
        const ds_location = opengl.callCheckError("glGetUniformLocation", .{ program, "dot_size" });
        const dc_location = opengl.callCheckError("glGetUniformLocation", .{ program, "dot_color" });
        const gs_location = opengl.callCheckError("glGetUniformLocation", .{ program, "graph_scale" });

        const tri = [_]f32{
            -1, -1,
            -1, 1,
            1,  1,
            1,  -1,
        };

        var vaos: [1]GL.uint = undefined;
        opengl.callCheckError("glGenVertexArrays", .{ 1, &vaos });
        opengl.callCheckError("glBindVertexArray", .{vaos[0]});

        var buffers: [2]GL.uint = undefined;
        opengl.callCheckError("glGenBuffers", .{ buffers.len, &buffers });

        opengl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, buffers[0] });
        opengl.callCheckError("glBufferData", .{ GL.ARRAY_BUFFER, tri.len * @sizeOf(f32), &tri, GL.STATIC_DRAW });
        opengl.callCheckError("glEnableVertexAttribArray", .{0});
        opengl.callCheckError("glVertexAttribPointer", .{ 0, 2, GL.GL_FLOAT, GL.GL_FALSE, 0, null });
        opengl.callCheckError("glVertexAttribDivisor", .{ 0, 0 });

        opengl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, buffers[1] });
        opengl.callCheckError("glBufferData", .{ GL.ARRAY_BUFFER, 16 * @sizeOf(f32), null, GL.STATIC_DRAW });
        opengl.callCheckError("glEnableVertexAttribArray", .{1});
        opengl.callCheckError("glVertexAttribPointer", .{ 1, 2, GL.GL_FLOAT, GL.GL_FALSE, @sizeOf(f32) * 2, null });
        opengl.callCheckError("glVertexAttribDivisor", .{ 1, 1 });

        var gpu_ring = GPURing.init(buffers[1], opengl);
        gpu_ring.resize(48_000 * 1);

        std.log.crit("GPU Ring has a size of {} samples ({} bytes)", .{ gpu_ring.allocated, gpu_ring.allocated * @sizeOf(f32) });

        opengl.glDisable(GL.DEPTH_TEST);
        opengl.glEnable(GL.CULL_FACE);
        opengl.glEnable(GL.BLEND);
        opengl.glCullFace(GL.BACK);
        opengl.glBlendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA);

        opengl.callCheckError("glUniform3f", .{ dc_location, 0.572, 0.909, 0.266 });

        while (!self.should_close) {
            gpu_ring.copyFromRing(&self.ring);

            opengl.glClearColor(0, 0, 0, 1);
            opengl.glClear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT);

            const num_frames = gpu_ring.max_capacity / 2;

            opengl.callCheckError("glUniform1f", .{ ds_location, self.params.get("Point Size") });
            opengl.callCheckError("glUniform1f", .{ gs_location, self.params.get("Graph Scale") });
            opengl.callCheckError("glUniform1f", .{ nf_location, @intToFloat(f32, num_frames) });
            opengl.callCheckError("glDrawArraysInstanced", .{ GL.TRIANGLE_FAN, 0, 6, @intCast(GL.sizei, num_frames) });

            _ = instance.swapBuffers();
        }

        std.log.debug("Running cleanup", .{});
    }
};

fn makeShader(allocator: *std.mem.Allocator, opengl: GL, shader_type: GL.Enum, source: []const u8) !GL.uint {
    const shader = opengl.glCreateShader(shader_type);

    const ptr = @ptrCast([*]const [*]const u8, &source[0..]);
    opengl.glShaderSource(shader, 1, ptr, &[_]GL.int{@intCast(GL.int, source.len)});
    opengl.glCompileShader(shader);

    var compile_status: GL.int = undefined;
    opengl.glGetShaderiv(shader, GL.COMPILE_STATUS, &compile_status);

    if (compile_status != GL.GL_TRUE) {
        var log_len: GL.int = undefined;
        opengl.glGetShaderiv(shader, GL.INFO_LOG_LENGTH, &log_len);

        var log = try allocator.alloc(u8, @intCast(usize, log_len));
        defer allocator.free(log);

        var out_len: GL.int = undefined;
        opengl.glGetShaderInfoLog(shader, log_len, &out_len, log.ptr);

        std.log.err("Failed to compile shader: {s}", .{log});
        return error.FailedToCompileShader;
    }

    return shader;
}

const vshader = @embedFile("./lissajous.vert");
const fshader = @embedFile("./lissajous.frag");

usingnamespace std.os.windows;

extern "user32" fn GetDC(hwnd: HWND) HDC;

extern "gdi32" fn ChoosePixelFormat(hdc: HDC, ppfd: *const PixelFormatDescriptor) c_int;
extern "gdi32" fn SetPixelFormat(hdc: HDC, format: c_int, ppfd: *const PixelFormatDescriptor) BOOL;

extern "opengl32" fn wglCreateContext(hdc: HDC) ?HGLRC;
extern "opengl32" fn wglDeleteContext(HGLRC) BOOL;
extern "opengl32" fn wglMakeCurrent(hdc: HDC, glrc: ?HGLRC) BOOL;
extern "opengl32" fn wglGetProcAddress(name: LPCSTR) ?*c_void;
extern "opengl32" fn SwapBuffers(hdc: HDC) BOOL;

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

pub fn wglSetup(allocator: *std.mem.Allocator, hwnd: HWND) !Instance {
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

    const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
    const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;

    const attribs = [_]i32{
        WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
        WGL_CONTEXT_MINOR_VERSION_ARB, 3,
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

// fn loadFunctions(allocator: *std.mem.Allocator) !Instance {
//     var success: bool = true;
//     var inst: Instance = undefined;
//     inst.dynlib = try std.DynLib.open("opengl32.dll");
// }

const Instance = struct {
    allocator: *std.mem.Allocator,
    dynlib: std.DynLib,
    hdc: HDC,
    ctx: HGLRC,

    pub fn deinit(self: *Instance) void {
        self.dynlib.close();
        std.debug.assert(wglDeleteContext(self.ctx) == TRUE);
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
