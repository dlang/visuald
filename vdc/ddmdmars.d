
module ddmd.mars;
import ddmd.dscope;
import ddmd.root.rmem;

extern (C++) void genCmain(Scope* sc)
{
}

extern (C++) void *mem_malloc(size_t u)
{
	return mem.xmalloc(u);
}

extern (C++) void mem_free(void* p)
{
	mem.xfree(p);
}

extern (C) void* allocmemory(size_t size) nothrow
{
	return GC.malloc(size);
}
