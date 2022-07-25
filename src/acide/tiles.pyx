# tiles.pyx
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

"""
import asyncio
import functools
from typing import (
    Any, Callable, Union, Optional, NoReturn, Sequence, Tuple,
    Coroutine, Awaitable
)

import gi
gi.require_version('Graphene', '1.0')
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Graphene

import blosc
cimport cython

from acide import format_size
from acide.types import TypedGrid, BufferProtocol, Rectangle, PixbufCallback
from acide.types import Pixbuf, Timer
from acide.asyncop import AsyncReadyCallback, Scheduler, Priority, Run
from acide.measure import Measurable, Unit
# from acide cimport gbytes


BLOSC_MAX_BYTES_CHUNK = 2**31

Timer.set_logging(False)

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


cdef class TilesGrid(TypedGrid):
    """
    A :class:`acide.types.TypedGrid` specialized in :class:`Tile` type. The overall
    TilesGrid represent the entire pixmap of a large Graphic object for
    a given scale factor.

    A :class:`TilesGrid` could also be a view of another :class:`TilesGrid` by
    slicing the latter, this view could be sliced again. Base :class:`TilesGrid`
    are kept in reference throughout slices (see: :class:`acide.types.TypedGrid`).

    Args:
        shape: A two lenght sequence of int describing the grid dimension,
               like (width, height), those integers are limited to a maximum
               value of *65535* (2 bytes unsigned int) by the implementation.

        format: a member of enumeration :class:`Gdk.MemoryFormat`
                describing formats that pixmap data will have in memory.
    """

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

    def __cinit__(
        self,
        shape=None,
        format=Gdk.MemoryFormat.R8G8B8,
        *args,
        **kwargs
    ):
        self.pytype = Tile
        self._u = 0
        self._z = 0
        self._r = 0
        self.memory_format = format
        self.compute_extents()

    def __init__(
        self,
        shape: Optional[Sequence[int]]=None,
        format: Gdk.MemoryFormat=Gdk.MemoryFormat.R8G8B8,
    ):
        pass

    cpdef invalidate(self):
        """Call :meth:`Tile.invalidate` on each :class:`Tile` in this Grid.
        """
        cdef Py_ssize_t x, y
        cdef object tile
        for x in range(self.view.shape[0]):
            for y in range(self.view.shape[1]):
                tile = self._ref.items[self.view[x, y]]
                if tile is not None:
                    (<Tile> tile).invalidate()

    def compress(self, pixbuf_cb: PixbufCallback, scale: int) -> None:
        """Compress all Tiles in this Grid that have not yet a valid internal buffer.

        Args:
            pixbuf_cb: a callback function to retrieve parts of a pixmap in
                        the form pixbuf_cb(rect: Graphene.Rect) -> BufferProtocol
            scale: an int as a scale factor passed to the pixbuf_cb function
        """
        cdef Py_ssize_t x, y
        self._u = self._z = 0
        for x in range(self.view.shape[0]):
            for y in range(self.view.shape[1]):
                tile = self._ref.items[self.view[x, y]]
                if isinstance(tile, Tile):
                    if (<Tile> tile).buffer is None:
                        pixbuf = pixbuf_cb((<Tile> tile).rect, scale)
                        (<Tile> tile).compress(pixbuf, self.memory_format)
                    self._u += (<Tile> tile)._u
                    self._z += (<Tile> tile)._z
        if self._z != 0:
            self._r = self._u / float(self._z)

    async def compress_async(
        self, pixbuf_cb: PixbufCallback, scale: int
    ) -> Coroutine:
        """Compress asynchronously all Tiles in this Grid.

        Args:
            pixbuf_cb: a callback function to retrieve parts of a pixmap in
                        the form pixbuf_cb(rect: Graphene.Rect) -> BufferProtocol
            scale: an int as a scale factor passed to the pixbuf_cb function

        Returns:
            a coroutine doing the compression.
        """
        self.compress(pixbuf_cb, scale)

    async def _compress_tile_co(self, tile, pixbuf_cb, int scale):
        cdef Tile _tile = <Tile> tile
        if  _tile.buffer is None:
            pixbuf = pixbuf_cb(_tile.rect, scale)
            _tile.compress(pixbuf, self.memory_format)
        self._u += _tile._u
        self._z += _tile._z
        if self._z != 0:
            self._r = self._u / float(self._z)

    def compress_async_generator(self, pixbuf_cb: PixbufCallback, scale: int):
        """Compress asynchronously all Tiles in this Grid.

        Args:
            pixbuf_cb: a callback function to retrieve parts of a pixmap in
                        the form pixbuf_cb(rect: Graphene.Rect) -> BufferProtocol
            scale: an int as a scale factor passed to the pixbuf_cb function

        Returns:
            a generator yielding for each Tile a coroutine doing the compression.
        """
        cdef Py_ssize_t x, y
        self._u = self._z = 0
        for x in range(self.view.shape[0]):
            for y in range(self.view.shape[1]):
                tile = self._ref.items[self.view[x, y]]
                if isinstance(tile, Tile):
                    yield self._compress_tile_co(tile, pixbuf_cb, scale)

    cdef compute_extents(self):
        cdef Extents_s tl, br
        if self.view is not None:
            try:
                tl = (<Tile?> self.getitem_at(0, 0)).get_extents()
                br = (<Tile?> self[-1, -1]).get_extents()
            except TypeError:
                self.extents = Extents_s(0, 0, 0, 0)
            else:
                self.extents = Extents_s(tl.x0, tl.y0, br.x1, br.y1)
        else:
            self.extents = Extents_s(0, 0, 0, 0)

    cdef bint contains_point(self, double x, double y):
        return x >= self.extents.x0 and x < self.extents.x1 and \
               y >= self.extents.y0 and y < self.extents.y1

    cdef bint contains_extents(
        self, double x0, double y0, double x1, double y1
    ):
        return self.contains_point(x0, y0) and self.contains_point(x1, y1)

    cpdef get_tile_indices(self, double x, double y):
        """Returns indices for the :class:`Tile` containing the point at
        (x, y) coordinates.

        If the point(x, y) lies outside the :class:`Measurable`
        this :class:`TilesGrid` belong to, indices for the nearest
        :class:`Tile` will be return.

        Args:
            x, y: coordinates express in unit of measure for
                  the :class:`Measurable` this :class:`TilesGrid` belong to.

        Returns:
            indices as an int tuple(x, y) where to find the Tile or None
            if this :class:`TilesGrid` is empty.
        """
        if self.view is not None:
            x = self.extents.x0 if x < self.extents.x0 else x
            y = self.extents.y0 if y < self.extents.y0 else y
            return (
                <Py_ssize_t> cmin(
                    self.view.shape[0],
                    self.view.shape[0] * (x / self.extents.x1)
                ),
                <Py_ssize_t> cmin(
                    self.view.shape[1],
                    self.view.shape[1] * (y / self.extents.y1)
                )
            )
        else:
            return None

    cdef stats(self):
        cdef Py_ssize_t x, y
        self._u = self._z = 0
        for x in range(self.view.shape[0]):
            for y in range(self.view.shape[1]):
                tile = self._ref.items[self.view[x, y]]
                if tile is not None:
                    self._u += (<Tile>tile)._u
                    self._z += (<Tile>tile)._z
        if self._z <> 0:
            self._r = self._u / float(self._z)

    def __str__(self):
        self.stats()
        return (
            f"{self.__class__.__name__}@({id(self)}):\n"
            f"{super().__str__()}\n"
            f"extents: ({self.extents.x0:.1f}, {self.extents.y0:.1f}, "
            f"{self.extents.x1:.1f}, {self.extents.y1:.1f})\n"
            f"u:{format_size(self._u)}, z:{format_size(self._z)}, r:{self._r:.1f}"
        )


cdef class SuperTile(TilesGrid):
    """A special view of another :class:`TilesGrid`.

    A :class:`SuperTile` could be moved on its referred :class:`TilesGrid`
    in the mean of doing diverses operations (eg: compression, deallocating
    buffer, getting stats...) only on :class:`Tile` belonging to this view.

    Args:
        grid: a :class:`TilesGrid` that this :class:`SuperTile` will refer to.
        width: an :class:`int` as the width of this view (default to 2).
        height: an :class:`int` as the height of this view (default to 2).
    """

    def __cinit__(self, grid, shape=(2, 2), *args, **kwargs):
        if grid is None or not isinstance(grid, TilesGrid):
            raise TypeError("grid should be a TilesGrid instance")
        width, height = shape
        if width < 1: width = 1
        else: width = cimin(width, (<TilesGrid> grid).view.shape[0])
        if height < 1: height = 1
        else: height = cimin(height, (<TilesGrid> grid).view.shape[1])
        self._ref = grid
        self.memory_format = (<TilesGrid> grid).memory_format
        self.slice_ref(slice(0, width, 1), slice(0, height, 1))
        self.compute_extents()
        self.stats()

    def __init__(self, grid: TilesGrid, shape=(2, 2)):
        pass

    cpdef bint move_to(self, int x, int y):
        """Move this :class:`SuperTile` onto its base :class:`TilesGrid`.

        This method always keep the :class:`SuperTile`
        fully contained in its base :class:`TilesGrid`.

        Args:
         x, y: indices for the top-left :class:`Tile` relatif
               to the :attr:`TilesGrid.base` :class:`TilesGrid`.
        """
        cdef int rw, rh, sw, sh, xo, yo
        sw, sh = self.view.shape
        rw, rh = self._ref.view.shape
        xo = cimax((rw - sw) if x >= (rw - sw) else x, 0)
        yo = cimax((rh - sh) if y >= (rh - sh) else y, 0)
        if self._ref.view[xo, yo] != self.view[0, 0]:
            self.slice_ref(slice(xo, xo + sw, 1), slice(yo, yo + sh, 1))
            self.compute_extents()
            self.stats()
            return True
        return False


cdef class Clip():
    """A simple structure to hold a rendered region
    returned by a :class:`RenderTile`.
    """

    def __cinit__(self, x=0, y=0, w=0, h=0):
        self._x = x
        self._y = y
        self._w = w
        self._h = h
        self._texture = None

    def __init__(self, x: float =0, y: float =0, w: int =0, h: int =0):
        pass

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
        return (
            f"Clip(x={self._x}, y={self._y}, w={self._w}, h={self._h}, "
            f"texture={self._texture})"
        )


cdef class RenderTile(SuperTile):
    """A two by two :class:`SuperTile`.

    A :class:`RenderTile` is a (2,2) shaped :class:`SuperTile`.
    The goal is to agregate the subTile's compressed buffer of this view
    in an uncompressed one available as a :class:`Gdk.Texture`.
    This :class:`Gdk.Texture` could be retrieved by accessing
    the :attr:`RenderTile.clip` property.

    Args:
        grid: a :class:`TilesGrid` that this RenderTile will refer to.
    """

    def __cinit__(self, grid, shape=(2, 2), *args, **kwargs):
        self.is_valid = False
        self.buffer = None
        self.glib_bytes = None
        self._clip = Clip.__new__(Clip)
        self._r_clip = Clip.__new__(Clip)

    def __init__(self, grid: TilesGrid, shape=(2, 2)):
        pass

    cpdef bint move_to(self, int x, int y):
        """Move this :class:`RenderTile` onto its base :class:`TilesGrid`.

        This method always keep the :class:`RenderTile`
        fully contained in its base :class:`TilesGrid`.

        Args:
         x, y: indices for the top-left :class:`Tile` relatif
               to the :attr:`TilesGrid.base` :class:`TilesGrid`.
        """
        cdef Clip clip
        if SuperTile.move_to(self, x, y):
            self.invalidate()
            clip = self._clip if self.switch else self._r_clip
            clip._x = self.extents.x0
            clip._y = self.extents.y0
            return True
        return False

    cpdef invalidate(self):
        """Mark the content of the internal uncompressed buffer as invalid.

        After this call the content of the internal buffer should be
        recomputed with a call to one of the rendering methods:
        :meth:`RenderTile.render_texture`,
        :meth:`RenderTile.render_texture_async`.
        """
        # self._clip._texture = None
        # self.glib_bytes = None
        # self.buffer = None
        self.switch = not self.switch
        self.is_valid = False

    cdef int allocate_buffer(self):
        """Allocate self.buffer to host offscreen image
        of the resulting union of compressed subtiles."""
        cdef Py_ssize_t sh = 0
        cdef int i
        cdef Clip clip

        self._z = self._u = self._r = 0
        for tile in self:
            if tile is None:
                self.msg = "Invalid Tiles to allocate buffer's RenderTile"
                return -1
            if (<Tile> tile).buffer:
                sh += (<Tile> tile).u_shape
                self._z += (<Tile> tile)._z
                self._u += (<Tile> tile)._u
            else:
                self.msg = "Invalid Tile's buffer to allocate buffer's RenderTile"
                self._z = self._u = self._r = 0
                return -2
        self._r = self._u / float(self._z)

        try:
            self.buffer = Carray.__new__(
                Carray,
                shape=(sh,),
                itemsize=(<Tile> self[0, 0]).u_itemsize,
                format=(<Tile> self[0, 0]).u_format,
                mode='c',
                allocate_buffer=True,
            )
        except MemoryError as m:
            self.msg = (
                f"{m}: "
                f"shape({sh},), "
            )
            return -3

        clip = self._clip if self.switch else self._r_clip
        clip._w = clip._h = 0
        for i in range(self.view.shape[0]):
            clip._w += (<Tile> self[i, 0])._size[0]
        for i in range(self.view.shape[1]):
            clip._h += (<Tile> self[0, i])._size[1]
        return 1

    cdef int fill_buffer(self):
        """Actually decompress the subtiles buffers in the RenderTile.buffer."""
        cdef list vbands = []
        cdef list vbands_shape = []
        cdef Py_ssize_t w_buf, rows
        cdef Py_ssize_t offset, ww, x, y
        cdef Py_ssize_t buf_width = 0
        cdef char* ptr
        cdef bint isvalid

        _T = Timer("prepare decompression")
        # is it safe for pixmap's buffer to be merged ?
        isvalid = True
        y = 0
        for x in range (self.view.shape[0]):
            vbands_shape.append(0)
            for y in range (self.view.shape[1] - 1):
                isvalid &= (
                    (<Tile> self.getitem_at(x, y))._size[0] == \
                    (<Tile> self.getitem_at(x, y + 1))._size[0]
                )
                vbands_shape[x] += (<Tile> self.getitem_at(x, y)).u_shape
            vbands_shape[x] += (<Tile> self.getitem_at(x, y + 1)).u_shape
        for y in range (self.view.shape[1]):
            for x in range (self.view.shape[0] - 1):
                isvalid &= (
                    (<Tile> self.getitem_at(x, y))._size[1] == \
                    (<Tile> self.getitem_at(x + 1, y))._size[1]
                )

        if self.buffer and isvalid:
            try:
                for x in range(self.view.shape[0]):
                    vbands.append(
                        Carray.__new__(
                            Carray,
                            shape=(vbands_shape[x], ),
                            itemsize=self.buffer.itemsize,
                            format=self.buffer.format,
                            mode='c',
                            allocate_buffer=True,
                        )
                    )
            except MemoryError:
                self.msg = "can´t allocate temporary buffers"
                return -3
            _T.stop()

            _T = Timer("decompress buffers")
            rows = 0
            for x in range(self.view.shape[0]):
                buf_width += (<Tile> self.getitem_at(x, 0))._size[0] * \
                             (<Tile> self.getitem_at(x, 0)).format_size
                offset = 0
                for y in range(self.view.shape[1]):
                    if x == 0:
                        rows += (<Tile> self.getitem_at(x, y))._size[1]
                    ptr = (<Carray> vbands[x]).data
                    blosc.decompress_ptr(
                        (<Tile> self.getitem_at(x, y)).buffer,
                        address=<Py_ssize_t> &ptr[offset],
                    )
                    offset += (<Tile> self.getitem_at(x, y)).u_shape
            _T.stop()

            _T = Timer("merge_side_buffers")
            offset = 0
            for x in range(self.view.shape[0]):
                ww = (<Tile> self.getitem_at(x, 0))._size[0] * \
                     (<Tile> self.getitem_at(x, 0)).format_size
                RenderTile.copy_vband(
                    vbands[x], self.buffer, rows,
                    ww, buf_width, offset
                )
                offset += ww
            _T.stop()

            return 1
        else:
            self.msg = "Invalid buffer or Tile's format to fill buffer"
            return -2

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @staticmethod
    cdef void copy_vband(
        const uc8[:] vband, uc8[:] buffer, Py_ssize_t rows,
        Py_ssize_t vband_width, Py_ssize_t buf_width, Py_ssize_t x_offset
    ) nogil:
        cdef Py_ssize_t x_in, x_out, y
        for y in range(rows):
            x_in = vband_width * y
            x_out = (buf_width * y) + x_offset
            buffer[x_out:x_out + vband_width] = vband[x_in:x_in + vband_width]

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @staticmethod
    cdef void merge_side_buffers(
        const uc8[:] west, const uc8[:] east, uc8[:] buffer,
        Py_ssize_t rows, Py_ssize_t west_width, Py_ssize_t east_width,
    ) nogil:
        cdef Py_ssize_t x_in, x_out, y
        cdef Py_ssize_t buf_width = east_width + west_width
        for y in range(rows):
            # copy west
            x_in = west_width * y
            x_out = buf_width * y
            buffer[x_out:x_out + west_width] = west[x_in:x_in + west_width]
            # copy east
            x_in = east_width * y
            x_out += west_width
            buffer[x_out:x_out + east_width] = east[x_in:x_in + east_width]

    cpdef render_texture(self):
        cdef Clip clip
        if not self.is_valid:
            if self.allocate_buffer() < 0:
                raise MemoryError(f"{self.msg}")
            clip = self._clip if self.switch else self._r_clip

            if self.fill_buffer() > 0:
                _T = Timer("glib.bytes")
                #FIXME: here data is copied 2 times !!!
                glib_bytes = GLib.Bytes.new_take(
                    PyBytes_FromObject(self.buffer)
                )
                self.buffer = None
                _T.stop()

                clip._texture = Gdk.MemoryTexture.new(
                    clip._w,
                    clip._h,
                    self.memory_format,
                    glib_bytes,
                    3 * clip._w,
                )
                self.is_valid = True
            else:
                self.invalidate()
        else:
            clip = self._r_clip if self.switch else self._clip
            clip._texture = None

    async def render_texture_async(self) -> Coroutine:
        self.render_texture()

    @property
    def clip(self) -> Clip:
        """A :class:`Clip` holding a :class:`Gdk.Texture` filled with
        the uncompressed data buffer of the subtiles (read only)."""
        cdef Clip clip
        clip = self._clip if self.switch else self._r_clip
        return clip

    def __str__(self):
        return (
            f"{super().__str__()}\n"
            f"validity: {self.is_valid}\n"
            f"buffer: {self.buffer}\n"
            f"texture: {self._clip._texture}"
        )


@cython.final
cdef class TilesPool():
    """An helper Class for :class:`acide.graphic.Graphic` to manage
    its :class:`Tile`.

    :meth:`TilesPool.__init__` could be safely call more than once. This is
    needed because :class:`TilesPool` could be instancied before the
    viewport widget is realized by Gtk and therefore will lack valid viewport's
    properties to be correctly initialized.

    Args:
        graphic: the :class:`acide.graphic.Graphic` holding ths
                 :class:`TilesPool`
        viewport: the rendering widget for :obj:`graphic`, should
                  implement :class:`acide.measure.Measurable`
        scales: A sequences of positive int as the available scale factors
        render_shape : A 2 lenght int sequence as the shape of the render tile
        mem_format: a enum's member of :class:`Gdk.MemoryFormat`
        pixbuf_cb: a callback function to retrieve parts of a pixmap with
                   the signature: pixbuf_cb(rect: Graphene.Rect, scale: int)
                   -> :class:`acide.types.Pixbuf`
    """

    def __cinit__(
        self, graphic, viewport, scales, render_shape, mem_format, pixbuf_cb
    ):
        if (
            not isinstance(graphic, Measurable) or \
            not isinstance(viewport, Measurable)
        ):
            raise TypeError(
                "graphic and viewport parameters should implement"
                " the Measurable interface"
            )
        self.graphic = graphic
        self.viewport = viewport
        if not test_sequence(render_shape, (int, int)):
            raise ValueError(
                f"render_shape should be a 2 lenght sequence of int not {render_shape}"
            )
        self.render_shape = tuple(render_shape)
        self.memory_format = mem_format
        self.pixbuf_cb = pixbuf_cb
        self.render_tile = None
        self.scheduler = Scheduler.new()
        self.scheduler.run(Run.FOREVER)
        self.null_clip = Clip()
        self.current = -1

    def __init__(
        self,
        graphic: Measurable,
        viewport: Measurable,
        scales: Sequence[int],
        render_shape: Sequence[int],
        mem_format: Gdk.MemoryFormat,
        pixbuf_cb: PixbufCallback,
    ):
        _T = Timer("TilesPool init")
        self.current = -1
        self.stack = []
        self.validate_scales(scales)

        for scl in scales:
            if self.make_tiles_grid(scale=int(scl)) > 0:
                # viewport.size could be (0, 0)
                # if widget is not yet realized
                # so be prepared to this
                self.current += 1
                self.init_tiles_grid(
                    <TilesGrid> self.stack[self.current], int(scl)
                )
            else:
                self.stack = []
                break
        self.depth = len(self.stack)
        # keep current at -1 so 1st call to set_rendering()
        # could initialize the render_tile
        self.current = -1
        _T.stop()

    @property
    def is_ready(self):
        "True if this :class:`TilesPool` is ready to accept rendering request."
        return bool(len(self.stack))

    cdef validate_scales(self, list scales):
        try:
            for scl in scales:
                assert (int(scl) > 0)
        except Exception:
            raise ValueError(
                f"scales should be a Sequence of value interpretable as"
                f"int > 0"
            )
        scales.sort()

    cdef int make_tiles_grid(self, unsigned int scale):
        cdef double vw, vh, gw, gh, trs
        cdef int width, height, rw, rh
        vw, vh = self.viewport.size
        rw, rh = self.render_shape
        trs = self.viewport.get_transform(self.graphic.unit)
        if vw!=0 and vh!=0:
            gw, gh = self.graphic.size
            gw *= scale
            gh *= scale
            width = cimax(rw, ciceil(gw / (vw * trs)))
            height = cimax(rh, ciceil(gh / (vh * trs)))
            self.stack.append(
                TilesGrid(
                    shape=(width, height),
                    format=self.memory_format
                )
            )
            return 1
        return 0

    cdef init_tiles_grid(self, TilesGrid tg, unsigned int scale):
        cdef int sw, sh, x, y
        cdef double w, h, wt, ht
        sw, sh = tg.view.shape
        w, h = self.graphic.size
        wt = w / sw
        ht = h / sh
        for x in range(sw):
            for y in range(sh):
                tg[x, y] = Tile(
                    rect=(wt * x, ht * y, wt, ht),
                    unit=self.graphic.unit,
                    dpi=self.graphic.dpi * scale,
                )
        tg.compute_extents()

    cdef schedule_compression(self):
        cdef int i = 0
        cdef int _next = 0
        cdef int scale = int(self.graphic.scale)

        tg = self.stack[self.current]

        self.scheduler.stop()
        gen = tg.compress_async_generator(self.pixbuf_cb, scale)
        for _co in gen:
            self.scheduler.add(
                _co,
                priority=Priority.NEXT,
                callback=None,
                name=f"tile_grid[{self.current}][{i}]_compress",
            )
            i += 1

        if self.current < len(self.stack) - 2:
            i = 0
            _next = self.current + 1
            tg = self.stack[_next]
            scale = int(self.graphic._scales[self.graphic._scale_index + 1])
            gen = tg.compress_async_generator(self.pixbuf_cb, scale)
            for _co in gen:
                self.scheduler.add(
                    _co,
                    priority=Priority.NEXT,
                    callback=None,
                    name=f"tile_grid[{_next}][{i}]_compress_#LOW",
                )
                i += 1

    cpdef set_rendering(self, double x, double y, int depth=0):
        """Setup the rendering :class:`RenderTile` so the point
        at :obj:`(x, y)` will fit in its region.

        This method is usually called by a :class:`acide.graphic.Graphic`
        before requesting rendering with :meth:`render`.

        Args:
            x, y: coordinates express in the unit of measure of
                    the :class:`acide.graphic.Graphic`
            depth: a positive integer as an index of scales given at
                   :class:`TilesPool` initialzation
        """
        cdef int i, j, cx, cy
        _T = Timer("set_rendering")
        i, j = self.stack[self.current].get_tile_indices(x, y)

        if depth != self.current:
            # FIXME: should we invalidate TilesGrid? or
            # keep all compressed buffer or an in beetween
            # (<TilesGrid> self.stack[self.current]).invalidate()
            self.current = depth
            # self.invalid_render = self.render_tile
            self.render_tile = RenderTile(
                self.stack[self.current], self.render_shape
            )
            self.schedule_compression()

        cx, cy = self.render_tile.get_center()
        self.render_tile.move_to(i - cx, j - cy)
        _T.stop()

    cpdef render(self):
        """Request rendering on the :class:`RenderTile`.

        Returns:
            a :class:`Clip` holding a :class:`Gdk.Tetxure`
        """
        if self.render_tile is not None:
            (<TilesGrid> self.stack[self.current]).compress(self.pixbuf_cb)
            self.render_tile.render_texture()
            return self.render_tile._clip
        else:
            return self.null_clip

    def render_async(
        self,
        cancellable: Gio.Cancellable,
        callback: AsyncReadyCallback,
        user_data: Any,
    ) -> None:
        """Request asynchronious rendering on the :class:`RenderTile`.

        :obj:`callback` function will be called when rendering will be done,
        :obj:`callback` function should request the result by calling
        :meth:`render_finish`.

        args:
            cancellable:
            callback:
            user_data:
        """
        if self.render_task is not None and \
           not self.render_task.done():
            self.render_task.cancel()

        if isinstance(user_data, Gio.Task):
            gtask = user_data
        else:
            gtask = Gio.Task.new(self, cancellable, callback, user_data)
        self.scheduler.stop()
        self.render_task = self.scheduler.add(
            self._render_super_tile_co(gtask),
            Priority.HIGH,
            callback=None,
            name="render_tile",
        )
        self.scheduler.run(Run.LAST)

    def render_async_mp(
        self,
        cancellable: Gio.Cancellable,
        callback: AsyncReadyCallback,
        user_data: Any,
    ) -> None:
        if self.render_task is not None and \
           not self.render_task.done():
            self.render_task.cancel()

        if isinstance(user_data, Gio.Task):
            gtask = user_data
        else:
            gtask = Gio.Task.new(self, cancellable, callback, user_data)
        self.scheduler.stop()
        self.render_task = self.scheduler.add(
            functools.partial(self._render_super_tile, gtask),
            Priority.HIGH,
            callback=None,
            name="render_tile_mp",
        )
        self.scheduler.run(Run.LAST)

    def _render_super_tile(self,  gtask: Gio.AsyncResult):
        print("_render_super_tile")
        _T = Timer("_render_super_tile")
        self.render_tile.compress(self.pixbuf_cb, self.graphic.scale)
        self.render_tile.render_texture()
        _T.stop()
        self._on_render_ready_cb(gtask)

    async def _render_super_tile_co(self,  gtask: Gio.AsyncResult):
        try:
            _T = Timer("_render_super_tile_co")
            await self.render_tile.compress_async(
                self.pixbuf_cb, self.graphic.scale
            )
            await self.render_tile.render_texture_async()
            _T.stop()
        except asyncio.CancelledError:
            print("render cancelled")
            raise
        else:
            self._on_render_ready_cb(gtask)
        finally:
            pass

    def _on_render_ready_cb(self, gtask: Gio.AsyncResult) -> None:
        # complete the gtask calling the render_async callback
        gtask.return_boolean(True)
        # self.dump_stack()

    def render_finish(self, result: Gio.Task, data: any = None):
        if result.propagate_boolean():
            # if self.invalid_render is not None:
            #     self.invalid_render.invalidate()
            #     self.invalid_render = None
            return self.render_tile.clip
        else:
            return self.null_clip

    def dump_stack(self):
        # for tg in self.stack:
        #     print(tg)
        # print(self.render_tile)
        z, u = self.memory_print()
        print(f"memory footprint: {format_size(z)} | {format_size(u)}")

    cpdef memory_print(self):
        cdef unsigned long mem = 0
        cdef unsigned long u_mem = 0
        if self.render_tile is not None:
            mem += self.render_tile._u
            u_mem = mem
        if self.invalid_render is not None:
            mem += self.invalid_render._u
            u_mem = mem
        for tg in self.stack:
            (<TilesGrid> tg).stats()
            mem += (<TilesGrid> tg)._z
            u_mem += (<TilesGrid> tg)._u
        return (mem, u_mem)


