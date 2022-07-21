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
"""
This module provides utilities to manage *Asynchronous Operations* (coroutines
and tasks) inside the context of a *main event loop* application. It was designed
to work with the `glib event loop <https://docs.gtk.org/glib/main-loop.html>`_
in mind and tested using the `Gbulb python package <https://github.com/beeware/gbulb>`_
as an interface with glib.
"""

import asyncio
import functools
from typing import Any, Awaitable, Callable, Coroutine, Optional
from enum import Enum, IntEnum, unique, auto

from gi.repository import Gio

cimport cython


AsyncReadyCallback = Callable[[Any, Gio.Task, Any], None]


@unique
class Run(Enum):
    """Enumeration of running mode for the :class:`Scheduler`'s loop.
    """
    ONCE = auto()
    UNTIL_COMPLETE = auto()
    FOREVER = auto()
    LAST = auto()

@unique
class Priority(IntEnum):
    """Enumeration of level of priority for scheuled task.
    """
    HIGH = 0
    NEXT = auto()
    LOW = -1


cdef int _id[1]
_id[0] = 0
cdef int _unique_id():
    _id[0] += 1
    return _id[0]

@cython.final
cdef class PriorityQueue():

    def __cinit__(self, id = None):
        if id is None:
            self.id = _unique_id()
        else:
            self.id = int(id)
        self.queue = set()
        self.pendings = set()
        self.dones = set()
        self.event = asyncio.Event()

    def __len__(self):
        return len(self.queue)

    def __nonzero__(self):
        return <bint> len(self.queue)

    @property
    def completed(self):
        return (len(self.pendings) == 0)

    def add(self, task):
        self.queue.add(task)

    def feed(self):
        self.pendings |= self.queue
        self.queue.clear()

    def clear_queue(self):
         self.queue.clear()

    def clear_dones(self):
         self.dones.clear()

    def set(self):
        self.event.set()

    def clear(self):
        self.event.clear()

    def is_set(self):
        return self.event.is_set()

    def check(self):
        for task in self.pendings.copy():
            if task.done():
                self.dones.add(task)
                self.pendings.remove(task)

    async def wait(self):
        await self.event.wait()

    def __repr__(self):
        return f"PriorityQueue #{self.id} q({len(self)})"


cdef Scheduler _sched_singleton = None
cdef Scheduler get_singleton():
    return _sched_singleton
cdef void set_singleton(Scheduler sched):
    _sched_singleton = sched

