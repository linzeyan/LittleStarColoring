#include <metal_stdlib>
using namespace metal;

// Layouts mirror Dab (StrokeBuilder.swift), DabUniforms and ComposeUniforms
// (CanvasRenderer.swift). Change both sides together.

struct Dab {
    float2 center;
    float size;
    float rotation;
    float opacity;
    float lightness;
    float dryness;
    float hue;           // < 0: the uniform color; else the rainbow brush's own
};

struct DabUniforms {
    float4 color;        // premultiplied
    float2 targetSize;   // pixels of the texture being drawn into
    float grainAmount;   // how deep the paper's valleys are
    float grainScale;
    float grainSoftness; // small: crisp specks of bare paper; 1: only lighter and darker
    float aspect;        // tip width / height
    uint tintMode;
};

struct ComposeUniforms {
    float strokeOpacity;
    float edgeDarken;
    float edgeRadius;    // uv units of the stroke texture
    float canvasSize;
    uint strokeMode;
};

// tintMode: 0 procedural tip (A = coverage, R = lightness); 1 kaomoji (A = coverage,
// drawn in the palette color); 2 emoji (the texture's own premultiplied color).
constant uint kTintShape = 0;
constant uint kTintImage = 2;

// strokeMode: 0 no stroke in progress; 1 painting; 2 erasing; 3 stamping (above the lines).
constant uint kStrokeOver = 1;
constant uint kStrokeErase = 2;
constant uint kStrokeAbove = 3;

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

// One oversized triangle covers the target; uv (0,0) is the top-left texel.
vertex FullscreenOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

// The in-progress stroke as it will land. Shared by the live preview (compose) and
// the merge into the paint layer, so what the child sees mid-stroke is what stays.
float4 stroke_effect(texture2d<float> stroke, float2 uv, constant ComposeUniforms &u) {
    constexpr sampler s(filter::linear, address::clamp_to_zero);
    float4 c = stroke.sample(s, uv);
    if (u.edgeDarken > 0.0 && c.a > 0.001) {
        // Watercolor pigment drifts to the edge of a wash as it dries: darken where
        // this texel is denser than its surroundings, i.e. just inside the boundary.
        float r = u.edgeRadius;
        float around = 0.25 * (stroke.sample(s, uv + float2(r, 0)).a + stroke.sample(s, uv - float2(r, 0)).a
                             + stroke.sample(s, uv + float2(0, r)).a + stroke.sample(s, uv - float2(0, r)).a);
        float edge = saturate((c.a - around) * 4.0);
        float3 color = c.rgb / c.a * (1.0 - edge * u.edgeDarken * 0.3);
        float a = saturate(c.a * (1.0 + edge * u.edgeDarken));
        c = float4(color * a, a);
    }
    return c * u.strokeOpacity;
}

