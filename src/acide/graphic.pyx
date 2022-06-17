# graphic.pyx
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
"""
Coordinate Systems:
    The coordinate system on a PDF page is called User Space.
    This is a flat 2-dimensional space, just like a piece of paper.
    And in fact that's a good way to think about it. The units of User Space
    are called "points" and there are 72 points/inch. The origin, or 0,0 point
    is located in the bottom left hand corner of the page. Horizontal,
    or X, coordinates increase to the rights and vertical, or Y, coordinates
    increase towards the top.
    NOTE: take into account, that in MuPDF’s coordinate system, the y-axis
    is oriented from top to bottom. So, the origin 0,0 point is located at
    the top left corner.
"""
import cython

from enum import IntEnum, unique, auto
from fractions import Fraction
from typing import Any, Union, Optional, NoReturn, Sequence, Tuple

import gi
gi.require_version('Graphene', '1.0')
gi.require_version("Gdk", "4.0")

from gi.repository import Gdk, GLib, Graphene
import blosc

from cython.view cimport array as Carray

from acide.types import TypedGrid
from acide.types cimport TypedGrid, test_sequence


cdef extern from "Python.h":
    ctypedef struct PyObject
    ctypedef Py_ssize_t Py_intptr_t
    ctypedef struct __pyx_buffer "Py_buffer":
        PyObject* obj
        void* buf
        Py_ssize_t len
        Py_ssize_t itemsize
        int ndim
        Py_ssize_t* shape

    int PyObject_GetBuffer(object obj, Py_buffer *view, int flags) except -1
    void PyBuffer_Release(Py_buffer *view)
    bint PyObject_CheckBuffer(object obj)
    bint PyBuffer_IsContiguous(Py_buffer *view, char fort)
    Py_buffer *PyMemoryView_GET_BUFFER(object mview)

    cdef enum:
        PyBUF_SIMPLE
        PyBUF_C_CONTIGUOUS,
        PyBUF_F_CONTIGUOUS,
        PyBUF_ANY_CONTIGUOUS


# Type hints Alias
BufferProtocol = Any


cdef object gdk_memory_format_mapping():
    mapping = dict()
    cdef int size
    for _enum in Gdk.MemoryFormat.__enum_values__.values():
        size = 0
        size = _enum.value_nick.count("8")
        size += _enum.value_nick.count("16") * 2
        size += _enum.value_nick.count("32") * 4
        mapping[_enum] = size
    return mapping
gdk_memory_format_sizes = gdk_memory_format_mapping()


