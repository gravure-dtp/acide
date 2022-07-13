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
from typing import Union, Any, Callable

import gi
gi.require_version("Gdk", "4.0")
gi.require_version('Graphene', '1.0')
from gi.repository import Gdk, GLib, Gio, GObject, Graphene

from acide.measure import Measurable, GObjectMeasurableMeta, Unit
from acide.types import Number, Rectangle, BufferProtocol
from acide.asyncop import AsyncReadyCallback
from acide.tiles import TilesPool, SuperTile, Clip
from acide import format_size


class _GraphicMeta(ABCMeta, GObjectMeasurableMeta):
    pass


class Graphic(GObject.GObject, Measurable, metaclass=_GraphicMeta):
    """Graphic Interface, extends :class:`GObject` implements
    :class:`acide.measure.Measurable`.

    An abstract base class representing any graphic object with
    some metric properties and eventually with an infinite resolution
    (eg: a vector based graphical object).
    Subclass should implement the abstract method :meth:`get_pixbuf`.

    Args:
        rect: A four length Sequence of numbers (x, y, width, height)
              or a :class:`Graphen.Rect` as the dimension of this :class:`Graphic`.
        mem_format: a enum's member of :class:`Gdk.MemoryFormat`
        unit: A member of enumeration :class:`acide.measure.Unit` as the unit
              of measure for the dimension of this :class:`Graphic`, default
              to :attr:`acide.measure.Unit.PS_POINT`
    """

    __gtype__name__ = "Graphic"
    __gsignals__ = {
        'ready': (GObject.SIGNAL_RUN_FIRST, None, (bool,)),
        'scaled': (GObject.SIGNAL_RUN_FIRST, None, (int,))
    }

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
        self._init_scales((1, 2 , 4, 8, 16, 32))
        self._scale_index = 0  # we start at 1:1
        self.tiles_pool = None

    def __str__(self):
        return f"Graphic({self._dump_props()})"

    def _init_scales(self, factors):
        # TODO: reduction factors
        self._scales = [Fraction(f, 1) for f in factors]

    def do_ready(self, state, *args):
        pass

    def do_scaled(self, scale, *args):
        self.on_scaled(scale)

    @property
    def scale(self) -> Fraction:
        """The actual scale to apply when rendering on screen
        (this doesn't change the internal size of this :class:`Graphic`).
        """
        return self._scales[self._scale_index]

    def scale_increase(self) -> Fraction:
        """Increment the scale factor

        Returns:
            a :class:`Fraction` as the resulting current scale factor
        """
        if self._scale_index + 1 < len(self._scales):
            self._scale_index += 1
        self.emit("scaled", self._scales[self._scale_index])
        return self._scales[self._scale_index]

    def scale_decrease(self) -> Fraction:
        """Decrement the scale factor

        Returns:
            a :class:`Fraction` as the resulting current scale factor
        """
        if self._scale_index - 1 >= 0:
            self._scale_index -= 1
        self.emit("scaled", self._scales[self._scale_index])
        return self._scales[self._scale_index]

    def scale_init(self) -> Fraction:
        """Set the scale factor to 1:1

        Returns:
            a :class:`Fraction` as the resulting current scale factor
        """
        self._scale_index = 0
        self.emit("scaled", self._scales[self._scale_index])
        return self._scales[self._scale_index]

    def scale_fit(self) -> Fraction:
        """Set the scale factor so the :class:`Graphic` fit in the :obj:`viewport`

        Returns:
            a :class:`Fraction` as the resulting current scale factor
        """
        self._scale_index = 0  # TODO: scale 2 fit
        self.emit("scaled", self._scales[self._scale_index])
        return self._scales[self._scale_index]

    @property
    def virtual_dpi(self) -> int:
        """The :attr:`scale` dependant dpi.

        This is computed as round(self.dpi * self.scale) (read only).
        """
        return round(self.dpi * self._scales[self._scale_index])

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
        """The viewport Widget implementing the :class:`acide.measure.Measurable`
        interface. None until added to a Widget (read only).
        """
        return self._viewport

    def on_added(self, viewport: Measurable) -> None:
        """Callback method for widget using this :class:`Graphic`.

        This method is called when this :class:`Graphic` is added to a widget.
        If you need to override this method don't forget a call to
        super().on_added().
        """
        self._viewport = viewport
        self.tiles_pool = TilesPool(
            self, viewport, self._scales, self._format, self.get_pixbuf
        )
        self.emit("ready", self.tiles_pool.is_ready)

    def on_updated(self) -> None:
        """Callback method for widget using this :class:`Graphic`.

        This method is called when some of the viewport Widget's properties
        haved changed. If you need to override this method don't forget a call to
        super().on_updated().
        """
        self.tiles_pool.__init__(
            self, self.viewport, self._scales, self._format, self.get_pixbuf
        )
        self.emit("ready", self.tiles_pool.is_ready)

    def on_removed(self) -> None:
        """Callback method for widget using this :class:`Graphic`.

        This method is called when this :class:`Graphic` is removed
        from a widget. If you need to override this method don't forget a call
        to super().on_removed().
        """
        self._viewport = None
        self.tiles_pool = None

    def on_scaled(self, scale) -> None:
        """Callback method for widget using this :class:`Graphic`.

        This method is called when this :class:`Graphic` is scaled
        for display. If you need to override this method don't forget a call
        to super().on_scaled().
        """
        pass

    def on_panned(self, x: float, y: float) -> None:
        """Callback method for widget using this :class:`Graphic`.

        This method should be called by widget that have panned their contents.
        This actually move the rendering region of this :class:`Graphic`
        so the point(x, y) will fit inside. The (x, y) coordinates has to be express
        in the :attr:`Graphic.unit` of measure.
        """
        self.tiles_pool.set_rendering(x, y, self._scale_index)

    def get_render(self) -> Clip:
        """Get the rendering region as a :class:`Clip`.

        If the :class:`Graphic` is not yet renderable, a :class:`acide.tiles.Clip`
        with *None* as the :attr:`acide.tiles.Clip.texture` will be returned.

        Returns: a :class:`acide.tiles.Clip` of the rendering region that holds
                 a :class:`Gtk.Texture` and corresponding clipping informations.
        """
        return self.tiles_pool.render()

    def get_render_async(
        self,
        cancellable: Gio.Cancellable,
        callback: AsyncReadyCallback,
        user_data: Any = None,
    ) -> None:
        gtask = Gio.Task.new(self, cancellable, callback, user_data)
        self.tiles_pool.render_async(None, callback, gtask)

    def get_render_finish(self, result: Gio.Task, data: any) -> Clip:
        return self.tiles_pool.render_finish(result)

    @abstractmethod
    def get_pixbuf(self, rect: Graphene.Rect) -> BufferProtocol:
        """Get pixbuf at clip rect.

        Implementation should return a pixmap buffer clipped to the region
        described by the parameter :obj:`rect` (defined in :attr:`acide.measure.Measurable.unit`
        of measure for this :class:`Graphic`).
        The returned object should implements the buffer protocol and should
        hold a c-contigous buffer with only one dimension for all its data.
        The pixel data should conform to the :attr:`Graphic.mem_format` property.
        When rendering the pixmap, subclass could consider using the
        :attr:`scale` and :attr:`virtual_dpi` properties to achieve expected
        result.
        """
        pass
