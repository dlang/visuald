module tracegc;

import core.stdc.string;

//version = traceGC;

// tiny helper to clear a page of the stack below the current stack pointer to avoid false pointers there
void wipeStack()
{
	char[4096] data = void;
	memset (data.ptr, 0xff, 4096);
}

version(traceGC):
import core.sys.windows.windows;
import core.stdc.stdio;
import gc.impl.conservative.gc;
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
		r"\core\memory.d",
		r"\std\array.d",
		r"\ddmd\root\rmem.d",
		r"\ddmd\root\array.d",
		r"\ddmd\root\aav.d",
		r"\ddmd\root\outbuffer.d",
		r"\ddmd\root\stringtable.d",
		r"\stdext\com.d",
		r"\ddmdrmem.d",
	];
	foreach (ex; excl)
		if (flen > ex.length && fn[flen - ex.length .. flen] == ex)
			return false;

	return true;
}

////////////////////////////////////////////////////////////

import gc.gcinterface;
import gc.os;
import core.exception;

class GCTraceProxy : GC
{
	GC gc;

	void Dtor()
	{
		gc.Dtor();
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

	BlkInfo qalloc(size_t size, uint bits, const TypeInfo ti) nothrow
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

	void runFinalizers(in void[] segment) nothrow
	{
		return gc.runFinalizers(segment);
	}

	bool inFinalizer() nothrow
	{
		return gc.inFinalizer();
	}

	TraceBuffer traceBuffer;
}

///////////////////////////////////////////////////////////
static struct TraceEntry
{
	void* addr;
	size_t[15] buffer;

