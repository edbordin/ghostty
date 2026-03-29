//! Wrapper for D3D11 render pipeline descriptors and native state.
const Self = @This();
const std = @import("std");
const api = @import("api.zig");
const zw = @import("zwindows");
const d3d = zw.d3d11;
const d3dcommon = zw.d3d;
const dxgi = zw.dxgi;
const d3dcompiler = zw.d3dcompiler;
const win32ext = @import("win32ext.zig");

pub const Options = struct {
    device: *d3d.IDevice,
    vertex_fn: [:0]const u8,
    fragment_fn: [:0]const u8,
    step_fn: StepFunction = .per_vertex,
    attachments: []const Attachment = &.{},
    blending_enabled: bool = true,
    d3d11: ?NativeDesc = null,

    pub const StepFunction = enum {
        constant,
        per_vertex,
        per_instance,
    };

    /// Mirrors Metal's attachment-level blending config.
    pub const Attachment = struct {
        blending_enabled: bool = true,
    };

    pub const NativeDesc = struct {
        shader_source: [:0]const u8,
        vertex_entry: [*:0]const u8 = "VSMain",
        pixel_entry: [*:0]const u8 = "PSMain",
        input_elements: []const InputElement = &.{},
        constant_buffer_slots: ConstantBufferSlots = .{},
        srv_slots: []const u32 = &.{},
        sampler_slots: []const u32 = &.{},
        default_sampler: ?SamplerDesc = null,

        pub const InputElement = struct {
            semantic_name: [*:0]const u8,
            semantic_index: u32 = 0,
            format: dxgi.FORMAT,
            input_slot: u32 = 0,
            aligned_byte_offset: u32,
            per_instance: bool = false,
            instance_step_rate: u32 = 0,
        };

        pub const ConstantBufferSlots = struct {
            vertex: ?u32 = null,
            pixel: ?u32 = null,
        };

        pub const SamplerDesc = struct {
            filter: d3d.FILTER = d3d.FILTER.MIN_MAG_MIP_LINEAR,
            address_u: d3d.TEXTURE_ADDRESS_MODE = d3d.TEXTURE_ADDRESS_MODE.CLAMP,
            address_v: d3d.TEXTURE_ADDRESS_MODE = d3d.TEXTURE_ADDRESS_MODE.CLAMP,
            address_w: d3d.TEXTURE_ADDRESS_MODE = d3d.TEXTURE_ADDRESS_MODE.CLAMP,
            min_lod: f32 = 0.0,
            max_lod: f32 = std.math.floatMax(f32),
        };
    };
};

pub const Kind = enum {
    unknown,
    bg_color,
    cell_bg,
    cell_text,
    image,
    bg_image,
    postprocess,
};

pub const NativeState = struct {
    vertex_shader: ?*d3d.IVertexShader = null,
    pixel_shader: ?*d3d.IPixelShader = null,
    input_layout: ?*d3d.IInputLayout = null,
    blend_state: ?*d3d.IBlendState = null,
    default_sampler: ?*d3d.ISamplerState = null,
};

pub const ResourceLayout = struct {
    constant_buffer_slots: Options.NativeDesc.ConstantBufferSlots = .{},
    srv_slots: []const u32 = &.{},
    sampler_slots: []const u32 = &.{},
};

stride: usize = 0,
blending_enabled: bool = true,
kind: Kind = .unknown,
step_fn: Options.StepFunction = .per_vertex,
vertex_fn: [:0]const u8,
fragment_fn: [:0]const u8,
default_primitive: api.Primitive = .triangle,
native: NativeState = .{},
layout: ResourceLayout = .{},

pub fn init(comptime VertexAttributes: ?type, opts: Options) !Self {
    const blending_enabled = if (opts.attachments.len > 0)
        opts.attachments[0].blending_enabled
    else
        opts.blending_enabled;

    const kind = classifyPipeline(opts.vertex_fn, opts.fragment_fn);
    var self: Self = .{
        .stride = if (VertexAttributes) |VA| @sizeOf(VA) else 0,
        .blending_enabled = blending_enabled,
        .kind = kind,
        .step_fn = opts.step_fn,
        .vertex_fn = opts.vertex_fn,
        .fragment_fn = opts.fragment_fn,
        .default_primitive = switch (kind) {
            .cell_text, .image => .triangle_strip,
            else => .triangle,
        },
        .native = .{},
        .layout = .{},
    };

    if (opts.d3d11) |native_desc| {
        self.layout = .{
            .constant_buffer_slots = native_desc.constant_buffer_slots,
            .srv_slots = native_desc.srv_slots,
            .sampler_slots = native_desc.sampler_slots,
        };
        try self.initNative(opts.device, native_desc);
        errdefer self.deinitNative();
    }

    return self;
}

