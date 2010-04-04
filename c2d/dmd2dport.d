module dmd2dport;

public 
{
	import std.c.stdio;
	import std.c.stdlib;
	import std.stdint;
	import std.bitmanip;
	import std.c.windows.windows;
	import std.c.string;
	import std.c.time;
	import std.ctype;
	import std.file;
	import std.math;
	import std.string;
	import std.md5;
	
	import core.stdc.errno;
	import core.bitop;
	import core.stdc.fenv;
	import core.stdc.complex;
	import core.stdc.tgmath : fmod;
	import core.stdc.math : fmodl, fmodf;
	import std.c.process;
}

alias wchar wchar_t;
alias void* va_list;

alias std.c.string.strlen std_strlen;
alias std.c.string.strcpy std_strcpy;
alias std.file.mkdir      std_mkdir;
alias std.file.getcwd     std_getcwd;
alias std.c.stdlib.malloc std_malloc;
alias std.c.stdlib.calloc std_calloc;
alias std.c.stdlib.realloc std_realloc;
alias std.c.stdlib.free   std_free;

alias fabs _inline_fabs;
alias fabs _inline_fabsl;
alias fabs _inline_fabsf;
alias sqrt _inline_sqrt;
alias sqrt _inline_sqrtl;
alias sin  _inline_sinl;
alias cos  _inline_cosl;
alias tan  tanl;

alias btr  _inline_btr;
alias bt   _inline_bt;
alias bts  _inline_bts;

alias std.c.stdlib.exit exit;

real creall(creal c) { return c.re; }
real cimagl(creal c) { return c.im; }

/////////////////////////////////////////////

int _status87()
{
    return fetestexcept(FE_ALL_EXCEPT);
}

void _clear87()
{
    feclearexcept(FE_ALL_EXCEPT);
}

/////////////////////////////////////////////

alias WIN32_FIND_DATA WIN32_FIND_DATAA;

extern (Windows)
{
    HANDLE CreateEventA(SECURITY_ATTRIBUTES *lpSecurityAttributes, BOOL bManualReset, BOOL bInitialState, in char* lpName);

    BOOL SetEvent(HANDLE hEvent);
    BOOL ResetEvent(HANDLE hEvent);

    HINSTANCE ShellExecuteA(HWND hwnd, in char* lpOperation, in char* lpFile, in char* lpParameters, in char* lpDirectory, int nShowCmd);
}

/////////////////////////////////////////////
static Object[] allObjects;

template toPtr(T)
{
    T* toPtr(T obj) { allObjects ~= obj; return cast(T*) &allObjects[$-1]; }
}

/////////////////////////////////////////////
void* memset(void* p, int val, int len)
{
	char* q = cast(char*)p;
	for(int i = 0; i < len; i++)
		q[i] = val;
	return p;
}

/////////////////////////////////////////////
void* malloc(int cnt)
{
	return std_malloc(cnt);
//	void* p = new byte[cnt];
//	return p;
}

void* alloca(int cnt)
{
	void* p = new byte[cnt];
	return p;
}

void* calloc(int elem_size, int elem_cnt)
{
	return std_calloc(elem_size, elem_cnt);
	//int cnt = elem_size * elem_cnt;
	//void* p = new byte[cnt];
	//memset(p, 0, cnt);
	//return p;
}

void free(void*p)
{
	std_free(p);
//	delete p;
}

void* realloc(void* p, int len)
{
	return std_realloc(p, len);
//	return p;
}

int putenv(char*e)
{
	return 0;
}

// posix style write
int write(int fd, const(void)*msg, int len)
{
	char[] s = (cast(char*) msg)[0..len];
	return printf("&s", s); // writef(s);
}

void local_assert(int line)
{
	assert(!"local_assert()");
}

void func_noreturnvalue()
{
	assert(!"func_noreturnvalue()");
}

/////////////////////////////////////////////
char* strdup(const char* s)
{
	int len = std_strlen(s);
	char* p = cast(char*) malloc(len + 1);
	memcpy(p, s, len + 1);
	return p;
}

int strlen(uint N, T)(T[N] s)
{
	return std_strlen(s.ptr);
}
int strlen(T)(T* s)
{
	return std_strlen(s);
}

char* strcpy(uint N, T)(char* p, T[N] s)
{
	return std_strcpy(p, s.ptr);
}

char* strcpy(T)(char* p, T* s)
{
	return std_strcpy(p, s);
}

const(char) [] toString(const char* s)
{
	int len = strlen(s);
	return s[0..len];
}

T* strupr(T)(T* p)
{
	int len = strlen(p);
	toupperInPlace!(T)(p[0..len]);
	return p;
}

void itoa(int val, char* p, int base)
{
	string s = format("%d", val);
	strcpy(p, s.ptr);
}

/////////////////////////////////////////////
bool mkdir(const(char)* pathname)
{
	std_mkdir(toString(pathname));
	return true; // throws exception on error
}

char* getcwd(char*cwd, int len)
{
	string wd = std_getcwd();
	if(wd.length + 1 > len)
		return null;
	memcpy(cwd, wd.ptr, wd.length);
	cwd[wd.length] = 0;
	return cwd;
}

size_t filesize(const char* cp)
{
	int len = strlen(cp);
	return getSize(cp[0..len]);
}

/////////////////////////////////////////////

T _rotl(T)(T x, uint n)
{
    return (x << n) | (x >> (8*T.sizeof-n));
}

T _rotr(T)(T x, uint n)
{
    return (x >> n) | (x << (8*T.sizeof-n));
}

// parsed, but not called
char* cpp_prettyident(void* s)
{
	return null;
}

/////////////////////////////////////////////

void MD5Init(MD5_CTX* ctx)
{
	ctx.start();
}

void MD5Update(MD5_CTX* ctx, ubyte *name, int len)
{
    ctx.update(name[0 .. len]);
}

void MD5Final(MD5_CTX* ctx, ubyte[16] digest)
{
    ctx.finish(digest);
}

/////////////////////////////////////////////

class GC
{
}

class CppMangleState
{
	// not used
}

struct EXCEPTION_POINTERS
{
	// not used
	struct EXCEPTIONRECORD
	{
		int ExceptionCode;
	}
	EXCEPTIONRECORD ExceptionRecord;
}

alias EXCEPTION_POINTERS *LPEXCEPTION_POINTERS;

class Thunk
{
	// not used
}

class Environment
{
	// not used
}

struct jmp_buf
{
}

void longjmp(jmp_buf jbuf, int code)
{
    throw new Exception("longjmp");
}

immutable(double) __nan = 0x0.ffffp1023;
const double __inf = 0x0p1023;

const(char)* __locale_decpoint = ".".ptr;

//////////////////////////////////////////////////////////////////

import dmd2 : d2d_main;

int main(char[][] argv)
{
	char** argvp = (new char*[argv.length + 1]).ptr;
	for(int i = 0; i < argv.length; i++)
	    argvp[i] = argv[i].ptr;

	return d2d_main(argv.length, argvp);
}
