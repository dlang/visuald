module tracegc;

import core.stdc.string;
import core.time;
import core.stdc.stdio;

// debug version = traceGC;

// tiny helper to clear a page of the stack below the current stack pointer to avoid false pointers there
void wipeStack()
{
	char[4096] data = void;
	memset (data.ptr, 0xff, 4096);
}

version(traceGC) {
import core.sys.windows.windows;
import core.internal.gc.impl.conservative.gc;
import core.thread;

extern(C) alias _CRT_ALLOC_HOOK = int function(int, void *, size_t, int, long, const(char) *, int);

extern(C) _CRT_ALLOC_HOOK _CrtSetAllocHook(_CRT_ALLOC_HOOK _PfnNewHook);

__gshared _CRT_ALLOC_HOOK _prevHook;

extern(C) int _CRT_allocHook(int op, void *p, size_t size, int nBlockUse, long lRequest, const(char) *filename, int line)
{
	import core.sys.windows.stacktrace;

	if (!filename && op == 1) // alloc hook
	{
		if (StackAddrInfo* ai = traceAndResolve(4))
		{
			filename = stringBuffer.ptr + ai.filenameOff;
			line = ai.line;

			version(Win64)
			{
				// tweaked to the VC2013 debug runtime
				const(char)** patchFilename = &filename + 11;
				*patchFilename = filename;

				int* patchLine = &line + 22;
				*patchLine = line;
			}
		}
	}
	if (_prevHook)
		return _prevHook(op, p, size, nBlockUse, lRequest, filename, line);
	return 1;
}

extern(Windows) void OutputDebugStringA(LPCSTR) nothrow;

alias RtlCaptureStackBackTraceFunc = extern(Windows) USHORT function(ULONG FramesToSkip, ULONG FramesToCapture, PVOID *BackTrace, PULONG BackTraceHash) nothrow;

private __gshared RtlCaptureStackBackTraceFunc RtlCaptureStackBackTrace;

extern(Windows) USHORT NoCaptureStackBackTrace(ULONG FramesToSkip, ULONG FramesToCapture, PVOID *BackTrace, PULONG BackTraceHash) nothrow
{
	return 0;
}

void initRtlCaptureStackBackTrace()
{
	if (RtlCaptureStackBackTrace is null)
	{
		RtlCaptureStackBackTrace = &NoCaptureStackBackTrace;

		import core.sys.windows.dbghelp;
		auto dbghelp = DbgHelp.get();
		if(dbghelp is null)
			return; // dbghelp.dll not available

		if (auto kernel32Handle = LoadLibraryA("kernel32.dll"))
			RtlCaptureStackBackTrace = cast(RtlCaptureStackBackTraceFunc) GetProcAddress(kernel32Handle, "RtlCaptureStackBackTrace");

		HANDLE hProcess = GetCurrentProcess();

		DWORD symOptions = dbghelp.SymGetOptions();
		symOptions |= SYMOPT_LOAD_LINES;
		symOptions |= SYMOPT_FAIL_CRITICAL_ERRORS;
		symOptions |= SYMOPT_DEFERRED_LOAD;
		symOptions  = dbghelp.SymSetOptions( symOptions );

		debug(PRINTF) printf("Search paths: %s\n", generateSearchPath().ptr);

		if (!dbghelp.SymInitialize(hProcess, null, TRUE))
			return;

		//dbghelp.SymRegisterCallback64(hProcess, &FixupDebugHeader, 0);
	}
}

StackAddrInfo* traceAndResolve(size_t skip)
{
	initRtlCaptureStackBackTrace();

	size_t[63] buffer = void; // On windows xp the sum of "frames to skip" and "frames to capture" can't be greater then 63
	auto backtraceLength = RtlCaptureStackBackTrace(cast(ULONG)skip, cast(ULONG)(buffer.length - skip), cast(void**)buffer.ptr, null);

	for (size_t p = 0; p < backtraceLength; p++)
	{
		StackAddrInfo* ai = resolveAddr(buffer[p]);
		if (ai.line != uint.max)
			return ai;
	}
	return null;
}

void initTraceMalloc()
{
	version(CRuntime_Microsoft)
		_prevHook = _CrtSetAllocHook(&_CRT_allocHook);
}

__gshared char[1 << 20] stringBuffer;
__gshared size_t stringBufferPos;

uint findOrAddString(const char* str)
{
	size_t len = strlen(str);
	uint p = 0;
	while (p < stringBufferPos)
	{
		size_t plen = strlen(stringBuffer.ptr + p);
		if (plen == len && strcmp (stringBuffer.ptr + p, str) == 0)
			return p;
		p += plen + 1;
	}

	stringBufferPos += len + 1;
	assert(stringBufferPos <= stringBuffer.length);

	stringBuffer[p .. stringBufferPos] = str[0 .. len + 1];
	return p;
}

struct StackAddrInfo
{
	size_t pc;
	uint filenameOff;
	uint line;
}

__gshared StackAddrInfo[1 << 16] addrInfo;
__gshared size_t addrInfoPos;

StackAddrInfo* findOrAddAddr(size_t pc) nothrow
{
	for (size_t p = 0; p < addrInfoPos; p++)
		if (addrInfo[p].pc == pc)
			return addrInfo.ptr + p;
	assert(addrInfoPos < addrInfo.length);
	addrInfo[addrInfoPos].pc = pc;
	return addrInfo.ptr + addrInfoPos++;
}

StackAddrInfo* resolveAddr(size_t pc) nothrow
{
	StackAddrInfo* ai = findOrAddAddr(pc);
	if (ai.line)
		return ai;

	ai.line = uint.max;

	try
	{
		import core.sys.windows.dbghelp;
		auto dbghelp = DbgHelp.get();
		assert(dbghelp);

		HANDLE hProcess = GetCurrentProcess();

		DWORD disp;
		IMAGEHLP_LINEA64 line = void;
		line.SizeOfStruct = IMAGEHLP_LINEA64.sizeof;

		if (dbghelp.SymGetLineFromAddr64(hProcess, pc, &disp, &line))
		{
			if (validFilename(line.FileName))
			{
				ai.filenameOff = findOrAddString(line.FileName);
				ai.line = line.LineNumber > 0 ? line.LineNumber : 1;
			}
		}
	}
	catch(Exception)
	{
	}
	return ai;
}

bool validFilename(const(char)* fn)
{
	if (!fn || fn[0] == 'f')
		return false;

	size_t flen = strlen(fn);
	static immutable string[] excl =
	[
		r"\object.d",
		r"\rt\lifetime.d",
		r"\rt\aaA.d",
		r"\rt\util\container\common.d",
		r"\rt\util\container\treap.d",
		r"\gc\proxy.d",
		r"\core\lifetime.d",
		r"\core\memory.d",
		r"\core\internal\array\appending.d",
		r"\core\internal\array\capacity.d",
		r"\core\internal\array\construction.d",
		r"\core\internal\array\concatenation.d",
		r"\core\internal\array\utils.d",
		r"\core\internal\newaa.d",
		r"\std\array.d",
		r"\dmd\root\rmem.d",
		r"\dmd\root\array.d",
		r"\dmd\root\aav.d",
		r"\dmd\root\outbuffer.d",
		r"\dmd\root\stringtable.d",
		r"\stdext\com.d",
		r"\dmdrmem.d",
	];
	foreach (ex; excl)
		if (flen > ex.length && fn[flen - ex.length .. flen] == ex)
			return false;

	return true;
}

////////////////////////////////////////////////////////////

import core.gc.gcinterface;
import core.gc.registry;
import core.internal.gc.os;
import core.exception;

extern (C) pragma(crt_constructor) void register_tracegc()
{
	registerGCFactory("trace", &GCTraceProxy.initialize);
}

class GCTraceProxy : GC
{
	GC gc;

	static GC initialize()
	{
		__gshared ubyte[__traits(classInstanceSize, GCTraceProxy)] buf;

		initRtlCaptureStackBackTrace();
		// initTraceMalloc();

		auto init = typeid(GCTraceProxy).initializer();
		assert(init.length == buf.length);
		auto instance = cast(GCTraceProxy) memcpy(buf.ptr, init.ptr, init.length);
		instance.__ctor();
		return instance;
	}

	this()
	{
		// unfortunately, registry cannot be invoked twice, and
		// initialize for ConservativeGC is private
		__gshared ubyte[__traits(classInstanceSize, ConservativeGC)] buf;

		ConservativeGC.isPrecise = true;
		auto init = typeid(ConservativeGC).initializer();
		assert(init.length == __traits(classInstanceSize, ConservativeGC));
		auto instance = cast(ConservativeGC) memcpy(buf.ptr, init.ptr, init.length);
		instance.__ctor();

		gc = instance;
		tracer = this;
 	}

	~this()
	{
		destroy(gc);
	}

	void enable()
	{
		gc.enable();
	}

	void disable()
	{
		gc.disable();
	}

	void collect() nothrow
	{
		gc.collect();
	}

	static if(__VERSION__ < 2_111)
		void collectNoStack() nothrow
		{
			gc.collectNoStack();
		}

	void minimize() nothrow
	{
		gc.minimize();
	}

	uint getAttr(void* p) nothrow
	{
		return gc.getAttr(p);
	}

	uint setAttr(void* p, uint mask) nothrow
	{
		return gc.setAttr(p, mask);
	}

	uint clrAttr(void* p, uint mask) nothrow
	{
		return gc.clrAttr(p, mask);
	}

	void* malloc(size_t size, uint bits, const TypeInfo ti) nothrow
	{
		void* p = gc.malloc(size, bits, ti);
		traceAlloc(p);
		return p;
	}

	BlkInfo qalloc(size_t size, uint bits, scope const TypeInfo ti) nothrow
	{
		BlkInfo bi = gc.qalloc(size, bits, ti);
		traceAlloc(bi.base);
		return bi;
	}

	void* calloc(size_t size, uint bits, const TypeInfo ti) nothrow
	{
		void* p = gc.calloc(size, bits, ti);
		traceAlloc(p);
		return p;
	}

	void* realloc(void* p, size_t size, uint bits, const TypeInfo ti) nothrow
	{
		void* q = gc.realloc(p, size, bits, ti);
		traceAlloc(q);
		return q;
	}

	size_t extend(void* p, size_t minsize, size_t maxsize, const TypeInfo ti) nothrow
	{
		return gc.extend(p, minsize, maxsize, ti);
	}

	size_t reserve(size_t size) nothrow
	{
		return gc.reserve(size);
	}

	void free(void* p) nothrow
	{
		gc.free(p);
	}

	void* addrOf(void* p) nothrow
	{
		return gc.addrOf(p);
	}

	size_t sizeOf(void* p) nothrow
	{
		return gc.sizeOf(p);
	}

	BlkInfo query(void* p) nothrow
	{
		return gc.query(p);
	}

	core.memory.GC.Stats stats() nothrow
	{
		return gc.stats();
	}

	core.memory.GC.ProfileStats profileStats() nothrow
	{
		return gc.profileStats();
	}

	void addRoot(void* p) nothrow @nogc
	{
		return gc.addRoot(p);
	}

	void removeRoot(void* p) nothrow @nogc
	{
		return gc.removeRoot(p);
	}

	@property RootIterator rootIter() @nogc
	{
		return gc.rootIter();
	}

	void addRange(void* p, size_t sz, const TypeInfo ti) nothrow @nogc
	{
		return gc.addRange(p, sz, ti);
	}

	void removeRange(void* p) nothrow @nogc
	{
		return gc.removeRange(p);
	}

	@property RangeIterator rangeIter() @nogc
	{
		return gc.rangeIter();
	}

	//static if (__VERSION__ >= 2087)
		void runFinalizers(scope const void[] segment) nothrow
		{
			return gc.runFinalizers(segment);
		}
	//else
		void runFinalizers(in void[] segment) nothrow
		{
			return gc.runFinalizers(segment);
		}

	bool inFinalizer() nothrow
	{
		return gc.inFinalizer();
	}
	ulong allocatedInCurrentThread() nothrow
	{
		return gc.allocatedInCurrentThread();
	}

	static if(__VERSION__ >= 2_111)
	{
		void[] getArrayUsed(void *ptr, bool atomic = false) nothrow
		{
			return gc.getArrayUsed(ptr, atomic);
		}
		bool expandArrayUsed(void[] slice, size_t newUsed, bool atomic = false) nothrow @safe
		{
			return gc.expandArrayUsed(slice, newUsed, atomic);
		}
		size_t reserveArrayCapacity(void[] slice, size_t request, bool atomic = false) nothrow @safe
		{
			return gc.reserveArrayCapacity(slice, request, atomic);
		}
		bool shrinkArrayUsed(void[] slice, size_t existingUsed, bool atomic = false) nothrow
		{
			return gc.shrinkArrayUsed(slice, existingUsed, atomic);
		}
	}
	static if(__VERSION__ >= 2_112)
	{
		void initThread(ThreadBase thread) nothrow @nogc
		{
			gc.initThread(thread);
		}

		void cleanupThread(ThreadBase thread) nothrow @nogc
		{
			gc.cleanupThread(thread);
		}
	}

	TraceBuffer traceBuffer;
}

///////////////////////////////////////////////////////////
static struct TraceEntry
{
	enum eagerResolve = true;

	void* addr;
	static if (eagerResolve)
	{
		StackAddrInfo* ai;

		StackAddrInfo* resolve() nothrow { return ai; }
	}
	else
	{
		size_t[15] buffer;

		StackAddrInfo* resolve() nothrow { return _resolve(buffer[]); }
	}

	void initialize(void* addr, ref size_t[15] buf) nothrow
	{
		this.addr = addr;
		static if (eagerResolve)
			ai = _resolve(buf[]);
		else
			buffer[] = buf[];
	}

	StackAddrInfo* _resolve(size_t[] buf) nothrow
	{
		for (size_t sp = 0; sp < buf.length && buf[sp]; sp++)
		{
			StackAddrInfo* ai = resolveAddr(buf[sp]);
			if (ai.line != uint.max)
				return ai;
		}
		return null;
	}
}

static struct Range
{
	TraceEntry* _entries;
	size_t _length;
	size_t _capacity;
}

static struct AddrTracePair
{
	void* addr;
	TraceEntry* entry;
}

size_t addrHash(void* addr, size_t mask) nothrow
{
	size_t hash = cast(size_t)addr;
	hash = (hash >> 4) ^ (hash >> 20) ^ (hash >> 30);
	return hash & mask;
}

static struct TraceBuffer
{
nothrow:
	void reset()
	{
		_length = 0;
		os_mem_unmap(_p, _cap * Range.sizeof);
		_p = null;
		_cap = 0;
	}

	void pushEntry(ref TraceEntry te)
	{
		if (!_length || _p[_length-1]._length >= _p[_length-1]._capacity)
			newRange();

		_p[_length-1]._entries[_p[_length-1]._length++] = te;
	}

	TraceEntry* findTraceEntry(void* addr)
	{
		foreach_reverse (ref rng; _p[0.._length])
			foreach_reverse (ref te; rng._entries[0..rng._length])
				if (te.addr == addr)
					return &te;
		return null;
	}

	AddrTracePair[] createTraceMap()
	{
		size_t n = numEntries();
		if (!n)
			return null;
		// next or same power of 2
		while (n & (n - 1))
			n += (n & -n); // add lowest bit
		n = n + n;
		auto arr = cast(AddrTracePair*)os_mem_map(n * AddrTracePair.sizeof);
		if (!arr)
			onOutOfMemoryErrorNoGC();
		memset(arr, 0, n * AddrTracePair.sizeof);

		foreach_reverse (ref rng; _p[0.._length])
			foreach_reverse (ref te; rng._entries[0..rng._length])
			{
				// insert with quadratic probing
				size_t k = addrHash(te.addr, n - 1);
				for (size_t j = 1; arr[k].addr !is te.addr; j++)
				{
					if (arr[k].addr is null)
					{
						arr[k].addr = te.addr;
						arr[k].entry = &te;
						break;
					}
					k = (k + j) & (n - 1);
				}
			}
		return arr[0..n];
	}

	void deleteTraceMap(AddrTracePair[] arr)
	{
		if (arr.ptr)
			os_mem_unmap(arr.ptr, arr.length * AddrTracePair.sizeof);
	}

	TraceEntry* findTraceEntry(AddrTracePair[] arr, void* addr)
	{
		// search with quadratic probing
		size_t k = addrHash(addr, arr.length - 1);
		size_t j = 1;
		while (arr[k].addr != addr)
		{
			if (arr[k].addr is null)
				return null;
			k = (k + j) & (arr.length - 1);
			j++;
		}
		return arr[k].entry;
	}

	void newRange()
	{
		if (_length == _cap)
			grow();

		enum entriesPerRange = 64 * 1024; // Windows VirtualAlloc granularity
		_p[_length]._entries = cast(TraceEntry*)os_mem_map(entriesPerRange * TraceEntry.sizeof);
		_p[_length]._capacity = entriesPerRange;
		_p[_length]._length = 0;
		if (_p[_length]._entries is null)
			onOutOfMemoryErrorNoGC();
		_length++;
	}

	size_t numEntries()
	{
		size_t sum = 0;
		for (size_t r = 0; r < _length; r++)
			sum += _p[r]._length;
		return sum;
	}

	size_t memUsage()
	{
		size_t sum = _cap * Range.sizeof;
		for (size_t r = 0; r < _length; r++)
			sum += _p[r]._capacity * TraceEntry.sizeof;
		return sum;
	}

private:
	void grow()
	{
		enum initSize = 64 * 1024; // Windows VirtualAlloc granularity
		immutable ncap = _cap ? 2 * _cap : initSize / Range.sizeof;
		auto p = cast(Range*)os_mem_map(ncap * Range.sizeof);
		if (p is null)
			onOutOfMemoryErrorNoGC();

		p[0 .. _length] = _p[0 .. _length];
		os_mem_unmap(_p, _cap * Range.sizeof);

		_p = p;
		_cap = ncap;
	}

	size_t _length;
	Range* _p;
	size_t _cap;
}

__gshared GCTraceProxy tracer;

/+
import core.demangle;
extern pragma(mangle, mangle!GC("gc.proxy.instance")) __gshared GC gc_instance;

__gshared GCTraceProxy tracer = new GCTraceProxy;

extern(C) void gc_init()
{
	import core.gc.config;

	config.initialize();
	ConservativeGC.initialize(gc_instance);
	insertGCTracer();
	thread_init();
}

extern(C) void gc_term()
{
	//gc_instance.collectNoStack(); // not really a 'collect all' -- still scans static data area, roots, and ranges.

	thread_term();
	removeGCTracer();
	ConservativeGC.finalize(gc_instance);
}

void insertGCTracer()
{
	initRtlCaptureStackBackTrace();

	tracer.gc = gc_instance;
	gc_instance = tracer;
}

void removeGCTracer()
{
	gc_instance = tracer.gc;
}
+/

void traceAlloc(void* addr) nothrow
{
	size_t[15] buf;

	auto backtraceLength = RtlCaptureStackBackTrace(2, cast(ULONG)buf.length, cast(void**)buf.ptr, null);

	TraceEntry te;
	te.initialize(addr, buf);

	tracer.traceBuffer.pushEntry(te);
}

extern(C) void dumpGC()
{
	dumpGC(tracer.gc);
}

void dumpAddr(AddrTracePair[] traceMap, void* addr, size_t size)
{
	char[256] buf;

	const(char)* filename;
	int line;
	if (auto te = tracer.traceBuffer.findTraceEntry(traceMap, addr))
	{
		if (auto ai = te.resolve())
		{
			filename = stringBuffer.ptr + ai.filenameOff;
			line = ai.line;
			addAddrInfoStat(ai, size);
		}
		else
			filename = "<unknown location>: ";
	}
	else
		filename = "<unknown address>: ";

	auto xtra = dumpExtra(addr);
	trace_printf("%s(%d): %p %llx %.*s\n", filename, line, addr, cast(long) size, cast(int)xtra.length, xtra.ptr);
}

struct AddrInfoStat
{
	@property ai() const nothrow { return cast(StackAddrInfo*) _ai; }
	size_t _ai; // pretend it is not a pointer
	size_t count;
	size_t size;
}

__gshared AddrInfoStat[1 << 13] addrInfoStat;

void addAddrInfoStat(StackAddrInfo* ai, size_t size)
{
	// search with quadratic probing
	size_t k = addrHash(ai, addrInfoStat.length - 1);
	size_t j = 1;
	while (addrInfoStat[k].ai != ai)
	{
		if (addrInfoStat[k].ai is null)
		{
			addrInfoStat[k]._ai = cast(size_t)ai;
			addrInfoStat[k].count = 1;
			addrInfoStat[k].size = size;
			return;
		}
		k = (k + j) & (addrInfoStat.length - 1);
		j++;
	}
	addrInfoStat[k].count++;
	addrInfoStat[k].size += size;
}

void dumpAddrInfoStat()
{
	char[256] buf;

	trace_printf("\nDump combined by stack location:\n");

	foreach(ref info; addrInfoStat)
		if (info.ai)
		{
			const(char)* filename = stringBuffer.ptr + info.ai.filenameOff;
			trace_printf("%s(%d): %lld allocs %llx bytes\n", filename, info.ai.line, cast(long)info.count, cast(long)info.size);
		}

	trace_printf("\n");
}

HashTab!(void*, void*)**pp_references;

///////////////////////////////////////////////////////////////
__gshared void** modvtbl;
__gshared void** aliasdeclvtbl;
__gshared void** funcdeclvtbl;
__gshared void** vardeclvtbl;
__gshared void** structdeclvtbl;
__gshared void** classdeclvtbl;
__gshared void** ifacedeclvtbl;
__gshared void** enumdeclvtbl;
__gshared void** enummembervtbl;
__gshared void** tmpldeclvtbl;
__gshared void** tmplinstvtbl; // package

shared static this()
{
	import dmd.dmodule;
	import dmd.declaration;
	import dmd.func;
	import dmd.dclass;
	import dmd.denum;
	import dmd.dstruct;
	import dmd.dtemplate;

	void** getVtbl(T)() { return *cast(void***)typeid(T).initializer().ptr; }
	modvtbl        = getVtbl!Module;
	aliasdeclvtbl  = getVtbl!AliasDeclaration;
	funcdeclvtbl   = getVtbl!FuncDeclaration;
	vardeclvtbl    = getVtbl!VarDeclaration;
	structdeclvtbl = getVtbl!StructDeclaration;
	classdeclvtbl  = getVtbl!ClassDeclaration;
	ifacedeclvtbl  = getVtbl!InterfaceDeclaration;
	enumdeclvtbl   = getVtbl!EnumDeclaration;
	enummembervtbl = getVtbl!EnumMember;
	tmpldeclvtbl   = getVtbl!TemplateDeclaration;
	tmplinstvtbl   = getVtbl!TemplateInstance;
}

char[] dumpExtra(void* p)
{
	import dmd.dmodule;
	import dmd.dsymbol;
	import dmd.identifier;
	import vdc.dmdserver.semanalysis;

	static bool isLive(Module m)
	{
		if (lastContext)
			foreach (ref md; lastContext.modules)
				if (m is md.parsedModule || m is md.semanticModule)
					return true;
		foreach (mod; Module.amodules)
			if (m is mod)
				return true;
		return false;
	}

	__gshared char[256] buf;
	void** vtbl = *cast(void***)p;
	if (vtbl is modvtbl)
	{
		Module m = cast(Module)p;
		if (!isLive(m))
		{
			Identifier ident = m.ident;
			auto len = snprintf(buf.ptr, buf.length, "stale Module %.*s", cast(int) ident.toString().length, ident.toString().ptr);
			return buf[0..len];
		}
	}
	else
	{
		if (vtbl is aliasdeclvtbl || vtbl is funcdeclvtbl || vtbl is vardeclvtbl ||
			vtbl is structdeclvtbl || vtbl is classdeclvtbl || vtbl is ifacedeclvtbl ||
			vtbl is enumdeclvtbl || vtbl is enummembervtbl ||
			vtbl is tmpldeclvtbl || vtbl is tmplinstvtbl)
		{
			auto sym = cast(Dsymbol)p;
			const(char)* cat;
			if (auto m = sym.getModule())
			{
				if (!isLive(m))
					cat = "stale";
			}
			else
			{
				cat = "detached";
			}
			if (cat)
			{
				Identifier ident = sym.ident;
				auto name = ident ? ident.toString() : "<anonymous>";
				auto len = snprintf(buf.ptr, buf.length, "%s %s %.*s", cat, sym.kind(), cast(int) name.length, name.ptr);
				if (len >= buf.length)
					return buf[0..$-1];
				else
					return buf[0..len];
			}
		}

	}
	return null;
}

///////////////////////////////////////////////////////////////
import core.internal.container.hashtab;

alias ScanRange = Gcx.ScanRange!false;
//Gcx.ToScanStack!ScanRange toscan;
// dmd BUG: alignment causes bad capture!

Gcx.ToScanStack!(Gcx.ScanRange!false) toscanConservative;
Gcx.ToScanStack!(Gcx.ScanRange!true) toscanPrecise;

HashTab!(void*, void*) *g_references;
HashTab!(void*, size_t) *g_objects;
ConservativeGC g_cgc;

void collectReferences(ConservativeGC cgc, bool precise, bool withStacks,
					   ref HashTab!(void*, void*) references, ref HashTab!(void*, size_t) objects)
{
	g_cgc = cgc;
	g_references = &references;
	g_objects = &objects;

	cgc.gcLock.lock();

    template scanStack(bool precise)
    {
        static if (precise)
            alias scanStack = toscanPrecise;
        else
            alias scanStack = toscanConservative;
    }

    /**
	* Search a range of memory values and mark any pointers into the GC pool.
	*/
    static void mark(bool precise)(Gcx.ScanRange!precise rng) nothrow
    {
        auto pooltable = g_cgc.gcx.pooltable;
        alias toscan = scanStack!precise;

        debug(MARK_PRINTF)
            printf("marking range: [%p..%p] (%#llx)\n", pbot, ptop, cast(long)(ptop - pbot));

        // limit the amount of ranges added to the toscan stack
        enum FANOUT_LIMIT = 32;
        size_t stackPos;
        Gcx.ScanRange!precise[FANOUT_LIMIT] stack = void;

        size_t pcache = 0;

        const highpool = pooltable.length - 1;
        const minAddr = pooltable.minAddr;
        size_t memSize = pooltable.maxAddr - minAddr;
        Pool* pool = null;

        // properties of allocation pointed to
        Gcx.ScanRange!precise tgt = void;

        for (;;)
        {
            auto p = *cast(void**)(rng.pbot);

            debug(MARK_PRINTF) printf("\tmark %p: %p\n", rng.pbot, p);

            if (cast(size_t)(p - minAddr) < memSize &&
                (cast(size_t)p & ~cast(size_t)(PAGESIZE-1)) != pcache)
            {
                static if (precise) if (rng.pbase)
                {
                    size_t bitpos = cast(void**)rng.pbot - rng.pbase;
                    while (bitpos >= rng.bmplength)
                    {
                        bitpos -= rng.bmplength;
                        rng.pbase += rng.bmplength;
                    }
                    import core.bitop;
                    if (!core.bitop.bt(rng.ptrbmp, bitpos))
                    {
                        debug(MARK_PRINTF) printf("\t\tskipping non-pointer\n");
                        goto LnextPtr;
                    }
                }

                if (!pool || p < pool.baseAddr || p >= pool.topAddr)
                {
                    size_t low = 0;
                    size_t high = highpool;
                    while (true)
                    {
                        size_t mid = (low + high) >> 1;
                        pool = pooltable[mid];
                        if (p < pool.baseAddr)
                            high = mid - 1;
                        else if (p >= pool.topAddr)
                            low = mid + 1;
                        else break;

                        if (low > high)
                            goto LnextPtr;
                    }
                }
                size_t offset = cast(size_t)(p - pool.baseAddr);
                size_t biti = void;
                size_t pn = offset / PAGESIZE;
                size_t bin = pool.pagetable[pn]; // not Bins to avoid multiple size extension instructions
				void* base;

                debug(MARK_PRINTF)
                    printf("\t\tfound pool %p, base=%p, pn = %lld, bin = %d\n", pool, pool.baseAddr, cast(long)pn, bin);

                // Adjust bit to be at start of allocated memory block
                if (bin < Bins.B_PAGE)
                {
                    // We don't care abou setting pointsToBase correctly
                    // because it's ignored for small object pools anyhow.
                    auto offsetBase = baseOffset(offset, cast(Bins)bin);
                    biti = offsetBase >> Pool.ShiftBy.Small;
                    //debug(PRINTF) printf("\t\tbiti = x%x\n", biti);

                    if (!pool.mark.testAndSet!false(biti) && !pool.noscan.test(biti))
                    {
						base = pool.baseAddr + offsetBase;
						(*g_references)[base] = rng.pbot;
						(*g_objects)[base] = binsize[bin];

                        tgt.pbot = pool.baseAddr + offsetBase;
                        tgt.ptop = tgt.pbot + binsize[bin];
                        static if (precise)
                        {
                            tgt.pbase = cast(void**)pool.baseAddr;
                            tgt.ptrbmp = pool.is_pointer.data;
                            tgt.bmplength = size_t.max; // no repetition
                        }
                        goto LaddRange;
                    }
                }
                else if (bin == Bins.B_PAGE)
                {
                    biti = offset >> Pool.ShiftBy.Large;
                    //debug(PRINTF) printf("\t\tbiti = x%x\n", biti);

                    pcache = cast(size_t)p & ~cast(size_t)(PAGESIZE-1);
                    tgt.pbot = cast(void*)pcache;

                    // For the NO_INTERIOR attribute.  This tracks whether
                    // the pointer is an interior pointer or points to the
                    // base address of a block.
                    if (tgt.pbot != sentinel_sub(p) && pool.nointerior.nbits && pool.nointerior.test(biti))
                        goto LnextPtr;

                    if (!pool.mark.testAndSet!false(biti) && !pool.noscan.test(biti))
                    {
						base = pool.baseAddr + (offset & ~cast(size_t)(PAGESIZE-1));
						(*g_references)[base] = rng.pbot;
						(*g_objects)[base] = (cast(LargeObjectPool*)pool).getSize(pn);

                        tgt.ptop = tgt.pbot + (cast(LargeObjectPool*)pool).getSize(pn);
                        goto LaddLargeRange;
                    }
                }
                else if (bin == Bins.B_PAGEPLUS)
                {
                    pn -= pool.bPageOffsets[pn];
                    biti = pn * (PAGESIZE >> Pool.ShiftBy.Large);

                    pcache = cast(size_t)p & ~cast(size_t)(PAGESIZE-1);
                    if (pool.nointerior.nbits && pool.nointerior.test(biti))
                        goto LnextPtr;

                    if (!pool.mark.testAndSet!false(biti) && !pool.noscan.test(biti))
                    {
						base = pool.baseAddr + (offset & ~cast(size_t)(PAGESIZE-1));
						(*g_references)[base] = rng.pbot;
						(*g_objects)[base] = (cast(LargeObjectPool*)pool).getSize(pn);

                        tgt.pbot = pool.baseAddr + (pn * PAGESIZE);
                        tgt.ptop = tgt.pbot + (cast(LargeObjectPool*)pool).getSize(pn);
                    LaddLargeRange:
                        static if (precise)
                        {
                            auto rtinfo = pool.rtinfo[biti];
                            if (rtinfo is rtinfoNoPointers)
                                goto LnextPtr; // only if inconsistent with noscan
                            if (rtinfo is rtinfoHasPointers)
                            {
                                tgt.pbase = null; // conservative
                            }
                            else
                            {
                                tgt.ptrbmp = cast(size_t*)rtinfo;
                                size_t element_size = *tgt.ptrbmp++;
                                tgt.bmplength = (element_size + (void*).sizeof - 1) / (void*).sizeof;
                                assert(tgt.bmplength);

                                debug(SENTINEL)
                                    tgt.pbot = sentinel_add(tgt.pbot);
                                if (pool.appendable.test(biti))
                                {
                                    // take advantage of knowing array layout in rt.lifetime
                                    void* arrtop = tgt.pbot + 16 + *cast(size_t*)tgt.pbot;
                                    assert (arrtop > tgt.pbot && arrtop <= tgt.ptop);
                                    tgt.pbot += 16;
                                    tgt.ptop = arrtop;
                                }
                                else
                                {
                                    tgt.ptop = tgt.pbot + element_size;
                                }
                                tgt.pbase = cast(void**)tgt.pbot;
                            }
                        }
                        goto LaddRange;
                    }
                }
                else
                {
                    // Don't mark bits in B_FREE pages
                    assert(bin == Bins.B_FREE);
                }
            }
        LnextPtr:
            rng.pbot += (void*).sizeof;
            if (rng.pbot < rng.ptop)
                continue;

        LnextRange:
            if (stackPos)
            {
                // pop range from local stack and recurse
                rng = stack[--stackPos];
            }
            else
            {
                if (toscan.empty)
                    break; // nothing more to do

                // pop range from global stack and recurse
				static if(__VERSION__ < 2_111)
					rng = toscan.pop();
				else
					toscan.pop(rng);
            }
            // printf("  pop [%p..%p] (%#zx)\n", p1, p2, cast(size_t)p2 - cast(size_t)p1);
            goto LcontRange;

        LaddRange:
            rng.pbot += (void*).sizeof;
            if (rng.pbot < rng.ptop)
            {
                if (stackPos < stack.length)
                {
                    stack[stackPos] = tgt;
                    stackPos++;
                    continue;
                }
                toscan.push(rng);
                // reverse order for depth-first-order traversal
                foreach_reverse (ref range; stack)
                    toscan.push(range);
                stackPos = 0;
            }
        LendOfRange:
            // continue with last found range
            rng = tgt;

        LcontRange:
            pcache = 0;
        }
    }

	/**
	* Search a range of memory values and mark any pointers into the GC pool.
	*/
	version(none)
	void markc(void *pbot, void *ptop) scope nothrow
	{
		void **p1 = cast(void **)pbot;
		void **p2 = cast(void **)ptop;

		// limit the amount of ranges added to the toscan stack
		enum FANOUT_LIMIT = 32;
		size_t stackPos;
		ScanRange[FANOUT_LIMIT] stack = void;

		import core.stdc.stdlib;
		if (&references != *pp_references)
			exit(1);

	Lagain:
		size_t pcache = 0;

		// let dmd allocate a register for this.pools
		const minAddr = pooltable.minAddr;
		const maxAddr = pooltable.maxAddr;

		//printf("marking range: [%p..%p] (%#zx)\n", p1, p2, cast(size_t)p2 - cast(size_t)p1);
	Lnext:
		for (; p1 < p2; p1++)
		{
			auto p = *p1;

			//if (log) debug(PRINTF) printf("\tmark %p\n", p);
			if (p >= minAddr && p < maxAddr)
			{
				if ((cast(size_t)p & ~cast(size_t)(PAGESIZE-1)) == pcache)
					continue;

				Pool* pool = pooltable.findPool(p);
				if (!pool)
					continue;

				size_t offset = cast(size_t)(p - pool.baseAddr);
				size_t biti = void;
				size_t pn = offset / PAGESIZE;
				Bins   bin = cast(Bins)pool.pagetable[pn];
				void* base = void;

				//debug(PRINTF) printf("\t\tfound pool %p, base=%p, pn = %zd, bin = %d, biti = x%x\n", pool, pool.baseAddr, pn, bin, biti);

				// Adjust bit to be at start of allocated memory block
				if (bin < Bins.B_PAGE)
				{
					// We don't care abou setting pointsToBase correctly
					// because it's ignored for small object pools anyhow.
					auto offsetBase = baseOffset(offset, cast(Bins)bin);
					biti = offsetBase >> pool.shiftBy;
					base = pool.baseAddr + offsetBase;
					//debug(PRINTF) printf("\t\tbiti = x%x\n", biti);

					if (!pool.mark.set(biti) && !pool.noscan.test(biti)) {
						references[base] = p1;
						objects[base] = binsize[bin];
						debug(COLLECT_PRINTF) printf("\t\tmark %p -> %p, off=%p\n", p1, base, p - base);
						stack[stackPos++] = ScanRange(base, base + binsize[bin]);
						if (stackPos == stack.length)
							break;
					}
				}
				else if (bin == Bins.B_PAGE)
				{
					auto offsetBase = offset & ~cast(size_t)(PAGESIZE-1);
					base = pool.baseAddr + offsetBase;
					biti = offsetBase >> pool.shiftBy;
					//debug(PRINTF) printf("\t\tbiti = x%x\n", biti);

					pcache = cast(size_t)p & ~cast(size_t)(PAGESIZE-1);

					// For the NO_INTERIOR attribute.  This tracks whether
					// the pointer is an interior pointer or points to the
					// base address of a block.
					bool pointsToBase = (base == sentinel_sub(p));
					if(!pointsToBase && pool.nointerior.nbits && pool.nointerior.test(biti))
						continue;

					if (!pool.mark.set(biti) && !pool.noscan.test(biti)) {
						references[base] = p1;
						objects[base] = pool.bPageOffsets[pn] * PAGESIZE;
						debug(COLLECT_PRINTF) printf("\t\tmark %p -> %p, off=%p\n", p1, base, p - base);
						stack[stackPos++] = ScanRange(base, base + pool.bPageOffsets[pn] * PAGESIZE);
						if (stackPos == stack.length)
							break;
					}
				}
				else if (bin == B_PAGEPLUS)
				{
					pn -= pool.bPageOffsets[pn];
					base = pool.baseAddr + (pn * PAGESIZE);
					biti = pn * (PAGESIZE >> pool.shiftBy);

					pcache = cast(size_t)p & ~cast(size_t)(PAGESIZE-1);
					if(pool.nointerior.nbits && pool.nointerior.test(biti))
						continue;

					if (!pool.mark.set(biti) && !pool.noscan.test(biti)) {
						references[base] = p1;
						objects[base] = pool.bPageOffsets[pn] * PAGESIZE;
						debug(COLLECT_PRINTF) printf("\t\tmark %p -> %p, off=%p\n", p1, base, p - base);
						stack[stackPos++] = ScanRange(base, base + pool.bPageOffsets[pn] * PAGESIZE);
						if (stackPos == stack.length)
							break;
					}
				}
				else
				{
					// Don't mark bits in B_FREE pages
					assert(bin == B_FREE);
					continue;
				}
			}
		}

		ScanRange next=void;
		if (p1 < p2)
		{
			// local stack is full, push it to the global stack
			assert(stackPos == stack.length);
			toscan.push(ScanRange(p1, p2));
			// reverse order for depth-first-order traversal
			foreach_reverse (ref rng; stack[0 .. $ - 1])
				toscan.push(rng);
			stackPos = 0;
			next = stack[$-1];
		}
		else if (stackPos)
		{
			// pop range from local stack and recurse
			next = stack[--stackPos];
		}
		else if (!toscan.empty)
		{
			// pop range from global stack and recurse
			next = toscan.pop();
		}
		else
		{
			// nothing more to do
			return;
		}
		p1 = cast(void**)next.pbot;
		p2 = cast(void**)next.ptop;
		// printf("  pop [%p..%p] (%#zx)\n", p1, p2, cast(size_t)p2 - cast(size_t)p1);
		goto Lagain;
	}

	thread_suspendAll();
	cgc.gcx.prepare(); // set freebits

	if (precise)
	{
		foreach(root; cgc.rootIter)
			mark!true(Gcx.ScanRange!true(&root, &root + 1, null));
		foreach(range; cgc.rangeIter)
			mark!true(Gcx.ScanRange!true(range.pbot, range.ptop, null));
		if (withStacks)
			thread_scanAll((b, t) => mark!true(Gcx.ScanRange!true(b, t)));
	}
	else
	{
		foreach(root; cgc.rootIter)
			mark!false(Gcx.ScanRange!false(&root, &root + 1));
		foreach(range; cgc.rangeIter)
			mark!false(Gcx.ScanRange!false(range.pbot, range.ptop));
		if (withStacks)
			thread_scanAll((b, t) => mark!false(Gcx.ScanRange!false(b, t)));
	}

	toscanConservative.clear();
	toscanPrecise.clear();

	g_cgc = null;
	g_references = null;
	g_objects = null;

	//thread_scanAll(&mark);
	thread_resumeAll();

	cgc.gcLock.unlock();
}

///////////////////////////////////////////////////////////////
void dumpGC(GC _gc)
{
	auto cgc = cast(ConservativeGC) _gc;
	assert(cgc);
	auto gcx = cgc.gcx;

	core.memory.GC.Stats stats = _gc.stats();

	cgc.gcLock.lock();

	trace_printf("Dump of GC %p: %d pools\n", _gc, gcx.pooltable.length);
	trace_printf("Trace buffer memory: %lld bytes\n", cast(long)tracer.traceBuffer.memUsage());

	trace_printf("GC stats: %lld used, %lld free\n", cast(long)stats.usedSize, cast(long)stats.freeSize);

	AddrTracePair[] traceMap = tracer.traceBuffer.createTraceMap();
	memset(addrInfoStat.ptr, 0, addrInfoStat.sizeof);

	thread_suspendAll();
	gcx.prepare(); // set freebits

	void dumpObjectAddrs() scope
	{
		size_t usedSize = 0;
		size_t freeSize = 0;
		foreach (pool; gcx.pooltable[0 .. gcx.pooltable.length])
		{
			foreach (pn, bin; pool.pagetable[0 .. pool.npages])
			{
				if (bin == Bins.B_PAGE)
				{
					auto lpool = cast(LargeObjectPool*) pool;
					size_t npages = lpool.bPageOffsets[pn];

					void* addr = sentinel_add(pool.baseAddr + pn * PAGESIZE);
					dumpAddr(traceMap, addr, npages * PAGESIZE);
					usedSize += npages * PAGESIZE;
				}
				else if (bin == Bins.B_FREE)
				{
					freeSize += PAGESIZE;
				}
				else if (bin < Bins.B_PAGE)
				{
					immutable size = binsize[bin];
					void *p = pool.baseAddr + pn * PAGESIZE;
					void *ptop = p + PAGESIZE;
					immutable base = pn * (PAGESIZE/16);
					immutable bitstride = size / 16;

					for (size_t i; p < ptop; p += size, i += bitstride)
					{
						immutable biti = base + i;

						if (!pool.freebits.test(biti))
						{
							void* addr = sentinel_add(p);
							dumpAddr(traceMap, addr, size);
							usedSize += size;
						}
						else
							freeSize += size;
					}
				}
			}
		}

		trace_printf("Sum of used memory: %lld bytes\n", cast(long)usedSize);
		trace_printf("Sum of free memory: %lld bytes\n", cast(long)freeSize);
	}

	trace_printf("=== GC objects:\n");
	dumpObjectAddrs();
	dumpAddrInfoStat();

	trace_printf("=== GC roots:\n");
	foreach(root; _gc.rootIter)
	{
		if (auto te = tracer.traceBuffer.findTraceEntry(traceMap, root))
		{
			if (StackAddrInfo* ai = te.resolve())
			{
				const(char)* filename = stringBuffer.ptr + ai.filenameOff;
				trace_printf("%s(%d): root %p\n", filename, ai.line, root);
			}
			else
				trace_printf("<unknown-location>: root %p\n", root);
		}
		else
			trace_printf("<unknown-address>: root %p\n", root);
	}

	import core.sys.windows.dbghelp;
	auto dbghelp = DbgHelp.get();
	HANDLE hProcess = GetCurrentProcess();

	void dumpRange(void *pbot, void *ptop) scope nothrow
	{
		bool rangeShown = false;
		for (void** p = cast(void**) pbot; p < ptop; p++)
		{
			void* root = *p;
			if (root < gcx.pooltable.minAddr || root >= gcx.pooltable.maxAddr)
				continue;

			Pool* pool = gcx.pooltable.findPool(root);
			if (!pool)
				continue;

			size_t offset = cast(size_t)(root - pool.baseAddr);
			size_t biti = void;
			size_t pn = offset / PAGESIZE;
			Bins   bin = cast(Bins)pool.pagetable[pn];
			void* base = void;

			if (bin < Bins.B_PAGE)
			{
				auto offsetBase = baseOffset(offset, cast(Bins)bin);
				base = pool.baseAddr + offsetBase;
				biti = offsetBase >> pool.shiftBy;
				if (pool.freebits.test(biti))
					continue;
			}
			else if (bin == Bins.B_PAGE)
			{
				auto offsetBase = offset & ~cast(size_t)(PAGESIZE-1);
				base = pool.baseAddr + offsetBase;
			}
			else if (bin == Bins.B_PAGEPLUS)
			{
				pn -= pool.bPageOffsets[pn];
				base = pool.baseAddr + (pn * PAGESIZE);
			}
			else
				continue; // B_FREE

			if (!rangeShown)
			{
				trace_printf("within range %p - %p:\n", pbot, ptop);
				rangeShown = true;
			}

			if (auto te = tracer.traceBuffer.findTraceEntry(traceMap, base))
			{
				if (StackAddrInfo* ai = te.resolve())
				{
					const(char)* filename = stringBuffer.ptr + ai.filenameOff;
					trace_printf("%s(%d): @range+%llx %p", filename, ai.line, cast(long)(cast(void*)p - pbot), root);
				}
				else
					trace_printf("<unknown-location>: @range+%llx %p", cast(long)(cast(void*)p - pbot), root);
			}
			else
			{
				trace_printf("<unknown-gc-address>: @range+%llx %p", cast(long)(cast(void*)p - pbot), root);
			}

			DWORD64 disp;
			char[300] symbuf;
			auto sym = cast(IMAGEHLP_SYMBOLA64*) symbuf.ptr;
			sym.SizeOfStruct = IMAGEHLP_SYMBOLA64.sizeof;
			sym.MaxNameLength = 300 - IMAGEHLP_SYMBOLA64.sizeof;

			try
			{
				if (dbghelp.SymGetSymFromAddr64(hProcess, cast(size_t)p, &disp, sym))
					trace_printf("    sym %s + %lld", sym.Name.ptr, disp);
			} catch(Exception) {}

			if (root != base)
				trace_printf(" base %p\n", base);
			else
				trace_printf("\n");
		}
	}

	trace_printf("=== GC ranges:\n");
	foreach(range; _gc.rangeIter)
	{
		dumpRange(range.pbot, range.ptop);
	}

	trace_printf("=== stack ranges:\n");
	wipeStack(); // remove anything that might be left by iterating through the GC
	thread_scanAll(&dumpRange);

	tracer.traceBuffer.deleteTraceMap(traceMap);
	thread_resumeAll();

	cgc.gcLock.unlock();

	findRoot(null);
}

shared static this()
{
	import dmd.identifier;
	//Identifier.anonymous();
}

const(char)[] dmdident(ConservativeGC cgc, void* p)
{
	import dmd.dsymbol;
	import dmd.identifier;

	BlkInfo inf = cgc.queryNoSync(p);
	if (inf.base is null || inf.size < Dsymbol.sizeof)
		return null;

	static Identifier dummyIdent;
	if (!dummyIdent)
		dummyIdent = Identifier.generateAnonymousId("ymous");
	auto sym = cast(Dsymbol)p;
	auto ident = sym.ident;
	if (!ident)
		return null;
	BlkInfo syminf = cgc.queryNoSync(cast(void*)ident);
	if (syminf.base is null || syminf.size < Identifier.sizeof)
		return null;
	if (*cast(void**)dummyIdent !is *cast(void**)ident)
		return null; // not an Identifier

	__gshared char[256] buf;
	int len = sprintf(buf.ptr, "%s %.*s", sym.kind(), ident.toString().length, ident.toString().ptr);
	return buf[0..len];
}

bool isInImage(void* p)
{
	import core.internal.traits : externDFunc;
	static if(__VERSION__ < 2_111)
	{
		alias findImageSection = externDFunc!("rt.sections_win64.findImageSection", void[] function(string) nothrow @nogc);
		void[] dataSection = findImageSection(".data");
	}
	else
	{
		alias findImageSection = externDFunc!("rt.sections_win64.findImageSection", void[] function(void*, string) nothrow @nogc);
		void* handle = GetModuleHandle(null); // only executables
		void[] dataSection = findImageSection(handle, ".data");
	}

	if (p - dataSection.ptr < dataSection.length)
		return true;
	return false;
}

const(char)[] dmdtype(ConservativeGC cgc, void* p)
{
	import dmd.mtype;
	import dmd.identifier;

	BlkInfo inf = cgc.queryNoSync(p);
	if (inf.base is null || inf.size < Type.sizeof)
		return null;

	auto vtbl = *cast(void***)p;
	if (!isInImage(vtbl))
		return null;
	auto func = vtbl[5];
	Type type = cast(Type)p;
	if (func != (&type.dyncast).funcptr)
		return null;

	__gshared char[256] buf;
	int len = sprintf(buf.ptr, "type %s %s", type.kind(), type.deco);
	return buf[0..len];
}

void** sobj_in_nongc_mem;

void findRoot(void* sobj)
{
	//sobj = cast(void*)1;
	if (!sobj)
		return;
	// avoid sobj been seen on the stack
	static import core.stdc.stdlib;
	if (!sobj_in_nongc_mem)
		sobj_in_nongc_mem = cast(void**)core.stdc.stdlib.malloc(sobj.sizeof);
	*sobj_in_nongc_mem = sobj;
	sobj = null;

	auto cgc = cast(ConservativeGC) tracer.gc;
	assert(cgc);

	HashTab!(void*, void*) references;
	HashTab!(void*, size_t) objects;

	HashTab!(void*, void*)* preferences = &references;
	pp_references = &preferences;

	collectReferences(cgc, true, true, references, objects);

	const(void*) minAddr = cgc.gcx.pooltable.minAddr;
	const(void*) maxAddr = cgc.gcx.pooltable.maxAddr;

	sobj = *sobj_in_nongc_mem;
	char[256] buf;
nextLoc:
	for ( ; ; )
	{
		TraceEntry* te = tracer.traceBuffer.findTraceEntry(sobj);
		StackAddrInfo* ai;
		if (te && (ai = te.resolve()) !is null)
		{
			const(char)* filename = stringBuffer.ptr + ai.filenameOff;
			auto id = dmdident(cgc, sobj);
			if (!id)
				id = dmdtype(cgc, sobj);
			auto xtra = dumpExtra(sobj);
			if (xtra.length)
				xtrace_printf("%s(%d): %p %.*s\n", filename, ai.line, sobj, xtra.length, xtra.ptr);
			else
				xtrace_printf("%s(%d): %p %.*s\n", filename, ai.line, sobj, id.length, id.ptr);
		}
		else
			xtrace_printf("no location: %p\n", sobj);

		ulong src;
		if (auto psrc = sobj in references)
		{
			BlkInfo info = cgc.queryNoSync(*psrc);
			if (info.base)
			{
				sobj = info.base;
				continue nextLoc;
			}

			for (void* base = *psrc; base >= minAddr && base <= maxAddr; )
			{
				if (auto pobj = base in objects)
				{
					if (*psrc < base + *pobj)
					{
						sobj = base;
						continue nextLoc;
					}
				}
				auto ubase = cast(size_t)base;
				if (ubase & 0xfff)
					base = cast(void*)(ubase ^ (ubase & -ubase)); // clear lowest bit
				else
					base -= 0x1000;
			}
			xtrace_printf("%p not a heap object\n", *psrc);

			DWORD64 disp;
			char[300] symbuf;
			auto sym = cast(IMAGEHLP_SYMBOLA64*) symbuf.ptr;
			sym.SizeOfStruct = IMAGEHLP_SYMBOLA64.sizeof;
			sym.MaxNameLength = 300 - IMAGEHLP_SYMBOLA64.sizeof;

			import core.sys.windows.dbghelp;
			auto dbghelp = DbgHelp.get();
			HANDLE hProcess = GetCurrentProcess();

			if (dbghelp.SymGetSymFromAddr64(hProcess, cast(size_t)*psrc, &disp, sym))
				xtrace_printf("    sym %s + %lld\n", sym.Name.ptr, disp);
		}
		break;
	}
}

} // version(traceGC)

