# tiles.pxd
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

from cython.view cimport array as Carray
from acide.types cimport TypedGrid, test_sequence, cmin, cmax, ciceil, cimin, cimax
from acide.measure cimport _CMeasurable, Extents_s

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

    cdef bytes PyBytes_FromObject(object o)
    cdef bytearray PyByteArray_FromObject(object o)


cdef object gdk_memory_format_mapping()


cdef class Tile(_CMeasurable):
    # MEMBERS
    cdef Py_ssize_t _u
    cdef Py_ssize_t _z
    cdef float _r
    cdef tuple _size
    cdef object buffer
    cdef Py_ssize_t u_shape
    cdef int u_itemsize
    cdef bytes u_format
    cdef int format_size

    # C METHODS
    cpdef object compress(Tile self, object buffer, object size, object format)
    cpdef object invalidate(Tile self)


cdef class TilesGrid(TypedGrid):
    # MEMBERS
    cdef Py_ssize_t _u
    cdef Py_ssize_t _z
    cdef float _r
    cdef object memory_format
    cdef Extents_s extents

    # C METHODS
    cpdef object invalidate(TilesGrid self)
    cpdef compress(TilesGrid self, object graphic)
    cdef compute_extents(TilesGrid self)
    cdef bint contains_point(TilesGrid self, double x, double y)
    cdef bint contains_extents(
        TilesGrid self, double x0, double y0, double x1, double y1
    )
    cdef stats(TilesGrid self)
    cpdef get_tile_indices(TilesGrid self, double x, double y)


cdef class Clip():
    cdef double _x, _y
    cdef int _w ,_h
    cdef object _texture

ctypedef unsigned char uc8

cdef class SuperTile(TilesGrid):
    # MEMBERS
    cdef Carray buffer
    cdef object glib_bytes
    cdef bint is_valid
    cdef Clip _clip
    cdef unicode msg

    # C METHODS
    cpdef invalidate(SuperTile self)
    cpdef move_to(SuperTile self, int x, int y)
    cdef int allocate_buffer(SuperTile self)
    cdef int fill_buffer(SuperTile self)
    @staticmethod
    cdef void merge_side_buffers(
        const uc8[:] west, const uc8[:] east, uc8[:] buffer,
        Py_ssize_t rows, Py_ssize_t west_width, Py_ssize_t east_width
    ) nogil
    cpdef render_texture(SuperTile self)


cdef class TilesPool():
    # MEMBERS
    cdef list stack
    cdef int depth
    cdef int current
    cdef SuperTile render_tile, invalid_render
    cdef object graphic
    cdef object viewport
    cdef object memory_format
    cdef object pixbuff_cb

    # C METHODS
    cdef int make_tiles_grid(TilesPool self, unsigned int scale)
    cdef object init_tiles_grid(
        TilesPool self, TilesGrid tg,  unsigned int scale
    )
    cpdef set_rendering(
        TilesPool self, double x, double y, int depth=?
    )
    cpdef object render(TilesPool self)
    cpdef object after_render_cb(TilesPool self)
    cdef object validate_scales(TilesPool self, list scales)
    cpdef int memory_print(TilesPool self)

