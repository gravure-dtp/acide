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
from enum import Enum, IntEnum, unique, auto
import functools
from concurrent import futures
from concurrent.futures import ProcessPoolExecutor
import os
from typing import Any, Awaitable, Callable, Coroutine, Optional, Tuple

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


cdef class Task():
    """A :class:`Task` represents a future result of an asynchronous operation.
    """
    cdef object source
    cdef object cancellable
    cdef object callback
    cdef object priority
    cdef object callback_data
    cdef object future
    cdef unicode name
    cdef bint mark_cancelled
    cdef bint scheduled
    cdef dict __dict__

    def __init__(
        self,
        source: Optional[Any] = None,
        cancellable: Optional[Gio.Cancellable] = None,
        callback: Optional[AsyncReadyCallback] = None,
        callback_data: Optional[Any] = None,
        priority: Optional[int] = Priority.LOW,
        name: Optional[str] = None,
    )
        self.source = source
        if isinstance(cancellable, Gio.Cancellable):
            self.cancellable = cancellable
            self.cancellable.connect("cancelled", self._on_cancelled)
        self.callback = callback
        self.callback_data = callback_data
        self.priority = priority
        self.name = name
        self.scheduled = False
        self.mark_cancelled = False

    cpdef link(self, task):


    cpdef run(self, target):
        sch = Scheduler.new()
        sch.stop()
        sch.add(self, target, callback, args)
        sch.run(Run.LAST)
        self.scheduled = True

    cdef set_future(self, object future, object loop=None):
        if isinstance(future, concurrent.futures.Future):
            self.future = asyncio.wrap_future(future, loop)
        elif isinstance(future, asyncio.Future):
            self.future = future
        else:
            raise TypeError("argument is not a Future instance")
        if self.callback:
            self.future.add_done_callback(self._on_done_cb)

    def _on_done_cb(self, future):
        self.callback(self.source, self, self.callback_data)

    cpdef done(self):
        """Return True if the Task is done."""
        if self.future:
            return self.future.done()
        return False

    cdef _on_cancelled(self, source, data):
        if self.future:
            self.future.cancel(f"task cancelled by {source}")
        self.mark_cancelled = True

    cpdef cancelled(self):
        """Return True if the Task is cancelled."""
        if self.future:
            if self.future.cancelled():
                self.mark_cancelled = True
        return self.mark_cancelled

    cpdef cancel(self. mesg=None):
        """Request the Task to be cancelled."""
        if self.future:
            self.future.cancel(mesg)
        self.mark_cancelled = True

    cpdef result(self):
        """Return the result of the Task."""
        if self.future:
            return self.future.result()
        else:
            raise asyncio.InvalidStateError(
                f"can´t obtain result from a Task that have not been scheduled."
            )

    cpdef exception(self):
        """Return the exception of the Task."""
        if self.future:
            return self.future.exception()
        return None

    cpdef get_priority(self):
        """Return the priority of the Task."""
        return self.priority

    cpdef get_name(self):
        """Return the name of the Task."""
        return self.name

    cpdef get_cancellable(self):
        """Return the Gio.cancellable of the Task."""
        return self.cancellable





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
        self.max_workers = cimax(len(os.sched_getaffinity(0)) - 2, 1)

    def __init__(self):
        raise RuntimeError(
            "Direct instantiation is not supported, instead call "
            "Scheduler.new() static method"
        )

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

    cpdef add(
        self,
        task: Task,
        target: [Coroutine, Callable],
        callback: Optional[Callable] = None,
        args: Optional[Tuple] = tuple(),
    ):
        """Add coroutine :obj:`co` as a scheduled :class:`asyncio.Task`
        with :obj:`priority`.

        Args:
            co: The coroutine or awaitable to schedule.
            priority: A member of enum :class:`Priority` or an int as
                      the priority of completion for the task.
            name: A string to explicitly name the :class:`asyncio.Task`
                  if :obj:`None` name will be build around coroutine.__name__
            callback: Any function to call after the task complete.
            args: A tuples of arguments
            cancellable: A Gio.Cancellable

        Returns:
            an :class:`asyncio.Task` as the scheduled coroutine.
        """
        cdef int i, _prio, lowest

        if task.cancelled():
            return

        lowest = len(self.priorities) - 1
        if task.priority is Priority.LOW:
            _prio = lowest
        elif task.priority is Priority.NEXT:
            _prio = lowest
            self.priorities.insert(-1, PriorityQueue())
            lowest += 1
        elif task.priority is Priority.HIGH:
            _prio = 0
        elif task.priority > lowest or task.priority < 0:
            task.cancel()
            raise ValueError(f"priority #{task.priority} unset")
        else:
            _prio = task.priority
        name = name

        if task.name is not None:
            task.name = f"{task.name}_{self.task_id}"
        else:
            task.name = f"{target.__name__}_{self.task_id}"

        if asyncio.iscoroutine(target):
            _task = asyncio.create_task(
                Scheduler._scheduled(
                    target, self.priorities[_prio], callback, task
                )
            )
        elif callable(target):
            _task = asyncio.create_task(
                self._executor(
                    target, args, self.priorities[_prio], callback, task,
                )
            )
        else:
            task.cancel()
            return

        task.set_future(_task)
        _task.set_name(name)
        self.task_id += 1
        if _prio < lowest:
            for i in range(_prio + 1, lowest + 1):
                self.priorities[i].clear()
        self.priorities[_prio].add(_task)

    async def _executor(
        self,
        func: Callable,
        args: Tuple,
        priority: PriorityQueue,
        callback: Callable,
        task: Task
    ) -> Coroutine:
        try:
            loop = asyncio.get_running_loop()
            start = loop.time()
            print(f"process {func} scheduled for #{priority.id} at {start} ...")
            await priority.wait()
            future = asyncio.wrap_future(
                self.process_executor.submit(func, *args), loop
            )
            result = await future
        except (asyncio.CancelledError, futures.CancelledError):
            raise
        except Exception as err:
            print(f"error in process: {err}")
            raise asyncio.CancelledError(str(err))
        else:
            print(f"{task.name} done for #{priority.id} in {loop.time() - start} sec.")
            if callback:
                # this ensure callback will be called
                # after result was returned
                loop.call_soon(callback)
            return result

    @staticmethod
    async def _scheduled(
        awt: Awaitable,
        priority: PriorityQueue,
        callback: Callable,
        task: Task
    ) -> Coroutine:
        try:
            loop = asyncio.get_running_loop()
            start = loop.time()
            print(f"{task.name} scheduled for #{priority.id} at {start} ...")
            await priority.wait()
            result = await awt
        except asyncio.CancelledError:
            # print(f"scheduled {name} cancelled")
            raise
        else:
            print(f"{name} done for #{priority.id} in {loop.time() - start} sec.")
            if callback:
                # this ensure callback will be called
                # after result was returned
                loop.call_soon(callback)
            return result

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
            raise
        finally:
            # self.process_executor.shutdown(wait=True, cancel_futures=True)
            self.priorities[0].clear()
            self.loop_run = False
            return

    async def run_once(self)  -> Coroutine:
        try:
            self.loop_run = True
            self.priorities[0].set()
            for p in self.priorities:
                await asyncio.sleep(self.rate)
                p.clear_dones()
                self.control(p)
            self.clear()
        except asyncio.CancelledError:
            raise
        finally:
            self.process_executor.shutdown(wait=True, cancel_futures=True)
            self.priorities[0].clear()
            self.loop_run = False

    async def run_until_complete(self)  -> Coroutine:
        try:
            self.loop_run = True
            self.priorities[0].set()
            while all(self.priorities):
                for p in self.priorities:
                    await asyncio.sleep(self.rate)
                    p.clear_dones()
                    self.control(p)
                self.clear()
        except asyncio.CancelledError:
            raise
        finally:
            self.process_executor.shutdown(wait=True, cancel_futures=True)
            self.priorities[0].clear()
            self.loop_run = False

    def run(self, mode: Optional[Run] = Run.ONCE) -> None:
        """Start the :class:`Scheduler`'s loop and run the scheduled
        tasks concurently respecting their priority.
        """
        if not self.loop_run:
            if mode is Run.LAST:
                mode = self.last_mode
            if mode is Run.ONCE:
                self.last_mode = Run.ONCE
                self.process_executor = ProcessPoolExecutor(self.max_workers)
                self.runner = asyncio.ensure_future(self.run_once())
            elif mode == Run.UNTIL_COMPLETE:
                self.last_mode = Run.UNTIL_COMPLETE
                self.process_executor = ProcessPoolExecutor(self.max_workers)
                self.runner = asyncio.ensure_future(self.run_until_complete())
            elif mode == Run.FOREVER:
                self.last_mode = Run.FOREVER
                self.process_executor = ProcessPoolExecutor(self.max_workers)
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



    

