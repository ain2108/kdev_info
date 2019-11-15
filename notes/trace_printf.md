# Studying printf
## ftrace and printf

`ftrace` is a badass tool that can help us on the kernel walks.
Since I am an amateur, I will use a script mentioned here:
https://www.kernel.org/doc/Documentation/trace/ftrace.txt

Armed with the script we are almost ready. we find out our kernel
version and go to https://elixir.bootlin.com/linux/latest/source
We can use this to explore the kernel code.

## Code Walk

While we try to limite the amount of data captured by ftrace, 
the loving mother that the kernel is does so much that even
a simple printf capture results in hunderds of lines of function calls.
When we look at the trace, we first find the starting point of printf.
That is very likely to be a syscall ;)

```c
 2)               | do_syscall_64() {
 2)               |    __x64_sys_write() {
 2)               |      ksys_write() {
 2)               |        __fdget_pos() {
 2)   0.684 us    |          __fget_light();
 2)   1.411 us    |        }
 2)               |        vfs_write() {
 2)               |          rw_verify_area() {
 2)               |            security_file_permission() {
 2)               |              apparmor_file_permission() {
 2)               |                common_file_perm() {
 2)   0.903 us    |                  aa_file_perm();
 2)   2.417 us    |                }
 2)   3.111 us    |              }
 2)   3.957 us    |            }
 2)   4.964 us    |          }
```

### do_syscall_64() 
Now if we go to the source code we can see the entry point: do_syscall_64()
```c
__visible void do_syscall_64(unsigned long nr, struct pt_regs *regs)
{
	struct thread_info *ti;

	enter_from_user_mode(); 
	local_irq_enable();
	ti = current_thread_info();
	if (READ_ONCE(ti->flags) & _TIF_WORK_SYSCALL_ENTRY)
		nr = syscall_trace_enter(regs);

	nr &= __SYSCALL_MASK;
	if (likely(nr < NR_syscalls)) {
		nr = array_index_nospec(nr, NR_syscalls);
		regs->ax = sys_call_table[nr](regs);
	}

	syscall_return_slowpath(regs);
}

```

First of all, we notice that enter_from_user_mode(), while being clearly called,
does not show on our ftrace. Checking the source we see that this is a inlined
funciton, so my guess that that's why. If we dig into the this function we find
this piece of logic, with an incredibly useful comment.

```c
/**
 * context_tracking_exit - Inform the context tracking that the CPU is
 *                         exiting user or guest mode and entering the kernel.
 *
 * This function must be called after we entered the kernel from user or
 * guest space before any use of RCU read side critical section. This
 * potentially include any high level kernel code like syscalls, exceptions,
 * signal handling, etc...
 *
 * This call supports re-entrancy. This way it can be called from any exception
 * handler without needing to know if we came from userspace or not.
 */
void __context_tracking_exit(enum ctx_state state)
{
	if (!context_tracking_recursion_enter())
		return;

	if (__this_cpu_read(context_tracking.state) == state) {
		if (__this_cpu_read(context_tracking.active)) {
			/*
			 * We are going to run code that may use RCU. Inform
			 * RCU core about that (ie: we may need the tick again).
			 */
			rcu_user_exit();
			if (state == CONTEXT_USER) {
				vtime_user_exit(current);
				trace_user_exit(0);
			}
		}
		__this_cpu_write(context_tracking.state, CONTEXT_KERNEL);
	}
	context_tracking_recursion_exit();
}
```

Lol a rapid WTF moment. It seems like vtime_user_exit(current) is really the heart of
what we need. But lets look at all these calls that have `recursion` in the name.
I think this code tries to detect when recursion is taking place. And if we look at
what context_tracking_enter() we see this:
```c
DEFINE_PER_CPU(struct context_tracking, context_tracking);
EXPORT_SYMBOL_GPL(context_tracking);

static bool context_tracking_recursion_enter(void)
{
	int recursion;

	recursion = __this_cpu_inc_return(context_tracking.recursion);
	if (recursion == 1)
		return true;

	WARN_ONCE((recursion < 1), "Invalid context tracking recursion value %d\n", recursion);
	__this_cpu_dec(context_tracking.recursion);

	return false;
}
```

