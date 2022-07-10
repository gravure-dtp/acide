# async.pyx
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
import asyncio
import functools
from typing import Awaitable, Coroutine
from enum import Enum, unique

cimport cython


@unique
class Priority(Enum):
    HIGHEST = 0
    LOWEST = 999
    NEXT = 888


@cython.final
cdef class Scheduler():
    _instance = None

    @staticmethod
    def new():
        if Scheduler._instance is None:
            Scheduler._instance = Scheduler.__new__(Scheduler)
        return Scheduler._instance

    def __cinit__(self):
        self.queues = [set(), set()]
        self.priorities = [asyncio.Event(), asyncio.Event()]
        self.priorities[0].set()  # priority 0 is always ready to start
        self.lowest = 1
        self.dones = set()
        self.task_id = 0

    @property
    def pendings(self):
        return set().union(*self.queues)

    @property
    def dones(self):
        return self.dones.copy()

    @staticmethod
    async def _scheduled(awt: Awaitable, priority: asyncio.Event) -> Coroutine:
        await priority.wait()
        await awt

    def set_priority_cb(self, current: int, future: asyncio.Future) -> None:
        if current < self.lowest:
            self.priorities[current + 1].set()

    cpdef object schedule(self, co: Coroutine, priority: int):
        if priority is Priority.LOWEST:
            _prio = self.lowest
        elif priority is Priority.NEXT:
            _prio = self.lowest
            self.priorities.insert(-1, asyncio.Event())
            self.queues.insert(-1, set())
            self.lowest += 1
        elif priority is Priority.HIGHEST:
            _prio = 0
        elif priority > self.lowest:
            raise ValueError(f"priority #{priority} unset")
        else:
            _prio = priority

        task = asyncio.create_task(
            Scheduler._scheduled(co, self.priorities[_prio])
        )
        task.set_name(f"{co.__name__}-{self.task_id}")
        self.queues[_prio].add(task)
        self.task_id += 1
        return task

    async def _runner(self, priority_id: int, policy) -> Awaitable:
        if self.queues[priority_id]:
            if priority_id == 0:
                policy = asyncio.ALL_COMPLETED
            done, pending = await asyncio.wait(
                self.queues[priority_id],
                timeout = 0.00001,
                return_when = policy
            )
            self.queues[priority_id] -= done
            self.dones |= done

    cpdef object _scheduler(
        self, int priority_id, policy=asyncio.FIRST_COMPLETED
    ):
        task = asyncio.create_task(
            self._runner(
                priority_id,
                policy = policy
            )
        )
        task.add_done_callback(
            functools.partial(self.set_priority_cb, priority_id)
        )
        return task

    async def wait(self) -> Coroutine:
        self.dones.clear()
        scheduler = [self._scheduler(i) for i in range(len(self.queues))]
        await asyncio.gather(*scheduler)
        for i in range(1, self.lowest + 1):
            self.priorities[i].clear()

    def __str__(self) -> str:
        st = do = ""
        for i, q in enumerate(self.queues):
            st += f"#{i} [ "
            for t in q:
                st+=  f"{t.get_name()}, "
            st += "]\n             "
        for d in self.dones:
            do += f"{d.get_name()}, "

        return (
            f"Scheduler state:(\n"
            f"    pendings: {st}\n"
            f"    dones: [ {do} ]"
        )



    
