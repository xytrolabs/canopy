# canopyfx is a hard fork of wlrfx/scenefx (MIT, see LICENSE), built as a
# static library rather than joined into the compositor's source lists: it is C
# compiled against wlroots' private struct layouts (-DWLR_PRIVATE=), and those
# flags must not leak into Canopy's C++23 units.

cc = meson.get_compiler('c')

# dladdr, for the scene helper guard. Folded into libc since glibc 2.34.
canopyfx_dl_dep = cc.find_library('dl', required: false)
canopyfx_egl_dep = dependency('egl')
canopyfx_gbm_dep = dependency('gbm')
canopyfx_glesv2_dep = dependency('glesv2')
canopyfx_math_dep = cc.find_library('m')
canopyfx_rt_dep = cc.find_library('rt')

# Older EGL headers cannot express the dmabuf import and fence attributes
# fx_texture.c and egl.c rely on.
canopyfx_eglext_version = cc.get_define(
  'EGL_EGLEXT_VERSION',
  dependencies: canopyfx_egl_dep,
  prefix: '#include <EGL/eglext.h>',
).to_int()
if canopyfx_eglext_version < 20210604
  error('canopyfx requires EGL headers with EGL_EGLEXT_VERSION >= 20210604')
endif

canopyfx_sources = files(
  'render/color.c',
  'render/egl.c',
  'render/pixel_format.c',
  'render/fx_renderer/fx_framebuffer.c',
  'render/fx_renderer/fx_offscreen_buffers.c',
  'render/fx_renderer/fx_pass.c',
  'render/fx_renderer/fx_renderer.c',
  'render/fx_renderer/fx_texture.c',
  'render/fx_renderer/effect_shader.c',
  'render/fx_renderer/pixel_format.c',
  'render/fx_renderer/shaders.c',
  'render/fx_renderer/tracy.c',
  'render/fx_renderer/util.c',
  'types/fx/blur_data.c',
  'types/fx/clipped_region.c',
  'types/linux_drm_syncobj.c',
  'types/output/output.c',
  'types/scene/capture.c',
  'types/scene/drag_icon.c',
  'types/scene/layer_shell_v1.c',
  'types/scene/linked_node.c',
  'types/scene/output_layout.c',
  'types/scene/scene_guard.c',
  'types/scene/subsurface_tree.c',
  'types/scene/surface.c',
  'types/scene/wlr_scene.c',
  'types/scene/xdg_shell.c',
  'util/array.c',
  'util/env.c',
  'util/matrix.c',
  'util/time.c',
)

canopyfx_deps = [
  libdrm_dep,
  pixman_dep,
  canopyfx_dl_dep,
  canopyfx_egl_dep,
  canopyfx_gbm_dep,
  canopyfx_glesv2_dep,
  canopyfx_math_dep,
  canopyfx_rt_dep,
  wayland_server_dep,
  wlroots_dep,
]

# ICC profile evaluation for client-supplied color management. Without lcms2
# the fallback rejects ICC profiles and leaves the parametric transforms.
canopyfx_lcms2_dep = dependency('lcms2', required: false)
if canopyfx_lcms2_dep.found()
  canopyfx_deps += canopyfx_lcms2_dep
  canopyfx_sources += files('render/color_lcms2.c')
else
  canopyfx_sources += files('render/color_fallback.c')
endif

# wlroots' layer-shell header pulls in the generated server protocol header.
canopyfx_sources += layer_shell_protocol_h

canopyfx_little_endian = target_machine.endian() == 'little'

canopyfx_c_args = [
  '-D_POSIX_C_SOURCE=200809L',
  '-DWLR_USE_UNSTABLE',
  '-DWLR_PRIVATE=',
  '-DWLR_LITTLE_ENDIAN=@0@'.format(canopyfx_little_endian.to_int()),
  '-DWLR_BIG_ENDIAN=@0@'.format((not canopyfx_little_endian).to_int()),
]

# Keep wlr_log's __FILE__ output relative to the source root rather than
# leaking the absolute build path.
canopyfx_relative_dir = fs.relative_to(
  meson.current_source_dir(),
  meson.global_build_root(),
) + '/'
if cc.has_argument('-fmacro-prefix-map=/prefix/to/hide=')
  canopyfx_c_args += '-fmacro-prefix-map=@0@='.format(canopyfx_relative_dir)
else
  canopyfx_c_args += '-D_WLR_REL_SRC_DIR="@0@"'.format(canopyfx_relative_dir)
