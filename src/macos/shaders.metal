#include "./shader.h"
#include <metal_stdlib>
#include <metal_math>

using namespace metal;

struct ColoredVertex
{
    float4 position [[position]];
    float time_decay;
    float max_sample;
};

struct AudioFrame
{
    float left;
    float right;
};

vertex ColoredVertex vertex_main(
    constant packed_float3 *position [[buffer(0)]],
    constant AudioFrame *audio_frames [[buffer(1)]],
    constant Uniforms &uniforms [[buffer(2)]],
    ushort vid [[vertex_id]],
    uint iid [[instance_id]]
) {
    ColoredVertex vert;

    AudioFrame frame = audio_frames[iid];

    frame.left *= uniforms.graph_scale;
    frame.right *= uniforms.graph_scale;

    float z = 1.0 - (float) iid / (float) (uniforms.num_frames - 1);

    vert.position = float4(position[vid] * uniforms.point_scale, 1);

    vert.position[0] += clamp(frame.right, -1.0, 1.0);
    vert.position[1] += clamp(frame.left, -1.0, 1.0);
    vert.position[2] = z;

    constant float *m = uniforms.matrix;
    float4x4 mat = float4x4(
        float4(m[0], m[1], m[2], m[3]),
        float4(m[4], m[5], m[6], m[7]),
        float4(m[8], m[9], m[10], m[11]),
        float4(m[12], m[13], m[14], m[15])
    );

    vert.position = mat * vert.position;

    vert.time_decay = 0.7 + (float) iid / (float) (uniforms.num_frames - 1) * 0.3;
    vert.max_sample = max(fabs(frame.left), fabs(frame.right));

    return vert;
}

fragment float4 fragment_main(ColoredVertex vert [[stage_in]])
{
    if (vert.max_sample > 1.0) {
        return float4(1.0, 0.0, 0.0, 1.0);
    } else {
        return float4(1.0, 1.0, 1.0, vert.time_decay);
    }
}
