# graphic.pxi part of graphic.pyx


cdef class Graphic(_CMeasurable):
    """Graphic Interface abstract base class, implements :class:`Measurable`."""
    cdef TilesPool tiles
    cdef object _scale
    cdef tuple _scale_factors
    cdef object _parent
    cdef float _transform

    def __cinit__(
        self,
        dimension: Graphene.Size,
        unit: UNIT = UNIT.PS_POINT,
    ):
        super().__init__()
        if test_sequence(dimension, ((int, float), (int, float))):
            self._rect.size.init(dimension[0], dimension[1])
        elif isinstance(dimension, Graphene.Size):
            self._rect.size.init_from_size(dimension)
        else:
            raise TypeError(
                "dimension should be either a Graphene.Size instance or"
                f" a two lenght sequence of int or float not {dimension}"
            )
        self._unit = UNIT(unit)
        self._parent = None
        self._scale_factors = (1, 2 , 4, 8, 16, 32)
        self._scale = Fraction(1, 1)
        self._transform = 1.0

        #TODO: make tiles holder structure
        self.tiles = None #TilesPool()

    def __init__(
        self,
        dimension: Graphene.Size,
        *args,
        unit: UNIT = UNIT.PS_POINT,
        **kwarggs
    ):
        pass

    @property
    def parent(self) -> Measurable:
        """The parent Widget implementing the :class:`Measurable` interface.
        None until added to a Widget (read only)."""
        return self._parent

    @property
    def scale(self) -> Fraction:
        """The actual scale to apply when rendering on screen
        (this doesn't change the size of this :class:`Graphic`)."""
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

    def on_added(self, parent: Measurable) -> None:
        """Callback method for widget supporting this interface.

        This method is called when this :class:`Graphic` is added to a widget.
        If you override this method don't forget to call super().on_added().
        """
        self._parent = parent
        self._transform = self.get_transform(parent.unit)

    def on_removed(self) -> None:
        """Callback method for widget supporting this interface.

        This method is called when this :class:`Graphic` is removed from a widget.
        If you override this method don't forget to call super().on_removed().
        """
        self._parent = None
        self._transform = 1.0

    def on_scaled(self):
        """abstractmethod"""
        raise NotImplementedError(
            "Abstract method should be overriden in your implentation"
        )