endif

canopyfx_c_args += cc.get_supported_arguments([
  '-Wundef',
  '-Wlogical-op',
  '-Wmissing-include-dirs',
  '-Wold-style-definition',
  '-Wpointer-arith',
  '-Winit-self',
  '-Wstrict-prototypes',
  '-Wimplicit-fallthrough=2',
  '-Wendif-labels',
  '-Wstrict-aliasing=2',
  '-Woverflow',
  '-Wmissing-prototypes',
  '-Walloca',

  '-Wno-missing-braces',
  '-Wno-missing-field-initializers',
  '-Wno-unused-parameter',
])

# Without these, tracy.c and every TRACY_* call site compile away.
if tracy_dep.found()
  canopyfx_deps += tracy_dep
  canopyfx_c_args += ['-DTRACY_ENABLE', '-DTRACY_ON_DEMAND']
endif

# Shaders are compiled at runtime, so they ship as generated char arrays rather
# than data files an installed binary would have to locate.
canopyfx_shader_embed = find_program(
  'render/fx_renderer/shaders/embed.sh',
  native: true,
)
foreach shader : [
  'blur1.frag',
  'blur2.frag',
  'border.frag',
  'box_shadow.frag',
  'common.vert',
  'corner_alpha.frag',
  'effect_light.frag',
  'gradient.frag',
  'output.frag',
  'quad.frag',
  'quad_grad.frag',
  'quad_grad_round.frag',
  'quad_round.frag',
  'tex.frag',
]
  canopyfx_sources += custom_target(
    shader.underscorify() + '_src.h',
    command: [canopyfx_shader_embed, shader.underscorify() + '_src'],
    input: 'render/fx_renderer/shaders' / shader,
    output: shader.underscorify() + '_src.h',
    feed: true,
    capture: true,
  )
endforeach

# Only `include` reaches the compositor. `internal` holds headers whose paths
# (`render/`, `types/`, `util/`) would otherwise sit at the root of every
# compositor translation unit's include path.
canopyfx_inc = include_directories('include')
canopyfx_internal_inc = include_directories('internal')

canopyfx_lib = static_library(
  'canopyfx',
  canopyfx_sources,
  c_args: canopyfx_c_args,
  dependencies: canopyfx_deps,
  include_directories: [canopyfx_inc, canopyfx_internal_inc],
  override_options: [
    'c_std=' + (meson.version().version_compare('>=1.4.0') ? 'c23,c11' : 'c11'),
  ],
  install: false,
)

# link_whole: the scene graph registers node type handlers and format tables
# through constructors and tables the compositor never names directly, so
# archive member pruning would drop them.
canopyfx_dep = declare_dependency(
  link_whole: canopyfx_lib,
  dependencies: canopyfx_deps,
  include_directories: canopyfx_inc,
)

