# types.pxd
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
from cython.view cimport array as Carray
from cython.view cimport memoryview as Mview


cdef inline double cmax(double a, double b):
    if b > a: return b
    else: return a


cdef inline int cimax(int a, int b):
    if b > a: return b
    else: return a


cdef inline double cmin(double a, double b):
    if b < a: return b
    else: return a


cdef inline int cimin(int a, int b):
    if b < a: return b
    else: return a


cdef inline int ciround(double number):
    if number >= 0: return <int> (number + 0.5)
    else: return <int>(number - 0.5)


cdef inline int ciceil(double number):
    cdef int i_num = <int> number
    if (<double> i_num) == number: return i_num
    else: return i_num + 1


cdef bint test_sequence(object seq, tuple _types)


cdef class Pixbuf():
    cdef readonly object buffer
    cdef readonly int width
    cdef readonly int height
    cdef readonly object obj


cdef class TypedGrid:
    # MEMBERS
    cdef object pytype
    cdef list items
    cdef TypedGrid _ref
    cdef Mview view
    cdef Carray indices

    # C METHODS
    cdef object getitem(TypedGrid self, index)
    cdef object getitem_at(TypedGrid self, x, y)
    cdef int getindex_at(self, int x, int y)
    cdef TypedGrid get_slice(TypedGrid self, object slice_x, object slice_y)
    cdef slice_inplace(TypedGrid self, object slx, object sly)
    cdef slice_ref(TypedGrid self, object slx, object sly)
    cpdef tuple get_center(TypedGrid self)
