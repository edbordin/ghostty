const builtin = @import("builtin");
const std = @import("std");

const win32 = if (builtin.os.tag == .windows) @import("win32").everything else struct {};
const win32ext = if (builtin.os.tag == .windows) @import("win32ext.zig") else struct {};

pub const UniformPrefix = extern struct {
    projection: [16]f32,
    screen_size: [2]f32,
    cell_size: [2]f32,
};

const TextConstants = extern struct {
    projection: [16]f32,
    cell_size: [2]f32,
    _pad0: [2]f32,
};

pub fn ensureTextPipeline(self: anytype) bool {
    if (builtin.os.tag != .windows) return false;
    if (self.text_ready) return true;
    if (self.device == null) return false;

    var vs_blob: ?*win32.ID3DBlob = null;
    var ps_blob: ?*win32.ID3DBlob = null;
    defer {
        if (vs_blob) |b| _ = b.IUnknown.Release();
    }
    defer {
        if (ps_blob) |b| _ = b.IUnknown.Release();
    }

    if (!compileShader("VSMain", "vs_5_0", &vs_blob)) return false;
    if (!compileShader("PSMain", "ps_5_0", &ps_blob)) return false;

    var vs: ?*win32.ID3D11VertexShader = null;
    const vs_hr = self.device.?.CreateVertexShader(
        @ptrCast(vs_blob.?.GetBufferPointer()),
        vs_blob.?.GetBufferSize(),
        null,
        @ptrCast(&vs),
    );
    if (vs_hr < 0 or vs == null) return false;

    var ps: ?*win32.ID3D11PixelShader = null;
    const ps_hr = self.device.?.CreatePixelShader(
        @ptrCast(ps_blob.?.GetBufferPointer()),
        ps_blob.?.GetBufferSize(),
        null,
        @ptrCast(&ps),
    );
    if (ps_hr < 0 or ps == null) {
        _ = vs.?.IUnknown.Release();
        return false;
    }

    const input_desc = [_]win32.D3D11_INPUT_ELEMENT_DESC{
        .{
            .SemanticName = "GLYPH_POS",
            .SemanticIndex = 0,
            .Format = win32.DXGI_FORMAT_R32G32_UINT,
            .InputSlot = 0,
            .AlignedByteOffset = 0,
            .InputSlotClass = win32.D3D11_INPUT_PER_INSTANCE_DATA,
            .InstanceDataStepRate = 1,
        },
        .{
            .SemanticName = "GLYPH_SIZE",
            .SemanticIndex = 0,
            .Format = win32.DXGI_FORMAT_R32G32_UINT,
            .InputSlot = 0,
            .AlignedByteOffset = 8,
            .InputSlotClass = win32.D3D11_INPUT_PER_INSTANCE_DATA,
            .InstanceDataStepRate = 1,
        },
        .{
            .SemanticName = "BEARINGS",
            .SemanticIndex = 0,
            .Format = win32.DXGI_FORMAT_R16G16_SINT,
            .InputSlot = 0,
            .AlignedByteOffset = 16,
            .InputSlotClass = win32.D3D11_INPUT_PER_INSTANCE_DATA,
            .InstanceDataStepRate = 1,
        },
        .{
            .SemanticName = "GRID_POS",
            .SemanticIndex = 0,
            .Format = win32.DXGI_FORMAT_R16G16_UINT,
            .InputSlot = 0,
            .AlignedByteOffset = 20,
            .InputSlotClass = win32.D3D11_INPUT_PER_INSTANCE_DATA,
            .InstanceDataStepRate = 1,
        },
        .{
            .SemanticName = "COLOR",
            .SemanticIndex = 0,
            .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .InputSlot = 0,
            .AlignedByteOffset = 24,
            .InputSlotClass = win32.D3D11_INPUT_PER_INSTANCE_DATA,
            .InstanceDataStepRate = 1,
        },
        .{
            .SemanticName = "ATLAS",
            .SemanticIndex = 0,
            .Format = win32.DXGI_FORMAT_R8_UINT,
            .InputSlot = 0,
            .AlignedByteOffset = 28,
            .InputSlotClass = win32.D3D11_INPUT_PER_INSTANCE_DATA,
            .InstanceDataStepRate = 1,
        },
    };

    var layout: ?*win32.ID3D11InputLayout = null;
    const layout_hr = self.device.?.CreateInputLayout(
        input_desc[0..].ptr,
        input_desc.len,
        @ptrCast(vs_blob.?.GetBufferPointer()),
        vs_blob.?.GetBufferSize(),
        @ptrCast(&layout),
    );
    if (layout_hr < 0 or layout == null) {
        _ = ps.?.IUnknown.Release();
        _ = vs.?.IUnknown.Release();
        return false;
    }

    var blend_desc: win32.D3D11_BLEND_DESC = std.mem.zeroes(win32.D3D11_BLEND_DESC);
    blend_desc.AlphaToCoverageEnable = win32.FALSE;
    blend_desc.IndependentBlendEnable = win32.FALSE;
    blend_desc.RenderTarget[0] = .{
        .BlendEnable = win32.TRUE,
        .SrcBlend = win32.D3D11_BLEND_ONE,
        .DestBlend = win32.D3D11_BLEND_INV_SRC_ALPHA,
        .BlendOp = win32.D3D11_BLEND_OP_ADD,
        .SrcBlendAlpha = win32.D3D11_BLEND_ONE,
        .DestBlendAlpha = win32.D3D11_BLEND_INV_SRC_ALPHA,
        .BlendOpAlpha = win32.D3D11_BLEND_OP_ADD,
        .RenderTargetWriteMask = @intFromEnum(win32.D3D11_COLOR_WRITE_ENABLE_ALL),
    };

    var blend: ?*win32.ID3D11BlendState = null;
    const blend_hr = self.device.?.CreateBlendState(&blend_desc, @ptrCast(&blend));
    if (blend_hr < 0 or blend == null) {
        _ = layout.?.IUnknown.Release();
        _ = ps.?.IUnknown.Release();
        _ = vs.?.IUnknown.Release();
        return false;
    }

    if (!ensureTextConstantBuffer(self)) {
        _ = blend.?.IUnknown.Release();
        _ = layout.?.IUnknown.Release();
        _ = ps.?.IUnknown.Release();
        _ = vs.?.IUnknown.Release();
        return false;
    }

    self.text_vs = vs;
    self.text_ps = ps;
    self.text_input_layout = layout;
    self.text_blend = blend;
    self.text_ready = true;
    return true;
}

