catch2_dep = dependency('catch2-with-main', required: false)

srcdir = '../src'

test_frame_generation_config = executable(
	'test_frame_generation_config',
	[srcdir / 'frame_generation_config.cpp', 'test_frame_generation_config.cpp'],
	include_directories: [srcdir],
	cpp_args: gamescope_cpp_args,
)
test('frame-generation-config', test_frame_generation_config)

if catch2_dep.found()
	unittest_src = []
	foreach src : gamescope_core_src + ['Script/Script.cpp', 'convar_script.cpp']
		unittest_src += srcdir / src
	endforeach

	test_convar = executable(
		'test_convar',
		unittest_src + ['test_convar.cpp'],
		include_directories: [srcdir, sol2_include],
		dependencies: [catch2_dep, luajit_dep, cap_dep, drm_dep, glm_dep, wlroots_dep],
		cpp_args: gamescope_cpp_args,
	)
	test('convar', test_convar)
endif
