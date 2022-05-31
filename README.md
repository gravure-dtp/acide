# Acide

## About

A Gnome Application to visualize pdf document using the MuPdf library.





## Installing

This project uses the [meson build system](http://mesonbuild.com/). 
Run the following commands to clone this project and initialize the build:

```bash
$ git clone https://github.com/gravures/acide.git
$ cd acide
$ meson build --prefix=~/.local
```

Note: `build` is the build output directory and can be changed to any other
directory name.

To build or re-build after code-changes, run:

```bash
$ meson --reconfigure --prefix=~/.local build
```

To install, run:

```bash
$ meson compile -C build
$ meson install -C build
```

## Configurable options

None.

## License

**Acide** is a free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 3 of the License, or (at your option) any later version.
