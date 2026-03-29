const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("../../math.zig");
const zw = @import("zwindows");
const d3d = zw.d3d11;
const dxgi = zw.dxgi;
const shadertoy = @import("../shadertoy.zig");

const Pipeline = @import("Pipeline.zig");
const log = std.log.scoped(.d3d11_shaders);

const frame_constants_source: [:0]const u8 = @embedFile("../shaders/hlsl/frame_constants.hlsi");
const bg_color_shader_source: [:0]const u8 = @embedFile("../shaders/hlsl/bg_color.hlsl");
const text_shader_source: [:0]const u8 = @embedFile("../shaders/hlsl/text.hlsl");
const image_shader_source: [:0]const u8 = @embedFile("../shaders/hlsl/image.hlsl");
const bg_image_shader_source: [:0]const u8 = @embedFile("../shaders/hlsl/bg_image.hlsl");
const cell_bg_shader_source: [:0]const u8 = @embedFile("../shaders/hlsl/cell_bg.hlsl");
const postprocess_vertex_shader_source: [:0]const u8 = @embedFile("../shaders/hlsl/postprocess_vertex.hlsl");

const text_input_elements = [_]Pipeline.Options.NativeDesc.InputElement{
    .{
        .semantic_name = "GLYPH_POS",
        .format = dxgi.FORMAT.R32G32_UINT,
        .aligned_byte_offset = 0,
        .per_instance = true,
    },
    .{
        .semantic_name = "GLYPH_SIZE",
        .format = dxgi.FORMAT.R32G32_UINT,
        .aligned_byte_offset = 8,
        .per_instance = true,
    },
    .{
        .semantic_name = "BEARINGS",
        .format = dxgi.FORMAT.R16G16_SINT,
        .aligned_byte_offset = 16,
        .per_instance = true,
    },
    .{
        .semantic_name = "GRID_POS",
        .format = dxgi.FORMAT.R16G16_UINT,
        .aligned_byte_offset = 20,
        .per_instance = true,
    },
    .{
        .semantic_name = "COLOR",
        .format = dxgi.FORMAT.R8G8B8A8_UNORM,
        .aligned_byte_offset = 24,
        .per_instance = true,
    },
    .{
        .semantic_name = "ATLAS",
        .format = dxgi.FORMAT.R8_UINT,
        .aligned_byte_offset = 28,
        .per_instance = true,
    },
    .{
        .semantic_name = "GLYPH_BOOLS",
        .format = dxgi.FORMAT.R8_UINT,
        .aligned_byte_offset = 29,
        .per_instance = true,
    },
};

const image_input_elements = [_]Pipeline.Options.NativeDesc.InputElement{
    .{
        .semantic_name = "GRID_POS",
        .format = dxgi.FORMAT.R32G32_FLOAT,
        .aligned_byte_offset = 0,
        .per_instance = true,
    },
    .{
        .semantic_name = "CELL_OFFSET",
        .format = dxgi.FORMAT.R32G32_FLOAT,
        .aligned_byte_offset = 8,
        .per_instance = true,
    },
    .{
        .semantic_name = "SOURCE_RECT",
        .format = dxgi.FORMAT.R32G32B32A32_FLOAT,
        .aligned_byte_offset = 16,
        .per_instance = true,
    },
    .{
        .semantic_name = "DEST_SIZE",
        .format = dxgi.FORMAT.R32G32_FLOAT,
        .aligned_byte_offset = 32,
        .per_instance = true,
    },
};

const bg_image_input_elements = [_]Pipeline.Options.NativeDesc.InputElement{
    .{
        .semantic_name = "OPACITY",
        .format = dxgi.FORMAT.R32_FLOAT,
        .aligned_byte_offset = 0,
        .per_instance = true,
    },
    .{
        .semantic_name = "INFO",
        .format = dxgi.FORMAT.R8_UINT,
        .aligned_byte_offset = 4,
        .per_instance = true,
    },
};

