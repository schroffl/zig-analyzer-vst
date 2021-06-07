const std = @import("std");
const Mat4 = @import("./util/matrix.zig");
const Ring = @import("./util/ring.zig");
const UI = @import("./util/ui.zig");
const GL = @import("./util/opengl.zig");
const Editor = @import("./editor.zig");
const Self = @This();

gl: *GL,

cpu_ring: *Ring,
gpu_ring: GPURing,

vaos: AutoGenerated(GL.uint, .{ "lissajous_2d", "frequency", "picking", "oscilloscope" }),
fbs: AutoGenerated(GL.uint, .{ "heat_sum", "picking_buffer" }),
textures: AutoGenerated(GL.uint, .{ "heat_sum_tex", "scale_tex", "picking_tex" }),
bufs: AutoGenerated(GL.uint, .{ "quad", "signal", "osc_lines" }),

lissajous_program: Program(.{
    "num_frames",
    "dot_size",
    "dot_color",
    "graph_scale",
    "matrix",
}),

heat_program: Program(.{
    "dot_size",
    "graph_scale",
}),

blit_heat_program: Program(.{
    "heat_tex",
    "scale_tex",
    "matrix",
}),

frequency_program: Program(.{
    "matrix",
    "col",
}),

picking_program: Program(.{
    "matrix",
    "picking_id",
}),

oscilloscope_program: Program(.{
    "matrix",
    "num_frames",
}),