pub fn updateTextConstants(self: anytype, uniforms: []const u8) bool {
    if (builtin.os.tag != .windows) return false;
    if (self.context == null or self.text_constants == null) return false;
    if (uniforms.len < @sizeOf(UniformPrefix)) return false;

    var prefix: UniformPrefix = undefined;
    @memcpy(
        std.mem.asBytes(&prefix),
        uniforms[0..@sizeOf(UniformPrefix)],
    );

    const constants: TextConstants = .{
        .projection = prefix.projection,
        .cell_size = prefix.cell_size,
        ._pad0 = .{ 0.0, 0.0 },
    };
    self.context.?.UpdateSubresource(
        @ptrCast(&self.text_constants.?.ID3D11Resource),
        0,
        null,
        @ptrCast(&constants),
        0,
        0,
    );
    return true;
}

pub fn updateInstanceBuffer(
    self: anytype,
    cells: []const u8,
    stride: u32,
    count: u32,
) bool {
    if (builtin.os.tag != .windows) return false;
    if (self.device == null or self.context == null) return false;
    if (stride == 0 or count == 0) return false;
    const needed: u32 = count * stride;
    if (needed == 0) return false;
    if (cells.len < needed) return false;

    if (self.text_instances == null or self.text_instance_capacity < needed) {
        win32ext.releaseAndNull(win32.ID3D11Buffer, &self.text_instances);
        const grow = if (self.text_instance_capacity == 0) needed else @max(needed, self.text_instance_capacity * 2);

        var buffer: ?*win32.ID3D11Buffer = null;
        const desc: win32.D3D11_BUFFER_DESC = .{
            .ByteWidth = grow,
            .Usage = .DEFAULT,
            .BindFlags = .{ .VERTEX_BUFFER = 1 },
            .CPUAccessFlags = .{},
            .MiscFlags = .{},
            .StructureByteStride = 0,
        };
        const hr = self.device.?.CreateBuffer(&desc, null, @ptrCast(&buffer));
        if (hr < 0 or buffer == null) return false;
        self.text_instances = buffer;
        self.text_instance_capacity = grow;
    }

    self.context.?.UpdateSubresource(
        @ptrCast(&self.text_instances.?.ID3D11Resource),
        0,
        null,
        @ptrCast(cells.ptr),
        0,
        0,
    );
    return true;
}