const pipeline_descs: []const struct { [:0]const u8, PipelineDescription } =
    &.{
        .{ "bg_color", .{
            .vertex_fn = "full_screen_vertex",
            .fragment_fn = "bg_color_fragment",
            .blending_enabled = false,
            .d3d11 = .{
                .shader_source = bg_color_shader_source,
                .constant_buffer_slots = .{ .pixel = 0 },
            },
        } },
        .{ "cell_bg", .{
            .vertex_fn = "full_screen_vertex",
            .fragment_fn = "cell_bg_fragment",
            .blending_enabled = true,
            .d3d11 = .{
                .shader_source = cell_bg_shader_source,
                .constant_buffer_slots = .{ .pixel = 0 },
                .srv_slots = &.{2},
            },
        } },
        .{ "cell_text", .{
            .vertex_attributes = CellText,
            .vertex_fn = "cell_text_vertex",
            .fragment_fn = "cell_text_fragment",
            .step_fn = .per_instance,
            .blending_enabled = true,
            .d3d11 = .{
                .shader_source = text_shader_source,
                .input_elements = &text_input_elements,
                .constant_buffer_slots = .{ .vertex = 0, .pixel = 0 },
                .srv_slots = &.{ 0, 1, 2 },
            },
        } },
        .{ "image", .{
            .vertex_attributes = Image,
            .vertex_fn = "image_vertex",
            .fragment_fn = "image_fragment",
            .step_fn = .per_instance,
            .blending_enabled = true,
            .d3d11 = .{
                .shader_source = image_shader_source,
                .input_elements = &image_input_elements,
                .constant_buffer_slots = .{ .vertex = 0, .pixel = 0 },
                .srv_slots = &.{0},
                .sampler_slots = &.{0},
                .default_sampler = .{
                    .filter = d3d.FILTER.MIN_MAG_MIP_LINEAR,
                },
            },
        } },
        .{ "bg_image", .{
            .vertex_attributes = BgImage,
            .vertex_fn = "bg_image_vertex",
            .fragment_fn = "bg_image_fragment",
            .step_fn = .per_instance,
            .blending_enabled = true,
            .d3d11 = .{
                .shader_source = bg_image_shader_source,
                .input_elements = &bg_image_input_elements,
                .constant_buffer_slots = .{ .vertex = 0, .pixel = 0 },
                .srv_slots = &.{0},
                .sampler_slots = &.{0},
                .default_sampler = .{
                    .filter = d3d.FILTER.MIN_MAG_MIP_LINEAR,
                },
            },
        } },
    };

const PipelineDescription = struct {
    vertex_attributes: ?type = null,
    vertex_fn: [:0]const u8,
    fragment_fn: [:0]const u8,
    step_fn: Pipeline.Options.StepFunction = .per_vertex,
    blending_enabled: bool = true,
    d3d11: ?Pipeline.Options.NativeDesc = null,

    fn initPipeline(
        self: PipelineDescription,
        device: *d3d.IDevice,
        shader_source: ?[:0]const u8,
    ) !Pipeline {
        var native_desc = self.d3d11;
        if (shader_source) |source| {
            if (native_desc) |desc| {
                var updated = desc;
                updated.shader_source = source;
                native_desc = updated;
            }
        }

        return try .init(self.vertex_attributes, .{
            .device = device,
            .vertex_fn = self.vertex_fn,
            .fragment_fn = self.fragment_fn,
            .step_fn = self.step_fn,
            .attachments = &.{.{
                .blending_enabled = self.blending_enabled,
            }},
            .d3d11 = native_desc,
        });
    }
};

fn composeShaderSource(alloc: Allocator, body: [:0]const u8) ![:0]u8 {
    const total_len = frame_constants_source.len + body.len;
    var source = try alloc.allocSentinel(u8, total_len, 0);
    @memcpy(source[0..frame_constants_source.len], frame_constants_source[0..]);
    @memcpy(source[frame_constants_source.len..], body[0..]);
    return source;
}

fn composePostShaderSource(
    alloc: Allocator,
    post_shader_source: [:0]const u8,
) ![:0]u8 {
    const separator = "\n\n";
    const total_len = postprocess_vertex_shader_source.len + separator.len + post_shader_source.len;
    var source = try alloc.allocSentinel(u8, total_len, 0);
    var off: usize = 0;
    @memcpy(source[off .. off + postprocess_vertex_shader_source.len], postprocess_vertex_shader_source[0..]);
    off += postprocess_vertex_shader_source.len;
    @memcpy(source[off .. off + separator.len], separator);
    off += separator.len;
    @memcpy(source[off .. off + post_shader_source.len], post_shader_source[0..]);
    return source;
}

pub const Uniforms = extern struct {
    projection_matrix: math.Mat align(16),
    screen_size: [2]f32 align(8),
    cell_size: [2]f32 align(8),
    grid_size: [2]u16 align(4),
    grid_padding: [4]f32 align(16),
    padding_extend: PaddingExtend align(4),
    min_contrast: f32 align(4),
    cursor_pos: [2]u16 align(4),
    cursor_color: [4]u8 align(4),
    bg_color: [4]u8 align(4),
    bools: Bools align(4),

    const Bools = packed struct(u32) {
        cursor_wide: bool,
        use_display_p3: bool,
        use_linear_blending: bool,
        use_linear_correction: bool = false,
        _padding: u28 = 0,
    };

    const PaddingExtend = packed struct(u32) {
        left: bool = false,
        right: bool = false,
        up: bool = false,
        down: bool = false,
        _padding: u28 = 0,
    };
};