pub fn init(allocator: *std.mem.Allocator, gl: *GL, ring: *Ring, images: Images) !Self {
    var self: Self = undefined;

    self.gl = gl;
    self.vaos = generate(self.vaos, "glGenVertexArrays", gl);
    self.fbs = generate(self.fbs, "glGenFramebuffers", gl);
    self.textures = generate(self.textures, "glGenTextures", gl);
    self.bufs = generate(self.bufs, "glGenBuffers", gl);

    try self.lissajous_program.init(allocator, gl, .{
        .{ GL.VERTEX_SHADER, @embedFile("./windows/lissajous.vert") },
        .{ GL.FRAGMENT_SHADER, @embedFile("./windows/lissajous.frag") },
    });

    try self.heat_program.init(allocator, gl, .{
        .{ GL.VERTEX_SHADER, @embedFile("./windows/heat_dot.vert") },
        .{ GL.FRAGMENT_SHADER, @embedFile("./windows/heat_dot.frag") },
    });

    try self.blit_heat_program.init(allocator, gl, .{
        .{ GL.VERTEX_SHADER, @embedFile("./windows/blit_heat.vert") },
        .{ GL.FRAGMENT_SHADER, @embedFile("./windows/blit_heat.frag") },
    });

    try self.frequency_program.init(allocator, gl, .{
        .{ GL.VERTEX_SHADER, @embedFile("./windows/frequency.vert") },
        .{ GL.FRAGMENT_SHADER, @embedFile("./windows/frequency.frag") },
    });

    try self.picking_program.init(allocator, gl, .{
        .{ GL.VERTEX_SHADER, @embedFile("./windows/picking.vert") },
        .{ GL.FRAGMENT_SHADER, @embedFile("./windows/picking.frag") },
    });

    try self.oscilloscope_program.init(allocator, gl, .{
        .{ GL.VERTEX_SHADER, @embedFile("./windows/oscilloscope.vert") },
        .{ GL.FRAGMENT_SHADER, @embedFile("./windows/oscilloscope.frag") },
    });

    self.gpu_ring = GPURing.init(self.bufs.signal, gl);
    self.cpu_ring = ring;

    {
        gl.glDisable(GL.DEPTH_TEST);
        gl.glEnable(GL.CULL_FACE);
        gl.glEnable(GL.BLEND);
        gl.glCullFace(GL.BACK);
    }

    // Heat Framebuffer Setup
    {
        gl.callCheckError("glActiveTexture", .{GL.TEXTURE0});
        gl.callCheckError("glBindTexture", .{ GL.TEXTURE_2D, self.textures.heat_sum_tex });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE });
        gl.callCheckError("glTexImage2D", .{ GL.TEXTURE_2D, 0, GL.RGBA, 512, 512, 0, GL.RGBA, GL.FLOAT, null });

        gl.callCheckError("glBindFramebuffer", .{ GL.FRAMEBUFFER, self.fbs.heat_sum });
        gl.callCheckError("glFramebufferTexture2D", .{ GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, self.textures.heat_sum_tex, 0 });
    }

    // Heat Scale Texture Setup
    {
        gl.callCheckError("glActiveTexture", .{GL.TEXTURE1});
        gl.callCheckError("glBindTexture", .{ GL.TEXTURE_2D, self.textures.scale_tex });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE });
        gl.callCheckError("glTexImage2D", .{ GL.TEXTURE_2D, 0, GL.RGBA, 1024, 1, 0, GL.RGBA, GL.UNSIGNED_BYTE, images.scale.ptr });
    }

    // Picking Framebuffer Setup
    {
        gl.callCheckError("glActiveTexture", .{GL.TEXTURE2});
        gl.callCheckError("glBindTexture", .{ GL.TEXTURE_2D, self.textures.picking_tex });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.NEAREST });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.NEAREST });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE });
        gl.callCheckError("glTexParameteri", .{ GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE });

        // TODO This needs to be the same size as the backbuffer
        gl.callCheckError("glTexImage2D", .{ GL.TEXTURE_2D, 0, GL.RGBA, 500, 500, 0, GL.RGBA, GL.FLOAT, null });

        gl.callCheckError("glBindFramebuffer", .{ GL.FRAMEBUFFER, self.fbs.picking_buffer });
        gl.callCheckError("glFramebufferTexture2D", .{ GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, self.textures.picking_tex, 0 });
    }

    // Quad Buffer
    {
        const quad = [_]GL.float{
            -1, -1,
            -1, 1,
            1,  1,
            1,  -1,
        };

        gl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.bufs.quad });
        gl.callCheckError("glBufferData", .{ GL.ARRAY_BUFFER, quad.len * @sizeOf(GL.float), &quad, GL.STATIC_DRAW });
    }

    // Icosahedron Model for 3D Lissajous
    {
        // TODO
    }

    // Lissajous VAO Setup
    {
        gl.callCheckError("glBindVertexArray", .{self.vaos.lissajous_2d});

        gl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.bufs.quad });
        gl.callCheckError("glEnableVertexAttribArray", .{0});
        gl.callCheckError("glVertexAttribPointer", .{ 0, 2, GL.FLOAT, GL.FALSE, 0, null });
        gl.callCheckError("glVertexAttribDivisor", .{ 0, 0 });

        gl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.bufs.signal });
        gl.callCheckError("glEnableVertexAttribArray", .{1});
        gl.callCheckError("glVertexAttribPointer", .{ 1, 2, GL.FLOAT, GL.FALSE, @sizeOf(f32) * 2, null });
        gl.callCheckError("glVertexAttribDivisor", .{ 1, 1 });
    }

    {
        gl.callCheckError("glBindVertexArray", .{self.vaos.frequency});
        gl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.bufs.quad });
        gl.callCheckError("glEnableVertexAttribArray", .{0});
        gl.callCheckError("glVertexAttribPointer", .{ 0, 2, GL.FLOAT, GL.FALSE, 0, null });
    }

    {
        gl.callCheckError("glBindVertexArray", .{self.vaos.picking});
        gl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.bufs.quad });
        gl.callCheckError("glEnableVertexAttribArray", .{0});
        gl.callCheckError("glVertexAttribPointer", .{ 0, 2, GL.FLOAT, GL.FALSE, 0, null });
    }

    // OSC Lines buffer setup
    {
        const lines = line_result: {
            const time_ms = 100;
            const frame_count = 48_000 * (time_ms / @as(f64, 1000.0));

            const vertex_count = frame_count * 2;
            var vertices = try allocator.alloc(GL.float, vertex_count * 2);
            var idx: usize = 0;
            var vertex_idx: usize = 0;

            while (idx < frame_count) : (idx += 1) {
                vertices[vertex_idx] = -1;
                vertices[vertex_idx + 1] = @intToFloat(f32, idx);

                vertices[vertex_idx + 2] = 1;
                vertices[vertex_idx + 3] = @intToFloat(f32, idx);

                vertex_idx += 4;
            }

            break :line_result vertices;
        };

        gl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.bufs.osc_lines });
        gl.callCheckError("glBufferData", .{ GL.ARRAY_BUFFER, @intCast(i32, lines.len) * @sizeOf(GL.float), lines.ptr, GL.STATIC_DRAW });
    }

    {
        gl.callCheckError("glBindVertexArray", .{self.vaos.oscilloscope});
        gl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.bufs.osc_lines });

        gl.callCheckError("glEnableVertexAttribArray", .{0});
        gl.callCheckError("glVertexAttribPointer", .{ 0, 2, GL.FLOAT, GL.FALSE, 0, null });

        // gl.callCheckError("glEnableVertexAttribArray", .{2});
        // gl.callCheckError("glVertexAttribPointer", .{ 2, 1, GL.FLOAT, GL.FALSE, stride, @intToPtr(*c_void, 12) });

        // gl.callCheckError("glEnableVertexAttribArray", .{3});
        // gl.callCheckError("glVertexAttribPointer", .{ 3, 1, GL.FLOAT, GL.FALSE, stride, @intToPtr(*c_void, 16) });

        gl.callCheckError("glBindBuffer", .{ GL.ARRAY_BUFFER, self.bufs.signal });

        gl.callCheckError("glEnableVertexAttribArray", .{1});
        gl.callCheckError("glVertexAttribPointer", .{ 1, 2, GL.FLOAT, GL.FALSE, 0, @intToPtr(*c_void, 8) });

        gl.callCheckError("glEnableVertexAttribArray", .{2});
        gl.callCheckError("glVertexAttribPointer", .{ 2, 2, GL.FLOAT, GL.FALSE, 0, @intToPtr(*c_void, 16) });

        gl.callCheckError("glEnableVertexAttribArray", .{3});
        gl.callCheckError("glVertexAttribPointer", .{ 3, 2, GL.FLOAT, GL.FALSE, 0, null });
    }

    gl.callCheckError("glUseProgram", .{self.lissajous_program.id});
    gl.callCheckError("glUniform3f", .{ self.lissajous_program.uniforms.dot_color, 0.572, 0.909, 0.266 });

    return self;
}

