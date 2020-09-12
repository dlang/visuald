module dmd.root.rmem;

import core.memory : GC;
import core.stdc.string : strlen;

extern (C++) struct Mem
{
	enum isGCEnabled = true;

	static char* xstrdup(const(char)* p) nothrow
	{
		return p[0 .. strlen(p) + 1].dup.ptr;
	}

	static void xfree(void* p) nothrow pure
	{
		return GC.free(p);
	}

	static void* xmalloc(size_t n) nothrow pure
	{
		if (*pcancel)
			throw new Error("cancel malloc"); //*pcancelError;
		return GC.malloc(n);
	}
	static void* xmalloc_noscan(size_t n) nothrow pure
	{
		if (*pcancel)
			throw new Error("cancel malloc");//*pcancelError;
		return GC.malloc(n, GC.BlkAttr.NO_SCAN);
	}

	static void* xcalloc(size_t size, size_t n) nothrow pure
	{
		return GC.calloc(size * n);
	}

	static void* xcalloc_noscan(size_t size, size_t n) nothrow pure
	{
		return GC.calloc(size * n, GC.BlkAttr.NO_SCAN);
	}

	static void* xrealloc(void* p, size_t size) nothrow pure
	{
		return GC.realloc(p, size);
	}

	static void* xrealloc_noscan(void* p, size_t size) nothrow pure
	{
		return GC.realloc(p, size, GC.BlkAttr.NO_SCAN);
	}

	static void error() nothrow
	{
		__gshared static oom = new Error("out of memory");
		throw oom;
	}
	static void* check(void* p) nothrow
	{
		if (!p)
			error();
		return p;
	}

	extern(D) __gshared immutable cancelError = new Error("cancel malloc");
	extern(D) __gshared bool cancel;
	// fake purity
	enum pcancel = cast(immutable) &cancel;
	enum pcancelError = cast(immutable) &cancelError;
}

extern (C++) const __gshared Mem mem;

/**
Makes a null-terminated copy of the given string on newly allocated memory.
The null-terminator won't be part of the returned string slice. It will be
at position `n` where `n` is the length of the input string.

Params:
    s = string to copy

Returns: A null-terminated copy of the input array.
*/
extern (D) char[] xarraydup(const(char)[] s) nothrow pure
{
    if (!s)
        return null;

    auto p = cast(char*)mem.xmalloc(s.length + 1);
    char[] a = p[0 .. s.length];
    a[] = s[0 .. s.length];
    p[s.length] = 0;    // preserve 0 terminator semantics
    return a;
}

/**
Makes a copy of the given array on newly allocated memory.

Params:
    s = array to copy

Returns: A copy of the input array.
*/
extern (D) T[] arraydup(T)(const scope T[] s) nothrow
{
    if (!s)
        return null;

    const dim = s.length;
    auto p = (cast(T*)mem.xmalloc(T.sizeof * dim))[0 .. dim];
    p[] = s;
    return p;
}

import core.stdc.string;

// Define this to have Pool emit traces of objects allocated and disposed
//debug = Pool;
// Define this in addition to Pool to emit per-call traces (otherwise summaries are printed at the end).
//debug = PoolVerbose;

/**
Defines a pool for class objects. Objects can be fetched from the pool with make() and returned to the pool with
dispose(). Using a reference that has been dispose()d has undefined behavior. make() may return memory that has been
previously dispose()d.

Currently the pool has effect only if the GC is NOT used (i.e. either `version(GC)` or `mem.isGCEnabled` is false).
Otherwise `make` just forwards to `new` and `dispose` does nothing.

Internally the implementation uses a singly-linked freelist with a global root. The "next" pointer is stored in the
first word of each disposed object.
*/
struct Pool(T)
if (is(T == class))
{
    /// The freelist's root
    private static T root;

    private static void trace(string fun, string f, uint l)()
    {
        debug(Pool)
        {
            debug(PoolVerbose)
            {
                fprintf(stderr, "%.*s(%u): bytes: %lu Pool!(%.*s)."~fun~"()\n",
						cast(int) f.length, f.ptr, l, T.classinfo.initializer.length,
						cast(int) T.stringof.length, T.stringof.ptr);
            }
            else
            {
                static ulong calls;
                if (calls == 0)
                {
                    // Plant summary printer
                    static extern(C) void summarize()
                    {
                        fprintf(stderr, "%.*s(%u): bytes: %lu calls: %lu Pool!(%.*s)."~fun~"()\n",
								cast(int) f.length, f.ptr, l, ((T.classinfo.initializer.length + 15) & ~15) * calls,
								calls, cast(int) T.stringof.length, T.stringof.ptr);
                    }
                    atexit(&summarize);
                }
                ++calls;
            }
        }
    }

    /**
    Returns a reference to a new object in the same state as if created with new T(args).
    */
    static T make(string f = __FILE__, uint l = __LINE__, A...)(auto ref A args)
    {
        if (!root)
        {
            trace!("makeNew", f, l)();
            return new T(args);
        }
        else
        {
            trace!("makeReuse", f, l)();
            auto result = root;
            root = *(cast(T*) root);
            memcpy(cast(void*) result, T.classinfo.initializer.ptr, T.classinfo.initializer.length);
            result.__ctor(args);
            return result;
        }
    }

    /**
    Signals to the pool that this object is no longer used, so it can recycle its memory.
    */
    static void dispose(string f = __FILE__, uint l = __LINE__, A...)(T goner)
    {
        version(GC)
        {
            if (mem.isGCEnabled) return;
        }
        trace!("dispose", f, l)();
        debug
        {
            // Stomp the memory so as to maximize the chance of quick failure if used after dispose().
            auto p = cast(ulong*) goner;
            p[0 .. T.classinfo.initializer.length / ulong.sizeof] = 0xdeadbeef;
        }
        *(cast(T*) goner) = root;
        root = goner;
    }
}
