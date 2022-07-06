# types.pyx
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
from typing import Any, Union, Optional, NoReturn, Sequence, Tuple
from decimal import Decimal

import gi
gi.require_version('Graphene', '1.0')
from gi.repository import Graphene

import cython

# Type hints Alias
BufferProtocol = Any
Number = Union[int, float, Decimal]
Rectangle = Union[Graphene.Rect, Sequence[Number]]


cdef bint test_sequence(object seq, tuple _types):
    """Fast helper c function for testing sequence
    argument in other function.
    """
    cdef Py_ssize_t i
    if isinstance(seq, (tuple, list)) and len(seq)==len(_types):
        for i in range(len(seq)):
            if not isinstance(seq[i], _types[i]):
                return False
        return True
    return False


cdef class TypedGrid():
    """A two dimensional typed array of :class:`object`.

    Args:
        pytype: The python Type (or class) holded by this :class:`TypedGrid`.

        shape: A two lenght sequence of int describing the grid dimension,
               like (width, height), those integers are limited to a maximum
               value of *65535* (2 bytes unsigned int) by the implementation.

    Methods:
        self[col[, row]]: self[*...*] returns *self*.

                          self[*col*, *row*] returns the :class:`Tile`
                          at (*col*, *row*).

                          self[*col*] returns a :class:`TypedGrid`
                          as a view of *self* sliced to *col*.

                          self[..., *row*] returns a :class:`TypedGrid`
                          as a view of *self* sliced to *row*.

                          self[*col a* : *col b*] returns a :class:`TypedGrid`
                          as a view of *self* sliced to (*col a*:*col b*).

                          self[*col a* : *col b*, *row a* : *row b*]
                          returns a :class:`TypedGrid` as a view of *self*
                          sliced to (*col a*:*col b*, *row a*:*row b*).

                          sliced are guaranteed to preserve the two dimensions.

                          Raises IndexError if (col, row) is out of bounds.

        self[col, row] = value: Set item at (*col*, *row*) to *value*.
                                Raises IndexError if (col, row) is out of bounds.
                                Raise TypedError if value is not an instance of
                                the :attr:`TypedGrid.type` (value could be None).

        del self[col, row]: Delete item at index(col, row). This is equivalent
                            to self[col, row] = None. This doesn't modify
                            the shape of grid. Raises IndexError if (col, row)
                            is out of bounds.

        x in self:  Returns True if x is in *self*, otherwise False.

        for item in self: Iterate over the Grid in a flatten manner, yielding
                          all items in a row before going to the next row
                          until the end of Grid is reach.
    """

    @property
    def type(self):
        """The python type holded by this TypedGrid."""
        return self._ref.pytype

    @property
    def shape(self):
        """Width and height as a :class:`tuple` (width, height), read only."""
        return self.view.shape

    @property
    def base(self):
        """A :class:`TypedGrid` instance if :obj:`self` is a view obtained from
        slicing another :class:`TypedGrid`, read only."""
        return self._ref

    def __cinit__(self, pytype=object, shape=None, *args, **kwargs):
        cdef int x, y

        self.pytype = pytype if isinstance(pytype, type) else type(pytype)
        self._ref = self
        if shape is None:
            shape = tuple((0, 0))
        else:
            if test_sequence(shape, (int, int)):
                shape = tuple((max(0, shape[0]), max(0, shape[1])))
            else:
                raise TypeError(
                    "shape should be None are a 2 length sequence of int"
                )

        self.items = []
        if shape[0] and shape[1]:
            self.indices = Carray(shape, 2, b'H', 'c', True)
            for y in range(shape[1]):
                for x in range(shape[0]):
                    self.items.append(None)
                    self.indices[x, y] = (y * shape[0]) + x
            self.view = self.indices[:,:]
        else:
            self.indices = None
            self.view = None

    def __init__(
        self,
        pytype: Optional[Any],
        shape: Optional[Sequence[int]],
    ):
        pass

    def __len__(self):
        """Returns the total count of item."""
        return self.view.shape[0] * self.view.shape[1] if self.view else 0

    def __repr__(self):
        """Returns a string representation of *self*."""
        cdef int x, y
        v = unicode()
        shape = self.view.shape if self.view else (0,0)
        for y in range(shape[1]):
            v += " ]\n [ " if y > 0 else "[ "
            for x in range(shape[0]):
                v += ", " if x > 0 else ""
                v += f"{self.getitem_at(x,y)}@{self.view[x,y]}"
        if v: v += " ]"
        return (
            f"[{v}]"
            f"\ntype: {self.pytype.__name__}"
            f"\nshape{shape}"
            f"\nlen: {self.__len__()}"
            f"\nbase: {self._ref.__class__.__name__}@({id(self._ref)})"
        )

    def __getitem__(self, index):
        if not self.view:
            raise IndexError(f"Grid index {index} out of range")
        if isinstance(index, tuple):
            if len(index)==1:
                return self.getitem(index[0])
            elif len(index)==2:
                if isinstance(index[1], int):
                    if isinstance(index[0], int):
                        return self.getitem_at(index[0], index[1])
                    else:
                        # special case where we could ending with
                        # one dimension, forbid that
                        return self.get_slice(
                            index[0], slice(index[1], index[1] + 1)
                        )
                else:
                    return self.get_slice(index[0], index[1])
            else:
                raise IndexError(
                    f"{self.__class__.__name__} have two dimensions not {len(tuple)}"
                )
        else:
            return self.getitem(index)

    cdef object getitem(self, index):
        if index is Ellipsis:
            return self
        elif isinstance(index, int):
            return self.get_slice(slice(index, index + 1, None), None)
        elif isinstance(index, slice):
            return self.get_slice(index, None)

    cdef object getitem_at(self, x, y):
        cdef int index = self.getindex_at(x, y)
        if index > -1:
            return self._ref.items[index]
        else:
            raise IndexError(f"Grid index ({x}, {y}) out of range")

    cdef int getindex_at(self, int x, int y):
        # print(f"DBG: shape{self.view.shape} | {self.view}")
        x = self.view.shape[0] + x if x < 0 else x
        y = self.view.shape[1] + y if y < 0 else y
        if x < 0 or x >= self.view.shape[0] or y < 0 or y >= self.view.shape[1]:
            return -1
        else:
            return self.view[x, y]

    cdef TypedGrid get_slice(self, object slx, object sly):
        cdef TypedGrid _tg
        _tg = TypedGrid.__new__(TypedGrid, self.pytype)
        _tg._ref = self._ref
        slx = slx if slx else slice(None, None, None)
        sly = sly if sly else slice(None, None, None)
        _tg.view = self.view[slx, sly]
        return _tg

    cdef slice_inplace(self, object slx, object sly):
        slx = slx if slx else slice(None, None, None)
        sly = sly if sly else slice(None, None, None)
        self.view = self.view[slx, sly]

    cdef slice_ref(self, object slx, object sly):
        slx = slx if slx else slice(None, None, None)
        sly = sly if sly else slice(None, None, None)
        self.view = self._ref.view[slx, sly]

    def __setitem__(self, index, item):
        cdef int indice
        if not self.view:
            raise IndexError(f"Grid index {index} out of range")

        if test_sequence(index, (int, int)):
            if isinstance(item, self._ref.pytype) or item is None:
                indice = self.getindex_at(index[0], index[1])
                if indice > -1:
                    self._ref.items[indice] = item
                else:
                    raise IndexError(
                        f"Grid index ({index[0]}, {index[1]}) out of range"
                    )
            else:
                raise ValueError(
                    f"item should be <None> or an instance "
                    f"of <{self._ref.pytype.__name__}>"
                    f" not <{item.__class__.__name__}>"
                )
        else:
            raise TypeError(f"index should be 2 length sequence of int not {index}")

    def __delitem__(self, index):
        cdef int indice
        if not self.view:
            raise IndexError(f"Grid index {index} out of range")
        if test_sequence(index, (int, int)):
            indice = self.getindex_at(index[0], index[1])
            if indice > -1:
                self._ref.items[indice] = None
            else:
                raise IndexError(
                    f"Grid index ({index[0]}, {index[1]}) out of range"
                )
        else:
            raise TypeError(
                f"index should be 2 length sequence of int not {index}"
            )

    def __contains__(self, item):
        if isinstance(item, self._ref.pytype) or item is None:
            for obj in self:
                if obj is item:
                    return True
        return False

    def __iter__(self):
        return __TypedGridIterator(self)


@cython.final
@cython.freelist(4)
cdef class __TypedGridIterator():
    cdef Py_ssize_t index, _len
    cdef TypedGrid grid

    def __cinit__(self, TypedGrid grid not None):
        self.grid = grid
        self.index = 0
        self._len = grid.view.shape[0] * grid.view.shape[1]

    def __iter__(self):
        return self

    def __next__(self):
        if self.index == self._len:
            self.index = 0
            raise StopIteration
        item = self.grid._ref.items[
            self.grid.view[
                self.index % self.grid.view.shape[0],
                self.index // self.grid.view.shape[0]
            ]
        ]
        self.index += 1
        return item



