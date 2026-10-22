shader_type canvas_item;
varying vec4 vertex_tint;
uniform vec4 panel = vec4(0.,0.,1.,1.);
void vertex() { vertex_tint = COLOR; }
uniform float clock = 0.0;
uniform float alarm = 0.0;
uniform float exposure = 1.0;
uniform float fade = 1.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
 vec2 local_uv=(UV-panel.xy)/panel.zw;
 vec2 uv = local_uv;
 uv.x += sin(clock*0.15)*0.002*uv.y*uv.y;
 vec4 c = texture(TEXTURE,panel.xy+clamp(uv,vec2(0.001),vec2(0.999))*panel.zw);
 float haze = noise(local_uv*vec2(6.,3.)+vec2(clock*0.02,-clock*0.01));
 float vignette = smoothstep(0.9,0.20,length((local_uv-0.5)*vec2(1.0,0.8)));
 float grain = (hash(FRAGCOORD.xy+floor(clock*12.0))-0.5)*0.012;
 vec3 tint = vec3(0.08,0.18,0.21)*haze*0.25;
 float siren = alarm*(0.5+0.5*sin(clock*5.0));
 c.rgb = c.rgb*exposure*(0.67+0.33*vignette)+tint+grain+vec3(0.12,0.004,0.0)*siren;
 COLOR = vertex_tint*vec4(c.rgb,c.a*fade);
}
