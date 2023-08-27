# mprendering.pyx
#
# Copyright 2022 Gilles Coissac
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
import cython
import blosc

import gi
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib

from acide.tile import _TileReduce
from acide.types import Timer


@cython.boundscheck(False)
@cython.wraparound(False)
cdef void copy_vband(
    const uc8[:] vband, uc8[:] buffer, Py_ssize_t rows,
    Py_ssize_t vband_width, Py_ssize_t buf_width, Py_ssize_t x_offset
) nogil:
    cdef Py_ssize_t x_in, x_out, y
    for y in range(rows):
        x_in = vband_width * y
        x_out = (buf_width * y) + x_offset
        buffer[x_out:x_out + vband_width] = vband[x_in:x_in + vband_width]


@cython.final
@cython.auto_pickle(False)
cdef class Clip():
    """A simple structure to hold a rendered region
    returned by a :class:`RenderTile`.
    """

    def __init__(self, x: float =0, y: float =0, w: int =0, h: int =0):
        self._x = x
        self._y = y
        self._w = w
        self._h = h
        self.msg = ""

    def __getstate__(self):
        print("__getstate__")
        return {
            'x': self._x, 'y': self._y, 'w': self._w, 'h': self._h,
            'bytes': self._bytes, 'memory_format': self.memory_format,
            'msg': self.msg
        }

    def __setstate__(self, state):
        print(f"__setstate__:")
        self._x = state['x']
        self._y = state['y']
        self._w = state['w']
        self._h = state['h']
        self._bytes = state['bytes']
        self.memory_format = state['memory_format']
        self.msg = state['msg']
        if self._bytes is not None:
            self._texture = Gdk.MemoryTexture.new(
                self._w,
                self._h,
                Gdk.MemoryFormat(self.memory_format),
                GLib.Bytes.new_take(self._bytes),
                3 * self._w,
            )
            self._bytes = None

    cdef int allocate_buffer(
        self, Py_ssize_t shape, Py_ssize_t itemsize, bytes format
    ):
        """Allocate self.buffer to host offscreen image
        of the resulting union of compressed subtiles."""
        cdef int i

        try:
            self.buffer = Carray.__new__(
                Carray,
                shape=(shape,) ,
                itemsize=itemsize,
                format=format,
                mode='c',
                allocate_buffer=True,
            )
        except MemoryError as m:
            self.msg = (f"{m}")
            return -1
        return 1

    cdef int fill_buffer(
        self, int width, int height, list tiles, list vbands_shape,
        Py_ssize_t itemsize, bytes format,
    ):
        """Actually decompress the subtiles buffers in the RenderTile.buffer."""
        cdef list vbands = []
        cdef Py_ssize_t w_buf, rows
        cdef Py_ssize_t offset, ww, x, y
        cdef Py_ssize_t buf_width = 0
        cdef int index
        cdef char* ptr

        if self.buffer:
            try:
                for sh in vbands_shape:
                    vbands.append(
                        Carray.__new__(
                            Carray,
                            shape=(sh, ),
                            itemsize=itemsize,
                            format=format,
                            mode='c',
                            allocate_buffer=True,
                        )
                    )
            except MemoryError:
                self.msg = "can´t allocate temporary buffers"
                return -3

            _T = Timer("decompress buffers")
            rows = 0
            for x in range(width):
                buf_width += (<_TileReduce> tiles[x])._size[0] * \
                             (<_TileReduce> tiles[x]).format_size
                offset = 0
                for y in range(height):
                    index = (y * width) + x
                    if x == 0:
                        rows += (<_TileReduce> tiles[index])._size[1]
                    ptr = (<Carray> vbands[x]).data
                    blosc.decompress_ptr(
                        (<_TileReduce> tiles[index]).buffer,
                        address=<Py_ssize_t> &ptr[offset],
                    )
                    offset += (<_TileReduce> tiles[index]).u_shape
            _T.stop()

            _T = Timer("merge_side_buffers")
            offset = 0
            for x in range(width):
                ww = (<_TileReduce> tiles[x])._size[0] * \
                     (<_TileReduce> tiles[x]).format_size
                copy_vband(
                    vbands[x], self.buffer, rows,
                    ww, buf_width, offset
                )
                offset += ww
            _T.stop()
            return 1
        else:
            self.msg = "Invalid buffer or Tile's format to fill buffer"
            return -2

    @property
    def x(self):
        """origin of the rendered region"""
        return self._x

    @property
    def y(self):
        """origin of the rendered region"""
        return self._y

    @property
    def w(self):
        """width of the rendered region"""
        return self._w

    @property
    def h(self):
        """height of the rendered region"""
        return self._h

    @property
    def texture(self):
        """A :class:`Gdk.Texture` holding the pixmap"""
        return self._texture

    def __str__(self):
        b = f"bytes@{id(self._bytes)}" if self._bytes else "None"
        return (
            f"Clip(x={self._x}, y={self._y}, w={self._w}, h={self._h}, "
            f"bytes={b} "
            f"texture={self._texture}, memory_format={self.memory_format})"
        )


def render_clip(
    clip, width, height, tiles, shape, itemsize,
    format, vbands_shape, memory_format
):
    if (<Clip> clip).allocate_buffer(shape, itemsize, format) < 0:
        raise MemoryError((<Clip> clip).msg)

    if (<Clip> clip).fill_buffer(
        width, height, tiles, vbands_shape, itemsize, format,
    ) < 0:
        raise MemoryError((<Clip> clip).msg)

    (<Clip> clip)._bytes = PyBytes_FromObject((<Clip> clip).buffer)
    (<Clip> clip).memory_format = memory_format
    (<Clip> clip).buffer = None
    print(f"render_clip: {clip}")
    return clip

