module diamond;

// options
version = MEMSTOMP;  // stomp on memory when it's freed
version = FREECHECK; // checks manual delete operations

version = MEMLOG;    // log memory operations and content 
version = MEMLOG_VERBOSE; // save memory dumps before and after memory operations
const MEMLOG_VERBOSE_STEP = 1000; // do a full memory dump every ... allocations
version = MEMLOG_CRC32; // incremental memory dumps using CRC sums to skip logging memory pages that haven't changed between memory dumps
const LOGDIR = ``;   // path prefix for memory logs

/++
  TODO: add hooks for:
ulong _d_newarrayT(TypeInfo ti, size_t length)
ulong _d_newarrayiT(TypeInfo ti, size_t length)
ulong _d_newarraymT(TypeInfo ti, int ndims, ...)
ulong _d_newarraymiT(TypeInfo ti, int ndims, ...)
byte[] _d_arraysetlengthT(TypeInfo ti, size_t newlength, Array *p)
byte[] _d_arraysetlengthiT(TypeInfo ti, size_t newlength, Array *p)
long _d_arrayappendT(TypeInfo ti, Array *px, byte[] y)
byte[] _d_arrayappendcT(TypeInfo ti, inout byte[] x, ...)
byte[] _d_arraycatT(TypeInfo ti, byte[] x, byte[] y)
byte[] _d_arraycatnT(TypeInfo ti, uint n, ...)
void* _d_arrayliteralT(TypeInfo ti, size_t length, ...)
long _adDupT(TypeInfo ti, Array2 a) - ?
+/

// system configuration
version(linux) const _SC_PAGE_SIZE = 30;  // IMPORTANT: may require changing on your platform, look it up in your C headers

private:

version(Tango)
{
	import tango.core.Memory;
	import tango.stdc.stdio;
	import tango.stdc.stdlib : stdmalloc = malloc;
	version(Windows) import tango.sys.win32.UserGdi : VirtualProtect, PAGE_EXECUTE_WRITECOPY;
	else import tango.stdc.posix.sys.mman : mprotect, PROT_READ, PROT_WRITE, PROT_EXEC;
	version(MEMLOG) import tango.stdc.time;

	// IMPORTANT: add .../tango/lib/gc/basic to the module search path
	import gcbits;
	import gcx;
	import gcstats;
	alias gcx.GC GC;

	extern (C) void* rt_stackBottom();
	alias rt_stackBottom os_query_stackBottom;

	extern(C) extern void* D2gc3_gcC3gcx2GC;
	alias D2gc3_gcC3gcx2GC gc;
}
else
{
	import std.gc;
	import std.c.stdio;
	import std.c.stdlib : stdmalloc = malloc;
	version(Windows) import std.c.windows.windows : VirtualProtect, PAGE_EXECUTE_WRITECOPY;
	else import std.c.linux.linux : mprotect, PROT_READ, PROT_WRITE, PROT_EXEC;
	version(MEMLOG) import std.c.time;

	// IMPORTANT: if the imports below don't work, remove "internal.gc." and add ".../dmd/src/phobos/internal/gc" to the module search path
	version (Win32) import internal.gc.win32;
	version (linux) import internal.gc.gclinux;
	import internal.gc.gcbits;
	import internal.gc.gcx;
	import gcstats;
	alias getGCHandle gc;
}

// configuration ends here

// ****************************************************************************

struct Array // D underlying array type
{
	size_t length;
	byte *data;
}

void** ebp()
{
	asm
	{
		naked;
		mov EAX, EBP;
		ret;
	}
}

void* esp()
{
	asm
	{
		naked;
		mov EAX, ESP;
		ret;
	}
}

public void printStackTrace()
{
	auto bottom = os_query_stackBottom();
	for (void** p=ebp();p;p=cast(void**)*p)
	{
		printf("%08X\n", *(p+1));
		if (*p <= p || *p > bottom)
			break;
	}
}