pub fn resize(self: *Self, viewport: Viewport) void {
    const gl = self.gl;
    gl.callCheckError("glBindTexture", .{ GL.TEXTURE_2D, self.textures.picking_tex });
    gl.callCheckError("glTexImage2D", .{ GL.TEXTURE_2D, 0, GL.RGBA, viewport.width, viewport.height, 0, GL.RGBA, GL.FLOAT, null });
}

pub fn deinit(self: *Self) void {
    cleanup(self.vaos, "glDeleteVertexArrays", self.gl);
    cleanup(self.fbs, "glDeleteFramebuffers", self.gl);
    cleanup(self.textures, "glDeleteTextures", self.gl);
    cleanup(self.bufs, "glDeleteBuffers", self.gl);
}

pub fn render(self: *Self, editor: Editor, viewport: Viewport, picking_pos: ?UI.MousePos) ?u32 {
    const gl = self.gl;
    const params = editor.params;
    const num_frames = self.gpu_ring.max_capacity / 2;

    self.gpu_ring.copyFromRing(self.cpu_ring);

    const lis_matrix = switch (editor.lissajous_mode) {
        .Lissajous3D => Mat4.multiplyMany(&[_]Mat4{
            Mat4.rotateY(-0.5),
            Mat4.translate(0, 0, -2),
            Mat4.perspective(70, 1, 0.01, 100),
        }),
        else => Mat4.identity,
    };

    const lis_pane_matrix = Mat4.multiplyMany(&[_]Mat4{
        Mat4.scale(std.math.sqrt1_2, std.math.sqrt1_2, 1),
        Mat4.scale(0.9, 0.9, 1),
        Mat4.rotateZ(-std.math.pi / 4.0),
        lis_matrix,
        paneMatrix(editor.layout.getPane("lissajous")),
    });

    gl.callCheckError("glEnable", .{GL.DEPTH_TEST});
    gl.callCheckError("glDisable", .{GL.BLEND});

    switch (editor.lissajous_mode) {
        .Lissajous3D, .Lissajous2D => {
            const lp = self.lissajous_program;

            gl.callCheckError("glBindVertexArray", .{self.vaos.lissajous_2d});

            gl.glUseProgram(lp.id);
            gl.glBlendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA);
            gl.callCheckError("glBindFramebuffer", .{ GL.FRAMEBUFFER, 0 });
            gl.glClear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT);
            gl.callCheckError("glUniformMatrix4fv", .{ lp.uniforms.matrix, 1, GL.FALSE, &lis_pane_matrix.data });
            gl.callCheckError("glUniform1f", .{ lp.uniforms.dot_size, params.get("Point Size") });
            gl.callCheckError("glUniform1f", .{ lp.uniforms.graph_scale, params.get("Graph Scale") });
            gl.callCheckError("glUniform1f", .{ lp.uniforms.num_frames, @intToFloat(f32, num_frames) });
            gl.callCheckError("glDrawArraysInstanced", .{ GL.TRIANGLE_FAN, 0, 8, @intCast(GL.sizei, num_frames) });
        },
        .Heatmap => {
            const hp = self.heat_program;
            const bhp = self.blit_heat_program;

            gl.callCheckError("glDisable", .{GL.DEPTH_TEST});
            gl.callCheckError("glEnable", .{GL.BLEND});

            gl.callCheckError("glBindVertexArray", .{self.vaos.lissajous_2d});

            {
                gl.callCheckError("glUseProgram", .{hp.id});
                gl.callCheckError("glBlendFunc", .{ GL.SRC_ALPHA, GL.ONE });
                gl.callCheckError("glBindFramebuffer", .{ GL.FRAMEBUFFER, self.fbs.heat_sum });
                gl.glViewport(0, 0, 512, 512);
                gl.glClearColor(0, 0, 0, 0);
                gl.glClear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT);
                gl.callCheckError("glUniform1f", .{ hp.uniforms.dot_size, params.get("Point Size") });
                gl.callCheckError("glUniform1f", .{ hp.uniforms.graph_scale, params.get("Graph Scale") });
                gl.callCheckError("glDrawArraysInstanced", .{ GL.TRIANGLE_FAN, 0, 8, @intCast(GL.sizei, num_frames) });
            }

            {
                gl.callCheckError("glUseProgram", .{bhp.id});
                gl.glBlendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA);
                gl.callCheckError("glBindFramebuffer", .{ GL.FRAMEBUFFER, 0 });
                gl.glClearColor(0, 0, 0, 1);
                gl.glViewport(0, 0, viewport.width, viewport.height);
                gl.glClear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT);
                gl.callCheckError("glUniformMatrix4fv", .{ bhp.uniforms.matrix, 1, GL.FALSE, &lis_pane_matrix.data });
                gl.callCheckError("glUniform1i", .{ bhp.uniforms.heat_tex, 0 });
                gl.callCheckError("glUniform1i", .{ bhp.uniforms.scale_tex, 1 });
                gl.callCheckError("glDrawArrays", .{ GL.TRIANGLE_FAN, 0, 8 });
            }
        },
    }

    const freq_pane_matrix = paneMatrix(editor.layout.getPane("frequency"));

    switch (editor.frequency_mode) {
        .Flat, .Waterfall => {
            const fp = self.frequency_program;

            gl.callCheckError("glBindVertexArray", .{self.vaos.frequency});

            gl.callCheckError("glUseProgram", .{fp.id});
            gl.callCheckError("glBlendFunc", .{ GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA });
            gl.callCheckError("glBindFramebuffer", .{ GL.FRAMEBUFFER, 0 });
            gl.glViewport(0, 0, viewport.width, viewport.height);
            gl.callCheckError("glUniformMatrix4fv", .{ fp.uniforms.matrix, 1, GL.FALSE, &freq_pane_matrix.data });
            gl.callCheckError("glUniform3f", .{ fp.uniforms.col, 0.2, 0.2, 0.2 });
            gl.callCheckError("glDrawArrays", .{ GL.TRIANGLE_FAN, 0, 8 });
        },
    }

    const osc_pane_matrix = paneMatrix(editor.layout.getPane("frequency"));

    switch (editor.oscilloscope_mode) {
        .Combined => {
            const op = self.oscilloscope_program;

            gl.callCheckError("glDisable", .{GL.DEPTH_TEST});

            gl.callCheckError("glBindVertexArray", .{self.vaos.oscilloscope});

            gl.callCheckError("glDisable", .{GL.BLEND});
            gl.callCheckError("glEnable", .{GL.DEPTH_TEST});

            gl.callCheckError("glUseProgram", .{op.id});
            gl.callCheckError("glBindFramebuffer", .{ GL.FRAMEBUFFER, 0 });
            gl.glViewport(0, 0, viewport.width, viewport.height);

            gl.callCheckError("glUniformMatrix4fv", .{ op.uniforms.matrix, 1, GL.FALSE, &osc_pane_matrix.data });
            gl.callCheckError("glUniform1f", .{ op.uniforms.num_frames, @intToFloat(f32, num_frames) });
            gl.callCheckError("glDrawArrays", .{ GL.TRIANGLE_STRIP, 0, @intCast(i32, num_frames * 2) });
        },
    }

    var picked_id: ?u32 = null;

    // Picking
    if (picking_pos) |pos| {
        const pip = self.picking_program;

        gl.callCheckError("glDisable", .{GL.BLEND});
        gl.callCheckError("glBindFramebuffer", .{ GL.FRAMEBUFFER, self.fbs.picking_buffer });
        gl.callCheckError("glBindVertexArray", .{self.vaos.picking});
        gl.callCheckError("glUseProgram", .{pip.id});

        gl.callCheckError("glClearColor", .{ 0, 0, 0, 0 });
        gl.callCheckError("glClear", .{GL.COLOR_BUFFER_BIT});

        inline for ([_][]const u8{
            "lissajous",
            "frequency",
            "oscilloscope",
            "graph_scale",
            "lissajous_controls",
        }) |element, i| {
            const matrix = paneMatrix(editor.layout.getPane(element));
            const id = 1 + @intCast(u32, i);

            gl.callCheckError("glUniformMatrix4fv", .{ pip.uniforms.matrix, 1, GL.FALSE, &matrix.data });
            gl.callCheckError("glUniform4f", .{
                pip.uniforms.picking_id,
                @intToFloat(f32, ((id >> 0) & 0xff)) / 0xff,
                @intToFloat(f32, (id >> 8) & 0xff) / 0xff,
                @intToFloat(f32, (id >> 16) & 0xff) / 0xff,
                @intToFloat(f32, (id >> 24) & 0xff) / 0xff,
            });

            gl.callCheckError("glDrawArrays", .{ GL.TRIANGLE_FAN, 0, 8 });
        }

        const h = 1;
        const w = 1;
        var data: [w * h * 4]u8 = undefined;
        gl.callCheckError("glReadPixels", .{ pos.x, viewport.height - pos.y, w, h, GL.RGBA, GL.UNSIGNED_BYTE, &data });
        const id = std.mem.readIntLittle(u32, &data);

        if (id != 0) picked_id = id;
    }

    {
        // For some reason this absolutely wrecks my CPU, causing the usage to go
        // up to 32%, whereas it's at a stable ~3% without these few lines.
        // Is this related to VSync? Maybe we have to call it outside of the render
        // routine and after the buffers were swapped? If so I should probably
        // move it to a separate function and make the wrapper responsible for
        // calling it at the appropriate time.

        // Even without runtime safety we want to at least know if any call
        // in the frame generated an error.
        // if (comptime !std.debug.runtime_safety) {
        //     const err = gl.glGetError();

        //     if (err != 0) {
        //         std.log.crit("An error was generated this frame: {}", .{err});
        //     }
        // }
    }

    return picked_id;
}

