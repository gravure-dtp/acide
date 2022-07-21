# measure.pyx
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

from enum import Enum, unique, auto
from typing import Any, Union, Optional, NoReturn, Sequence, Tuple

import gi
gi.require_version('Graphene', '1.0')
from gi.repository import Graphene

from acide.types import Number, Rectangle


cdef:
    double ps2inch_transform = 1.0 / 72.0
    double inch2ps_transform = 72.0
    double inch2mm_transform = 25.4
    double mm2inch_transform = 1.0 / 25.4
    double ps2mm_transform = 25.4 / 72.0
    double mm2ps_transform = 72.0 / 25.4


@unique
class Unit(Enum):
    """Unit enumeration.
    """
    UNSET = auto()
    MILLIMETER = auto()
    PS_POINT = auto()
    INCH = auto()
    PIXEL = auto()

    __nick__ = {
        "UNSET":"",
        "MILLIMETER":"mm",
        "PS_POINT":"pt",
        "INCH":"\"",
        "PIXEL":"px"
    }

    @property
    def abbr(self) -> str:
        """A string as the abbreviation for this unit of measure.

        e.g.: 'mm' for Unit.MILLIMETERS
        """
        return self.__nick__[self.name]

    def convert(self, value, other: 'Unit', dpi: float = 1.0) -> float:
        """Convert :obj:`value` as :obj:`self` unit to :obj:`other` unit.

        Args:
            value: the value to convert
            other: :class:`Unit` member to convert to.
            dpi: a :class:`float` as dpi if requesting a convertion that
                 involved a :attr:`Unit.PIXEL`

        returns:
            A :class:`float` as the converted value.
        """
        return value * transform(self, Unit(other), dpi)

    def get_transform(self, other: 'Unit', dpi: float = 1.0) -> float:
        """Get the transform coefficient to convert between
        :attr:`self` and :obj:`other`.

        Args:
            other: another :class:`Unit` member.
            dpi: a :class:`float` as dpi if requesting a transformation that
                 involved a :attr:`Unit.PIXEL`

        returns:
            A :class:`float`, return 1.0 if units are the same
            or one of them was :obj:`Unit.UNSET`.
        """
        return transform(self, Unit(other), dpi)


cdef double transform(object unit1, object unit2, double dpi=1.0):
    if unit1 is Unit.PS_POINT:
        if unit2 is Unit.MILLIMETER:
            return ps2mm_transform
        if unit2 is Unit.INCH:
            return ps2inch_transform
        if unit2 is Unit.PIXEL:
            return dpi * ps2inch_transform
    elif unit1 is Unit.INCH:
        if unit2 is Unit.MILLIMETER:
            return inch2mm_transform
        if unit2 is Unit.PS_POINT:
            return inch2ps_transform
        if unit2 is Unit.PIXEL:
            return dpi
    elif unit1 is Unit.MILLIMETER:
        if unit2 is Unit.INCH:
            return mm2inch_transform
        if unit2 is Unit.PS_POINT:
            return mm2ps_transform
        if unit2 is Unit.PIXEL:
            return dpi * mm2inch_transform
    elif unit1 is Unit.PIXEL:
        if unit2 is Unit.INCH:
            return 1.0 / dpi
        if unit2 is Unit.PS_POINT:
            return 1.0 / (dpi * ps2inch_transform)
        if unit2 is Unit.MILLIMETER:
            return 1.0 / (dpi * mm2inch_transform)
    else:
        return 1.0


