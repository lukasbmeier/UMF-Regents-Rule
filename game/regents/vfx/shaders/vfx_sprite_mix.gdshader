// A PARTICLE THAT COVERS (smoke, dust, snow): `vfx_sprite.gdshaderinc` says how. Lit by the scene (the sun, a
// blast's light), so smoke is dark at night and glows orange over a fire.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://game/regents/vfx/shaders/vfx_sprite.gdshaderinc"
