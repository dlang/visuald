module sdk.port.bitfields;

version(Win64)
version = bitmanip;

version(bitmanip)
{
import std.typetuple;
import std.traits;
static import std.bitmanip;

template CountBits(T...)
{
	static if(T.length == 0)
		enum CountBits = 0;
	else
		enum CountBits = T[2] + CountBits!(T[3..$]);
}

template PadBits(T...)
{
	enum bits = CountBits!T;
	static if(bits == 8 || bits == 16 || bits == 32 || bits == 64)
		alias T PadBits;
	else static if(bits < 8)
		alias TypeTuple!(T, uint, "", 8 - bits) PadBits;
	else static if(bits < 16)
		alias TypeTuple!(T, uint, "", 16 - bits) PadBits;
	else static if(bits < 32)
		alias TypeTuple!(T, uint, "", 32 - bits) PadBits;
	else
		alias TypeTuple!(T, uint, "", 64 - bits) PadBits;
}

template bitfields(T...)
{
	static import std.bitmanip;
    enum bitfields = std.bitmanip.bitfields!(PadBits!T);
}

} else {
private template myToString(ulong n, string suffix = n > uint.max ? "UL" : "U")
{
    static if (n < 10)
        enum myToString = cast(char) (n + '0') ~ suffix;
    else
        enum myToString = .myToString!(n / 10, "")
            ~ .myToString!(n % 10, "") ~ suffix;
}

private template createAccessors(
    string store, T, string name, size_t len, size_t offset)
{
    static if (!name.length)
    {
        // No need to create any accessor
        enum result = "";
    }
    else static if (len == 0)
    {
        // Fields of length 0 are always zero
        enum result = "const "~T.stringof~" "~name~" = 0;\n";
    }
    else
    {
        static if (len + offset <= uint.sizeof * 8)
            alias uint MasksType;
        else
            alias ulong MasksType;
        enum MasksType
            maskAllElse = ((1uL << len) - 1u) << offset,
            signBitCheck = 1uL << (len - 1),
            extendSign = ~((cast(MasksType)1u << len) - 1);
        static if (T.min < 0)
        {
            enum long minVal = -(1uL << (len - 1));
            enum ulong maxVal = (1uL << (len - 1)) - 1;
        }
        else
        {
            enum ulong minVal = 0;
            enum ulong maxVal = (1uL << len) - 1;
        }

        static if (is(T == bool))
        {
            static assert(len == 1);
            enum result =
            // getter
                "bool " ~ name ~ "() { return "
                ~"("~store~" & "~myToString!(maskAllElse)~") != 0;}\n"
            // setter
                ~"void " ~ name ~ "(bool v){"
                ~"if (v) "~store~" |= "~myToString!(maskAllElse)~";"
                ~"else "~store~" &= ~"~myToString!(maskAllElse)~";}\n";
        }
        else
        {
            // getter
            enum result = T.stringof~" "~name~"() { auto result = "
                ~"("~store~" & "
                ~ myToString!(maskAllElse) ~ ") >>"
                ~ myToString!(offset) ~ ";"
                ~ (T.min < 0
                   ? "if (result >= " ~ myToString!(signBitCheck)
                   ~ ") result |= " ~ myToString!(extendSign) ~ ";"
                   : "")
                ~ " return cast("~T.stringof~") result;}\n"
            // setter
                ~"void "~name~"("~T.stringof~" v){ "
                ~"assert(v >= "~name~"_min); "
                ~"assert(v <= "~name~"_max); "
                ~store~" = cast(typeof("~store~"))"
                ~" (("~store~" & ~"~myToString!(maskAllElse)~")"
                ~" | ((cast(typeof("~store~")) v << "~myToString!(offset)~")"
                ~" & "~myToString!(maskAllElse)~"));}\n"
            // constants
                ~"enum "~T.stringof~" "~name~"_min = cast("~T.stringof~")"
                ~myToString!(minVal)~"; "
                ~" enum "~T.stringof~" "~name~"_max = cast("~T.stringof~")"
                ~myToString!(maxVal)~"; ";
        }
    }
}

private template createStoreName(Ts...)
{
    static if (Ts.length < 2)
        enum createStoreName = "_val";
    else
        enum createStoreName = Ts[1] ~ createStoreName!(Ts[3 .. $]);
}

private template createFields(string store, size_t offset, Ts...)
{
    static if (!Ts.length)
    {
        static if (offset <= ubyte.sizeof * 8)
            alias ubyte StoreType;
        else static if (offset <= ushort.sizeof * 8)
            alias ushort StoreType;
        else static if (offset <= uint.sizeof * 8)
            alias uint StoreType;
        else static if (offset <= ulong.sizeof * 8)
            alias ulong StoreType;
        else
        {
            static assert(false, "Field widths must less than 64");
            alias ulong StoreType; // just to avoid another error msg
        }
        enum result = "private " ~ StoreType.stringof ~ " " ~ store ~ ";";
    }
    else
    {
        enum result
            = createAccessors!(store, Ts[0], Ts[1], Ts[2], offset).result
            ~ createFields!(store, offset + Ts[2], Ts[3 .. $]).result;
    }
}

/**
Allows creating bit fields inside $(D_PARAM struct)s and $(D_PARAM
class)es.

Example:

----
struct A
{
    int a;
    mixin(bitfields!(
        uint, "x",    2,
        int,  "y",    3,
        uint, "z",    2,
        bool, "flag", 1));
}
A obj;
obj.x = 2;
obj.z = obj.x;
----

The example above creates a bitfield pack of eight bits, which fit in
one $(D_PARAM ubyte). The bitfields are allocated starting from the
least significant bit, i.e. x occupies the two least significant bits
of the bitfields storage.

The sum of all bit lengths in one $(D_PARAM bitfield) instantiation
must be exactly 8, 16, 32, or 64. If padding is needed, just allocate
one bitfield with an empty name.

Example:

----
struct A
{
    mixin(bitfields!(
        bool, "flag1",    1,
        bool, "flag2",    1,
        uint, "",         6));
}
----

The type of a bit field can be any integral type or enumerated
type. The most efficient type to store in bitfields is $(D_PARAM
bool), followed by unsigned types, followed by signed types.
*/

template bitfields(T...)
{
    enum bitfields = createFields!(createStoreName!(T), 0, T).result;
}

//pragma(msg,bitfields!(uint, "x",    5));
}

unittest
{
	static struct A
	{
	    mixin(bitfields!(
		uint, "x",    8,
		int,  "y",    3,
		uint, "z",    2,
		bool, "flag", 1
	    ));
	}
	static assert(A.sizeof == 2);
	A obj;
	obj.x = 2;
	obj.z = obj.x;

	import std.stdio;
	writeln("done");
}