////////////////////////////////////////////////////////////////
private __gshared MonoTime gcStartTick;
private __gshared FILE* gcx_fh;
private __gshared bool hadNewline = false;

int trace_printf(ARGS...)(const char* fmt, ARGS args) nothrow
{
    if (!gcx_fh)
        gcx_fh = fopen("tracegc.log", "w");
    if (!gcx_fh)
        return 0;

    int len;
    if (MonoTime.ticksPerSecond == 0)
    {
        len = fprintf(gcx_fh, "before init: ");
    }
    else if (hadNewline)
    {
        if (gcStartTick == MonoTime.init)
            gcStartTick = MonoTime.currTime;
        immutable timeElapsed = MonoTime.currTime - gcStartTick;
        immutable secondsAsDouble = timeElapsed.total!"hnsecs" / cast(double)convert!("seconds", "hnsecs")(1);
        len = fprintf(gcx_fh, "%10.6lf: ", secondsAsDouble);
    }
    len += fprintf(gcx_fh, fmt, args);
    fflush(gcx_fh);
    import core.stdc.string;
    hadNewline = fmt && fmt[0] && fmt[strlen(fmt) - 1] == '\n';
    return len;
}

int xtrace_printf(ARGS...)(const char* fmt, ARGS args) nothrow
{
	char[1024] buf;
	sprintf(buf.ptr, fmt, args);
	OutputDebugStringA(buf.ptr);

	return trace_printf(fmt, args);
}

