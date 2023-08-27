# mprendering.pxd
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
from cython.view cimport array as Carray
from acide.types cimport uc8
from acide.tile cimport _TileReduce


cdef extern from "Python.h":
    cdef bytes PyBytes_FromObject(object o)


cdef void copy_vband(
    const uc8[:] vband, uc8[:] buffer, Py_ssize_t rows,
    Py_ssize_t vband_width, Py_ssize_t buf_width, Py_ssize_t x_offset
) nogil


cdef class Clip():
    # MEMBERS
    cdef double _x, _y
    cdef int _w ,_h
    cdef Carray buffer
    cdef bytes _bytes
    cdef object _texture
    cdef int memory_format
    cdef unicode msg

    # C METHODS
    cdef int allocate_buffer(
        Clip self, Py_ssize_t shape, Py_ssize_t itemsize, bytes format
    )
    cdef int fill_buffer(
        Clip self, int width, int height, list tiles, list vbands_shape,
        Py_ssize_t itemsize, bytes format,
    )

    