pub const Images = struct {
    scale: []const u8,
};

pub const Viewport = struct {
    width: i32,
    height: i32,
};

fn paneMatrix(pane: Editor.Pane) Mat4 {
    return Mat4.multiplyMany(&[_]Mat4{
        Mat4.translate(1, -1, 0),
        Mat4.scale(0.5, 0.5, 1),

        Mat4.scale(pane.width, pane.height, 1),
        Mat4.translate(pane.x, -pane.y, 0),

        Mat4.scale(2, 2, 1),
        Mat4.translate(-1, 1, 0),
    });
}

fn Program(comptime uniforms: anytype) type {
    return struct {
        id: GL.uint,
        uniforms: AutoGenerated(GL.int, uniforms),

        pub fn init(self: *@This(), allocator: *std.mem.Allocator, gl: *GL, comptime shader_source: anytype) !void {
            self.id = gl.callCheckError("glCreateProgram", .{});

            inline for (shader_source) |pair| {
                const shader = try makeShader(allocator, gl, pair.@"0", pair.@"1");

                gl.callCheckError("glAttachShader", .{ self.id, shader });
            }

            gl.callCheckError("glLinkProgram", .{self.id});

            var link_status: GL.int = undefined;
            gl.callCheckError("glGetProgramiv", .{ self.id, GL.LINK_STATUS, &link_status });

            if (link_status != GL.TRUE) {
                var log_len: GL.int = undefined;
                gl.callCheckError("glGetProgramiv", .{ self.id, GL.INFO_LOG_LENGTH, &log_len });

                var log = try allocator.alloc(u8, @intCast(usize, log_len));
                defer allocator.free(log);

                var out_len: GL.int = undefined;
                gl.callCheckError("glGetProgramInfoLog", .{ self.id, log_len, &out_len, log.ptr });

                std.log.crit("Failed to link program: {s}", .{log});
                return error.FailedToLinkProgram;
            }

            inline for (uniforms) |name| {
                @field(self.uniforms, name) = gl.callCheckError("glGetUniformLocation", .{ self.id, name });

                if (@field(self.uniforms, name) == -1) {
                    std.log.warn("Uniform '{s}' could not be found", .{name});
                }
            }
        }
    };
}

