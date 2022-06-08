# Build acide documentation

sphinx_build = find_program('sphinx-build', required: true)
if not sphinx_build.found()
	error('Error: sphinx-build not found, cannot build documentation')
else
	# message('sphinx-build path: @0@'.format(sphinx.full_path()))
	sphinx_version = run_command(sphinx_build, '--version').stdout()
	message(sphinx_version)
endif

message('Building project documentation')
returned = run_command(
	sphinx_build,
	'-v',
	'-b', 'html',
	'-D', 'version=@0@'.format(meson.project_version()),
	'-D', 'release=@0@'.format(meson.project_version()),
	'sources',
	'build'
)
message(returned.stdout())
message(returned.stderr())

install_subdir(
	'build/html',
	exclude_directories: [],
	exclude_files: [],
	install_dir: join_paths(get_option('datadir'), 'doc/acide'),
	strip_directory: true
)

