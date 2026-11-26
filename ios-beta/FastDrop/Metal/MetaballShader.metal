#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// ──────────────────────────────────────────────
// Shared structs (must match Swift side)
// ──────────────────────────────────────────────

struct Metaball {
    float2 pos;       // normalized 0..1
    float2 vel;       // normalized velocity
    float  radius;    // base radius in normalized coords
    float  stretch;   // 0..0.55 stretch factor along velocity
    float  phase;     // idle wobble phase
    float  _pad[3];   // alignment to 16 bytes
};

struct Uniforms {
    uint       count;
    float      time;
    float2     resolution;   // viewport size in points
    float      pixelRatio;   // UIScreen.scale
    float      threshold;    // metaball threshold (default 0.378)
    float      _pad[3];
};

// ──────────────────────────────────────────────
// Vertex shader (full-screen quad)
// ──────────────────────────────────────────────

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexMain(uint vid [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    const float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = texCoords[vid];
    return out;
}

// ──────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────

float smoothstep3(float edge0, float edge1, float x) {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// HTML prototype: w*w*w falloff
float metaballField(float2 d, float radius, float stretch, float2 vel) {
    if (length(vel) < 0.001) {
        return 1.0 / (1.0 + dot(d, d) / (radius * radius) * 3.61);
    }
    float2 v = normalize(vel);
    float2 perp = float2(-v.y, v.x);
    float2 local = float2(dot(d, v), dot(d, perp));
    float2 scaled = local / float2(radius * (1.0 + stretch), radius * (1.0 - stretch * 0.45));
    return 1.0 / (1.0 + dot(scaled, scaled) * 3.61);
}

// ──────────────────────────────────────────────
// Fragment shader — Metaballs
// ──────────────────────────────────────────────

fragment float4 metaballFragment(
    VertexOut in [[stage_in]],
    constant Uniforms &u [[buffer(0)]],
    constant Metaball *balls [[buffer(1)]]
) {
    float2 uv = in.texCoord;
    float field = 0.0;

    for (uint i = 0; i < u.count; ++i) {
        Metaball b = balls[i];
        float2 d = (uv - b.pos) * u.resolution; // convert to points for radius math
        field += metaballField(d, b.radius, b.stretch, b.vel);
    }

    // ─── Threshold & lighting (match HTML renderDrops) ───
    const float T = 0.378;
    float ins = smoothstep3(T - 0.03, T + 0.03, field);

    if (ins < 0.01) return float4(0.0);

    // Approximate normal via finite differences (cheap, good enough)
    float eps = 1.0 / u.resolution.x;
    float2 dx = float2(eps, 0.0);
    float2 dy = float2(0.0, eps);

    float fx = 0.0, fy = 0.0;
    for (uint i = 0; i < u.count; ++i) {
        Metaball b = balls[i];
        float2 p = (uv - b.pos) * u.resolution;
        fx += metaballField(p + dx, b.radius, b.stretch, b.vel) - metaballField(p - dx, b.radius, b.stretch, b.vel);
        fy += metaballField(p + dy, b.radius, b.stretch, b.vel) - metaballField(p - dy, b.radius, b.stretch, b.vel);
    }
    float2 grad = float2(fx, fy) * u.resolution;
    float g = length(grad);
    float2 n = g > 0.0 ? grad / g : float2(0.0, 1.0);

    // Lighting
    float nl = (n.x + n.y) * 0.7071;              // diagonal light
    float w  = 1.0 - smoothstep3(T, T + 0.2, field);
    float rim = w * ins;
    float spec = pow(max(0.0, nl), 3.0) * rim;
    float back = max(0.0, -nl) * rim;

    float a = min(0.96, 0.34 * ins + 0.4 * rim + 0.55 * spec + 0.22 * back);
    float t = min(1.0, rim * 0.6 + spec);

    // Accent color: #30D158 → rgb(48, 209, 88)
    float3 base = float3(48.0, 209.0, 88.0) / 255.0;
    float3 highlight = float3(125.0, 255.0, 160.0) / 255.0; // #7DFF A0
    float3 color = mix(base, highlight, t);

    return float4(color, a);
}

// ──────────────────────────────────────────────
// Fragment shader — Transfer Scene (rings, black hole, ripple)
// ──────────────────────────────────────────────

struct TransferUniforms {
    float  time;
    float2 center;
    float  progress;       // 0..1 overall
    uint   ringCount;      // active rings
    float  ringProgress[8]; // per-ring progress 0..1
    float2 ringCenter[8];   // per-ring center
    float  ringRadius[8];   // per-ring max radius
    float  blackHoleRadius;
    float  blackHolePulse;
    float  _pad[2];
};

fragment float4 transferFragment(
    VertexOut in [[stage_in]],
    constant TransferUniforms &u [[buffer(0)]]
) {
    float2 uv = in.texCoord;
    float2 p = (uv - 0.5) * 2.0; // -1..1 centered
    float dist = length(p - (u.center - 0.5) * 2.0);
    float3 col = float3(0.0);
    float alpha = 0.0;

    // Black hole
    float bh = smoothstep(u.blackHoleRadius - 0.02, u.blackHoleRadius, dist);
    bh *= 0.5 + 0.5 * sin(u.time * 2.4 + u.blackHolePulse);
    col += float3(0.0, 0.05, 0.02) * bh;
    alpha = max(alpha, bh * 0.9);

    // Rings
    for (uint i = 0; i < u.ringCount; ++i) {
        float2 rc = (u.ringCenter[i] - 0.5) * 2.0;
        float rd = length(p - rc);
        float ringR = u.ringRadius[i];
        float prog = u.ringProgress[i];

        // Stroke ring
        float stroke = smoothstep(ringR - 0.008, ringR, rd) - smoothstep(ringR, ringR + 0.008, rd);
        stroke *= 1.0 - prog; // fade out as progresses
        col += float3(0.3, 1.0, 0.5) * stroke;
        alpha = max(alpha, stroke * 0.8);

        // Fill progress
        if (prog > 0.35) {
            float fill = smoothstep(0.0, ringR * prog, rd);
            col += float3(0.1, 0.4, 0.2) * fill * 0.3;
            alpha = max(alpha, fill * 0.4);
        }
    }

    // Vignette
    float vig = 1.0 - smoothstep(0.7, 1.2, length(p));
    col *= vig;
    alpha *= vig;

    return float4(col, alpha);
}