version(MEMLOG)
{
	FILE* log;

	void logDword(uint  i) { fwrite(&i, 4, 1, log); }		
	void logDword(void* i) { fwrite(&i, 4, 1, log); }
	void logData(void[] d) { fwrite(d.ptr, d.length, 1, log); }
	void logBits(ref GCBits bits) { logDword(bits.nwords); if (bits.nbits) logData(bits.data[1..1+bits.nwords]); }

	void logStackTrace()
	{
		auto bottom = os_query_stackBottom();
		for (void** p=ebp();p;p=cast(void**)*p)
		{
			if (*(p+1))
				logDword(*(p+1));
			if (*p <= p || *p > bottom)
				break;
		}
		logDword(null);
	}
	
	enum : int
	{
		PACKET_MALLOC,
		PACKET_CALLOC,
		PACKET_REALLOC,
		PACKET_EXTEND,
		PACKET_FREE,
		PACKET_MEMORY_DUMP,
		PACKET_MEMORY_MAP,
		PACKET_TEXT,
		PACKET_NEWCLASS, // metainfo
	}

	Object logsync;
}

// ****************************************************************************

version(Windows)
{
	bool makeWritable(void* address, size_t size)
	{
		uint old; 
		return VirtualProtect(address, size, PAGE_EXECUTE_WRITECOPY, &old) != 0;
	}
}
else
{   
	extern (C) int sysconf(int);	
	bool makeWritable(void* address, size_t size)
	{
		uint pageSize = sysconf(_SC_PAGE_SIZE);
		address = cast(void*)((cast(uint)address) & ~(pageSize-1));
		int pageCount = (cast(size_t)address/pageSize == (cast(size_t)address+size)/pageSize) ? 1 : 2;
		return mprotect(address, pageSize * pageCount, PROT_READ | PROT_WRITE | PROT_EXEC) == 0;
	}
}

static uint calcDist(void* from, void* to) { return cast(ubyte*)to - cast(ubyte*)from; }

template Hook(TargetType, HandlerType)
{
	static ubyte[] target;
	static ubyte[5] oldcode, newcode;
	static void initialize(TargetType addr, HandlerType fn)
	{
		target = cast(ubyte[])(cast(void*)addr)[0..5];
		oldcode[] = target;
		newcode[0] = 0xE9; // long jump
		*cast(uint*)&newcode[1] = calcDist(target.ptr+5, fn);
		auto b = makeWritable(target.ptr, target.length);
		assert(b);
		hook();
	}

	static void hook() { target[] = newcode; }
	static void unhook() { target[] = oldcode; }
}

/// Hook a function by overwriting the first bytes with a jump to your handler. Calls the original by temporarily restoring the hook (caller needs to do that manually due to the way arguments are passed on).
/// WARNING: this may only work with the calling conventions specified in the D documentation ( http://www.digitalmars.com/d/1.0/abi.html ), thus may not work with GDC
struct FunctionHook(int uniqueID, ReturnType, Args ...)
{
	mixin Hook!(ReturnType function(Args), ReturnType function(Args));
}

/// The last argument of the handler is the context.
struct MethodHook(int uniqueID, ReturnType, ContextType, Args ...)
{
	mixin Hook!(ReturnType function(Args), ReturnType function(Args, ContextType));
}

/// Hook for extern(C) functions.
struct CFunctionHook(int uniqueID, ReturnType, Args ...)
{
	extern(C) alias ReturnType function(Args) FunctionType;
	mixin Hook!(FunctionType, FunctionType);
}

MethodHook!(1, size_t, Gcx*, void*) fullcollectHook;
version(MEMSTOMP)
{
	CFunctionHook!(2, byte[], TypeInfo, size_t, Array*) arraysetlengthTHook;	
	CFunctionHook!(3, byte[], TypeInfo, size_t, Array*) arraysetlengthiTHook;
}
version(MEMLOG)
{
	CFunctionHook!(1, Object, ClassInfo) newclassHook;
}

// ****************************************************************************

void enforce(bool condition, char[] message)
{
	if (!condition)
	{
		//printStackTrace();
		throw new Exception(message);
	}
}

final class DiamondGC : GC
{
	// note: we can't add fields here because we are overwriting the original class's virtual call table
	
	final void mallocHandler(size_t size, void* p)
	{
		//printf("Allocated %d bytes at %08X\n", size, p); printStackTrace();
		version(MEMLOG) synchronized(logsync)
			if (p)
			{
				logDword(PACKET_MALLOC);
				logDword(time(null));
				logStackTrace();
				logDword(p);
				logDword(size);			
			}
		version(MEMLOG_VERBOSE) verboseLog();
	}

