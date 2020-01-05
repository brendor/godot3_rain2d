shader_type canvas_item;
render_mode unshaded;

uniform float frame_count = 1.0f;
varying flat lowp float frame_offset;

void vertex() {
	frame_offset = INSTANCE_CUSTOM.x; //INSTANCE_CUSTOM;
}

void fragment() {
	vec2 uv = UV;
	uv.y += frame_offset * (1.0f / frame_count);
	COLOR = texture(TEXTURE, uv) * COLOR;
}
