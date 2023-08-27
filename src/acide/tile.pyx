# tile.pyx
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
from typing import (
    Any, Callable, Union, Optional, NoReturn, Sequence, Tuple,
    Coroutine, Awaitable
)

import gi
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk

from acide import format_size
from acide.types import Pixbuf


BLOSC_MAX_BYTES_CHUNK = 2**31


cdef object gdk_memory_format_mapping():
    mapping = dict()
    cdef int size
    for _enum in Gdk.MemoryFormat.__enum_values__.values():
        size = _enum.value_nick.count("8")
        size += _enum.value_nick.count("16") * 2
        size += _enum.value_nick.count("32") * 4
        mapping[_enum] = size
    return mapping
gdk_memory_format_sizes = gdk_memory_format_mapping()


cdef class Tile(_CMeasurable):
    """A :class:`Tile` is a part of a larger graphic object.
    :class:`Tile` implements the :class:`Measurable` interface.

    :class:`Tile` are pats of :class:`TilesGrid` which represent a view of
    a graphic object too large to be kept in memory in a monolithic uncompressed
    form. Original graphic surface should be cut down in equally sized Tiles
    grouped in a :class:`TilesGrid`. Corresponding pixels buffer area
    for each :class:`Tile` should be passed to the :meth:`compress` method.
    The idea is that graphic object could provide those buffers in an async
    way to manage priority and memory preserving the responsiveness of application.

    :class:`Tile` will only kept buffer in a compressed form.

    A :class:`Tile` is rectangular and are defined by the :obj:`rect` argument,
    which could be in whatever unit of measure choosen by the implementation,
    and defined the position and size relative to the original graphic surface.

    Compressions are done by the `Blosc Library <http://python-blosc.blosc.org/tutorial.html>`_ .

    Args:
        rect: A four length Sequence of numbers or a :class:`Graphen.Rect`
              describing the origin and size of the Tile. If set to None,
              rect will be initialized at (0, 0, 0, 0), default to None .
    """
    blosc.set_releasegil(True)
    blosc.set_nthreads(blosc.detect_number_of_cores() - 2)

    @property
    def u(self) -> int:
        """An :class:`int` as the size in bytes of the origin uncompressed
        buffer (read only)."""
        return self._u

    @property
    def z(self) -> int:
        """An :class:`int` as the size in bytes of the Tile's compressed
        buffer (read only)."""
        return self._z

    @property
    def r(self) -> float:
        """A :class:`float` as the ratio of compression of
        the Tile's buffer (read only)."""
        return self._r

    def __cinit__(self, *args, **kwargs):
        self._u = 0
        self._z = 0
        self._r = 0
        self.buffer = None
        self.u_shape = 0
        self.u_itemsize = 0
        self._size = (0, 0)

    def __dealloc__(self):
        self.buffer = None

    cpdef invalidate(self):
        """invalidate the compressed internal buffer (deallocate).
        After this call *self.buffer* will be set to *None*.
        """
        self.buffer = None
        self._u = self._z = self._r = 0

    cpdef compress(
        self,
        Pixbuf pixbuf,
        format: Gdk.MemoryFormat,
    ):
        """Compress the given :obj:`pixbuf` in the :class:`Tile`'s own buffer.
        Blosc has a maximum blocksize of 2**31 bytes = 2Gb, larger arrays must
        be chunked by slicing.

        Args:
            pixbuf: A :class:`acide.types.Pixbuf` holding an one dmensional
                    c-contigous buffer to compress.
            format: a member of enumeration :class:`Gdk.MemoryFormat`
                    describing formats that pixmap data have in memory.

        Raises:
            TypeError: if :obj:`buffer` doesn't implement the *buffer protocol*,
                       are not c-contigous or have more than one dimension.
            ValueError: if there is a missmatch between :obj:`buffer`'s lenght
                        and given pixmap size for memory format or if
                        buffer's lenght is larger than blosc's maximum blocksize.
        """
        cdef Py_buffer view
        cdef Py_buffer* p_view = &view
        cdef char* ptr
        cdef int ret

        if pixbuf is None:
            raise ValueError("argument pixbuf couldn´t be None")

        if isinstance(pixbuf.buffer, memoryview):
            p_view = PyMemoryView_GET_BUFFER(pixbuf.buffer)
        elif PyObject_CheckBuffer(pixbuf.buffer):
            ret = PyObject_GetBuffer(pixbuf.buffer, p_view, PyBUF_CONTIG_RO)
        else:
            raise TypeError(
                "buffer should be either a memoryview"
                "or an object implementing the buffer protocol"
                "and data should be contigous in memory"
            )

        if not PyBuffer_IsContiguous(p_view, b'C'):
            raise TypeError("buffer should be c-contigous in memory")

        if p_view.ndim <> 1:
            raise TypeError("buffer should only have one dimension")

        # Sanity check between size and buffer size
        self.format_size = gdk_memory_format_sizes.get(format, 0)
        if pixbuf.width * pixbuf.height * self.format_size  <> \
            p_view.len:
            raise ValueError(
                "Missmatch between buffer's lenght and pixmap"
                f" size for {format}"
            )

        # blosc limit
        if p_view.len > BLOSC_MAX_BYTES_CHUNK:
            raise ValueError(
                f"Buffer size to large to be compressed, maximum size is "
                f"{format_size(BLOSC_MAX_BYTES_CHUNK)}, given buffer have "
                f"{format_size(p_view.len)}."
            )

        self._size = (pixbuf.width, pixbuf.height)
        self._u = p_view.len
        self.u_shape = p_view.shape[0]
        self.u_itemsize = p_view.itemsize

        # we don't care of the buffer format,
        # buffer will be compressed as bytes in buffer
        # and we have itemsize and a Gdk.MemoryFormat to carry
        # buffer's items type info.
        # self.u_format = <bytes> p_view.format
        self.u_format = b'B'  # unsigned char
        ptr = <char*> p_view.buf

        self.buffer = blosc.compress_ptr(
            <Py_ssize_t> &ptr[0],
            p_view.len,
            typesize=p_view.itemsize,
            clevel=9,
            shuffle=blosc.SHUFFLE,
            cname='blosclz',
        )
        self._z = len(self.buffer)
        self._r = self._u / float(self._z)
        if isinstance(pixbuf.buffer, memoryview):
            pixbuf.buffer.release()
        else:
            PyBuffer_Release(p_view)
        del(pixbuf)

    cpdef _dump_props(self):
        return (
            f"{_CMeasurable._dump_props(self)}, "
            #f"u:{format_size(self._u)}, z:{format_size(self._z)}, "
            #f"r:{self._r:.1f}, "
            f"_size:{self._size}"
        )

    def __str__(self):
        return f"Tile({self._dump_props()})"


@cython.final
@cython.auto_pickle(False)
cdef class _TileReduce():

    def __init__(self, tile):
        self._size = (<Tile> tile)._size
        self.u_shape = (<Tile> tile).u_shape
        self.format_size = (<Tile> tile).format_size
        self.buffer = (<Tile> tile).buffer

    def __getstate__(self):
        return (self._size, self.u_shape, self.format_size, self.buffer)

    def __setstate__(self, state):
        self._size, self.u_shape, self.format_size, self.buffer = state