fn AutoGenerated(comptime T: type, comptime names: anytype) type {
    const TypeInfo = std.builtin.TypeInfo;
    var fields: [names.len]TypeInfo.StructField = undefined;

    inline for (names) |name, i| {
        fields[i].name = name;
        fields[i].field_type = T;
        fields[i].default_value = null;
        fields[i].is_comptime = false;
        fields[i].alignment = @alignOf(T);
    }

    return @Type(TypeInfo{
        .Struct = .{
            .layout = .Auto,
            .fields = &fields,
            .decls = &[_]TypeInfo.Declaration{},
            .is_tuple = false,
        },
    });
}

fn generate(any: anytype, comptime fn_name: []const u8, opengl: *GL) @TypeOf(any) {
    const FieldT = @TypeOf(any);
    const fields = comptime std.meta.fields(FieldT);

    if (comptime fields.len == 0) {
        return FieldT{};
    } else {
        const T = fields[0].field_type;
        var ids: [fields.len]T = undefined;
        var result: FieldT = undefined;
        opengl.callCheckError(fn_name, .{ ids.len, &ids });

        inline for (fields) |field, i| {
            @field(result, field.name) = ids[i];
        }

        return result;
    }
}

fn cleanup(any: anytype, comptime fn_name: []const u8, opengl: *GL) void {
    const FieldT = @TypeOf(any);
    const fields = comptime std.meta.fields(FieldT);

    if (comptime fields.len > 0) {
        const T = fields[0].field_type;

        var ids: [fields.len]T = undefined;

        inline for (fields) |field, i| {
            ids[i] = @field(any, field.name);
        }

        opengl.callCheckError(fn_name, .{ ids.len, &ids });
    }
}