@cython.final
cdef class Scheduler():
    """Schedule *coroutines* and *awaitable* concurently as prioritized *Tasks*.

    """
    def __cinit__(self):
        self.priorities = [PriorityQueue(Priority.HIGH),
                           PriorityQueue(Priority.LOW)]
        self.task_id = 0
        self.rate = 0.001
        self.last_mode = Run.ONCE
        self.loop_run = False

    @staticmethod
    def new() -> 'Scheduler':
        cdef Scheduler sch
        sch = get_singleton()
        if sch is None:
            sch = Scheduler.__new__(Scheduler)
            set_singleton(sch)
        return sch

    def __len__(self):
        return sum([len(p) for p in self.properties])

    @property
    def priority_levels(self):
        """A :class:`int` as the actual level of priority in this
        :class:`Scheduler` (read only)."""
        return len(self.priorities)

    @property
    def pendings(self):
        """A :class:`set` of scheduled pendings :class:`Task` (read only)."""
        pendings = set()
        for p in self.priorities:
           pendings |= (<PriorityQueue>p).queue
        return pendings

    @property
    def dones(self):
        """A :class:`set` of scheduled and completed :class:`Task` (read only).
        Note that this set is clened at the begining of each :class:`Scheduler`
        loop iteraton.
        """
        dones = set()
        for p in self.priorities:
           dones |= (<PriorityQueue>p).dones
        return dones

    @property
    def is_running(self):
        """A boolean indicating if the :class:`Scheduler` loop is running (read only).
        """
        return self.loop_run

    @property
    def rate(self):
        """A :class:`float` as the time in second between each :class:`Scheduler`
        loop iteraton (default to 0.001sec.).
        """
        return self.rate

    @rate.setter
    def rate(self, value):
        if value > 0:
            self.rate = float(value)

    cpdef int add_priority(self):
        """Add a priority level to the :class:`Scheduler`.

        The new priority will be inserted just before :attr:`Priority.LOW`
        and should be referred in :meth:`Scheduler.add` with the value
        returned by this method.

        Caution:
            This method will stop the :class:`Scheduler` running loop
            and it should be restarted after scheduling new coroutines
            with the :meth:`Scheduler.add` method. Restarting could
            be done with scheduler.run(Run.LAST).
            Validity of the index value returned by this method is tight
            to the scheduler pause and should not be used after calling
            scheduler.run(Run.LAST).

        Returns:
            index of the added Priority
        """
        self.stop()
        self.priorities.insert(-1, PriorityQueue())
        return len(self.priorities) - 2

    cpdef object add(
        self,
        co: Coroutine,
        priority: int,
        callback: Optional[Callable] = None,
        name: Optional[str] = None,
    ):
        """Add coroutine :obj:`co` as a scheduled :class:`asyncio.Task`
        with :obj:`priority`.

        Args:
            co: The coroutine or awaitable to schedule.
            priority: A member of enum :class:`Priority` or an int as
                      the priority of completion for the task.
            callback: Any function to call after the task complete.
            name: A string to explicitly name the :class:`asyncio.Task`
                  if :obj:`None` name will be build around coroutine.__name__

        Returns:
            an :class:`asyncio.Task` as the scheduled coroutine.
        """
        cdef int i, _prio, lowest
        lowest = len(self.priorities) - 1
        if priority is Priority.LOW:
            _prio = lowest
        elif priority is Priority.NEXT:
            _prio = lowest
            self.priorities.insert(-1, PriorityQueue())
            lowest += 1
        elif priority is Priority.HIGH:
            _prio = 0
        elif priority > lowest or priority < 0:
            raise ValueError(f"priority #{priority} unset")
        else:
            _prio = priority
        name = name
        if name is not None:
            name = f"{name}_{self.task_id}"
        else:
            name = f"{co.__name__}_{self.task_id}"
        task = asyncio.create_task(
            Scheduler._scheduled(
                co, self.priorities[_prio], callback, name
            )
        )
        task.set_name(name)
        self.task_id += 1
        if _prio < lowest:
            for i in range(_prio + 1, lowest + 1):
                self.priorities[i].clear()
        self.priorities[_prio].add(task)
        return task

    @staticmethod
    async def _scheduled(
        awt: Awaitable,
        priority: PriorityQueue,
        callback: Callable,
        name: str
    ) -> Coroutine:
        try:
            loop = asyncio.get_running_loop()
            start = loop.time()
            print(f"{name} scheduled for #{priority.id} at {start} ...")
            await priority.wait()
            result = await awt
        except asyncio.CancelledError:
            print(f"scheduled {name} cancelled")
            raise
        else:
            print(f"{name} done for #{priority.id} in {loop.time() - start} sec.")
            if callback:
                callback()
            return result
        finally:
            pass

    cdef control(self, PriorityQueue priority):
        priority.check() # put pending tasks done in dones
        if priority.is_set():
            priority.feed() # put tasks from queue to pendings
            if priority.id != Priority.LOW and priority.completed:
                _next = self.priorities[self.priorities.index(priority) + 1]
                _next.set()
            if priority.id != Priority.HIGH:
                priority.clear()

    cdef clear(self):
        cdef int i, r
        r = 0
        for i in range(1, len(self.priorities) - 1):
            if not self.priorities[i - r]:
                self.priorities.pop(i - r)
                r += 1

    async def run_forever(self)  -> Coroutine:
        try:
            self.loop_run = True
            self.priorities[0].set()
            while True:
                for p in self.priorities:
                    await asyncio.sleep(self.rate)
                    p.clear_dones()
                    self.control(p)
                self.clear()
        except asyncio.CancelledError:
            print("runner cancelled")
            raise
        finally:
            self.priorities[0].clear()
            self.loop_run = False
            return

    async def run_once(self)  -> Coroutine:
        print("run_once")
        # try:
        #     loop = asyncio.get_running_loop()
        #     self.loop_run = True
        #     self.priorities[0].set()
        #     for p in self.priorities:
        #         p.clear_dones()
        #         self.time = loop.time()
        #         asyncio.create_task(self._runner(p))
        #     await asyncio.sleep(self.rate)
        #     self.clear()
        # except asyncio.CancelledError:
        #     raise
        # finally:
        #     self.priorities[0].clear()
        #     self.loop_run = False

    async def run_until_complete(self)  -> Coroutine:
        print("run_until_complete")
        # try:
        #     loop = asyncio.get_running_loop()
        #     self.loop_run = True
        #     for p in self.priorities:
        #         p.clear_dones()
        #     self.priorities[0].set()
        #     while all(self.priorities) and self.loop_run == True:
        #         self.time = loop.time()
        #         await asyncio.gather(
        #             *[self._runner(p) for p in self.priorities]
        #         )
        #         await asyncio.sleep(self.rate)
        #         self.clear()
        # except asyncio.CancelledError:
        #     raise
        # finally:
        #     self.priorities[0].clear()
        #     self.loop_run = False

    def run(self, mode: Optional[Run] = Run.ONCE) -> None:
        """Start the :class:`Scheduler`'s loop and run the scheduled
        tasks concurently respecting their priority.
        """
        if not self.loop_run:
            if mode is Run.LAST:
                mode = self.last_mode
            if mode is Run.ONCE:
                self.last_mode = Run.ONCE
                self.runner = asyncio.ensure_future(self.run_once())
            elif mode == Run.UNTIL_COMPLETE:
                self.last_mode = Run.UNTIL_COMPLETE
                self.runner = asyncio.ensure_future(self.run_until_complete())
            elif mode == Run.FOREVER:
                self.last_mode = Run.FOREVER
                self.runner = asyncio.ensure_future(self.run_forever())
            else:
                raise ValueError(f"Unavailable mode {mode}")
        else:
            print("scheduler already running")

    def stop(self) -> None:
        """Stop the :class:`Scheduler`'s loop at the end of the current iteration."""
        self.loop_run = False
        if self.runner:
            self.runner.cancel()

    def _short_dump(self):
        return (
            f"Scheduler state {self.is_running}: pendings({len(self.pendings)}) "
            f"| dones({len(self.dones)}) "
            f"| levels({self.priority_levels})"
        )

    def __str__(self) -> str:
        st = do = ""
        for p in self.priorities:
            st += f"{p}[ "
            for t in (<PriorityQueue> p).queue:
                st+=  f"{t.get_name()}, "
            st += "], "
        return (
            f"Scheduler state: pendings({st})"
        )



    
