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

from abc import ABCMeta, abstractmethod
from fractions import Fraction
from typing import Union, Any

import gi
gi.require_version("Gdk", "4.0")
gi.require_version('Graphene', '1.0')
from gi.repository import Gdk, GObject, Graphene

from acide.measure import Measurable, GObjectMeasurableMeta, Unit
from acide.types import Number, Rectangle, BufferProtocol
from acide.tiles import TilesPool, SuperTile, Clip


class _GraphicMeta(ABCMeta, GObjectMeasurableMeta):
    pass


class Graphic(GObject.GObject, Measurable, metaclass=_GraphicMeta):
    """Graphic Interface.

    An abstract base class, extends :class:`GObject` implements
    :class:`Measurable`.
    """

    __gtype__name__ = "Graphic"

    def __init__(
        self,
        rect: Rectangle,
        mem_format: Gdk.MemoryFormat,
        unit: Unit = Unit.PS_POINT
    ):
        if not isinstance(mem_format, Gdk.MemoryFormat):
            raise TypeError(
                "mem_format should be a mamber of Gdk.MemoryFormat "
                f"not {mem_format.__class__.__name__}"
            )
        GObject.GObject.__init__(self)
        Measurable.__init__(self, unit=unit, rect=rect)

        self._viewport = None
        self._format = mem_format
        self._scale_factors = (1, 2 , 4, 8, 16, 32)
        self._scale = Fraction(1, 1)  # we start at 1:1
        self.tiles_pool = None

    def __str__(self):
        return f"Graphic({self._dump_props()})"

    @property
    def virtual_dpi(self) -> int:
        """The :attr:`scale` dependant dpi.

        This is computed as round(self.dpi * self.scale) (read only).
        """
        return round(self.dpi * self._scale)

    @property
    def mem_format(self) -> Gdk.MemoryFormat:
        """a member of enumeration :class:`Gdk.MemoryFormat`
        describing formats that pixmap data have in memory.
        """
        return self._format

    @mem_format.setter
    def mem_format(self, value: Gdk.MemoryFormat):
        if not isinstance(value, Gdk.MemoryFormat):
            raise TypeError(
                "mem_format should be a mamber of Gdk.MemoryFormat "
                f"not {format.__class__.__name__}"
            )
        self._format = value

    @property
    def viewport(self) -> Measurable:
        """The viewport Widget implementing the :class:`Measurable` interface.
        None until added to a Widget (read only).
        """
        return self._viewport

    @property
    def scale(self) -> Fraction:
        """The actual scale to apply when rendering on screen
        (this doesn't change the internal size of this :class:`Graphic`).
        """
        return self._scale

    @scale.setter
    def scale(self, value: Fraction):
        if not all(
            value.numerator in self._scale_factors,
            value.denominator in self._scale_factors,
        ):
            return
        self._scale = value
        self.on_scaled()

    def on_added(self, viewport: Measurable) -> None:
        """Callback method for widget supporting this interface.

        This method is called when this :class:`Graphic` is added to a widget.
        If you need to override this method don't forget a call to
        super().on_added().
        """
        self._viewport = viewport
        self.tiles_pool = TilesPool(self, viewport, self._format, self.get_pixbuf)

    def on_updated(self) -> None:
        """Callback method for widget supporting this interface.

        This method is called when some of the viewport Widget's properties
        has changed. If you need to override this method don't forget a call to
        super().on_updated().
        """
        self.tiles_pool.__init__(self, self.viewport, self._format, self.get_pixbuf)

    def on_removed(self) -> None:
        """Callback method for widget supporting this interface.

        This method is called when this :class:`Graphic` is removed
        from a widget. If you need to override this method don't forget a call
        to super().on_removed().
        """
        self._viewport = None
        self.tiles_pool = None

    def on_scaled(self) -> None:
        """Callback method for widget supporting this interface.

        This method is called when this :class:`Graphic` is scaled
        for display. If you need to override this method don't forget a call
        to super().on_scaled().
        """
        pass

    def get_render(self, x: float, y: float) -> Clip:
        # print(f"RENDER at {x}, {y})")
        clip = self.tiles_pool.set_rendering(x, y)
        self.tiles_pool.render()
        return clip

    @abstractmethod
    def get_pixbuf(self, rect: Graphene.Rect) -> BufferProtocol:
        """Get pixbuf at clip rect.

        Implementation should return a pixmap buffer clipped to the region
        described by the parameter *rect* (defined in :attr:`Measurable.unit`
        measure of this :class:`Graphic`).
        The returned object should implements the buffer protocol and should
        hold a c-contigous buffer with only one dimension for all its data.
        The pixel data should conform to the :attr:`Graphic.format` property.
        When rendering the pixmap, subclass could consider using the
        :attr:`scale` and :attr:`virtual_dpi` properties to achieve expected
        result.
        """
        pass