fn makeShader(allocator: *std.mem.Allocator, opengl: *GL, shader_type: GL.Enum, source: []const u8) !GL.uint {
    const shader = opengl.glCreateShader(shader_type);

    const ptr = @ptrCast([*]const [*]const u8, &source[0..]);
    opengl.glShaderSource(shader, 1, ptr, &[_]GL.int{@intCast(GL.int, source.len)});
    opengl.glCompileShader(shader);

    var compile_status: GL.int = undefined;
    opengl.glGetShaderiv(shader, GL.COMPILE_STATUS, &compile_status);

    if (compile_status != GL.TRUE) {
        var log_len: GL.int = undefined;
        opengl.glGetShaderiv(shader, GL.INFO_LOG_LENGTH, &log_len);

        var log = try allocator.alloc(u8, @intCast(usize, log_len));
        defer allocator.free(log);

        var out_len: GL.int = undefined;
        opengl.glGetShaderInfoLog(shader, log_len, &out_len, log.ptr);

        std.log.crit("Failed to compile shader: {s}", .{log});
        return error.FailedToCompileShader;
    }

    return shader;
}

pub const GPURing = struct {
    buffer: GL.uint,
    opengl: *GL,
    max_capacity: usize = 0,
    allocated: usize = 0,
    write_index: usize = 0,
    read_index: usize = 0,

    pub fn init(buffer: GL.uint, opengl: *GL) GPURing {
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