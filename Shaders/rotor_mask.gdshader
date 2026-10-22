shader_type canvas_item;
uniform vec4 frame = vec4(0.,0.,1.,1.);
varying vec4 vertex_tint;
void vertex() { vertex_tint=COLOR; }
void fragment() {
 vec2 p=(UV-frame.xy)/frame.zw;
 float mask=1.0-smoothstep(.45,.5,length(p-.5));
 vec4 texel=texture(TEXTURE,UV);
 COLOR=vertex_tint*vec4(texel.rgb,texel.a*mask);
}
