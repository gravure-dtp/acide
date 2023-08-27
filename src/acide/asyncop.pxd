# asyncop.pxd
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
cimport cython
from acide.types cimport cimax

@cython.final
cdef class PriorityQueue():
    cdef int id
    cdef object queue
    cdef object event
    cdef object pendings
    cdef object dones

@cython.final
cdef class Scheduler():
    cdef list priorities
    cdef int task_id
    cdef double rate
    cdef bint loop_run
    cdef double time
    cdef object last_mode
    cdef object runner
    cdef object process_executor
    cdef int max_workers

    cpdef int add_priority(Scheduler self)
    cpdef object add(
        Scheduler self,
        object co, object priority, object name=*, object callback=*,
        object cancellable=*, object args=*
    )
    cdef clear(Scheduler self)
    cdef control(Scheduler self, PriorityQueue priority)


