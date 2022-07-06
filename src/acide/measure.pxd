# measure.pxd
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
from acide.types cimport test_sequence, ciround


cdef double transform(object unit1, object unit2, double dpi=?)


ctypedef struct Extents_s:
    double x0
    double y0
    double x1
    double y1


cdef class _CMeasurable():
    # MEMBERS
    cdef public object unit
    cdef public object rect
    cdef public double dpi
    cdef readonly double ps2inch_transform
    cdef readonly double inch2ps_transform
    cdef readonly double inch2mm_transform
    cdef readonly double mm2inch_transform
    cdef readonly double ps2mm_transform
    cdef readonly double mm2ps_transform

    # C METHODS
    # cdef double inch2px_transform(_CMeasurable self)
    # cdef double px2inch_transform(_CMeasurable self)
    # cdef double ps2px_transform(_CMeasurable self)
    # cdef double px2ps_transform(_CMeasurable self)
    # cdef double mm2px_transform(_CMeasurable self)
    # cdef double px2mm_transform(_CMeasurable self)

    cdef Extents_s get_extents(_CMeasurable self)

    cpdef double get_transform(_CMeasurable self, object unit)
    cpdef object get_center(_CMeasurable self)
    cpdef object get_top_left(_CMeasurable self)
    cpdef object get_top_right(_CMeasurable self)
    cpdef object get_bottom_left(_CMeasurable self)
    cpdef object get_bottom_right(_CMeasurable self)
    cpdef float get_area(_CMeasurable self)
    cpdef unsigned int get_pixmap_area(_CMeasurable self)
    cpdef object get_pixmap_rect(_CMeasurable self)
    cpdef round(_CMeasurable self)
    cpdef bint contains(_CMeasurable self, object other)
    cpdef offset(_CMeasurable self, float x, float y)
    cpdef object _dump_props(_CMeasurable self)
