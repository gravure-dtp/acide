# -*- coding: utf-8 -*-
# main.py
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
"""duplex modules.

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


cdef class Duplex():
    cdef float ps_x = 0
    cdef float ps_y = 0
    cdef int ds_x = 0
    cdef int ds_y = 0

    
