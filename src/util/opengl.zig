const std = @import("std");

pub const uint = u32;
pub const sizei = i32;
pub const int = i32;
pub const Enum = c_uint;
pub const char = u8;
pub const boolean = u8;
pub const float = f32;
pub const byte = i8;

pub const GL_FALSE = 0x0;
pub const GL_TRUE = 0x1;
pub const COLOR_BUFFER_BIT = 0x00004000;
pub const DEPTH_BUFFER_BIT = 0x00000100;
pub const FRAGMENT_SHADER = 0x8B30;
pub const VERTEX_SHADER = 0x8B31;
pub const COMPILE_STATUS = 0x8B81;
pub const INFO_LOG_LENGTH = 0x8B84;
pub const STATIC_DRAW = 0x88E4;
pub const LINK_STATUS = 0x8B82;
pub const ARRAY_BUFFER = 0x8892;
pub const GL_FLOAT = 0x1406;
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
glGenTextures: fn (Enum, uint) void,
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
glUniform3f: fn (int, float, float, float) void,
glBufferSubData: fn (Enum, int, sizei, ?*const c_void) void,
glEnable: fn (Enum) void,
glDisable: fn (Enum) void,
glCullFace: fn (Enum) void,
glBlendFunc: fn (Enum, Enum) void,
glUniformMatrix4fv: fn (int, sizei, boolean, [*]const f32) void,

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
