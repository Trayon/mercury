%---------------------------------------------------------------------------%
% Copyright (C) 2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% Main author: conway
% Stability: medium.
%
% This module implements a simple semaphore data type for allowing
% coroutines to synchronise with one another.
%
% The operations in this module are no-ops in the hlc grades which don't
% contain a .par component.
%
%---------------------------------------------------------------------------%
:- module semaphore.

:- interface.

:- import_module bool, io.

:- type semaphore.

	% new(Sem, IO0, IO) creates a new semaphore `Sem' with its counter
	% initialized to 0.
:- pred semaphore__new(semaphore, io__state, io__state).
:- mode semaphore__new(out, di, uo) is det.

	% wait(Sem, IO0, IO) blocks until the counter associated with `Sem'
	% becomes greater than 0, whereupon it wakes, decrements the
	% counter and returns.
:- pred semaphore__wait(semaphore, io__state, io__state).
:- mode semaphore__wait(in, di, uo) is det.

	% try_wait(Sem, Succ, IO0, IO) is the same as wait/3, except that
	% instead of blocking, it binds `Succ' to a boolean indicating
	% whether the call succeeded in obtaining the semaphore or not.
:- pred semaphore__try_wait(semaphore, bool, io__state, io__state).
:- mode semaphore__try_wait(in, out, di, uo) is det.

	% signal(Sem, IO0, IO) increments the counter associated with `Sem'
	% and if the resulting counter has a value greater than 0, it wakes
	% one or more coroutines that are waiting on this semaphore (if
	% any).
:- pred semaphore__signal(semaphore, io__state, io__state).
:- mode semaphore__signal(in, di, uo) is det.

%---------------------------------------------------------------------------%
:- implementation.

:- import_module std_util.

:- type semaphore	== c_pointer.

