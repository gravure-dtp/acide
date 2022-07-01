pkgdatadir = join_paths(get_option('prefix'), get_option('datadir'), meson.project_name())
moduledir = join_paths(pkgdatadir, 'acide')
gnome = import('gnome')

gnome.compile_resources(
  'acide',
  'acide.gresource.xml',
  gresource_bundle: true,
  install: true,
  install_dir: pkgdatadir,
)

python = import('python')

conf = configuration_data()
conf.set('PYTHON', python.find_installation('python3').path())
conf.set('VERSION', meson.project_version())
conf.set('localedir', join_paths(get_option('prefix'), get_option('localedir')))
conf.set('pkgdatadir', pkgdatadir)

configure_file(
  input: 'acide.in',
  output: 'acide',
  configuration: conf,
  install: true,
  install_dir: get_option('bindir')
)

cythonize = find_program('cythonize', required: true)
if not cythonize.found()
	error('Error: cythonize command not found, cannot build python extensions')
endif

message('Building python extensions...')
returned = run_command(
	cythonize,
	'-3',
	'--build',
	'--inplace',
  '-s', 'annotate=False',
	'-X', 'language_level=3',
  '-X', 'binding=False',
  '-X', 'boundscheck=True',
  '-X', 'wraparound=True',
  '-X', 'overflowcheck=True',
  '-X', 'initializedcheck=True',
  '-X', 'nonecheck=False',
  '-X', 'embedsignature=True',
  '-X', 'optimize.use_switch=False',
  '-X', 'optimize.unpack_method_calls=True',
  '-X', 'warn.undeclared=False',
  '-X', 'warn.unreachable=True',
  '-X', 'warn.maybe_uninitialized=True',
  '-X', 'warn.unused=True',
  '-X', 'warn.unused_arg=True',
  '-X', 'warn.unused_result=True',
  '-X', 'warn.multiple_declarators=True',
  'acide/types.pyx',
  'acide/measure.pyx',
  'acide/tiles.pyx'
)
message(returned.stdout())
message(returned.stderr())

install_subdir(
	'acide',
	exclude_directories: ['__pycache__', 'ui/__pycache__'],
	exclude_files: ['measure.pyx', 'measure.c',
									'tiles.pyx', 'tiles.c',
									'types.pyx', 'types.c'
								 ],
	install_dir: moduledir,
	strip_directory: true
)

