const std = @import("std");
const font = @import("../font/main.zig");
const shadertoy = @import("shadertoy.zig");
const Interface = @import("interface").Interface;

pub fn validateRendererContracts(
    comptime GraphicsAPI: type,
    comptime RendererType: type,
) void {
    @setEvalBranchQuota(200_000);
    validateGraphicsApiDecls(GraphicsAPI);
    validateGraphicsApiMethods(GraphicsAPI, RendererType);
    validateGraphicsTypes(GraphicsAPI);
    validateBufferTypes(GraphicsAPI);
}

fn validateGraphicsApiDecls(comptime GraphicsAPI: type) void {
    _ = GraphicsAPI.Target;
    _ = GraphicsAPI.Buffer;
    _ = GraphicsAPI.Sampler;
    _ = GraphicsAPI.Texture;
    _ = GraphicsAPI.RenderPass;
    _ = GraphicsAPI.Frame;
    _ = GraphicsAPI.Pipeline;
    _ = GraphicsAPI.shaders;
    _ = GraphicsAPI.shaders.Shaders;

    _ = GraphicsAPI.SurfaceSize;
    _ = GraphicsAPI.Sampler.Options;
    _ = GraphicsAPI.Texture.Options;
    _ = GraphicsAPI.ImageTextureFormat;
    _ = GraphicsAPI.RenderPass.Options;
    _ = GraphicsAPI.RenderPass.Options.Attachment;
    _ = GraphicsAPI.RenderPass.Step;
    _ = GraphicsAPI.bufferOptions;
    _ = GraphicsAPI.uniformBufferOptions;
    _ = GraphicsAPI.fgBufferOptions;
    _ = GraphicsAPI.bgBufferOptions;
    _ = GraphicsAPI.imageBufferOptions;
    _ = GraphicsAPI.bgImageBufferOptions;
    _ = GraphicsAPI.textureOptions;
    _ = GraphicsAPI.imageTextureOptions;
    _ = GraphicsAPI.samplerOptions;

    const custom_shader_target: shadertoy.Target = GraphicsAPI.custom_shader_target;
    _ = custom_shader_target;
    const custom_shader_y_is_down: bool = GraphicsAPI.custom_shader_y_is_down;
    _ = custom_shader_y_is_down;
    const swap_chain_count: usize = GraphicsAPI.swap_chain_count;
    _ = swap_chain_count;

    if (!@hasField(GraphicsAPI, "blending")) {
        @compileError(std.fmt.comptimePrint(
            "Renderer contract: type '{s}' is missing field 'blending'",
            .{@typeName(GraphicsAPI)},
        ));
    }
}

fn validateGraphicsApiMethods(
    comptime GraphicsAPI: type,
    comptime RendererType: type,
) void {
    const GraphicsApiContract = Interface(.{
        .deinit = fn() void,
        .drawFrameStart = fn() void,
        .drawFrameEnd = fn() void,
        .initShaders = fn(std.mem.Allocator, []const [:0]const u8) anyerror!GraphicsAPI.shaders.Shaders,
        .surfaceSize = fn() anyerror!GraphicsAPI.SurfaceSize,
        .initTarget = fn(usize, usize) anyerror!GraphicsAPI.Target,
        .presentLastTarget = fn() anyerror!void,
        .beginFrame = fn(*RendererType, *GraphicsAPI.Target) anyerror!GraphicsAPI.Frame,
        .initAtlasTexture = fn(*const font.Atlas) anyerror!GraphicsAPI.Texture,
    }, null);
    comptime GraphicsApiContract.validation.satisfiedBy(GraphicsAPI);
}

fn validateGraphicsTypes(comptime GraphicsAPI: type) void {
    const FrameContract = Interface(.{
        .renderPass = fn([]const GraphicsAPI.RenderPass.Options.Attachment) GraphicsAPI.RenderPass,
        .complete = fn(bool) void,
    }, null);
    comptime FrameContract.validation.satisfiedBy(GraphicsAPI.Frame);

    const RenderPassContract = Interface(.{
        .step = fn(GraphicsAPI.RenderPass.Step) void,
        .complete = fn() void,
    }, null);
    comptime RenderPassContract.validation.satisfiedBy(GraphicsAPI.RenderPass);

    const TargetContract = Interface(.{
        .deinit = fn() void,
    }, null);
    comptime TargetContract.validation.satisfiedBy(GraphicsAPI.Target);

    const TextureContract = Interface(.{
        .deinit = fn() void,
        .replaceRegion = fn(usize, usize, usize, usize, []const u8) anyerror!void,
    }, null);
    comptime TextureContract.validation.satisfiedBy(GraphicsAPI.Texture);

    const SamplerContract = Interface(.{
        .deinit = fn() void,
    }, null);
    comptime SamplerContract.validation.satisfiedBy(GraphicsAPI.Sampler);

    const ShaderContract = Interface(.{
        .deinit = fn(std.mem.Allocator) void,
    }, null);
    comptime ShaderContract.validation.satisfiedBy(GraphicsAPI.shaders.Shaders);
}

fn validateBufferTypes(comptime GraphicsAPI: type) void {
    const shaderpkg = GraphicsAPI.shaders;

    validateBufferType(GraphicsAPI.Buffer(shaderpkg.Uniforms), shaderpkg.Uniforms, false);
    validateBufferType(GraphicsAPI.Buffer(shaderpkg.CellBg), shaderpkg.CellBg, false);
    validateBufferType(GraphicsAPI.Buffer(shaderpkg.CellText), shaderpkg.CellText, true);
    validateBufferType(GraphicsAPI.Buffer(shaderpkg.BgImage), shaderpkg.BgImage, false);
    validateBufferType(GraphicsAPI.Buffer(shadertoy.Uniforms), shadertoy.Uniforms, false);
    validateBufferType(GraphicsAPI.Buffer(shaderpkg.Image), shaderpkg.Image, true);
}

fn validateBufferType(
    comptime BufferType: type,
    comptime ElemType: type,
    comptime needs_sync_from_lists: bool,
) void {
    @setEvalBranchQuota(50_000);

    const BufferContract = Interface(.{
        .deinit = fn() void,
        .sync = fn([]const ElemType) anyerror!void,
    }, null);
    comptime BufferContract.validation.satisfiedBy(BufferType);

    if (needs_sync_from_lists) {
        const SyncFromListsContract = Interface(.{
            .syncFromArrayLists = fn([]const std.ArrayListUnmanaged(ElemType)) anyerror!usize,
        }, null);
        comptime SyncFromListsContract.validation.satisfiedBy(BufferType);
    }
}
