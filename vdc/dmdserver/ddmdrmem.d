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
			throw *pcancelError;
		return GC.malloc(n);
	}

	static void* xcalloc(size_t size, size_t n) nothrow pure
	{
		return GC.calloc(size * n);
	}

	static void* xrealloc(void* p, size_t size) nothrow pure
	{
		return GC.realloc(p, size);
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
