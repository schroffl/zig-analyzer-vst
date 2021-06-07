const std = @import("std");

pub const LissajousMode = enum {
    Lissajous2D,
    Lissajous3D,
    Heatmap,
};

pub const FrequencyMode = enum {
    Flat,
    Waterfall,
};

pub const OscilloscopeMode = enum {
    Combined,
};

pub const Element = struct {
    id: []const u8,
    pane: Pane = Pane.identity,
    relative: ?struct {
        id: []const u8,
        self: Pane.Anchor,
        parent: Pane.Anchor,
        relative_size: bool = true,
    } = null,
};

const ResolvedElement = struct {
    pane: Pane = Pane.identity,
    relative: ?struct {
        index: usize,
        self: Pane.Anchor,
        parent: Pane.Anchor,
        relative_size: bool = true,
    },
};

pub fn Layout(comptime elements: []const Element) type {
    var initial_panes: [elements.len]ResolvedElement = undefined;

    const Helper = struct {
        fn getIndex(comptime id: []const u8) usize {
            return inline for (elements) |elem, i| {
                if (comptime std.mem.eql(u8, elem.id, id))
                    break i;
            } else @compileError("No Element with id '" ++ id ++ "'");
        }
    };

    inline for (elements) |elem, i| {
        initial_panes[i].pane = elem.pane;
        initial_panes[i].relative = null;

        if (elem.relative) |relative| {
            initial_panes[i].relative = .{
                .index = Helper.getIndex(relative.id),
                .self = relative.self,
                .parent = relative.parent,
                .relative_size = relative.relative_size,
            };
        }
    }

    return struct {
        elems: []ResolvedElement = &initial_panes,

        pub fn getPane(self: @This(), comptime id: []const u8) Pane {
            var elem = self.elems[comptime Helper.getIndex(id)];
            var out = elem.pane;

            while (elem.relative) |parent| {
                elem = self.elems[parent.index];
                out = Pane.translate(
                    parent.self,
                    out,
                    parent.parent,
                    elem.pane,
                    parent.relative_size,
                );
            }

            return out;
        }
    };
}

pub const Pane = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 1,
    height: f32 = 1,

    pub const identity = Pane{};

    pub const Anchor = struct {
        pub const TopLeft = Anchor{ .x = 0, .y = 0 };
        pub const TopCenter = Anchor{ .x = 0.5, .y = 0 };
        pub const TopRight = Anchor{ .x = 1, .y = 0 };

        pub const Left = Anchor{ .x = 0, .y = 0.5 };
        pub const Center = Anchor{ .x = 0.5, .y = 0.5 };
        pub const Right = Anchor{ .x = 1, .y = 0.5 };

        pub const BottomLeft = Anchor{ .x = 0, .y = 1 };
        pub const BottomCenter = Anchor{ .x = 0.5, .y = 1 };
        pub const BottomRight = Anchor{ .x = 1, .y = 1 };

        x: f32,
        y: f32,
    };

    pub fn translate(src_anchor: Anchor, src: Pane, dst_anchor: Anchor, dst: Pane, resize: bool) Pane {
        var out = src;

        if (resize) {
            out.width *= dst.width;
            out.height *= dst.height;
        }

        out.x -= src_anchor.x * out.width;
        out.y -= src_anchor.y * out.height;

        out.x = dst.x + dst.width * dst_anchor.x + out.x;
        out.y = dst.y + dst.height * dst_anchor.y + out.y;

        return out;
    }
};

params: *@import("./shared.zig").Parameters,

lissajous_mode: LissajousMode = .Heatmap,
frequency_mode: FrequencyMode = .Waterfall,
oscilloscope_mode: OscilloscopeMode = .Combined,

layout: Layout(&[_]Element{
    .{ .id = "viewport" },
    .{
        .id = "lissajous",
        .pane = .{
            .width = 0.5,
            .height = 0.5,
        },
        .relative = .{
            .id = "viewport",
            .self = Pane.Anchor.TopLeft,
            .parent = Pane.Anchor.TopLeft,
        },
    },
    .{
        .id = "frequency",
        .pane = .{
            .width = 0.5,
            .height = 0.5,
        },
        .relative = .{
            .id = "lissajous",
            .self = Pane.Anchor.TopLeft,
            .parent = Pane.Anchor.TopRight,
            .relative_size = false,
        },
    },
    .{
        .id = "oscilloscope",
        .pane = .{
            .width = 1,
            .height = 0.5,
        },
        .relative = .{
            .id = "lissajous",
            .self = Pane.Anchor.TopLeft,
            .parent = Pane.Anchor.BottomLeft,
            .relative_size = false,
        },
    },
    .{
        .id = "graph_scale",
        .pane = .{
            .width = 0.4,
            .height = 0.1,
            .y = -0.04,
        },
        .relative = .{
            .id = "viewport",
            .self = Pane.Anchor.BottomCenter,
            .parent = Pane.Anchor.BottomCenter,
            .relative_size = false,
        },
    },
    .{
        .id = "lissajous_controls",
        .pane = .{
            .width = 0.2,
            .height = 0.1,
            .x = -0.04,
            .y = 0.04,
        },
        .relative = .{
            .id = "lissajous",
            .self = Pane.Anchor.TopRight,
            .parent = Pane.Anchor.TopRight,
            .relative_size = false,
        },
    },
}) = .{},