	StackAddrInfo* resolve() nothrow
	{
		for (size_t sp = 0; sp < buffer.length && buffer[sp]; sp++)
		{
			StackAddrInfo* ai = resolveAddr(buffer[sp]);
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

import core.demangle;
extern pragma(mangle, mangle!GC("gc.proxy.instance")) __gshared GC gc_instance;

__gshared GCTraceProxy tracer = new GCTraceProxy;

extern(C) void gc_init()
{
	import gc.config;

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

void traceAlloc(void* addr) nothrow
{
	TraceEntry te;

	te.addr = addr;
	auto backtraceLength = RtlCaptureStackBackTrace(2, cast(ULONG)te.buffer.length, cast(void**)te.buffer.ptr, null);

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

	gc.impl.conservative.gc.printf("%s(%d): %p %llx\n", filename, line, addr, cast(long) size);
	//sprintf(buf.ptr, "%s(%d): %p %llx\n", filename, line, addr, cast(long) size);
	//OutputDebugStringA(buf.ptr);
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

	OutputDebugStringA("Dump combined by stack location:\n");

	foreach(ref info; addrInfoStat)
		if (info.ai)
		{
			const(char)* filename = stringBuffer.ptr + info.ai.filenameOff;
			sprintf(buf.ptr, "%s(%d): %lld allocs %llx bytes\n", filename, info.ai.line, cast(long)info.count, cast(long)info.size);
			OutputDebugStringA(buf.ptr);
		}

}

///////////////////////////////////////////////////////////////
import rt.util.container.hashtab;

void collectReferences(ConservativeGC cgc, ref HashTab!(void*, void*) references, ref HashTab!(void*, size_t) objects)
{
	auto gcx = cgc.gcx;

	cgc.gcLock.lock();
	auto pooltable = gcx.pooltable;

	alias ScanRange = gc.gcinterface.Range;

	Gcx.ToScanStack toscan;

	/**
	* Search a range of memory values and mark any pointers into the GC pool.
	*/
	void mark(void *pbot, void *ptop) scope nothrow
	{
		void **p1 = cast(void **)pbot;
		void **p2 = cast(void **)ptop;

		// limit the amount of ranges added to the toscan stack
		enum FANOUT_LIMIT = 32;
		size_t stackPos;
		ScanRange[FANOUT_LIMIT] stack = void;

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
				if (bin < B_PAGE)
				{
					// We don't care abou setting pointsToBase correctly
					// because it's ignored for small object pools anyhow.
					auto offsetBase = offset & notbinsize[bin];
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
				else if (bin == B_PAGE)
				{
					auto offsetBase = offset & notbinsize[bin];
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
	gcx.prepare(); // set freebits

	foreach(root; cgc.rootIter)
		mark(&root, &root + 1);
	foreach(range; cgc.rangeIter)
		mark(range.pbot, range.ptop);

	thread_scanAll(&mark);
	thread_resumeAll();

	cgc.gcLock.unlock();
}

///////////////////////////////////////////////////////////////
void dumpGC(GC _gc)
{
	auto cgc = cast(ConservativeGC) _gc;
	assert(cgc);
	auto gcx = cgc.gcx;

	cgc.gcLock.lock();

	char[256] buf;
	sprintf(buf.ptr, "Dump of GC %p: %d pools\n", _gc, gcx.npools);
	OutputDebugStringA(buf.ptr);
	sprintf(buf.ptr, "Trace buffer memory: %lld bytes\n", cast(long)tracer.traceBuffer.memUsage());
	OutputDebugStringA(buf.ptr);

	AddrTracePair[] traceMap = tracer.traceBuffer.createTraceMap();
	memset(addrInfoStat.ptr, 0, addrInfoStat.sizeof);

	thread_suspendAll();
	gcx.prepare(); // set freebits

	void dumpObjectAddrs() scope
	{
		size_t usedSize = 0;
		size_t freeSize = 0;
		foreach (pool; gcx.pooltable[0 .. gcx.npools])
		{
			foreach (pn, bin; pool.pagetable[0 .. pool.npages])
			{
				if (bin == B_PAGE)
				{
					auto lpool = cast(LargeObjectPool*) pool;
					size_t npages = lpool.bPageOffsets[pn];

					void* addr = sentinel_add(pool.baseAddr + pn * PAGESIZE);
					dumpAddr(traceMap, addr, npages * PAGESIZE);
					usedSize += npages * PAGESIZE;
				}
				else if (bin == B_FREE)
				{
					freeSize += PAGESIZE;
				}
				else if (bin < B_PAGE)
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

		sprintf(buf.ptr, "Sum of used memory: %lld bytes\n", cast(long)usedSize);
		OutputDebugStringA(buf.ptr);
		sprintf(buf.ptr, "Sum of free memory: %lld bytes\n", cast(long)freeSize);
		OutputDebugStringA(buf.ptr);
	}

	dumpObjectAddrs();
	dumpAddrInfoStat();

	foreach(root; _gc.rootIter)
	{
		if (auto te = tracer.traceBuffer.findTraceEntry(traceMap, root))
		{
			if (StackAddrInfo* ai = te.resolve())
			{
				const(char)* filename = stringBuffer.ptr + ai.filenameOff;
				sprintf(buf.ptr, "%s(%d): root %p\n", filename, ai.line, root);
			}
			else
				sprintf(buf.ptr, "<unknown-location>: root %p\n", root);
		}
		else
			sprintf(buf.ptr, "<unknown-address>: root %p\n", root);

		OutputDebugStringA(buf.ptr);
	}

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

			if (bin < B_PAGE)
			{
				auto offsetBase = offset & notbinsize[bin];
				base = pool.baseAddr + offsetBase;
				biti = offsetBase >> pool.shiftBy;
				if (pool.freebits.test(biti))
					continue;
			}
			else if (bin == B_PAGE)
			{
				auto offsetBase = offset & notbinsize[bin];
				base = pool.baseAddr + offsetBase;
			}
			else if (bin == B_PAGEPLUS)
			{
				pn -= pool.bPageOffsets[pn];
				base = pool.baseAddr + (pn * PAGESIZE);
			}
			else
				continue; // B_FREE

			if (!rangeShown)
			{
				sprintf(buf.ptr, "within range %p - %p:\n", pbot, ptop);
				OutputDebugStringA(buf.ptr);
				rangeShown = true;
			}
			int len;
			if (auto te = tracer.traceBuffer.findTraceEntry(traceMap, base))
			{
				if (StackAddrInfo* ai = te.resolve())
				{
					const(char)* filename = stringBuffer.ptr + ai.filenameOff;
					len = sprintf(buf.ptr, "%s(%d): @range+%llx %p", filename, ai.line, cast(long)(cast(void*)p - pbot), root);
				}
				else
					len = sprintf(buf.ptr, "<unknown-location>: @range+%llx %p", cast(long)(cast(void*)p - pbot), root);
			}
			else
			{
				len = sprintf(buf.ptr, "<unknown-gc-address>: @range+%llx %p", cast(long)(cast(void*)p - pbot), root);
			}

			if (root != base)
				len += sprintf(buf.ptr + len, " base %p", base);
			buf.ptr[len++] = '\n';
			buf.ptr[len] = 0;
			OutputDebugStringA(buf.ptr);
		}
	}
	foreach(range; _gc.rangeIter)
	{
		dumpRange(range.pbot, range.ptop);
	}

	wipeStack(); // remove anything that might be left by iterating through the GC
	thread_scanAll(&dumpRange);

	tracer.traceBuffer.deleteTraceMap(traceMap);
	thread_resumeAll();

	cgc.gcLock.unlock();

	findRoot(null);
}

void findRoot(void* sobj)
{
	if (!sobj)
		return;

	auto cgc = cast(ConservativeGC) tracer.gc;
	assert(cgc);

	HashTab!(void*, void*) references;
	HashTab!(void*, size_t) objects;
	collectReferences(cgc, references, objects);

	const(void*) minAddr = cgc.gcx.pooltable.minAddr;
	const(void*) maxAddr = cgc.gcx.pooltable.maxAddr;

	char[256] buf;
nextLoc:
	for ( ; ; )
	{
		TraceEntry* te = tracer.traceBuffer.findTraceEntry(sobj);
		StackAddrInfo* ai;
		if (te && (ai = te.resolve()) !is null)
		{
			const(char)* filename = stringBuffer.ptr + ai.filenameOff;
			sprintf(buf.ptr, "%s(%d): %p\n", filename, ai.line, sobj);
		}
		else
			sprintf(buf.ptr, "no location: %p\n", sobj);
		OutputDebugStringA(buf.ptr);

		ulong src;
		if (auto psrc = sobj in references)
		{
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
			sprintf(buf.ptr, "%p not a heap object\n", *psrc);
			OutputDebugStringA(buf.ptr);
		}
		break;
	}
}
