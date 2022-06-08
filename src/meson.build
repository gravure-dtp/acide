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

install_subdir(
	'acide',
	exclude_directories: [],
	exclude_files: ['ui/duplex.pyx'],
	install_dir: moduledir,
	strip_directory: true
)