cdef class _CMeasurable():

    def __cinit__(self, rect=None, unit=Unit.UNSET, dpi=0, *args, **kwargs):
        self.dpi = float(dpi)
        if self.dpi < 0:
            raise ValueError("dpi should be positive")
        self.unit = Unit(unit)
        self.rect = Graphene.Rect()

        if rect is None:
            self.rect.init(0, 0, 0, 0)
        elif test_sequence(
            rect, ((int, float), (int, float), (int, float), (int, float))
        ):
            self.rect.init(rect[0], rect[1], rect[2], rect[3])
        elif isinstance(rect, Graphene.Rect):
            self.rect.init_from_rect(rect)
        else:
            raise TypeError(
                "rect should be None, a Graphen.Rect or a 4 lenght Sequence"
                f" of int or float, not {rect}"
            )

        self.ps2inch_transform = ps2inch_transform
        self.inch2ps_transform = inch2ps_transform
        self.inch2mm_transform = inch2mm_transform
        self.mm2inch_transform = mm2inch_transform
        self.ps2mm_transform = ps2mm_transform
        self.mm2ps_transform = mm2ps_transform

    def __init__(
        self,
        rect: Optional[Rectangle] = None,
        unit: Optional[Unit] = Unit.UNSET,
        dpi: Optional[Union[int, float]] = 0,
    ):
        pass

    # cdef double inch2px_transform(self):
    #     return self.dpi

    # cdef double px2inch_transform(self):
    #     return 1.0 / self.dpi

    # cdef double ps2px_transform(self):
    #     return self.dpi * self.ps2inch_transform

    # cdef double px2ps_transform(self):
    #     return 1.0 / self.ps2px_transform()

    # cdef double mm2px_transform(self):
    #     return self.dpi * self.mm2inch_transform

    # cdef double px2mm_transform(self):
    #     return 1.0 / self.mm2px_transform()

    @property
    def size(self):
        return (self.rect.get_width(), self.rect.get_height())

    @size.setter
    def size(self, value):
        if test_sequence(value, ((int, float), (int, float))):
            self.rect.init(
                self.rect.get_x(), self.rect.get_y(), value[0], value[1]
            )
        else:
            raise TypeError("size should be a two lenght sequence of float")

    @property
    def point(self):
        p = self.rect.get_top_left()
        return (p.x, p.y)

    @point.setter
    def point(self, value):
        if test_sequence(value, ((int, float), (int, float))):
            self.rect.init(
                value[0], value[1], self.rect.get_width(), self.rect.get_height()
            )
        else:
            raise TypeError("point should be a two lenght sequence of float")

    @property
    def mm2px_transform(self):
        #return self.mm2px_transform()
        return transform(Unit.MILLIMETER, Unit.PIXEL, self.dpi)

    @property
    def px2mm_transform(self):
        #return self.px2mm_transform()
        return transform(Unit.PIXEL, Unit.MILLIMETER, self.dpi)

    @property
    def inch2px_transform(self):
        #return self.inch2px_transform()
        return transform(Unit.INCH, Unit.PIXEL, self.dpi)

    @property
    def px2inch_transform(self):
        # return self.px2inch_transform()
        return transform(Unit.PIXEL, Unit.INCH, self.dpi)

    @property
    def ps2px_transform(self):
        #return self.ps2px_transform()
        return transform(Unit.PS, Unit.PIXEL, self.dpi)

    @property
    def px2ps_transform(self):
        #return self.px2ps_transform()
        return transform(Unit.PIXEL, Unit.PS, self.dpi)

    cpdef double get_transform(self, unit: Unit):
        return transform(self.unit, Unit(unit), self.dpi)
        unit = Unit(unit)
        # if self.unit is Unit.PS_POINT:
        #     if unit is Unit.MILLIMETER:
        #         return self.ps2mm_transform
        #     if unit is Unit.INCH:
        #         return self.ps2inch_transform
        #     if unit is Unit.PIXEL:
        #         return self.ps2px_transform()
        # elif self.unit is Unit.INCH:
        #     if unit is Unit.MILLIMETER:
        #         return self.inch2mm_transform
        #     if unit is Unit.PS_POINT:
        #         return self.inch2ps_transform
        #     if unit is Unit.PIXEL:
        #         return self.inch2px_transform()
        # elif self.unit is Unit.MILLIMETER:
        #     if unit is Unit.INCH:
        #         return self.mm2inch_transform
        #     if unit is Unit.PS_POINT:
        #         return self.mm2ps_transform
        #     if unit is Unit.PIXEL:
        #         return self.mm2px_transform()
        # elif self.unit is Unit.PIXEL:
        #     if unit is Unit.INCH:
        #         return self.px2inch_transform()
        #     if unit is Unit.PS_POINT:
        #         return self.px2ps_transform()
        #     if unit is Unit.MILLIMETER:
        #         return self.px2mm_transform()
        # else:
        #     return 1.0

    cdef Extents_s get_extents(self):
        cdef Extents_s extents
        tl = self.get_top_left()
        br = self.get_bottom_right()
        extents.x0 = tl.x
        extents.y0 = tl.y
        extents.x1 = br.x
        extents.y1 = br.y
        return extents

    cpdef object get_center(self):
        return self.rect.get_center()

    cpdef object get_top_left(self):
        return self.rect.get_top_left()

    cpdef object get_top_right(self):
        return self.rect.top_right()

    cpdef object get_bottom_left(self):
        return self.rect.get_bottom_left()

    cpdef object get_bottom_right(self):
        return self.rect.get_bottom_right()

    cpdef float get_area(self):
        return self.rect.get_area()

    cpdef unsigned int get_pixmap_area(self):
        _t = transform(self.unit, Unit.PIXEL, ciround(self.dpi))
        px_rect = self.rect.scale(_t, _t)
        px_rect.round_extents()
        return <unsigned int> (px_rect.get_area())

    cpdef object get_pixmap_rect(self):
        _t = transform(self.unit, Unit.PIXEL, ciround(self.dpi))
        px_rect = self.rect.scale(_t, _t)
        return px_rect.round_extents()

    cpdef round(self):
        self.rect.round_extents()

    cpdef bint contains(self, other):
        if other is None:
            return False
        elif isinstance(other, Measurable):
            return self.rect.contains_rect(other.rect)
        elif isinstance(other, Graphene.Rect):
            return self.rect.contains_rect(other)
        elif isinstance(other, Graphene.Point):
            return self.rect.contains_point(other)
        elif test_sequence(other, ((int, float), (int, float))):
            p = Graphene.Point()
            return self.rect.contains_point(p.init(other[0], other[1]))
        else:
            raise TypeError(
                "other should either be another Measurable, a Graphene.Rect, "
                "a Graphene.Point or a two length sequence of number."
            )

    cpdef offset(self, float x, float y):
        self.rect.offset(x, y)

    cpdef _dump_props(self):
        return (
            f"{self.point[0]:.1f}{self.unit.abbr}, "
            f"{self.point[1]:.1f}{self.unit.abbr}, "
            f"{self.size[0]:.1f}{self.unit.abbr}, "
            f"{self.size[1]:.1f}{self.unit.abbr}, "
            f"{self.dpi:.1f}dpi"
        )

    def __str__(self):
        return f"Measurable({self._dump_props()})"


