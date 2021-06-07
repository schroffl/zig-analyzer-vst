const std = @import("std");

pub const uint = u32;
pub const sizei = i32;
pub const int = i32;
pub const Enum = c_uint;
pub const char = u8;
pub const boolean = u8;
pub const float = f32;
pub const byte = i8;

pub const FALSE = 0x0;
pub const TRUE = 0x1;
pub const COLOR_BUFFER_BIT = 0x00004000;
pub const DEPTH_BUFFER_BIT = 0x00000100;
pub const FRAGMENT_SHADER = 0x8B30;
pub const VERTEX_SHADER = 0x8B31;
pub const GEOMETRY_SHADER = 0x8DD9;
pub const COMPILE_STATUS = 0x8B81;
pub const INFO_LOG_LENGTH = 0x8B84;
pub const STATIC_DRAW = 0x88E4;
pub const LINK_STATUS = 0x8B82;
pub const ARRAY_BUFFER = 0x8892;
pub const FLOAT = 0x1406;
pub const UNSIGNED_BYTE = 0x1401;
pub const POINTS = 0x0000;
pub const TRIANGLES = 0x0004;
pub const TRIANGLE_STRIP = 0x0005;
pub const TRIANGLE_FAN = 0x0006;
pub const LINE_STRIP = 0x0003;
pub const DYNAMIC_DRAW = 0x88E8;
pub const DEPTH_TEST = 0x0B71;
pub const CULL_FACE = 0x0B44;
pub const FRONT = 0x0405;
pub const BACK = 0x0404;
pub const EXTENSIONS = 0x1F03;
pub const BLEND = 0x0BE2;
pub const ZERO = 0;
pub const ONE = 1;
pub const SRC_COLOR = 0x0300;
pub const ONE_MINUS_SRC_COLOR = 0x0301;
pub const SRC_ALPHA = 0x0302;
pub const ONE_MINUS_SRC_ALPHA = 0x0303;
pub const DST_ALPHA = 0x0304;
pub const ONE_MINUS_DST_ALPHA = 0x0305;
pub const FRAMEBUFFER = 0x8D40;
pub const TEXTURE_2D = 0x0DE1;
pub const TEXTURE_MAG_FILTER = 0x2800;
pub const TEXTURE_MIN_FILTER = 0x2801;
pub const TEXTURE_WRAP_S = 0x2802;
pub const TEXTURE_WRAP_T = 0x2803;
pub const NEAREST = 0x2600;
pub const LINEAR = 0x2601;
pub const CLAMP_TO_EDGE = 0x812F;
pub const RGBA = 0x1908;
pub const COLOR_ATTACHMENT0 = 0x8CE0;
pub const READ_FRAMEBUFFER = 0x8CA8;
pub const DRAW_FRAMEBUFFER = 0x8CA9;
pub const TEXTURE0 = 0x84C0;
pub const TEXTURE1 = 0x84C1;
pub const TEXTURE2 = 0x84C2;
pub const VIEWPORT = 0x0BA2;

glClear: fn (c_uint) void,
glClearColor: fn (f32, f32, f32, f32) void,
glUseProgram: fn (c_uint) void,
glCreateProgram: fn () uint,
glCreateShader: fn (Enum) uint,
glAttachShader: fn (uint, uint) void,
glShaderSource: fn (uint, sizei, [*]const [*]const char, ?[*]const int) void,
glCompileShader: fn (uint) void,
glGetShaderiv: fn (uint, Enum, *int) void,
glGetShaderInfoLog: fn (uint, sizei, *sizei, [*]char) void,
glGenBuffers: fn (sizei, [*]uint) void,
glBindBuffer: fn (Enum, uint) void,
glGenTextures: fn (sizei, [*]uint) void,
glBufferData: fn (Enum, sizei, ?*const c_void, Enum) void,
glLinkProgram: fn (uint) void,
glGetProgramiv: fn (uint, Enum, *int) void,
glGetProgramInfoLog: fn (uint, sizei, *sizei, [*]char) void,
glEnableVertexAttribArray: fn (uint) void,
glVertexAttribPointer: fn (uint, int, Enum, boolean, sizei, ?*c_void) void,
glDrawArrays: fn (Enum, int, sizei) void,
glGetError: fn () Enum,
glGenVertexArrays: fn (sizei, [*]uint) void,
glBindVertexArray: fn (uint) void,
glDrawArraysInstanced: fn (Enum, int, sizei, sizei) void,
glVertexAttribDivisor: fn (uint, uint) void,
glGetUniformLocation: fn (uint, [*:0]const char) int,
glUniform1f: fn (int, float) void,
glUniform1i: fn (int, int) void,
glUniform3f: fn (int, float, float, float) void,
glUniform4f: fn (int, float, float, float, float) void,
glBufferSubData: fn (Enum, int, sizei, ?*const c_void) void,
glEnable: fn (Enum) void,
glDisable: fn (Enum) void,
glCullFace: fn (Enum) void,
glBlendFunc: fn (Enum, Enum) void,
glUniformMatrix4fv: fn (int, sizei, boolean, [*]const f32) void,
glGenFramebuffers: fn (sizei, [*]uint) void,
glBindFramebuffer: fn (Enum, uint) void,
glBindTexture: fn (Enum, uint) void,
glTexParameteri: fn (Enum, Enum, int) void,
glTexImage2D: fn (Enum, int, int, sizei, sizei, int, Enum, Enum, ?*const c_void) void,
glFramebufferTexture2D: fn (Enum, Enum, Enum, uint, int) void,
glViewport: fn (int, int, sizei, sizei) void,
glActiveTexture: fn (Enum) void,
glGetIntegerv: fn (Enum, [*]int) void,
glReadPixels: fn (int, int, sizei, sizei, Enum, Enum, *c_void) void,
glDeleteVertexArrays: fn (sizei, [*]uint) void,
glDeleteBuffers: fn (sizei, [*]uint) void,
glDeleteFramebuffers: fn (sizei, [*]uint) void,
glDeleteTextures: fn (sizei, [*]uint) void,

pub fn callCheckError(self: @This(), comptime name: []const u8, args: anytype) ReturnT: {
    @setEvalBranchQuota(10000);
    const idx = std.meta.fieldIndex(@This(), name).?;
    const info = @typeInfo(std.meta.fields(@This())[idx].field_type);

    break :ReturnT info.Fn.return_type.?;
} {
    const result = @call(.{}, @field(self, name), args);

    if (comptime std.debug.runtime_safety) {
        const err = self.glGetError();

        if (err != 0) {
            std.log.err("Calling '{s}' resulted in an error: {}", .{ name, err });
        }
    }

    return result;
}