pub const CellText = extern struct {
    glyph_pos: [2]u32 align(8) = .{ 0, 0 },
    glyph_size: [2]u32 align(8) = .{ 0, 0 },
    bearings: [2]i16 align(4) = .{ 0, 0 },
    grid_pos: [2]u16 align(4),
    color: [4]u8 align(4),
    atlas: Atlas align(1),
    bools: packed struct(u8) {
        no_min_contrast: bool = false,
        is_cursor_glyph: bool = false,
        _padding: u6 = 0,
    } align(1) = .{},

    pub const Atlas = enum(u8) {
        grayscale = 0,
        color = 1,
    };
};

pub const CellBg = [4]u8;

pub const Image = extern struct {
    grid_pos: [2]f32 align(8),
    cell_offset: [2]f32 align(8),
    source_rect: [4]f32 align(16),
    dest_size: [2]f32 align(8),
};

pub const BgImage = extern struct {
    opacity: f32 align(4),
    info: Info align(1),

    pub const Info = packed struct(u8) {
        position: Position,
        fit: Fit,
        repeat: bool,
        _padding: u1 = 0,

        pub const Position = enum(u4) {
            tl = 0,
            tc = 1,
            tr = 2,
            ml = 3,
            mc = 4,
            mr = 5,
            bl = 6,
            bc = 7,
            br = 8,
        };

        pub const Fit = enum(u2) {
            contain = 0,
            cover = 1,
            stretch = 2,
            none = 3,
        };
    };
};

const PipelineCollection = t: {
    var fields: [pipeline_descs.len]std.builtin.Type.StructField = undefined;
    for (pipeline_descs, 0..) |pipeline, i| {
        fields[i] = .{
            .name = pipeline[0],
            .type = Pipeline,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Pipeline),
        };
    }
    break :t @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
};

pub const Shaders = struct {
    pipelines: PipelineCollection,
    post_pipelines: []const Pipeline = &.{},
    defunct: bool = false,

    pub fn init(
        alloc: Allocator,
        device: *d3d.IDevice,
        post_shaders: []const [:0]const u8,
    ) !Shaders {
        var pipelines: PipelineCollection = undefined;
        var initialized: usize = 0;
        errdefer inline for (pipeline_descs, 0..) |pipeline, i| {
            if (i < initialized) @field(pipelines, pipeline[0]).deinit();
        };

        inline for (pipeline_descs) |pipeline| {
            var composed_source: ?[:0]u8 = null;
            defer if (composed_source) |source| alloc.free(source);

            if (pipeline[1].d3d11) |desc| {
                composed_source = try composeShaderSource(alloc, desc.shader_source);
            }

            @field(pipelines, pipeline[0]) = try pipeline[1].initPipeline(
                device,
                if (composed_source) |source| source else null,
            );
            initialized += 1;
        }

        const post_pipelines: []Pipeline = initPostPipelines(
            alloc,
            device,
            post_shaders,
        ) catch |err| err: {
            // Keep renderer startup resilient if a custom shader fails.
            log.warn("error initializing postprocess shaders err={}", .{err});
            break :err &.{};
        };

        return .{
            .pipelines = pipelines,
            .post_pipelines = post_pipelines,
        };
    }

    pub fn deinit(self: *Shaders, alloc: Allocator) void {
        if (self.defunct) return;
        self.defunct = true;
        inline for (pipeline_descs) |pipeline| {
            @field(self.pipelines, pipeline[0]).deinit();
        }

        for (self.post_pipelines) |*pipeline| {
            pipeline.deinit();
        }
        if (self.post_pipelines.len > 0) {
            alloc.free(self.post_pipelines);
        }
    }
};

fn initPostPipelines(
    alloc: Allocator,
    device: *d3d.IDevice,
    post_shaders: []const [:0]const u8,
) ![]Pipeline {
    if (post_shaders.len == 0) return &.{};

    var built = try alloc.alloc(Pipeline, post_shaders.len);
    errdefer alloc.free(built);
    var post_initialized: usize = 0;
    errdefer {
        for (built, 0..) |*pipeline, i| {
            if (i >= post_initialized) break;
            pipeline.deinit();
        }
    }

    for (post_shaders, 0..) |post_shader_source, i| {
        const composed_post_source = try composePostShaderSource(alloc, post_shader_source);
        defer alloc.free(composed_post_source);

        built[i] = try Pipeline.init(null, .{
            .device = device,
            .vertex_fn = "full_screen_vertex",
            .fragment_fn = "postprocess_fragment",
            .attachments = &.{.{
                .blending_enabled = false,
            }},
            .d3d11 = .{
                .shader_source = composed_post_source,
                .vertex_entry = "GhosttyPostVS",
                .pixel_entry = shadertoy.hlsl_entry_point,
                .constant_buffer_slots = .{ .pixel = 1 },
                .srv_slots = &.{0},
                .sampler_slots = &.{0},
                .default_sampler = .{
                    .filter = d3d.FILTER.MIN_MAG_MIP_LINEAR,
                },
            },
        });
        post_initialized += 1;
    }

    return built;
}
