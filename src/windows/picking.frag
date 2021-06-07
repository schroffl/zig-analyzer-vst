#version 330

layout (location = 0) out vec4 picking;

uniform vec4 picking_id;

void main() {
    picking = picking_id;
}
