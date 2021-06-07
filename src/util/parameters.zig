const std = @import("std");

pub const ParamDescription = struct {
    name: []const u8,
    label: []const u8,
    automatable: bool = true,
    display: fn (f32, []u8) []const u8 = displayDefault,
    initial: f32 = 0,
};

pub fn Parameters(comptime descriptions: []const ParamDescription) type {
    var initial_values: [descriptions.len]f32 = undefined;

    for (descriptions) |desc, i| initial_values[i] = desc.initial;

    return struct {
        pub const count = descriptions.len;

        values: [descriptions.len]f32 = initial_values,

        pub fn get(self: @This(), comptime name: []const u8) f32 {
            return inline for (descriptions) |desc, i| {
                if (comptime std.mem.eql(u8, name, desc.name)) return self.values[i];
            } else @compileError("Unknown parameter '" ++ name ++ "'");
        }

        pub fn set(self: *@This(), comptime name: []const u8, value: f32) void {
            self.values[index] = value;
        }

        pub fn displayByIndex(self: @This(), index: usize, buf: []u8) ?[]const u8 {
            const desc = getDescription(index) orelse return null;
            return desc.display(self.values[index], buf);
        }

        pub fn setByIndex(self: *@This(), index: usize, value: f32) void {
            if (index >= count) return;
            self.values[index] = value;
        }

        pub fn getByIndex(self: @This(), index: usize) ?f32 {
            if (index >= count) return null;
            return self.values[index];
        }

        pub fn getDescription(index: usize) ?ParamDescription {
            if (index >= count) return null;
            return descriptions[index];
        }
    };
}

pub fn displayDefault(value: f32, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "{d:.5}", .{value}) catch return out;
}

pub fn displayPercentage(value: f32, out: []u8) []const u8 {
    return std.fmt.bufPrint(out, "{d:.2} %", .{value * 100}) catch return out;
}

fn identity(x: f32) f32 {
    return x;
}

const ParamDefinition = struct {
    name: []const u8,
    external: ?struct {
        label: []const u8,
        automatable: bool = true,
        display: fn (f32, []u8) []const u8 = displayDefault,
    } = null,
};

pub fn ParamMapping(comptime T: type) type {
    return struct {
        from: fn (f32) T,
        to: fn (T) f32,
    };
}

pub fn FloatRange(comptime min: f32, comptime max: f32) ParamMapping(f32) {
    const Helper = struct {
        pub fn from(raw: f32) f32 {
            return min + raw * (max - min);
        }

        pub fn to(value: f32) f32 {
            return (value - min) / (max - min);
        }
    };

    return ParamMapping(f32){
        .from = Helper.from,
        .to = Helper.to,
    };
}

pub fn Param(
    comptime ParamT: type,
    def: ParamDefinition,
    comptime mapping: ParamMapping(ParamT),
    comptime init: ?ParamT,
) type {
    return struct {
        pub const T = ParamT;
        pub const definition = def;
        pub const initial = init;

        pub fn fromNormalized(value: f32) def.T {
            return mapping.from(value);
        }

        pub fn toNormalized(value: def.T) f32 {
            return mapping.to(value);
        }
    };
}

pub fn EnumMapping(comptime EnumT: type) ParamMapping(EnumT) {
    const Helper = struct {
        pub fn from(raw: f32) EnumT {
            const fields = comptime std.meta.fields(EnumT);
            const f_idx = std.math.floor(raw * 0.99999 * @intToFloat(f32, fields.len));
            const idx = @floatToInt(std.meta.Tag(EnumT), f_idx);

            return @intToEnum(EnumT, idx);
        }

        pub fn to(value: EnumT) f32 {
            const fields = comptime std.meta.fields(EnumT);
            const idx = @enumToInt(value);

            return @intToFloat(f32, idx) / @intToFloat(f32, fields.len - 1);
        }
    };

    return ParamMapping(EnumT){
        .from = Helper.from,
        .to = Helper.to,
    };
}

pub fn Params(comptime params: anytype) type {
    var external_count = 0;
    var ext_index_to_index: [params.len]usize = undefined;
    var initial_values: [params.len]f32 = undefined;

    inline for (params) |param, i| {
        if (param.definition.external != null) {
            ext_index_to_index[external_count] = i;
            external_count += 1;
        }

        initial_values[i] = param.toNormalized(param.initial);
    }

    return struct {
        pub const external_param_count: usize = external_count;

        values: [params.len]f32 = initial_values,
        external: []const usize = ext_index_to_index[0..external_count],

        pub fn get(self: @This(), comptime name: []const u8) params[getIndex(name)].definition.T {
            const param = params[comptime getIndex(name)];
            const raw = self.values[comptime getIndex(name)];

            return param.fromNormalized(raw);
        }

        pub fn getExternal(self: @This(), idx: usize) fn getIndex(comptime name: []const u8) usize {
            return inline for (params) |param, i| {
                if (comptime std.mem.eql(u8, param.definition.name, name))
                    break i;
            } else @compileError("Unknown Parameter '" ++ name ++ "'");
        }
    };
}

const M = enum {
    Lissajous,
    Waterfall,
    Oscilloscope,
};