	final void callocHandler(size_t size, void* p)
	{
		//printf("Allocated %d initialized bytes at %08X\n", size, p); printStackTrace();
		version(MEMLOG) synchronized(logsync)
			if (p)
			{
				logDword(PACKET_CALLOC);
				logDword(time(null));
				logStackTrace();
				logDword(p);			
				logDword(size);			
			}
		version(MEMLOG_VERBOSE) verboseLog();
	}

	final void reallocHandler(size_t size, void* p1, void* p2)
	{
		//printf("Reallocated %d bytes from %08X to %08X\n", size, p1, p2); printStackTrace();
		version(MEMLOG) synchronized(logsync)
			if (p2)
			{
				logDword(PACKET_REALLOC);
				logDword(time(null));
				logStackTrace();
				logDword(p1);
				logDword(p2);
				logDword(size);			
			}
		version(MEMLOG_VERBOSE) verboseLog();
	}

	override size_t extend(void* p, size_t minsize, size_t maxsize) 
	{
		auto result = super.extend(p, minsize, maxsize); 
		version(MEMLOG) synchronized(logsync)
			if (result)
			{
				logDword(PACKET_EXTEND);
				logDword(time(null));
				logStackTrace();
				logDword(p);
				logDword(result);
			}
		version(MEMLOG_VERBOSE) verboseLog();
		return result;
	}

	override void free(void *p) 
	{ 
		version(FREECHECK)
		{
			Pool* pool = gcx.findPool(p);
			enforce(pool !is null, "Freed item is not in a pool");

			uint pagenum = (p - pool.baseAddr) / PAGESIZE;
			Bins bin = cast(Bins)pool.pagetable[pagenum];
			enforce(bin <= B_PAGE, "Freed item is not in an allocated page");
			
			size_t size = binsize[bin];
			enforce((cast(size_t)p & (size - 1)) == 0, "Freed item is not aligned to bin boundary");

			if (bin < B_PAGE)  // Check that p is not on a free list
				for (List *list = gcx.bucket[bin]; list; list = list.next)
					enforce(cast(void *)list != p, "Freed item is on a free list");
		}
		version(MEMLOG) synchronized(logsync)
		{
			logDword(PACKET_FREE);
			logDword(time(null));
			logStackTrace();
			logDword(p);
		}
		version(MEMLOG_VERBOSE) verboseLog();
		version(MEMSTOMP)
		{
			auto c = capacity(p);
			super.free(p);
			if (c>4)
				(cast(ubyte*)p)[4..c] = 0xBD;
		}
		else
			super.free(p); 
		version(MEMLOG_VERBOSE) verboseLog();
	}

	version(Tango)
	{
		override void *malloc(size_t size, uint bits) { version(MEMLOG_VERBOSE) verboseLog(); auto result = super.malloc(size, bits); mallocHandler(size, result); return result; }
		override void *calloc(size_t size, uint bits) { version(MEMLOG_VERBOSE) verboseLog(); auto result = super.calloc(size, bits); callocHandler(size, result); return result; }
		override void *realloc(void *p, size_t size, uint bits) { version(MEMLOG_VERBOSE) verboseLog(); auto result = super.realloc(p, size, bits); reallocHandler(size, p, result); return result; }
		alias sizeOf capacity;
	}
	else
	{
		override void *malloc(size_t size) { version(MEMLOG_VERBOSE) verboseLog(); auto result = super.malloc(size); mallocHandler(size, result); return result; }
		override void *calloc(size_t size, size_t n) { version(MEMLOG_VERBOSE) verboseLog(); auto result = super.calloc(size, n); callocHandler(size*n, result); return result; }
		override void *realloc(void *p, size_t size) { version(MEMLOG_VERBOSE) verboseLog(); auto result = super.realloc(p, size); reallocHandler(size, p, result); return result; }
	}
}

