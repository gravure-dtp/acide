# measure.pxi part of graphic.pyx


@unique
class UNIT(IntEnum):
    """UNIT enumeration.
    """
    UNSET = auto()
    MILLIMETER = auto()
    PS_POINT = auto()
    INCH = auto()
    PIXEL = auto()


cdef class _CMeasurable():
    cdef public object unit
    cdef public object rect
    cdef public unsigned int dpi
    cdef readonly double ps2inch_transform
    cdef readonly double inch2ps_transform
    cdef readonly double inch2mm_transform
    cdef readonly double mm2inch_transform
    cdef readonly double ps2mm_transform
    cdef readonly double mm2ps_transform

    def __cinit__(self):
        self.dpi = 0
        self.unit = UNIT.UNSET
        self.rect = Graphene.Rect()
        self.rect.init(0, 0, 0, 0)
        self.ps2inch_transform = 1.0 / 72.0
        self.inch2ps_transform = 72.0
        self.inch2mm_transform = 25.4
        self.mm2inch_transform = 1.0 / 25.4
        self.ps2mm_transform = 25.4 / 72.0
        self.mm2ps_transform = 72.0 / 25.4

    def __init__(self, *args, **kwargs):
        pass

    cdef double inch2px_transform(self):
        return self.dpi

    cdef double px2inch_transform(self):
        return 1.0 / self.dpi

    cdef double ps2px_transform(self):
        return self.dpi * self.ps2inch_transform

    cdef double px2ps_transform(self):
        return 1.0 / self.ps2px_transform()

    cdef double mm2px_transform(self):
        return self.dpi * self.mm2inch_transform

    cdef double px2mm_transform(self):
        return 1.0 / self.mm2px_transform()

    cpdef double get_transform(self, unit: UNIT):
        unit = UNIT(unit)
        if self.unit is UNIT.PS_POINT:
            if unit is UNIT.MILLIMETER:
                return self.ps2mm_transform
            if unit is UNIT.INCH:
                return self.ps2inch_transform
            if unit is UNIT.PIXEL:
                return self.ps2px_transform()
        elif self.unit is UNIT.INCH:
            if unit is UNIT.MILLIMETER:
                return self.inch2mm_transform
            if unit is UNIT.PS_POINT:
                return self.inch2ps_transform
            if unit is UNIT.PIXEL:
                return self.inch2px_transform()
        elif self.unit is UNIT.MILLIMETER:
            if unit is UNIT.INCH:
                return self.mm2inch_transform
            if unit is UNIT.PS_POINT:
                return self.mm2ps_transform
            if unit is UNIT.PIXEL:
                return self.mm2px_transform()
        elif self.unit is UNIT.PIXEL:
            if unit is UNIT.INCH:
                return self.px2inch_transform()
            if unit is UNIT.PS_POINT:
                return self.px2ps_transform()
            if unit is UNIT.MILLIMETER:
                return self.px2mm_transform()
        else:
            return 1.0


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


class Measurable(metaclass=_MeasurableMeta):
    """Measurable interface
    """

    def __init__(self, *args, **kwargs):
        self._proxy = _CMeasurable()

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
    def dpi(self) -> int:
        """An :class:`int` as the resolution in dot per inch for this
        :class:`Measurable`. Zero until set by implementation."""
        return (<_CMeasurable> self._proxy).dpi

    @dpi.setter
    def dpi(self, value: int):
        (<_CMeasurable> self._proxy).dpi = int(value)

    @property
    def unit(self) -> UNIT:
        """A member of enumeration :class:`UNIT` describing the measurement
        unit for this :class:`Measurable`. :obj:`UNIT.UNSET` until
        set by implementation."""
        return (<_CMeasurable> self._proxy).unit

    @unit.setter
    def unit(self, value: UNIT):
        (<_CMeasurable> self._proxy).unit = UNIT(value)

    def get_transform(self, unit: UNIT) -> float:
        """Get the transform to convert between :attr:`Measurable.unit`
        and :obj:`unit`.

        returns:
            A :class:`float`, return 1.0 if units are the same
            or one of them was :obj:`UNIT.UNSET`.
        """
        return (<_CMeasurable> self._proxy).get_transform(unit)




# cdef class Duplex():
#     cdef float ps_x = 0
#     cdef float ps_y = 0
#     cdef int ds_x = 0
#     cdef int ds_y = 0
