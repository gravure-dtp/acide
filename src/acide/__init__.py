# -*- coding: utf-8 -*-
# doc.py
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
from typing import Optional


def format_size(
    nbytes: int,
    unit: Optional[str] =None,
    ndigits: Optional[int] =2,
    suffix: Optional[str] ="b",
) -> str:
    """Format bytes size.

    Scale bytes to its proper byte format.
    e.g: 1253656678 => '1.17 Gb'

    Args:
        b (int): bytes size.
        unit (str, , optional): unit to convert bytes, if not set
                                unit will be search for best fit.
        ndigits (int, optional): Precision in decimal digits.
                                 Defaults to 2
        suffix (str, optional): Defaults to "b".
    Returns:
        str: formated string.
    """
    factor = 1024
    units = ["B", "K", "M", "G", "T", "P", "E", "Z"]

    if unit:
        if unit not in units:
            raise ValueError(f"unit {unit} not in {units}")
        suffix = f"{unit}{suffix}" if suffix else ""
        nbytes = nbytes if unit == "B" else nbytes / factor ** (units.index(unit))
        return f"{round(nbytes, ndigits)} {suffix}"
    else:
        units[0] = ""
        for unit in units:
            if nbytes < factor:
                return f"{round(nbytes, ndigits)} {unit}{suffix}"
            nbytes /= factor
    return f"{round(nbytes, ndigits)} Y{suffix}"