Notice the DEFINE_PER_CPU of the context_tracking. We increment the counter and check if it is 1.
If it is 1, there is no recursion, so we return True and thus can proceed with __context_tracking_exit().
If it is not 1, then we must be a recursive call, so we decrement the counter and return false, which
in turn results in immediate return from __context_tracking_exit() (which is why we need to decrement). 
Some other cool stuff here are: __this_cpu_inc_return() and __this_cpu_dec(). Tried to follow
these macros but there is some darkenss there, my guess they just increment/decrement value. "_return"
specifies that on top of increment, we also need to return the new value. Don't fully understand the
role of "__this_cpu" part. But we are getting sidetracked. After the __context_tracking_exit() is over,
last thing we do is decrement that counter back to 0. 

To perform the actual mode swithc I am a little lost. The vtime stuff seems just to do some stuff with,
you know, time. Might need to learn wtf rcu is before digging further here. Lets just assume we have
succesfully left user space.

Next thing that draws our attention in do_syscall_64() is the call to local_irq_enable(). Probably going
to leave it for later, because I don't fully understand how interrupts come into the picture here.

Next we have this beauty:
```c
	if (likely(nr < NR_syscalls)) {
		nr = array_index_nospec(nr, NR_syscalls);
		regs->ax = sys_call_table[nr](regs);
	}
```
This is suprisingly straight forward. We index into the table of syscalls, get the function pointer
and call it while passing registers to the call. Notice how if we try to find the sys_call_table, we end
up seeing that it is defined on per arch basis. Kind of makes sense considering that writing the registers
needs some assembly. 

### __x64_sys_write()
If we start digging deeper we find this, as one of the places where the table is defined:
```c
asmlinkage const sys_call_ptr_t sys_call_table[__NR_syscall_max+1] = {
	/*
	 * Smells like a compiler bug -- it doesn't work
	 * when the & below is removed.
	 */
	[0 ... __NR_syscall_max] = &sys_ni_syscall,
#include <asm/syscalls_64.h>
};
```

Not entirely sure how this piece of C works. Like what on earth is this [0 ... MAX_NUM] = sys_ni_syscall,
are we somehow intitalizing the table to "syscall not implemented" syscall?
The include at the end sounds intriguing though.
After poking around in /arch/x86/entry we find this file of peculiar format with interesting content:
```bash
#/arch/x86/entry/syscalls/syscall_64.tbl 
0	common	read			__x64_sys_read
1	common	write			__x64_sys_write
2	common	open			__x64_sys_open
3	common	close			__x64_sys_close
4	common	stat			__x64_sys_newstat
...
```
ftrace tells us that __x64_sys_write() is the next function. So it must be that the source code
defining it is dynamically generated. Checkout the Makefile in the same directory:
```make
out := arch/$(SRCARCH)/include/generated/asm
...
syscall64 := $(srctree)/$(src)/syscall_64.tbl
...
$(out)/syscalls_64.h: $(syscall64) $(systbl)
	$(call if_changed,systbl)
```
Seems like the code is generating that interesting include that will indeed contain our __x64_sys_write()
Lets assume this mechanism for the time being and move on.

### ksys_write()
Next stop is ksys_write(). We get the source code for it:
```c
ssize_t ksys_write(unsigned int fd, const char __user *buf, size_t count)
{
	struct fd f = fdget_pos(fd);
	ssize_t ret = -EBADF;

	if (f.file) {
		loff_t pos = file_pos_read(f.file);
		ret = vfs_write(f.file, buf, count, &pos);
		if (ret >= 0)
			file_pos_write(f.file, pos);
		fdput_pos(f);
	}

	return ret;
}

SYSCALL_DEFINE3(write, unsigned int, fd, const char __user *, buf,
		size_t, count)
{
	return ksys_write(fd, buf, count);
}
```

We definately need to find out what SYSCALL_DEFINE3 really does in addition to knowing that
3 stands for the number of arguments. Time to focus on ksys_write().









