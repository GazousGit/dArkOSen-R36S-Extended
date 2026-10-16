// abort-trace: LD_PRELOAD helper that prints the call stack (library + offset, and the
// exported symbol name when there is one) when abort() is called or SIGABRT arrives.
// The console has no gdb or strace; this is how the modern core's startup abort was found
// (vixl Assembler::bl -> UnimplementedDelegate, see ../README.md).
//
// Build (WSL, the armhf chroot of ../build.sh):
//   cp abort-trace.c /root/flycast-build/trixie/build/
//   chroot /root/flycast-build/trixie arm-linux-gnueabihf-gcc -shared -fPIC -O1 \
//       -funwind-tables -o /build/abort-trace.so /build/abort-trace.c
// Use on the console (32-bit processes only; 64-bit helpers print "wrong ELF class", harmless):
//   LD_PRELOAD=/tmp/abort-trace.so /opt/retroarch/bin/retroarch32 ... 2> log
// Offsets inside a stripped core map to names only with a build linked without -s.
// glibc's own fatal errors (heap corruption) abort from inside libc and bypass abort() here;
// the SIGABRT handler then tries to unwind from the signal frame, which may stop early.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <unwind.h>

static _Unwind_Reason_Code frame(struct _Unwind_Context *ctx, void *arg)
{
    int *n = arg;
    uintptr_t pc = _Unwind_GetIP(ctx);
    if (pc == 0)
        return _URC_END_OF_STACK;
    Dl_info info;
    if (dladdr((void *)pc, &info) && info.dli_fname)
        dprintf(2, "abort-trace #%d %s+0x%lx %s\n", *n, info.dli_fname,
                (unsigned long)(pc - (uintptr_t)info.dli_fbase), info.dli_sname ? info.dli_sname : "");
    else
        dprintf(2, "abort-trace #%d %p\n", *n, (void *)pc);
    return ++*n > 48 ? _URC_END_OF_STACK : _URC_NO_REASON;
}

static void trace(const char *why)
{
    int n = 0;
    dprintf(2, "abort-trace: %s\n", why);
    _Unwind_Backtrace(frame, &n);
}

void abort(void)
{
    trace("abort() called");
    signal(SIGABRT, SIG_DFL);
    syscall(SYS_tgkill, getpid(), syscall(SYS_gettid), SIGABRT);
    _exit(134);
}

static void on_signal(int sig)
{
    trace(sig == SIGABRT ? "SIGABRT" : "fatal signal");
    signal(sig, SIG_DFL);
    raise(sig);
}

__attribute__((constructor)) static void install(void)
{
    signal(SIGABRT, on_signal);
}
