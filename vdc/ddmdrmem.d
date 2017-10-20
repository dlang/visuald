module ddmd.root.rmem;

import core.memory : GC;
import core.stdc.string : strlen;

extern (C++) struct Mem
{
	static char* xstrdup(const(char)* p) nothrow
	{
		return p[0 .. strlen(p) + 1].dup.ptr;
	}

	static void xfree(void* p) nothrow
	{
		return GC.free(p);
	}

	static void* xmalloc(size_t n) nothrow
	{
		if (cancel)
			throw cancelError;
		return GC.malloc(n);
	}

	static void* xcalloc(size_t size, size_t n) nothrow
	{
		return GC.calloc(size * n);
	}

	static void* xrealloc(void* p, size_t size) nothrow
	{
		return GC.realloc(p, size);
	}
	static void error() nothrow
	{
		__gshared static oom = new Error("out of memory");
		throw oom;
	}

	__gshared cancelError = new Error("cancel malloc");
	__gshared bool cancel;
}

extern (C++) const __gshared Mem mem;