@cython.freelist(16)
cdef class Tile():
    """Tile is a part of a larger graphic object.

    :class:`Tile` could be find in Class implementing the :class:`GraphicInterface`.
    They are smaller parts of a graphic object too large to be keep in a monolithic
    uncompressed form in memory. Original graphic surface should be cut down
    in equally sized Tiles and corresponding pixels buffer area should be passed
    to the :meth:`compress` method. The idea is that graphic object providing
    this buffer area should render each part once at a time.

    Tiles will keep buffer only in a compressed form.

    Tiles are rectangular and are defined by the 'rect' argument, which could
    be in whatever unit choosen by the implementation, and defined the position
    and size relative to the original graphic surface.

    Compressions are done by the Blosc c Library.

    Args:
        rect: A :class:`Graphene.Rect` defining the origin and size of the Tile.
    """
    cdef Py_ssize_t _u
    cdef Py_ssize_t _z
    cdef float _r
    cdef object _rect
    cdef tuple _size
    cdef object _format
    cdef object buffer
    cdef Carray u_shape
    cdef Py_ssize_t u_itemsize
    cdef bytes u_format

    @property
    def u(self) -> int:
        """An :class:`int`, size in bytes of the origin uncompressed
        buffer (read only)."""
        return self._u

    @property
    def z(self) -> int:
        """An :class:`int`, size in bytes of the Tile's compressed
        buffer (read only)."""
        return self._z

    @property
    def r(self) -> float:
        """A :class:`float`, the ratio of compression of
        the Tile's buffer (read only)."""
        return self._r

    @property
    def rect(self) -> Graphene.Rect:
        """A :class:`Graphene.Rect` defining the origin and size
        of the Tile  (read only)."""
        return self._rect

    def __cinit__(self, rect: Graphene.Rect):
        self._u = 0
        self._z = 0
        self._r = 0
        self.buffer = None
        self._rect = rect
        self._size = (0, 0)

    def __init__(self, rect: Graphene.Rect, *arg, **kwargs):
        pass

    def __dealloc__(self):
        self.buffer = None

    cpdef compress(
        self,
        buffer: Union[memoryview, BufferProtocol],
        size: Sequence[int, int],
        format: Gdk.MemoryFormat,
    ):
        """Compress buffer.

        The given buffer is compressed in the Tile's own buffer.
        blosc has a maximum blocksize of 2**31 bytes = 2 GB.
        Larger arrays must be chunked by slicing.

        Args:
            buffer: A one dmensional c-contigous buffer to compress.
            size: A two lenght :class:`Sequence` of :class:`int` (width, height)
                  describing the pixmap size in pixel behind the buffer.
            format: a member of enumeration :class:`Gdk.MemoryFormat`
                    describing formats that pixmap data have in memory.

        Raises:
            TypeError: if buffer doesn't implement the buffer protocol,
                       are not c-contigous or have more than one dimension.
        """
        cdef Py_buffer view
        cdef Py_buffer* p_view = &view
        cdef char* ptr

        if not test_sequence(size, (int, int)):
            raise TypeError(
                f"size should be a 2 length sequence of int not {size}"
            )

        if isinstance(buffer, memoryview):
            p_view = PyMemoryView_GET_BUFFER(buffer)
        elif PyObject_CheckBuffer(buffer):
            PyObject_GetBuffer(buffer, p_view, PyBUF_SIMPLE)
        else:
            raise TypeError(
                "Argument buffer should be either a memoryview"
                "or an object implementing the buffer protocol"
                "data should be contigous in memory"
            )

        if not PyBuffer_IsContiguous(p_view, b'c'):
            raise TypeError("buffer should be c-contigous in memory")

        if p_view.ndim <> 1:
            raise TypeError("buffer should have only one dimension")

        # Sanity check between size and buffer size
        if size[0] * size[1] * gdk_memory_format_sizes.get(format, 0) <> \
            p_view.len:
            raise ValueError(
                "Missmatch between buffer's lenght and pixmap"
                f" size for {format}"
            )

        self._size = tuple(size)
        self._format = format
        self._u = p_view.len
        self.u_shape = <Py_ssize_t[:view.ndim]> view.shape
        self.u_itemsize = p_view.itemsize
        self.u_format = <bytes> p_view.format

        # TODO: blosc size limit
        ptr = <char*> p_view.buf
        self.buffer = blosc.compress_ptr(
            adress=<Py_ssize_t> &ptr[0],
            items=p_view.len,
            typesize=p_view.itemsize,
            clevel=9,
            shuffle=blosc.BITSHUFFLE,
            cname='lz4',
        )
        self._z = len(self.buffer)
        self._r = self._u / float(self._z)
        PyBuffer_Release(p_view)


cdef class TilesGrid(TypedGrid):
    cdef Py_ssize_t _u
    cdef Py_ssize_t _z
    cdef float _r

    @property
    def u(self) -> int:
        """An :class:`int`, size in bytes of the origin uncompressed
        buffer (read only)."""
        return self._u

    @property
    def z(self) -> int:
        """An :class:`int`, size in bytes of the Tile's compressed
        buffer (read only)."""
        return self._z

    @property
    def r(self) -> float:
        """A :class:`float`, the ratio of compression of
        the Tile's buffer (read only)."""
        return self._r

    def __cinit__(self, shape=None):
        #TODO: all tiles should have same properties, shape, pixel format,...
        self._u = 0
        self._z = 0
        self._r = 0

    def __init__(self, *args, shape=None, **kwargs):
        super().__init__(Tile, shape, *args, **kwargs)

    cdef stats(self):
        cdef Py_ssize_t x, y
        for x in range(self.view.shape[0]):
            for y in range(self.view.shape[1]):
                tile = self.getitem_at(x, y)
                if tile is not None:
                    self._u += (<Tile>tile)._u
                    self._z += (<Tile>tile)._z
        if self._z <> 0:
            self._r = self._u / float(self._z)