pub fn updateAtlas(self: anytype, atlas: anytype, data: anytype) bool {
    if (builtin.os.tag != .windows) return false;
    if (self.device == null or self.context == null) return false;
    if (data.width == 0 or data.height == 0) return false;
    const bpp: u32 = switch (data.format) {
        .red => 1,
        .rgba, .bgra => 4,
    };
    const min_size = @as(usize, data.width) * @as(usize, data.height) * @as(usize, bpp);
    if (data.pixels.len < min_size) return false;

    if (atlas.texture == null or atlas.width != data.width or atlas.height != data.height or atlas.format != data.format) {
        releaseAtlas(atlas);

        const format = switch (data.format) {
            .red => win32.DXGI_FORMAT_R8_UNORM,
            .rgba => win32.DXGI_FORMAT_R8G8B8A8_UNORM,
            .bgra => win32.DXGI_FORMAT_B8G8R8A8_UNORM,
        };

        var texture: ?*win32.ID3D11Texture2D = null;
        const desc: win32.D3D11_TEXTURE2D_DESC = .{
            .Width = data.width,
            .Height = data.height,
            .MipLevels = 1,
            .ArraySize = 1,
            .Format = format,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Usage = .DEFAULT,
            .BindFlags = .{ .SHADER_RESOURCE = 1 },
            .CPUAccessFlags = .{},
            .MiscFlags = .{},
        };
        const texture_hr = self.device.?.CreateTexture2D(&desc, null, @ptrCast(&texture));
        if (texture_hr < 0 or texture == null) return false;

        var view: ?*win32.ID3D11ShaderResourceView = null;
        const view_hr = self.device.?.CreateShaderResourceView(
            @ptrCast(&texture.?.ID3D11Resource),
            null,
            @ptrCast(&view),
        );
        if (view_hr < 0 or view == null) {
            _ = texture.?.IUnknown.Release();
            return false;
        }

        atlas.texture = texture;
        atlas.view = view;
        atlas.width = data.width;
        atlas.height = data.height;
        atlas.format = data.format;
    }

    self.context.?.UpdateSubresource(
        @ptrCast(&atlas.texture.?.ID3D11Resource),
        0,
        null,
        @ptrCast(data.pixels.ptr),
        data.width * bpp,
        0,
    );
    return true;
}

pub fn releaseTextPipeline(self: anytype) void {
    if (builtin.os.tag != .windows) return;
    self.text_ready = false;
    releaseAtlas(&self.atlas_gray);
    releaseAtlas(&self.atlas_color);
    self.text_instance_capacity = 0;
    win32ext.releaseAndNull(win32.ID3D11Buffer, &self.text_instances);
    win32ext.releaseAndNull(win32.ID3D11Buffer, &self.text_constants);
    win32ext.releaseAndNull(win32.ID3D11BlendState, &self.text_blend);
    win32ext.releaseAndNull(win32.ID3D11InputLayout, &self.text_input_layout);
    win32ext.releaseAndNull(win32.ID3D11PixelShader, &self.text_ps);
    win32ext.releaseAndNull(win32.ID3D11VertexShader, &self.text_vs);
}

fn compileShader(
    entry: [*:0]const u8,
    target: [*:0]const u8,
    out_blob: *?*win32.ID3DBlob,
) bool {
    var blob: ?*win32.ID3DBlob = null;
    var errors: ?*win32.ID3DBlob = null;
    defer {
        if (errors) |e| _ = e.IUnknown.Release();
    }

    const hr = win32.D3DCompile(
        text_shader_source.ptr,
        text_shader_source.len,
        "ghostty_d3d11_text.hlsl",
        null,
        null,
        entry,
        target,
        0,
        0,
        @ptrCast(&blob),
        @ptrCast(&errors),
    );
    if (hr < 0 or blob == null) return false;
    out_blob.* = blob;
    return true;
}

fn ensureTextConstantBuffer(self: anytype) bool {
    if (self.text_constants != null) return true;
    if (self.device == null) return false;

    var buffer: ?*win32.ID3D11Buffer = null;
    const desc: win32.D3D11_BUFFER_DESC = .{
        .ByteWidth = @sizeOf(TextConstants),
        .Usage = .DEFAULT,
        .BindFlags = .{ .CONSTANT_BUFFER = 1 },
        .CPUAccessFlags = .{},
        .MiscFlags = .{},
        .StructureByteStride = 0,
    };
    const hr = self.device.?.CreateBuffer(&desc, null, @ptrCast(&buffer));
    if (hr < 0 or buffer == null) return false;
    self.text_constants = buffer;
    return true;
}

fn releaseAtlas(atlas: anytype) void {
    win32ext.releaseAndNull(win32.ID3D11ShaderResourceView, &atlas.view);
    win32ext.releaseAndNull(win32.ID3D11Texture2D, &atlas.texture);
    atlas.width = 0;
    atlas.height = 0;
}

const text_shader_source: [:0]const u8 = @embedFile("shaders/text.hlsl");