if build_tests
  canopyfx_hdr_capture_test = executable(
    'canopyfx-hdr-capture-test',
    'tests/hdr_capture.c',
    c_args: canopyfx_c_args,
    dependencies: canopyfx_deps,
    include_directories: [canopyfx_inc, canopyfx_internal_inc],
    link_with: canopyfx_lib,
    build_by_default: false,
  )
  test('hdr-sdr-capture', canopyfx_hdr_capture_test, suite: 'canopyfx')

  canopyfx_color_test = executable(
    'canopyfx-color-test',
    'tests/color.c',
    c_args: canopyfx_c_args,
    dependencies: canopyfx_deps,
    include_directories: [canopyfx_inc, canopyfx_internal_inc],
    link_with: canopyfx_lib,
    build_by_default: false,
  )
  foreach case_name : [
    'implicit-srgb-target',
    'scene-unset-primaries',
    'scene-custom-color',
    'scene-custom-white',
    'scene-custom-bt1886',
    'scene-scrgb-absolute-luminance',
    'scene-hdr-sdr-fallback',
    'hdr-white-point-math',
    'hdr-white-point',
    'sdr-white-point-alpha',
    'sdr-curve-consistency',
    'sdr-transfer-policy',
    'optimized-blur-sdr-curve',
    'optimized-blur-encoded-cache',
    'optimized-blur-size-change',
    'optimized-blur-copy-failure',
    'gamma22-to-srgb',
    'pq-roundtrip',
    'bt2020-to-srgb',
    'scrgb-negative-channels',
    'fp16-blending',
    'fp16-blur',
    'fp16-blur-effects',
    'fp16-save-restore',
    'sdr10-blur-buffer-format',
    'optimized-blur-format-cache',
    'shared-output-buffers',
    'output-lut-cache',
    'shared-sdr-capture',
    'shared-output-transform-transition',
    'shared-sdr-capture-lock',
    'shared-sdr-capture-storage-change',
    'capture-read-format',
    'framebuffer-texture-binding',
  ]
    test(
      'color-' + case_name,
      canopyfx_color_test,
      args: case_name,
      suite: 'canopyfx',
    )
  endforeach

  canopyfx_capture_pacing_test = executable(
    'canopyfx-capture-pacing-test',
    'tests/capture_pacing.c',
    c_args: canopyfx_c_args,
    dependencies: canopyfx_deps,
    include_directories: [canopyfx_inc, canopyfx_internal_inc],
    link_with: canopyfx_lib,
    build_by_default: false,
  )

  test(
    'capture-pacing',
    canopyfx_capture_pacing_test,
    suite: 'canopyfx',
  )

  canopyfx_effects_test = executable(
    'canopyfx-effects-test',
    'tests/effects.c',
    c_args: canopyfx_c_args,
    dependencies: canopyfx_deps,
    include_directories: [canopyfx_inc, canopyfx_internal_inc],
    link_with: canopyfx_lib,
    build_by_default: false,
  )
  foreach case_name : [
    'kinds',
    'reads',
    'uniforms',
    'long-running-trig',
    'expand',
    'renderer-destroy',
    'persistent-scene',
    'occlusion',
    'background-clear',
    'damage-confinement',
    'whole-box-invalidation',
    'transient-policy',
    'margin-damage',
    'move-margin-damage',
    'offscreen-margin',
    'effect-bounds',
    'border-geometry',
    'border-geometry-tree',
    'border-light',
    'border-light-capture',
    'border-light-hdr-low-alpha',
    'border-light-lifecycle',
    'border-light-motion',
    'visible-in-box',
    'in-place',
    'damage-expansion',
    'capture-policy',
    'capture-policy-encoding',
    'capture-feedback',
    'workspace-reveal',
    'in-place-feedback',
    'capture-composition',
    'capture-exclusion',
    'in-place-shape',
    'output-effects',
    'audio-spectrum',
  ]
    test('effects-' + case_name, canopyfx_effects_test, args: case_name, suite: 'canopyfx')
  endforeach

  # Renderer ownership and descriptor stability against a real GPU. It takes
  # DRM render nodes as arguments, so it is a tool run by `just gpu-test`
  # rather than a suite entry. Built by default so the warning gate compiles
  # it.
  executable(
    'canopyfx-renderer-test',
    'tests/renderer.c',
    c_args: canopyfx_c_args,
    dependencies: canopyfx_deps,
    include_directories: [canopyfx_inc, canopyfx_internal_inc],
    link_with: canopyfx_lib,
  )

  if cc.get_define('WLR_HAS_GLES2_RENDERER', prefix: '#include <wlr/config.h>', dependencies: wlroots_dep) == '1'
    canopyfx_egl_abi_test = executable(
      'canopyfx-egl-abi-test',
      'tests/egl_abi.c',
      c_args: canopyfx_c_args,
      dependencies: canopyfx_deps,
      include_directories: canopyfx_internal_inc,
      export_dynamic: true,
      build_by_default: false,
    )
    test('canopyfx-egl-abi', canopyfx_egl_abi_test, suite: 'canopyfx')
  endif
  # canopyfx's scene structs must extend wlroots' as a strict prefix. One source,
  # built against each header, proves the offsets still agree.
  canopyfx_abi_probes = []
  foreach probe : [
    ['wlroots', '<wlr/types/wlr_scene.h>', [wlroots_dep]],
    ['canopyfx', '<canopyfx/types/wlr_scene.h>', [wlroots_dep, canopyfx_dep]],
  ]
    canopyfx_abi_probes += executable(
      'canopyfx-abi-probe-' + probe[0],
      'tests/abi.c',
      c_args: canopyfx_c_args + ['-DABI_PROBE_HEADER=' + probe[1]],
      dependencies: probe[2],
      build_by_default: false,
    )
  endforeach

  test(
    'scene-abi',
    find_program('tests/abi_compare.sh', native: true),
    args: canopyfx_abi_probes,
    suite: 'canopyfx',
  )
endif