fragment float4 compose_fragment(FullscreenOut in [[stage_in]],
                                 texture2d<uint, access::read> labels [[texture(0)]],
                                 texture2d<float> layer [[texture(1)]],
                                 texture2d<float> stroke [[texture(2)]],
                                 texture2d<float> line [[texture(3)]],
                                 texture2d<float> stamps [[texture(4)]],
                                 constant float4 *palette [[buffer(0)]],
                                 constant ComposeUniforms &u [[buffer(1)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
    uint2 px = uint2(clamp(in.uv * u.canvasSize, 0.0, u.canvasSize - 1.0));
    float4 base = palette[labels.read(px).r];
    float4 paint = layer.sample(s, in.uv);
    float4 top = stamps.sample(s, in.uv);
    if (u.strokeMode == kStrokeOver) {
        float4 st = stroke_effect(stroke, in.uv, u);
        paint = st + paint * (1.0 - st.a);
    } else if (u.strokeMode == kStrokeAbove) {
        float4 st = stroke_effect(stroke, in.uv, u);
        top = st + top * (1.0 - st.a);
    } else if (u.strokeMode == kStrokeErase) {
        float keep = 1.0 - stroke.sample(s, in.uv).a;
        paint *= keep;
        top *= keep;
    }
    // Fill sits under paint, line art over that, stamps over everything: a stroke can't
    // hide the lines, a fill can't hide a stroke, and a stamp is a sticker on top.
    float3 c = paint.rgb + base.rgb * (1.0 - paint.a);
    float ink = line.sample(s, in.uv).r;
    c *= 1.0 - ink;
    return float4(top.rgb + c * (1.0 - top.a), 1.0);
}

// The kept composite onto the drawable, texel for pixel: both are the same size.
fragment float4 copy_fragment(FullscreenOut in [[stage_in]],
                              texture2d<float, access::read> source [[texture(0)]]) {
    return source.read(uint2(in.position.xy));
}

// Lands a finished stroke on its layer.
fragment float4 merge_fragment(FullscreenOut in [[stage_in]],
                               texture2d<float> stroke [[texture(0)]],
                               constant ComposeUniforms &u [[buffer(0)]]) {
    return stroke_effect(stroke, in.uv, u);
}

struct DabOut {
    float4 position [[position]];
    float2 uv;
    float2 canvasPos;
    float opacity;
    float lightness;
    float dryness;
    float hue;
};

// Bright and saturated, so every band of a rainbow stroke reads as a crayon-box color
// (HSV with saturation 0.8, value 0.95).
float3 rainbow(float hue) {
    float3 k = fmod(float3(5.0, 3.0, 1.0) + hue * 6.0, 6.0);
    return 0.95 - 0.95 * 0.8 * saturate(min(k, 4.0 - k));
}

vertex DabOut dab_vertex(uint vid [[vertex_id]],
                         uint iid [[instance_id]],
                         const device Dab *dabs [[buffer(0)]],
                         constant DabUniforms &u [[buffer(1)]]) {
    const float2 corners[4] = { float2(-0.5, -0.5), float2(0.5, -0.5), float2(-0.5, 0.5), float2(0.5, 0.5) };
    Dab d = dabs[iid];
    float2 c = corners[vid];
    float2 local = float2(c.x * u.aspect, c.y) * d.size;
    float cs = cos(d.rotation), sn = sin(d.rotation);
    float2 p = d.center + float2(local.x * cs - local.y * sn, local.x * sn + local.y * cs);
    DabOut out;
    out.position = float4(p.x / u.targetSize.x * 2.0 - 1.0, 1.0 - p.y / u.targetSize.y * 2.0, 0.0, 1.0);
    out.uv = c + 0.5;
    out.canvasPos = p;
    out.opacity = d.opacity;
    out.lightness = d.lightness;
    out.dryness = d.dryness;
    out.hue = d.hue;
    return out;
}

fragment float4 dab_fragment(DabOut in [[stage_in]],
                             texture2d<float> tip [[texture(0)]],
                             texture2d<float> grain [[texture(1)]],
                             constant DabUniforms &u [[buffer(1)]]) {
    constexpr sampler tipSampler(filter::linear, mip_filter::linear, address::clamp_to_zero);
    constexpr sampler grainSampler(filter::linear, address::repeat);
    float4 t = tip.sample(tipSampler, in.uv);
    if (u.tintMode == kTintImage) {
        return t * in.opacity;
    }
    // How hard this spot of the tip presses paint onto the paper.
    float a = t.a * in.opacity;
    float3 rgb = in.hue < 0.0 ? u.color.rgb : rainbow(in.hue);
    if (u.tintMode == kTintShape) {
        // R 0.5 keeps the color; above lifts it toward white (light catching a ridge of
        // paint), below darkens it (the groove between bristles).
        float l = t.r * 2.0 * in.lightness;
        rgb = l > 1.0 ? mix(rgb, float3(1.0), saturate(l - 1.0)) : rgb * l;
        if (in.dryness > 0.0) {
            // G is how much paint each hair carries. A drying brush loses its poorest
            // hairs first, so the stroke breaks into streaks along its length.
            a *= smoothstep(in.dryness - 0.08, in.dryness + 0.08, t.g);
        }
    }
    if (u.grainAmount > 0.0) {
        // Paper tooth, fixed to the canvas so it doesn't smear along a stroke: paint
        // reaches the peaks first, and a valley only under enough pressure.
        float h = grain.sample(grainSampler, in.canvasPos / (256.0 * u.grainScale)).r;
        a = saturate((a - (1.0 - h) * u.grainAmount) / u.grainSoftness);
    }
    return float4(rgb * a, a);
}
