# asyncop.pyx
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
from typing import Any, Awaitable, Callable, Coroutine, Optional
from enum import Enum, unique

from gi.repository import Gio

cimport cython


AsyncReadyCallback = Callable[[Any, Gio.Task, Any], None]


@unique
class Priority(Enum):
    HIGHEST = 0
    LOWEST = 999
    NEXT = 888


cdef Scheduler _sched_singleton = None
cdef Scheduler get_singleton():
    return _sched_singleton

cdef set_singleton(Scheduler sched):
    _sched_singleton = sched


@cython.final
cdef class Scheduler():
    def __cinit__(self):
        self.queues = [set(), set()]
        self.priorities = [asyncio.Event(), asyncio.Event()]
        #self.priorities[0].set()  # priority 0 is always ready to start
        self.lowest = 1
        self.dones = set()
        self.task_id = 0
        self.rate = 0.001

    @staticmethod
    def new() -> 'Scheduler':
        cdef Scheduler sch
        sch = get_singleton()
        if sch is None:
            sch = Scheduler.__new__(Scheduler)
            set_singleton(sch)
        return sch

    @property
    def pendings(self):
        return set().union(*self.queues)

    @property
    def dones(self):
        return self.dones.copy()

    @staticmethod
    async def _scheduled(
        awt: Awaitable,
        result: asyncio.Future,
        priority: asyncio.Event,
        callback: Callable
    ) -> Coroutine:
        name = awt.__name__
        loop = asyncio.get_running_loop()
        # print(f"{name} scheduled at {loop.time()} ...")
        await priority.wait()
        result.set_result(await awt)
        #print(f"{name} done at {loop.time()}")
        if callback:
            callback()

    cpdef object schedule(
        self, co: Coroutine, priority: int, callback: Callable=None
    ):
        cdef int i, _prio
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
        future = asyncio.get_running_loop().create_future()
        task = asyncio.create_task(
            Scheduler._scheduled(
                co, future, self.priorities[_prio], callback
            )
        )
        task.set_name(f"{co.__name__}_{self.task_id}")
        self.task_id += 1
        if _prio < self.lowest:
            for i in range(_prio + 1, self.lowest + 1):
                self.priorities[i].clear()
        self.queues[_prio].add(task)
        return task

    async def _runner(self, priority_id: int, policy) -> Coroutine:
        if self.queues[priority_id]:
            if priority_id == 0:
                policy = asyncio.ALL_COMPLETED
            done, pending = await asyncio.wait(
                self.queues[priority_id],
                timeout = 0,
                return_when = policy
            )
            self.queues[priority_id] -= done
            self.dones |= done

    async def _task(
        self,
        runner: Coroutine,
        priority_id: int
    )  -> Coroutine:
        await runner
        if priority_id < self.lowest:
            if len(self.queues[priority_id]) == 0:
                # print(f"set priority to {priority_id + 1}")
                if priority_id != 0:
                    self.queues.pop(priority_id)
                    self.priorities.pop(priority_id)
                    self.lowest -= 1
                    self.priorities[priority_id].set()
                else:
                    self.priorities[priority_id + 1].set()

    async def _scheduler(
        self,
        priority_id: int,
        policy=asyncio.FIRST_COMPLETED
    )  -> Coroutine:
        await self._task(
            self._runner(priority_id, policy), priority_id
        )

    async def run_once(self)  -> Coroutine:
        self.dones.clear()
        self.priorities[0].set()
        for i in range(len(self.queues)):
            asyncio.create_task(self._scheduler(i))
        await asyncio.sleep(self.rate)
        self.priorities[0].clear()
        print(f"scheduler completed {self}")

    async def run_completed(self)  -> Coroutine:
        self.dones.clear()
        self.priorities[0].set()
        while len(self.pendings) > 0:
            scheduler = [self._scheduler(i) for i in range(len(self.queues))]
            await asyncio.gather(*scheduler)
            #print(f"Scheduler loop {self}")
            await asyncio.sleep(self.rate)
        self.priorities[0].clear()
        print(f"scheduler completed {self}")

    async def run_forever(self)  -> Coroutine:
        self.priorities[0].set()
        while True:
            try:
                self.dones.clear()
                scheduler = [self._scheduler(i) for i in range(len(self.queues))]
                await asyncio.gather(*scheduler)
                #print(f"Scheduler loop {self}")
                await asyncio.sleep(self.rate)
            except:
                raise
                break
        self.priorities[0].clear()
        print(f"scheduler stopped {self}")

    def run(self, mode: Optional[str] = None) -> None:
        if mode is None:
            asyncio.ensure_future(self.run_once())
        elif mode == "completed":
            asyncio.ensure_future(self.run_completed())
        elif mode == "forever":
            asyncio.ensure_future(self.run_forever())
        else:
            raise ValueError(f"Unavailable mode {mode}")

    def __str__(self) -> str:
        st = do = ""
        for i, q in enumerate(self.queues):
            st += f"#{i}[ "
            for t in q:
                st+=  f"{t.get_name()}, "
            st += "], "
        for d in self.dones:
            do += f"{d.get_name()}, "

        return (
            f"Scheduler state: pendings({st}) | dones({do})"
        )



    
