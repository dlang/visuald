// replacement module to disable stack traces and avoid the default stacktrace code
// to be linked in

module core.sys.windows.stacktrace;

import core.sys.windows.windows;

class StackTrace : Throwable.TraceInfo
{
public:
	this(size_t skip, CONTEXT* context)
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
	override string toString() const
	{
    	return null;
	}
	static ulong[] trace(size_t skip = 0, CONTEXT* context = null)
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
