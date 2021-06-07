#version 330

in vec2 tex_pos;

uniform sampler2D heat_tex;
uniform sampler2D scale_tex;

uniform float gamma, exposure;

out vec4 color;

float reinhardToneMapping(float value) {
    float gamma = 0.7;
    float exposure = 1.9;

    value *= exposure / (1.0 + value / exposure);
    value = pow(value, 1.0 / gamma);
    return value;
}

void main() {
    vec2 offset = vec2(0.01, 0.01);

    float intensity = 0.0;
    float corner = 0.0625;
    float adjacent = 0.125;
    float center = 0.25;

    intensity += texture(heat_tex, tex_pos + vec2(-offset.x, -offset.y)).a * corner;
    intensity += texture(heat_tex, tex_pos + vec2(0.0, -offset.y)).a * adjacent;
    intensity += texture(heat_tex, tex_pos + vec2(offset.x, -offset.y)).a * corner;
    intensity += texture(heat_tex, tex_pos + vec2(-offset.x, 0.0)).a * adjacent;
    intensity += texture(heat_tex, tex_pos + vec2(0.0, 0.0)).a * center;
    intensity += texture(heat_tex, tex_pos + vec2(offset.x, 0.0)).a * corner;
    intensity += texture(heat_tex, tex_pos + vec2(-offset.x, offset.y)).a * corner;
    intensity += texture(heat_tex, tex_pos + vec2(0.0, offset.y)).a * adjacent;
    intensity += texture(heat_tex, tex_pos + vec2(offset.x, offset.y)).a * corner;

    intensity = reinhardToneMapping(intensity);

    vec3 low = vec3(0.3, 0.05, 0.1);
    vec3 high = vec3(0.7, 0.5, 0.3);
    // vec3 col = vec3(1.0, 0.0, 0.0);
    vec3 col = mix(low, high, intensity);

    float scale_pos = 1.0 - intensity;
    color = texture(scale_tex, vec2(scale_pos, 0.0));
}