pub fn deinit(self: Self) void {
    if (self.native.default_sampler) |v| _ = v.Release();
    if (self.native.blend_state) |v| _ = v.Release();
    if (self.native.input_layout) |v| _ = v.Release();
    if (self.native.pixel_shader) |v| _ = v.Release();
    if (self.native.vertex_shader) |v| _ = v.Release();
}

fn classifyPipeline(
    vertex_fn: [:0]const u8,
    fragment_fn: [:0]const u8,
) Kind {
    if (std.mem.eql(u8, fragment_fn, "bg_color_fragment")) return .bg_color;
    if (std.mem.eql(u8, fragment_fn, "cell_bg_fragment")) return .cell_bg;
    if (std.mem.eql(u8, fragment_fn, "cell_text_fragment")) return .cell_text;
    if (std.mem.eql(u8, fragment_fn, "image_fragment")) return .image;
    if (std.mem.eql(u8, fragment_fn, "bg_image_fragment")) return .bg_image;
    if (std.mem.eql(u8, vertex_fn, "full_screen_vertex")) return .postprocess;
    return .unknown;
}

fn initNative(
    self: *Self,
    device: *d3d.IDevice,
    desc: Options.NativeDesc,
) !void {
    var vs_blob: ?*d3dcommon.IBlob = null;
    var ps_blob: ?*d3dcommon.IBlob = null;
    defer {
        if (vs_blob) |blob| _ = blob.Release();
    }
    defer {
        if (ps_blob) |blob| _ = blob.Release();
    }

    if (!compileShader(desc.shader_source, desc.vertex_entry, "vs_5_0", &vs_blob)) {
        return error.D3D11Failed;
    }
    if (!compileShader(desc.shader_source, desc.pixel_entry, "ps_5_0", &ps_blob)) {
        return error.D3D11Failed;
    }

    var vs: ?*d3d.IVertexShader = null;
    const vs_hr = device.CreateVertexShader(
        @ptrCast(vs_blob.?.GetBufferPointer()),
        vs_blob.?.GetBufferSize(),
        null,
        @ptrCast(&vs),
    );
    if (vs_hr < 0 or vs == null) return error.D3D11Failed;
    errdefer win32ext.releaseAndNull(d3d.IVertexShader, &vs);

    var ps: ?*d3d.IPixelShader = null;
    const ps_hr = device.CreatePixelShader(
        @ptrCast(ps_blob.?.GetBufferPointer()),
        ps_blob.?.GetBufferSize(),
        null,
        @ptrCast(&ps),
    );
    if (ps_hr < 0 or ps == null) return error.D3D11Failed;
    errdefer win32ext.releaseAndNull(d3d.IPixelShader, &ps);

    var input_layout: ?*d3d.IInputLayout = null;
    if (desc.input_elements.len > 0) {
        const native_inputs = try std.heap.page_allocator.alloc(
            d3d.INPUT_ELEMENT_DESC,
            desc.input_elements.len,
        );
        defer std.heap.page_allocator.free(native_inputs);

        for (desc.input_elements, 0..) |element, i| {
            native_inputs[i] = .{
                .SemanticName = element.semantic_name,
                .SemanticIndex = element.semantic_index,
                .Format = element.format,
                .InputSlot = element.input_slot,
                .AlignedByteOffset = element.aligned_byte_offset,
                .InputSlotClass = if (element.per_instance)
                    d3d.INPUT_CLASSIFICATION.INPUT_PER_INSTANCE_DATA
                else
                    d3d.INPUT_CLASSIFICATION.INPUT_PER_VERTEX_DATA,
                .InstanceDataStepRate = if (element.per_instance)
                    @max(@as(u32, 1), element.instance_step_rate)
                else
                    0,
            };
        }

        const input_hr = device.CreateInputLayout(
            native_inputs.ptr,
            @intCast(native_inputs.len),
            @ptrCast(vs_blob.?.GetBufferPointer()),
            vs_blob.?.GetBufferSize(),
            @ptrCast(&input_layout),
        );
        if (input_hr < 0 or input_layout == null) return error.D3D11Failed;
    }
    errdefer win32ext.releaseAndNull(d3d.IInputLayout, &input_layout);

    var blend_desc: d3d.BLEND_DESC = std.mem.zeroes(d3d.BLEND_DESC);
    blend_desc.AlphaToCoverageEnable = zw.FALSE;
    blend_desc.IndependentBlendEnable = zw.FALSE;
    blend_desc.RenderTarget[0] = .{
        .BlendEnable = if (self.blending_enabled) zw.TRUE else zw.FALSE,
        .SrcBlend = d3d.BLEND.ONE,
        .DestBlend = d3d.BLEND.INV_SRC_ALPHA,
        .BlendOp = d3d.BLEND_OP.ADD,
        .SrcBlendAlpha = d3d.BLEND.ONE,
        .DestBlendAlpha = d3d.BLEND.INV_SRC_ALPHA,
        .BlendOpAlpha = d3d.BLEND_OP.ADD,
        .RenderTargetWriteMask = d3d.COLOR_WRITE_ENABLE.ALL,
    };

    var blend: ?*d3d.IBlendState = null;
    const blend_hr = device.CreateBlendState(&blend_desc, @ptrCast(&blend));
    if (blend_hr < 0 or blend == null) return error.D3D11Failed;

    var sampler: ?*d3d.ISamplerState = null;
    if (desc.default_sampler) |sampler_desc| {
        var native_sampler_desc: d3d.SAMPLER_DESC = .{
            .Filter = sampler_desc.filter,
            .AddressU = sampler_desc.address_u,
            .AddressV = sampler_desc.address_v,
            .AddressW = sampler_desc.address_w,
            .MipLODBias = 0.0,
            .MaxAnisotropy = 1,
            .ComparisonFunc = d3d.COMPARISON_FUNC.NEVER,
            .BorderColor = .{ 0.0, 0.0, 0.0, 0.0 },
            .MinLOD = sampler_desc.min_lod,
            .MaxLOD = sampler_desc.max_lod,
        };
        const sampler_hr = device.CreateSamplerState(
            &native_sampler_desc,
            @ptrCast(&sampler),
        );
        if (sampler_hr < 0 or sampler == null) return error.D3D11Failed;
    }

    self.native = .{
        .vertex_shader = vs,
        .pixel_shader = ps,
        .input_layout = input_layout,
        .blend_state = blend,
        .default_sampler = sampler,
    };
}

