// serval-15q
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Stable semantic center: schema model, value representation, errors.
    const core_mod = b.addModule("serval-core", .{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Constraints, defaults, coercions, validation engine.
    const validate_mod = b.addModule("serval-validate", .{
        .root_source_file = b.path("src/validate/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    validate_mod.addImport("serval-core", core_mod);

    // Reader/writer-facing encode/decode interfaces and allocation strategies.
    const codec_mod = b.addModule("serval-codec", .{
        .root_source_file = b.path("src/codec/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    codec_mod.addImport("serval-core", core_mod);
    codec_mod.addImport("serval-validate", validate_mod);

    // JSON backend (first format; ZON and msgpack land in later milestones).
    const json_mod = b.addModule("serval-json", .{
        .root_source_file = b.path("src/formats/json/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    json_mod.addImport("serval-core", core_mod);
    json_mod.addImport("serval-codec", codec_mod);
    // serval-r4h: decode pipeline integrates validation
    json_mod.addImport("serval-validate", validate_mod);

    // Umbrella module: `@import("serval")` re-exports core/validate/codec/json.
    const umbrella = b.addModule("serval", .{
        .root_source_file = b.path("src/serval.zig"),
        .target = target,
        .optimize = optimize,
    });
    umbrella.addImport("serval-core", core_mod);
    umbrella.addImport("serval-validate", validate_mod);
    umbrella.addImport("serval-codec", codec_mod);
    umbrella.addImport("serval-json", json_mod);

    // Tests
    const test_step = b.step("test", "Run unit tests");
    const test_files = [_][]const u8{
        "tests/schema_test.zig",
        "tests/validation_test.zig",
        "tests/json_test.zig",
    };
    for (test_files) |tf| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(tf),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "serval", .module = umbrella },
                },
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // Examples
    const examples_step = b.step("examples", "Build examples");
    const examples = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "basic_json", .path = "examples/basic_json.zig" },
        .{ .name = "config_validation", .path = "examples/config_validation.zig" },
        .{ .name = "zero_alloc_decode", .path = "examples/zero_alloc_decode.zig" },
    };
    for (examples) |ex| {
        const exe = b.addExecutable(.{
            .name = ex.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(ex.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "serval", .module = umbrella },
                },
            }),
        });
        examples_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    }
}
