# tile.pxd
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
cimport cython

from acide.measure cimport _CMeasurable
from acide.types cimport Pixbuf


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
        PyBUF_CONTIG
        PyBUF_CONTIG_RO


cdef object gdk_memory_format_mapping()


cdef class Tile(_CMeasurable):
    # MEMBERS
    cdef Py_ssize_t _u
    cdef Py_ssize_t _z
    cdef float _r
    cdef tuple _size
    cdef bytes buffer
    cdef Py_ssize_t u_shape
    cdef int u_itemsize
    cdef bytes u_format
    cdef int format_size

    # C METHODS
    cpdef object compress(Tile self, Pixbuf pixbuf, object format)
    cpdef object invalidate(Tile self)


cdef class _TileReduce():
    cdef tuple _size
    cdef object buffer
    cdef Py_ssize_t u_shape
    cdef int format_size
