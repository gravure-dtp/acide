# graphic.py
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

from abc import ABC, abstractmethod
from enum import IntEnum, unique, auto
from typing import Any, Union, Optional, Tuple

from gi.repository import Gdk, GLib, Graphene

import blosc

from cython.view cimport array as carray

BufferProtocol = Any

@unique
class UNIT(IntEnum):
    MILLIMETER = auto()
    INCH = auto()
    PS_POINT = auto()


ps2inch_transform: float = 1.0 / 72.0
inch2ps_transform: float = 72.0
ps2mm_transform: float = 25.4 / 72.0
mm2ps_transform: float = 72.0 / 25.4


cdef extern from "Python.h":
    ctypedef struct PyObject
    ctypedef Py_ssize_t Py_intptr_t
    ctypedef struct __pyx_buffer "Py_buffer":
        PyObject *obj
        void* buf
        Py_ssize_t len
        Py_ssize_t itemsize

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


cdef class Tile():
    cdef readonly int u
    cdef readonly int z
    cdef readonly float r
    cdef public object point
    cdef public object size
    cdef object buffer

    def __cinit__(self):
        self.u = 0
        self.z = 0
        self.r = 0

    def __dealloc__(self):
        self.buffer = None

    def __init__(self, point: Graphene.Point, size: Graphene.Size):
        self.buffer = None
        self.point = point
        self.size = size

    def compress(self, buffer: Union[memoryview, BufferProtocol]):
        cdef Py_buffer view
        cdef Py_buffer* p_view = &view
        cdef char* ptr

        if isinstance(buffer, memoryview):
            p_view = PyMemoryView_GET_BUFFER(buffer)
        elif PyObject_CheckBuffer(buffer):
            PyObject_GetBuffer(buffer, p_view, PyBUF_SIMPLE)
        else:
            raise TypeError(
                "Argument buffer should be either a memoryview"
                "or an object implenting the buffer protocol"
                "data should be contigous in memory"
            )

        if not PyBuffer_IsContiguous(p_view, b'c'):
            raise TypeError("data should be contigous in memory")

        self.u = p_view.len
        ptr = <char*> p_view.buf
        self.buffer = blosc.compress_ptr(
            adress=<Py_ssize_t> &ptr[0],
            items=p_view.len,
            typesize=p_view.itemsize,
            clevel=9,
            shuffle=blosc.BITSHUFFLE,
            cname='lz4',
        )
        self.z = len(self.buffer)
        self.r = self.u / float(self.z)
        PyBuffer_Release(p_view)


class SuperTile(Tile):
    __slots__ = (
        'tile_0',
        'tile_1',
        'tile_2',
        'tile_3',
    )

    def __init__(self, tile_0, tile_1, tile_2, tile_3, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.tile_0 = tile_0
        self.tile_1 = tile_1
        self.tile_2 = tile_2
        self.tile_3 = tile_3
        self.c_buffer = None

    def texture(self):
        buf_0 = blosc.decompress(self.tile_0.buffer)
        buf_1 = blosc.decompress(self.tile_1.buffer)
        buf_2 = blosc.decompress(self.tile_2.buffer)
        buf_3 = blosc.decompress(self.tile_3.buffer)

        # here data is copied
        self._gbytes = GLib.Bytes.new(
            self._pixmap.samples_mv
        )

        self._texture = Gdk.MemoryTexture.new(
            self._pixmap.width,
            self._pixmap.height,
            Gdk.MemoryFormat.R8G8B8,
            self.gbytes,
            3 * self._pixmap.width,
        )


class GraphicInterface(ABC):
    __slots__ = (
        'tile',
        'point',
        'size',
        '_dpi',
        '_zoom',
        '_viewport_size',
        '_sub_tiles',
    )

    def __init__(self, monitor_dpi, viewport_size):
        self._dpi = monitor_dpi
        self._viewport_size = viewport_size
        self._zoom = 1.0
        self._subtiles = []

    @abstractmethod
    def zoom_in(self):
        pass

    @abstractmethod
    def zoom_out(self):
        pass


# cdef class Duplex():
#     cdef float ps_x = 0
#     cdef float ps_y = 0
#     cdef int ds_x = 0
#     cdef int ds_y = 0

