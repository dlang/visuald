// replacement module to disable stack traces and avoid the default stacktrace code
// to be linked in

module core.sys.windows.stacktrace;

import core.sys.windows.windows;

class StackTrace : Throwable.TraceInfo
{
public:
	static if (__VERSION__ < 2102)
		this(size_t skip, CONTEXT* context)
		{
		}
	else
		this(size_t skip, CONTEXT* context) @nogc
		{
		}

	int opApply(scope int delegate(ref const(char[])) dg) const
	{
		return 0;
	}
	int opApply(scope int delegate(ref size_t, ref const(char[])) dg) const
	{
		return 0;
	}
	override string toString() const @trusted
	{
		return null;
	}
	static ulong[] trace(size_t skip = 0, CONTEXT* context = null)
	{
		return null;
	}
	static ulong[] trace(ulong[] buffer, size_t skip = 0, CONTEXT* context = null) @nogc
	{
		return null;
	}
	static char[][] resolve(const(ulong)[] addresses)
	{
		return [];
	}
private:
	ulong[] m_trace;
}