version(MEMLOG)
{
	const uint FORMAT_VERSION = 4; // format of the log file

	version(MEMLOG_CRC32)
	{
		const MAX_POOLS = 1024;
		uint*[MAX_POOLS] poolCRCs;

		uint[256] crc32_table = [0x00000000,0x77073096,0xee0e612c,0x990951ba,0x076dc419,0x706af48f,0xe963a535,0x9e6495a3,0x0edb8832,0x79dcb8a4,0xe0d5e91e,0x97d2d988,0x09b64c2b,0x7eb17cbd,0xe7b82d07,0x90bf1d91,0x1db71064,0x6ab020f2,0xf3b97148,0x84be41de,0x1adad47d,0x6ddde4eb,0xf4d4b551,0x83d385c7,0x136c9856,0x646ba8c0,0xfd62f97a,0x8a65c9ec,0x14015c4f,0x63066cd9,0xfa0f3d63,0x8d080df5,0x3b6e20c8,0x4c69105e,0xd56041e4,0xa2677172,0x3c03e4d1,0x4b04d447,0xd20d85fd,0xa50ab56b,0x35b5a8fa,0x42b2986c,0xdbbbc9d6,0xacbcf940,0x32d86ce3,0x45df5c75,0xdcd60dcf,0xabd13d59,0x26d930ac,0x51de003a,0xc8d75180,0xbfd06116,0x21b4f4b5,0x56b3c423,0xcfba9599,0xb8bda50f,0x2802b89e,0x5f058808,0xc60cd9b2,0xb10be924,0x2f6f7c87,0x58684c11,0xc1611dab,0xb6662d3d,0x76dc4190,0x01db7106,0x98d220bc,0xefd5102a,0x71b18589,0x06b6b51f,0x9fbfe4a5,0xe8b8d433,0x7807c9a2,0x0f00f934,0x9609a88e,0xe10e9818,0x7f6a0dbb,0x086d3d2d,0x91646c97,0xe6635c01,0x6b6b51f4,0x1c6c6162,0x856530d8,0xf262004e,0x6c0695ed,0x1b01a57b,0x8208f4c1,0xf50fc457,0x65b0d9c6,0x12b7e950,0x8bbeb8ea,0xfcb9887c,0x62dd1ddf,0x15da2d49,0x8cd37cf3,0xfbd44c65,0x4db26158,0x3ab551ce,0xa3bc0074,0xd4bb30e2,0x4adfa541,0x3dd895d7,0xa4d1c46d,0xd3d6f4fb,0x4369e96a,0x346ed9fc,0xad678846,0xda60b8d0,0x44042d73,0x33031de5,0xaa0a4c5f,0xdd0d7cc9,0x5005713c,0x270241aa,0xbe0b1010,0xc90c2086,0x5768b525,0x206f85b3,0xb966d409,0xce61e49f,0x5edef90e,0x29d9c998,0xb0d09822,0xc7d7a8b4,0x59b33d17,0x2eb40d81,0xb7bd5c3b,0xc0ba6cad,0xedb88320,0x9abfb3b6,0x03b6e20c,0x74b1d29a,0xead54739,0x9dd277af,0x04db2615,0x73dc1683,0xe3630b12,0x94643b84,0x0d6d6a3e,0x7a6a5aa8,0xe40ecf0b,0x9309ff9d,0x0a00ae27,0x7d079eb1,0xf00f9344,0x8708a3d2,0x1e01f268,0x6906c2fe,0xf762575d,0x806567cb,0x196c3671,0x6e6b06e7,0xfed41b76,0x89d32be0,0x10da7a5a,0x67dd4acc,0xf9b9df6f,0x8ebeeff9,0x17b7be43,0x60b08ed5,0xd6d6a3e8,0xa1d1937e,0x38d8c2c4,0x4fdff252,0xd1bb67f1,0xa6bc5767,0x3fb506dd,0x48b2364b,0xd80d2bda,0xaf0a1b4c,0x36034af6,0x41047a60,0xdf60efc3,0xa867df55,0x316e8eef,0x4669be79,0xcb61b38c,0xbc66831a,0x256fd2a0,0x5268e236,0xcc0c7795,0xbb0b4703,0x220216b9,0x5505262f,0xc5ba3bbe,0xb2bd0b28,0x2bb45a92,0x5cb36a04,0xc2d7ffa7,0xb5d0cf31,0x2cd99e8b,0x5bdeae1d,0x9b64c2b0,0xec63f226,0x756aa39c,0x026d930a,0x9c0906a9,0xeb0e363f,0x72076785,0x05005713,0x95bf4a82,0xe2b87a14,0x7bb12bae,0x0cb61b38,0x92d28e9b,0xe5d5be0d,0x7cdcefb7,0x0bdbdf21,0x86d3d2d4,0xf1d4e242,0x68ddb3f8,0x1fda836e,0x81be16cd,0xf6b9265b,0x6fb077e1,0x18b74777,0x88085ae6,0xff0f6a70,0x66063bca,0x11010b5c,0x8f659eff,0xf862ae69,0x616bffd3,0x166ccf45,0xa00ae278,0xd70dd2ee,0x4e048354,0x3903b3c2,0xa7672661,0xd06016f7,0x4969474d,0x3e6e77db,0xaed16a4a,0xd9d65adc,0x40df0b66,0x37d83bf0,0xa9bcae53,0xdebb9ec5,0x47b2cf7f,0x30b5ffe9,0xbdbdf21c,0xcabac28a,0x53b39330,0x24b4a3a6,0xbad03605,0xcdd70693,0x54de5729,0x23d967bf,0xb3667a2e,0xc4614ab8,0x5d681b02,0x2a6f2b94,0xb40bbe37,0xc30c8ea1,0x5a05df1b,0x2d02ef8d];
		uint fastCRC(void[] data) // we can't use the standard Phobos crc32 function because we can't rely on inlining being available (because it's natural to compile debuggees without optimizations), and calling a function for every byte would be too slow
		{
			uint crc = cast(uint)-1;
			foreach (ubyte val;cast(ubyte[])data)
				crc = crc32_table[cast(ubyte) crc ^ val] ^ (crc >> 8);
			return crc;
		}
	}

	extern(C) public void logMemoryDump(bool dataDump, Gcx* gcx = null)
	{
		synchronized(logsync)
		{
			//dataDump ? printf("Dumping memory contents...\n") : printf("Dumping memory map...\n");
			if (gcx is null) gcx = (cast(GC)gc).gcx;
			logDword(dataDump ? PACKET_MEMORY_DUMP : PACKET_MEMORY_MAP);
			logDword(time(null));
			logStackTrace();
			
			// log stack
			void* stackTop = esp();
			void* stackBottom = gcx.stackBottom;
			logDword(stackTop);
			logDword(stackBottom);
			logDword(ebp);
			if (dataDump)
				logData(stackTop[0..stackBottom-stackTop]);

			void logRoots(void* bottom, void* top)
			{
				logDword(bottom);
				logDword(top);
				if (dataDump)
					if (gcx.findPool(bottom)) // in heap?
						logDword(0);
					else
					{
						logDword(1);
						logData(bottom[0..cast(ubyte*)top-cast(ubyte*)bottom]);
					}
			}
			logDword(gcx.nranges+1);
			logRoots(gcx.roots, gcx.roots + gcx.nroots);
			foreach (ref range; gcx.ranges[0..gcx.nranges])
				logRoots(range.pbot, range.ptop);
			
			logDword(gcx.npools);
			for (int pn=0;pn<gcx.npools;pn++)
			{
				auto p = gcx.pooltable[pn];
				logDword(p.baseAddr);
				logDword(p.npages);
				logDword(p.ncommitted);
				logData(p.pagetable[0..p.npages]);
				logBits(p.freebits);
				logBits(p.finals);
				logBits(p.noscan);
				if (dataDump)
				{
					version(MEMLOG_CRC32)
					{
						assert(pn < MAX_POOLS);
						if (poolCRCs[pn] is null)
						{
							poolCRCs[pn] = cast(uint*)stdmalloc(4*p.npages);
							poolCRCs[pn][0..p.npages] = 0;
						}
					}
					for (int pg=0;pg<p.ncommitted;pg++)
					{
						bool doSave = true;
						auto page = p.baseAddr[pg*PAGESIZE..(pg+1)*PAGESIZE];
						version(MEMLOG_CRC32)
						{
							uint newCRC = fastCRC(page);
							if (newCRC==poolCRCs[pn][pg] && newCRC!=0)
								doSave = false;
							else
								poolCRCs[pn][pg] = newCRC;
						}
						logDword(doSave?1:0);
						if (doSave)
							logData(page);
					}
				}
			}
			if (dataDump)
				logData(gcx.bucket);
			fflush(log);
			//printf("Done\n");
		}
	}

	version(MEMLOG_VERBOSE)
		void verboseLog()
		{
			static int n = 0;
			if (n++ % MEMLOG_VERBOSE_STEP == 0)
				logMemoryDump(true);
		}

	extern(C) public void logText(char[] text)
	{
		synchronized(logsync)
		{
			logDword(PACKET_TEXT);
			logDword(time(null));
			logStackTrace();
			logDword(text.length);
			logData(text);
		}
	}

	extern(C) public void logNumber(uint n)
	{
		char[24] buf;
		sprintf(buf.ptr, "%08X (%d)", n, n);
		for (int i=12;i<buf.length;i++)
			if (!buf[i])
				return logText(buf[0..i]);
	}
}

