shader_type canvas_item;
varying vec4 vertex_tint;
void vertex() { vertex_tint = COLOR; }
uniform vec4 frame = vec4(0.0,0.0,1.0,1.0);
uniform float gait = 0.0;
uniform float walking = 1.0;
uniform float hurt = 0.0;
uniform float dissolve = 0.0;
uniform vec4 limb_mask = vec4(1.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
 vec2 uv = (UV-frame.xy)/frame.zw;
 float lower = smoothstep(0.34,0.85,uv.y);
 uv.x += sin(gait + uv.y*7.0)*0.012*walking*lower;
 uv.y += cos(gait*2.0+uv.x*3.0)*0.006*walking*lower;
 vec4 texel = texture(TEXTURE,frame.xy+clamp(uv,vec2(0.002),vec2(0.998))*frame.zw);
 float wear = 1.0;
 if (uv.y>0.28 && uv.y<0.68) {
  if (uv.x<0.23) wear *= limb_mask.x;
  if (uv.x>0.78) wear *= limb_mask.y;
 }
 if (uv.y>0.8) wear *= uv.x<0.5 ? limb_mask.z : limb_mask.w;
 float grain = hash(floor(uv*170.0));
 float edge = smoothstep(dissolve-0.12,dissolve,grain);
 texel.rgb = mix(texel.rgb,vec3(1.0,0.8,0.63),hurt*0.7);
 texel.rgb += vec3(0.08,0.38,0.40)*smoothstep(0.08,0.0,abs(grain-dissolve))*step(0.01,dissolve);
 COLOR = vertex_tint*vec4(texel.rgb,texel.a*wear*edge);
}