:- pragma c_header_code("
	#include <stdio.h>
	#include ""mercury_context.h""
	#include ""mercury_thread.h""

	typedef struct ME_SEMAPHORE_STRUCT {
		int		count;
#ifndef MR_HIGHLEVEL_CODE
		MR_Context	*suspended;
#else
  #ifdef MR_THREAD_SAFE
		MercuryCond	cond;
  #endif 
#endif
#ifdef MR_THREAD_SAFE
		MercuryLock	lock;
#endif
	} ME_Semaphore;
").

:- pragma c_header_code("
#ifdef CONSERVATIVE_GC
  void ME_finalize_semaphore(GC_PTR obj, GC_PTR cd);
#endif
").

:- pragma c_code(semaphore__new(Semaphore::out, IO0::di, IO::uo),
		[will_not_call_mercury, thread_safe], "{
	MR_Word sem_mem;
	ME_Semaphore	*sem;

	incr_hp(sem_mem, round_up(sizeof(ME_Semaphore), sizeof(MR_Word)));
	sem = (ME_Semaphore *) sem_mem;
	sem->count = 0;
#ifndef MR_HIGHLEVEL_CODE
	sem->suspended = NULL;
#else
  #ifdef MR_THREAD_SAFE
	pthread_cond_init(&(sem->cond), MR_COND_ATTR);
  #endif
#endif
#ifdef MR_THREAD_SAFE
	pthread_mutex_init(&(sem->lock), MR_MUTEX_ATTR);
#endif

	/*
	** The condvar and the mutex will need to be destroyed
	** when the semaphore is garbage collected.
	*/
#ifdef CONSERVATIVE_GC
	GC_REGISTER_FINALIZER(sem, ME_finalize_semaphore, NULL, NULL, NULL);
#endif

	Semaphore = (MR_Word) sem;
	IO = IO0;
}").

:- pragma c_code("
#ifdef CONSERVATIVE_GC
  void
  ME_finalize_semaphore(GC_PTR obj, GC_PTR cd)
  {
	ME_Semaphore    *sem;

	sem = (ME_Semaphore *) obj;

  #ifdef MR_THREAD_SAFE
    #ifdef MR_HIGHLEVEL_CODE
	pthread_cond_destroy(&(sem->cond));
    #endif
	pthread_mutex_destroy(&(sem->lock));
  #endif

	return;
  }
#endif
").

		% because semaphore__signal has a local label, we may get
		% C compilation errors if inlining leads to multiple copies
		% of this code.
		% XXX get rid of this limitation at some stage.
:- pragma no_inline(semaphore__signal/3).
:- pragma c_code(semaphore__signal(Semaphore::in, IO0::di, IO::uo),
		[will_not_call_mercury, thread_safe], "{
	ME_Semaphore	*sem;
#ifndef MR_HIGHLEVEL_CODE
	MR_Context	*ctxt;
#endif

	sem = (ME_Semaphore *) Semaphore;

	MR_LOCK(&(sem->lock), ""semaphore__signal"");

#ifndef MR_HIGHLEVEL_CODE
	if (sem->count >= 0 && sem->suspended != NULL) {
		ctxt = sem->suspended;
		sem->suspended = ctxt->next;
		MR_UNLOCK(&(sem->lock), ""semaphore__signal"");
		schedule(ctxt);
			/* yield() */
		save_context(MR_ENGINE(this_context));
		MR_ENGINE(this_context)->resume = &&signal_skip_to_the_end_1;
		schedule(MR_ENGINE(this_context));
		runnext();
signal_skip_to_the_end_1:
	} else {
		sem->count++;
		MR_UNLOCK(&(sem->lock), ""semaphore__signal"");
			/* yield() */
		save_context(MR_ENGINE(this_context));
		MR_ENGINE(this_context)->resume = &&signal_skip_to_the_end_2;
		schedule(MR_ENGINE(this_context));
		runnext();
signal_skip_to_the_end_2:
	}
#else
	sem->count++;
	MR_UNLOCK(&(sem->lock), ""semaphore__signal"");
	MR_SIGNAL(&(sem->cond));
#endif
	IO = IO0;
}").

		% because semaphore__wait has a local label, we may get
		% C compilation errors if inlining leads to multiple copies
		% of this code.
		% XXX get rid of this limitation at some stage.
:- pragma no_inline(semaphore__wait/3).
:- pragma c_code(semaphore__wait(Semaphore::in, IO0::di, IO::uo),
		[will_not_call_mercury, thread_safe], "{
	ME_Semaphore	*sem;
#ifndef MR_HIGHLEVEL_CODE
	MR_Context	*ctxt;
#endif

	sem = (ME_Semaphore *) Semaphore;

	MR_LOCK(&(sem->lock), ""semaphore__wait"");

#ifndef MR_HIGHLEVEL_CODE
	if (sem->count > 0) {
		sem->count--;
		MR_UNLOCK(&(sem->lock), ""semaphore__wait"");
	} else {
		save_context(MR_ENGINE(this_context));
		MR_ENGINE(this_context)->resume = &&wait_skip_to_the_end;
		MR_ENGINE(this_context)->next = sem->suspended;
		sem->suspended = MR_ENGINE(this_context);
		MR_UNLOCK(&(sem->lock), ""semaphore__wait"");
		runnext();
wait_skip_to_the_end:
	}
#else
	while (sem->count <= 0) {
		MR_WAIT(&(sem->cond), &(sem->lock));
	}

	sem->count--;

	MR_UNLOCK(&(sem->lock), ""semaphore__wait"");
#endif
	IO = IO0;
}").

semaphore__try_wait(Sem, Res) -->
	semaphore__try_wait0(Sem, Res0),
	( { Res0 = 0 } ->
		{ Res = yes }
	;
		{ Res = no }
	).

:- pred semaphore__try_wait0(semaphore, int, io__state, io__state).
:- mode semaphore__try_wait0(in, out, di, uo) is det.

:- pragma c_code(semaphore__try_wait0(Semaphore::in, Res::out, IO0::di, IO::uo),
		[will_not_call_mercury, thread_safe], "{
	ME_Semaphore	*sem;

	sem = (ME_Semaphore *) Semaphore;

	MR_LOCK(&(sem->lock), ""semaphore__try_wait"");
	if (sem->count > 0) {
		sem->count--;
		MR_UNLOCK(&(sem->lock), ""semaphore__try_wait"");
		Res = 0;
	} else {
		MR_UNLOCK(&(sem->lock), ""semaphore__try_wait"");
		Res = 1;
	}
	IO = IO0;
}").