cdef class SuperTile(TilesGrid):
    """A two by two :class:`TilesGrid`.

    """
    cdef object _texture

    def __cinit__(self):
        self._texture = None

    def __init__(self, *args, **kwargs):
        super().__init__(*args, shape=(2,2), **kwargs)

    cdef int allocate_buffer(self):
        """Allocate self.buffer to host offscreen image
        of the resulting union of compressed subtiles."""
        if all(
            self.tile_0.buffer, self.tile_1.buffer,
            self.tile_2.buffer, self.tile_3.buffer,
            ):
            self.buffer = Carray.__new__(
                Carray,
                shape=(self.tile_0.u_shape[0] * 4,),
                itemsize=self.tile_0.u_itemsize,
                format=self.tile_0.u_format,
                mode='c',
                allocate_buffer=True,
            )
            self._shape = (
                self.tile_0._shape[0] + self.tile_1._shape[0],
                self.tile_0._shape[1] + self.tile_2._shape[1],
            )
            self._z = self.tile_0._z + self.tile_1._z + \
                      self.tile_2._z + self.tile_3._z
            self._u = self.tile_0._u * 4
            self._r = self._u / float(self._z)
            return 0
        else:
            return -1

    cdef int fill_buffer(self):
        """Actually decompress the subtiles buffers in the SuperTile.buffer."""
        cdef Carray buffer_west
        cdef Carray buffer_east
        cdef int x, y, start, width, height

        if self.buffer:
            buffer_west = Carray.__new__(
                Carray,
                shape=(self.tile_0.u_shape[0] + self.tile_2.u_shape[0],),
                itemsize=self.tile_0.u_itemsize,
                format=self.tile_0.u_format,
                mode='c',
                allocate_buffer=True,
            )
            buffer_east = Carray.__new__(
                Carray,
                shape=(self.tile_1.u_shape[0] + self.tile_3.u_shape[0],),
                itemsize=self.tile_1.u_itemsize,
                format=self.tile_1.u_format,
                mode='c',
                allocate_buffer=True,
            )

            # decompress tiles in two temporary buffers
            blosc.decompress_ptr(
                self.tile_0.buffer,
                address=<Py_ssize_t> &buffer_west.data[0],
            )
            blosc.decompress_ptr(
                self.tile_2.buffer,
                address=<Py_ssize_t> &buffer_west.data[self.tile_0.u_shape[0]],
            )
            blosc.decompress_ptr(
                self.tile_1.buffer,
                address=<Py_ssize_t> &buffer_east.data[0],
            )
            blosc.decompress_ptr(
                self.tile_3.buffer,
                address=<Py_ssize_t> &buffer_east.data[self.tile_1.u_shape[0]],
            )

            # fusion of the 2 temporary buffers
            width = self.tile_0.shape[0]
            height = self.tile_0.shape[1]
            for y in range(height):
                start = y * width
                x = start * 2
                self.buffer[x:x + width] = buffer_west[start:start + width]
                x += width
                self.buffer[x:x + width] = buffer_east[start:start + width]

            return 0
        else:
            return -1

    cdef make_texture(self):
        # here data is copied
        self._gbytes = GLib.Bytes.new(self.buffer)
        self._texture = Gdk.MemoryTexture.new(
            self._pixmap.width,
            self._pixmap.height,
            Gdk.MemoryFormat.R8G8B8,
            self.gbytes,
            3 * self._pixmap.width,
        )

    @property
    def texture(self) -> Gdk.Texture:
        """A :class:`Gdk.Texture` filled with the uncompressed data buffer
        of the subtiles (read only)."""
        self.make_texture()
        return self._texture


@cython.final
cdef class TilesPool():
    """TilesPool."""
    cdef unsigned int width
    cdef unsigned int height
    cdef list tiles_grids_stack
    cdef unsigned int depth
    cdef unsigned int current
    cdef SuperTile render_tile

    def __cinit__(self, width, height):
        self.depth = 1
        self.current = 0
        self.tiles_grids_stack = []
        self.tiles_grids_stack.append(TilesGrid(shape=(width, height)))
        self.render_tile = SuperTile()

    def __init__(self, width, height):
        pass


include "measure.pxi"
include "graphic.pxi"




