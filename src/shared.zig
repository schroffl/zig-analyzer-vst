const std = @import("std");
const param = @import("./util/parameters.zig");

pub const Parameters = param.Parameters(&[_]param.ParamDescription{
    .{
        .name = "Graph Scale",
        .label = "%",
        .display = param.displayPercentage,
        .initial = 1,
    },
    .{
        .name = "Point Size",
        .label = "dots",
        .initial = 0.01,
    },
});