size_t fullcollectHandler(void* stackTop, Gcx* gcx)
{
	//printf("minaddr=%08X maxaddr=%08X\n", gcx.minAddr, gcx.maxAddr);	
	//printf("Beginning garbage collection\n");	
	version(MEMLOG) logMemoryDump(true, gcx);
	fullcollectHook.unhook();
	auto result = gcx.fullcollect(stackTop);
	fullcollectHook.hook();
	version(MEMLOG) logMemoryDump(false, gcx);
	//printf("Garbage collection done, %d pages freed\n", result);
	return result;
}

version(MEMSTOMP)
{
	// stomp on shrunk arrays
	 
	extern(C) extern byte[] _d_arraysetlengthT(TypeInfo ti, size_t newlength, Array *p);
	extern(C) extern byte[] _d_arraysetlengthiT(TypeInfo ti, size_t newlength, Array *p);

	extern(C) byte[] arraysetlengthTHandler(TypeInfo ti, size_t newlength, Array *p)
	{
		Array old = *p;
		arraysetlengthTHook.unhook();
		auto result = _d_arraysetlengthT(ti, newlength, p);
		arraysetlengthTHook.hook();
		//printf("_d_arraysetlengthT: %d => %d\n", oldlength, p.length);
		size_t sizeelem = ti.next.tsize();
		if (old.data == p.data && p.length < old.length)
			(cast(ubyte*)p.data)[p.length*sizeelem .. old.length*sizeelem] = 0xBD;
		return result;
	}

	extern(C) byte[] arraysetlengthiTHandler(TypeInfo ti, size_t newlength, Array *p)
	{
		Array old = *p;
		arraysetlengthiTHook.unhook();
		auto result = _d_arraysetlengthiT(ti, newlength, p);
		arraysetlengthiTHook.hook();
		//printf("_d_arraysetlengthiT: %d => %d\n", oldlength, p.length);
		size_t sizeelem = ti.next.tsize();
		if (old.data == p.data && p.length < old.length)
			(cast(ubyte*)p.data)[p.length*sizeelem .. old.length*sizeelem] = 0xBD;
		return result;
	}
}

