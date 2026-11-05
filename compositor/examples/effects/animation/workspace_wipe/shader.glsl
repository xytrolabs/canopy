uniform vec2 canopy_workspace_axis;

vec4 animation(vec2 uv) {
  float coordinate = dot(uv, abs(canopy_workspace_axis));
  if (canopy_workspace_axis.x + canopy_workspace_axis.y < 0.0)
    coordinate = 1.0 - coordinate;
  float visible = step(coordinate, canopy_clamped_progress);
  return mix(canopy_sample(uv), canopy_sample_incoming(uv), visible);
}