fn compileShader(
    source: [:0]const u8,
    entry: [*:0]const u8,
    target: [*:0]const u8,
    out_blob: *?*d3dcommon.IBlob,
) bool {
    var blob: ?*d3dcommon.IBlob = null;
    var errors: ?*d3dcommon.IBlob = null;
    defer {
        if (errors) |e| _ = e.Release();
    }

    const hr = d3dcompiler.D3DCompile(
        source.ptr,
        source.len,
        "ghostty_d3d11_pipeline.hlsl",
        null,
        null,
        entry,
        target,
        0,
        0,
        @ptrCast(&blob),
        @ptrCast(&errors),
    );
    if (hr < 0 or blob == null) {
        if (errors) |e| {
            const ptr = @as([*]const u8, @ptrCast(e.GetBufferPointer()));
            const len = e.GetBufferSize();
            std.debug.print(
                "d3d11 shader compile failed entry={s} target={s} hr=0x{x} errors={s}\n",
                .{ entry, target, @as(u32, @bitCast(hr)), ptr[0..len] },
            );
        } else {
            std.debug.print(
                "d3d11 shader compile failed entry={s} target={s} hr=0x{x}\n",
                .{ entry, target, @as(u32, @bitCast(hr)) },
            );
        }
        return false;
    }
    out_blob.* = blob;
    return true;
}
