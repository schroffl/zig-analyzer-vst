const std = @import("std");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const version = std.builtin.Version{
        .major = 0,
        .minor = 1,
        .patch = 0,
    };

    // For some reason a versioned shared library causes zig build to crash
    // on windows.
    const target_tag = target.os_tag orelse std.Target.current.os.tag;

    var bundle_step = MacOSBundle.create(b, "zig-analyzer", "src/main.zig", .{
        .identifier = "org.zig-analyzer",
        .version = if (target_tag == .windows) null else version,
        .target = target,
        .mode = mode,
    });

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    main_tests.addPackagePath("known-folders", "./libs/known-folders/known-folders.zig");
    bundle_step.lib_step.addPackagePath("known-folders", "./libs/known-folders/known-folders.zig");

    b.default_step.dependOn(&bundle_step.step);
}

const MacOSBundle = struct {
    pub const Options = struct {
        identifier: []const u8,
        version: ?std.builtin.Version = null,

        target: std.zig.CrossTarget = std.zig.CrossTarget{},
        mode: ?std.builtin.Mode = null,
    };

    builder: *Builder,
    lib_step: *std.build.LibExeObjStep,
    step: std.build.Step,
    name: []const u8,
    options: Options,

    pub fn create(builder: *Builder, name: []const u8, root_src: []const u8, options: Options) *MacOSBundle {
        const self = builder.allocator.create(MacOSBundle) catch unreachable;

        if (options.version) |version| {
            self.lib_step = builder.addSharedLibrary(name, root_src, .{ .versioned = version });
        } else {
            self.lib_step = builder.addSharedLibrary(name, root_src, .{ .unversioned = {} });
        }

        self.builder = builder;
        self.name = name;
        self.step = std.build.Step.init(.Custom, "macOS .vst bundle", builder.allocator, make);
        self.options = options;

        if (options.mode) |mode| self.lib_step.setBuildMode(mode);
        self.lib_step.setTarget(options.target);
        self.lib_step.install();

        self.step.dependOn(&self.lib_step.step);

        return self;
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(MacOSBundle, "step", step);

        return switch (self.options.target.getOsTag()) {
            .macos => self.makeMacOS(),
            else => {},
        };
    }

    fn makeMacOS(self: *MacOSBundle) !void {
        const bundle_path = try self.getOutputDir();

        const cwd = std.fs.cwd();
        var bundle_dir = try cwd.makeOpenPath(bundle_path, .{});
        defer bundle_dir.close();

        try bundle_dir.makePath("Contents/MacOS");

        const binary_path = try std.fs.path.join(self.builder.allocator, &[_][]const u8{
            "Contents/MacOS",
            self.name,
        });

        const lib_output_path = self.lib_step.getOutputPath();
        try cwd.copyFile(lib_output_path, bundle_dir, binary_path, .{});

        const plist_file = try bundle_dir.createFile("Contents/Info.plist", .{});
        defer plist_file.close();
        try self.writePlist(plist_file);

        const pkginfo_file = try bundle_dir.createFile("Contents/PkgInfo", .{});
        defer pkginfo_file.close();
        try pkginfo_file.writeAll("BNDL????");

        try self.buildObjectiveC();
        try self.buildMetalShaders();
    }

    fn getOutputDir(self: *MacOSBundle) ![]const u8 {
        const vst_path = self.builder.getInstallPath(.Prefix, "vst");
        const bundle_basename = self.builder.fmt("{s}.vst", .{self.name});

        return try std.fs.path.join(self.builder.allocator, &[_][]const u8{
            vst_path,
            bundle_basename,
        });
    }

    fn buildObjectiveC(self: *MacOSBundle) !void {
        const objc_path = try std.fs.path.join(self.builder.allocator, &[_][]const u8{
            self.builder.build_root,
            "src/macos/renderer.m",
        });

        const output_dir = try self.getOutputDir();
        const output_path = try std.fs.path.join(self.builder.allocator, &[_][]const u8{
            output_dir,
            "Contents/MacOS/za-renderer.dynlib",
        });

        _ = try self.builder.exec(&[_][]const u8{
            "clang",
            "-shared",
            "-framework",
            "Foundation",
            "-framework",
            "AppKit",
            "-framework",
            "Metal",
            "-framework",
            "QuartzCore",
            objc_path,
            "-o",
            output_path,
        });
    }

    fn buildMetalShaders(self: *MacOSBundle) !void {
        const src_path = try std.fs.path.join(self.builder.allocator, &[_][]const u8{
            self.builder.build_root,
            "src/macos/shaders.metal",
        });

        const output_dir = try self.getOutputDir();
        const output_path = try std.fs.path.join(self.builder.allocator, &[_][]const u8{
            output_dir,
            "Contents/MacOS/zig-analyzer.metallib",
        });

        _ = try self.builder.exec(&[_][]const u8{
            "xcrun",
            "-sdk",
            "macosx",
            "metal",
            "-fdebug-info-for-profiling",
            "-o",
            output_path,
            src_path,
        });
    }

    fn writePlist(self: *MacOSBundle, file: std.fs.File) !void {
        var writer = file.writer();
        const template = @embedFile("./Info.plist");
        const version_string = if (self.options.version) |version|
            self.builder.fmt("{}.{}.{}", .{
                version.major,
                version.minor,
                version.patch,
            })
        else
            "unversioned";

        var replace_idx: usize = 0;
        const replace = [_][]const u8{
            "English",
            self.name,
            self.options.identifier,
            self.name,
            "????",
            version_string,
            version_string,
        };

        for (template) |char| {
            if (char == '$' and replace_idx < replace.len) {
                try writer.writeAll(replace[replace_idx]);
                replace_idx += 1;
            } else {
                try writer.writeByte(char);
            }
        }
    }
};