class _MeasurableMeta(type):
    def __new__(cls, name, bases, dict):
        dict['_proxy'] = None
        return super().__new__(cls, name, bases, dict)

    def __instancecheck__(self, instance):
        if isinstance(instance, _CMeasurable):
            return True
        else:
            return super().__instancecheck__(instance)

    def __subclasscheck__(self, cls):
        if issubclass(cls, _CMeasurable):
            return True
        else:
            return super().__subclasscheck__(cls)


class GObjectMeasurableMeta(gi.types.GObjectMeta, _MeasurableMeta):
    def __new__(cls, name, bases, dict):
        return super().__new__(cls, name, bases, dict)


class Measurable(metaclass=_MeasurableMeta):
    """Measurable interface

    Args:
        rect: A four length Sequence of numbers, a :class:`Graphen.Rect`, if
              set to None, rect will be initialized at (0, 0, 0, 0),
              default to None
        unit: A member of enumeration :class:`Unit`, defautl to Unit.UNSET
        dpi: Any positive number, default to 0

    Raises: TypeError if rect is of an unexpected Type, ValueError if dpi is negative
    """

    def __init__(
        self, *args,
        rect: Optional[Rectangle]=None,
        unit: Optional[Unit]=Unit.UNSET,
        dpi: Optional[Number]=0,
        **kwargs
    ):
        self._proxy = _CMeasurable(rect, unit, dpi)

    @property
    def ps2inch_transform(self):
        """a :obj:`float` for convertion between unit of measure."""
        return (<_CMeasurable> self._proxy).ps2inch_transform

    @property
    def inch2ps_transform(self):
        """a :obj:`float` for convertion between unit of measure."""
        return (<_CMeasurable> self._proxy).inch2ps_transform

    @property
    def inch2mm_transform(self):
        """a :obj:`float` for convertion between unit of measure."""
        return (<_CMeasurable> self._proxy).inch2mm_transform

    @property
    def mm2inch_transform(self):
        """a :obj:`float` for convertion between unit of measure."""
        return (<_CMeasurable> self._proxy).mm2inch_transform

    @property
    def ps2mm_transform(self):
        """a :obj:`float` for convertion between unit of measure."""
        return (<_CMeasurable> self._proxy).ps2mm_transform

    @property
    def mm2ps_transform(self):
        """a :obj:`float` for convertion between unit of measure."""
        return (<_CMeasurable> self._proxy).mm2ps_transform

    @property
    def mm2px_transform(self):
        """a :obj:`float` for convertion between unit of measure.
        This transform obviously reflect change in :attr:`Measurable.dpi`.
        """
        return (<_CMeasurable> self._proxy).mm2px_transform()

    @property
    def px2mm_transform(self):
        """a :obj:`float` for convertion between unit of measure.
        This transform obviously reflect change in :attr:`Measurable.dpi`.
        """
        return (<_CMeasurable> self._proxy).px2mm_transform()

    @property
    def inch2px_transform(self):
        """a :obj:`float` for convertion between unit of measure.
        This transform obviously reflect change in :attr:`Measurable.dpi`.
        """
        return (<_CMeasurable> self._proxy).inch2px_transform()

    @property
    def px2inch_transform(self):
        """a :obj:`float` for convertion between unit of measure.
        This transform obviously reflect change in :attr:`Measurable.dpi`.
        """
        return (<_CMeasurable> self._proxy).px2inch_transform()

    @property
    def ps2px_transform(self):
        """a :obj:`float` for convertion between unit of measure.
        This transform obviously reflect change in :attr:`Measurable.dpi`.
        """
        return (<_CMeasurable> self._proxy).ps2px_transform()

    @property
    def px2ps_transform(self):
        """a :obj:`float` for convertion between unit of measure.
        This transform obviously reflect change in :attr:`Measurable.dpi`.
        """
        return (<_CMeasurable> self._proxy).px2ps_transform()

    @property
    def rect(self) -> Graphene.Rect:
        """A :class:`Graphene.Rect` describing the dimension
        and position of this :class:`Measurable` in :attr:`Measurable.unit`.
        A :obj:`Rect(0, 0, 0, 0)` until set by implementation."""
        return (<_CMeasurable> self._proxy).rect

    @rect.setter
    def rect(self, value: Graphene.Rect):
        (<_CMeasurable> self._proxy).rect.init_from_rect(value)

    @property
    def size(self) -> Tuple[float, float]:
        """A :class:`tuple` of float as the (with, height)
        of this :class:`Measurable`."""
        return (<_CMeasurable> self._proxy).size

    @size.setter
    def size(self, value: Sequence[float]):
        (<_CMeasurable> self._proxy).size = value

    @property
    def point(self) -> Tuple[float, float]:
        """A :class:`tuple` of float as the top-left corner(x, y)
        describing the position of this :class:`Measurable`."""
        return (<_CMeasurable> self._proxy).point

    @point.setter
    def point(self, value: Sequence[float]):
        (<_CMeasurable> self._proxy).point = value

    @property
    def dpi(self) -> float:
        """An :class:`float` as the resolution in dot per inch for this
        :class:`Measurable`. Zero until set by implementation."""
        return (<_CMeasurable> self._proxy).dpi

    @dpi.setter
    def dpi(self, value: Number):
        if value < 0:
            raise ValueError("dpi should be positive")
        (<_CMeasurable> self._proxy).dpi = float(value)

    @property
    def unit(self) -> Unit:
        """A member of enumeration :class:`Unit` describing the measurement
        unit for this :class:`Measurable`. :obj:`Unit.UNSET` until
        set by implementation."""
        return (<_CMeasurable> self._proxy).unit

    @unit.setter
    def unit(self, value: Unit):
        (<_CMeasurable> self._proxy).unit = Unit(value)

    def get_transform(self, unit: Unit) -> float:
        """Get the transform to convert between :attr:`Measurable.unit`
        and :obj:`unit`.

        returns:
            A :class:`float`, return 1.0 if units are the same
            or one of them was :obj:`Unit.UNSET`.
        """
        return (<_CMeasurable> self._proxy).get_transform(unit)

    def get_center(self) -> Graphene.Point:
        """Returns: a Graphene.Point as the coordinates of the
        center of self."""
        return (<_CMeasurable> self._proxy).get_center()

    def get_top_left(self) -> Graphene.Point:
        """Returns: a Graphene.Point as the the coordinates of the top-left
        corner of self."""
        return (<_CMeasurable> self._proxy).get_top_left()

    def get_top_right(self) -> Graphene.Point:
        """Returns: a Graphene.Point as the the coordinates of the top-right
        corner of self."""
        return (<_CMeasurable> self._proxy).top_right()

    def get_bottom_left(self) -> Graphene.Point:
        """Returns: a Graphene.Point as the the coordinates of the bottom-left
        corner of self."""
        return (<_CMeasurable> self._proxy).get_bottom_left()

    def get_bottom_right(self) -> Graphene.Point:
        """Returns: a Graphene.Point as the the coordinates of the bottom-right
        corner of self."""
        return (<_CMeasurable> self._proxy).get_bottom_right()

    def contains(
        self,
        other: Union['Measurable', Graphene.Rect, Graphene.Point, Sequence[Number]]
    ) -> bool:
        """Returns: a bool whether self fully contains other.
        """
        return (<_CMeasurable> self._proxy).contains(other)

    def rounds(self) -> None:
        """Rounds :attr:`rect`.

        Rounds the origin of :attr:`rect` to its nearest integer value
        and recompute the size so that the rectangle is large enough to contain
        all the corners of the original rectangle.
        This function is the equivalent of calling floor on the coordinates
        of the origin, and recomputing the size calling ceil on the
        bottom-right coordinates.
        """
        (<_CMeasurable> self._proxy).round()

    def get_area(self) -> float:
        """Returns area of :attr:`rect`.

        Compute the area of the normalized rectangle :attr:`rect`.
        """
        return (<_CMeasurable> self._proxy).get_area()

    def get_pixmap_area(self) -> int:
        """Returns area in pixel.

        Compute the area in pixel with regard to :attr:`dpi`.
        """
        return (<_CMeasurable> self._proxy).get_pixmap_area()

    def get_pixmap_rect(self) -> Graphene.Rect:
        """Returns a rect in pixel unit.

        Compute the rect in pixel unit with regard to :attr:`dpi`.
        """
        return (<_CMeasurable> self._proxy).get_pixmap_rect()

    def offset(self, x: float, y: float) -> None:
        """Offsets the origin of :attr:`rect` by x and y.

        The size of the rectangle is unchanged.
        """
        (<_CMeasurable> self._proxy).offset(x, y)

    def _dump_props(self):
        return (<_CMeasurable> self._proxy)._dump_props()

    def __str__(self) -> str:
        return (<_CMeasurable> self._proxy).__str__()


