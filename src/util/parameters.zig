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