version(MEMLOG)
{
	extern(C) extern Object _d_newclass(ClassInfo ci);

	extern(C) Object newclassHandler(ClassInfo ci)
	{
		if ((ci.flags & 1)==0)
			synchronized(logsync)
			{
				logDword(PACKET_NEWCLASS);
				logDword(ci.name.length);
				logData(ci.name);
			}
		newclassHook.unhook();
		auto result = _d_newclass(ci);
		newclassHook.hook();
		return result;
	}
	
}

// ****************************************************************************

static this()
{
	version(MEMLOG) logsync = new Object;
	// replace the garbage collector Vtable
	*cast(void**)gc = DiamondGC.classinfo.vtbl.ptr;

	fullcollectHook.initialize(&Gcx.fullcollect, &fullcollectHandler);
	version(MEMSTOMP)
	{
		arraysetlengthTHook.initialize(&_d_arraysetlengthT, &arraysetlengthTHandler);
		arraysetlengthiTHook.initialize(&_d_arraysetlengthiT, &arraysetlengthiTHandler);
	}
	version(MEMLOG)
	{
		newclassHook.initialize(&_d_newclass, &newclassHandler);
		time_t t = time(null);
		tm *tm = localtime(&t);
		char[256] name;
		sprintf(name.ptr, "%sdiamond_%d-%02d-%02d_%02d.%02d.%02d.mem", LOGDIR.length?LOGDIR.ptr:"", 1900+tm.tm_year, tm.tm_mon, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
		log = fopen(name.ptr, "wb");
		logDword(FORMAT_VERSION);
	}
}

static ~this()
{
	version(MEMLOG) 
	{
		//printf("Closing memory log...\n");
		fclose(log);
	}
}
