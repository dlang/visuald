// replace dmd.location for faster line/file lookup and incremental updates

module dmd.location;

import core.stdc.stdio;

import dmd.common.outbuffer;
import dmd.root.array;
import dmd.root.filename;
import dmd.root.rmem : xarraydup;
import dmd.root.string: toDString;
import dmd.root.stringtable;

/// How code locations are formatted for diagnostic reporting
enum MessageStyle : ubyte
{
    digitalmars,  /// filename.d(line): message
    gnu,          /// filename.d:line: message, see https://www.gnu.org/prep/standards/html_node/Errors.html
    sarif         /// JSON SARIF output, see https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
}
/**
A source code location

Used for error messages, `__FILE__` and `__LINE__` tokens, `__traits(getLocation, XXX)`,
debug info etc.
*/
struct Loc
{
    private ulong data = 0; // bitfield of file, line and column

    static immutable Loc initial; /// use for default initialization of Loc's

    extern (C++) __gshared bool showColumns;
    extern (C++) __gshared MessageStyle messageStyle;

nothrow:
    /*******************************
	* Configure how display is done
	* Params:
	*  showColumns = when to display columns
	*  messageStyle = digitalmars or gnu style messages
	*/
    extern (C++) static void set(bool showColumns, MessageStyle messageStyle)
    {
        this.showColumns = showColumns;
        this.messageStyle = messageStyle;
    }

    /// Returns: a Loc that simply holds a filename, with no line / column info
    extern (C++) static Loc singleFilename(const char* filename)
    {
        return singleFilename(filename.toDString);
    }

    /// Returns: a Loc that simply holds a filename, with no line / column info
    static Loc singleFilename(const(char)[] filename)
    {
		ulong fileIndex = toLocFileIndex(filename);
        return Loc((fileIndex << 48) | 1); // default to charnum 1
    }

    /// utf8 code unit index relative to start of line, starting from 1
    extern (C++) uint charnum() const @nogc @safe
    {
        return data & 0xffff;
    }

    /// line number, starting from 1
    extern (C++) uint linnum() const @nogc @trusted
    {
        return (data >> 16) & 0xffff_ffff;
    }

    /***
	* Returns: filename for this location, null if none
	*/
	extern (C++) const(char)* filename() const @nogc
    {
        return locFileName[data >> 48].ptr;
    }

    /// Advance this location to the first column of the next line
    void nextLine() @safe pure @nogc
    {
        data = (data & ~0xffffL) + 0x10001;
    }

    bool isValid() const pure @safe
    {
        return data != 0;
    }

	extern (C++) const(char)* toChars(bool showColumns = Loc.showColumns,
									  MessageStyle messageStyle = Loc.messageStyle) const nothrow
	{
		return SourceLoc(this).toChars(showColumns, messageStyle);
	}
    /**
	* Checks for equivalence by comparing the filename contents (not the pointer) and character location.
	*
	* Note:
	*  - Uses case-insensitive comparison on Windows
	*  - Ignores `charnum` if `Columns` is false.
	*/
    extern (C++) bool equals(Loc loc) const
    {
		auto this_data = showColumns ? data : data & ~0xffff;
		auto loc_data = showColumns ? loc.data : loc.data & ~0xffff;
		return this_data == loc_data;
    }

    /**
	* `opEquals()` / `toHash()` for AA key usage
	*
	* Compare filename contents (case-sensitively on Windows too), not
	* the pointer - a static foreach loop repeatedly mixing in a mixin
	* may lead to multiple equivalent filenames (`foo.d-mixin-<line>`),
	* e.g., for test/runnable/test18880.d.
	*/
    extern (D) bool opEquals(ref const(Loc) loc) const @trusted nothrow @nogc
    {
        return this.data == loc.data;
    }

    /// ditto
    extern (D) size_t toHash() const @trusted nothrow
    {
        return hashOf(this.data);
    }
}

/**
 * Format a source location for error messages
 *
 * Params:
 *   buf = buffer to write string into
 *   loc = source location to write
 *   showColumns = include column number in message
 *   messageStyle = select error message format
 */
void writeSourceLoc(ref OutBuffer buf, SourceLoc loc, bool showColumns, MessageStyle messageStyle) nothrow
{
	auto filename = loc.filename;
    if (filename is null)
        return;
    buf.writestring(loc.filename);
    if (loc.linnum == 0)
        return;

    final switch (messageStyle)
    {
        case MessageStyle.digitalmars:
            buf.writeByte('(');
            buf.print(loc.linnum);
            if (showColumns && loc.charnum)
            {
                buf.writeByte(',');
                buf.print(loc.charnum);
            }
            buf.writeByte(')');
            break;
        case MessageStyle.gnu: // https://www.gnu.org/prep/standards/html_node/Errors.html
            buf.writeByte(':');
            buf.print(loc.linnum);
            if (showColumns && loc.charnum)
            {
                buf.writeByte(':');
                buf.print(loc.charnum);
            }
            break;
        case MessageStyle.sarif: // https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
            // No formatting needed here for SARIF
            break;
    }
}

// Global string table to make file names comparable via `is`
private __gshared StringTable!(size_t) locFileNameIndex;
private __gshared const(char)[][] locFileName;

size_t toLocFileIndex(const(char)[] fname) nothrow @trusted
{
	if (locFileName.length == 0)
	{
		locFileNameIndex.reset();
		locFileName ~= null;
		locFileNameIndex.insert("", 0); // for loc.initial
	}
    if (auto p = locFileNameIndex.lookup(fname))
        return p.value;
	size_t idx = locFileName.length;
	locFileName ~= fname.xarraydup;
    locFileNameIndex.insert(fname, idx);
    return idx;
}

const(char)[] toLocFilename(const(char)[] fname) nothrow
{
	return locFileName[toLocFileIndex(fname)];
}

const(char)[] toLocFilename(const(char)* fname) nothrow
{
    return toLocFilename(fname.toDString);
}

void location_init()
{
	locFileName = null;
	locFileNameIndex.reset();
}

struct SourceLoc
{
	Loc loc;

	//alias loc this;

    // aliases for backwards compatibility
    alias linnum = loc.linnum;
    alias line = loc.linnum;
    alias charnum = loc.charnum;
    alias column = loc.charnum;

	this(Loc oloc) nothrow @safe
	{
		loc = oloc;
	}

    this(const(char)[] filename, uint line, uint column,
		 uint fileOffset = 0, const(char)[] fileContent = null) nothrow @safe
	{
		if (column > 0xffff)
			column = 0xffff;
		ulong fileIndex = toLocFileIndex(filename);
		loc.data = (fileIndex << 48) | (line << 16) | column;
	}

	void filename(const(char)[] fname) nothrow
	{
		ulong fileIndex = toLocFileIndex(fname);
        loc.data = (loc.data & ((1L << 48) - 1)) | (fileIndex << 48);
	}
	const(char)[] filename() const nothrow @nogc
	{
		return loc.filename.toDString;
	}
	uint xline() const nothrow
	{
		return loc.linnum();
	}
	uint xcolumn() const nothrow
	{
		return loc.charnum();
	}
	const(char)[] fileContent() const nothrow
	{
		return null; // only for error messages with context
	}
	uint fileOffset() const nothrow
	{
		return 0; // only for error messages with context
	}

    bool opEquals(SourceLoc other) const nothrow
    {
        return loc == other.loc;
    }

	extern (C++) const(char)* toChars(bool showColumns = Loc.showColumns,
									  MessageStyle messageStyle = Loc.messageStyle) const nothrow
	{
		OutBuffer buf;
		writeSourceLoc(buf, this, showColumns, messageStyle);
		return buf.extractChars();
	}
}

struct BaseLoc
{
	SourceLoc loc;

	uint startLine;
	uint startOffset;
	uint lastLineOffset;
    BaseLoc[] substitutions; /// Substitutions from #line / #file directives

	alias loc this;

nothrow:
	this(const(char)[] filename, uint startLine)
	{
		this.loc = SourceLoc(filename, 1, 1);
		this.startLine = startLine;
	}

    Loc getLoc(uint offset) @nogc
	{
		Loc nloc;
		nloc.data = loc.loc.data + offset - lastLineOffset; // add char offset
		return nloc;
	}

    /**
	* Register a new file/line mapping from #file and #line directives
	* Params:
	*     offset = byte offset in the source file at which the substitution starts
	*     filename = new filename from this point on (null = unchanged)
	*     line = line number from this point on
	*/
    void addSubstitution(uint offset, const(char)* filename, uint line) @system
    {
        auto fname = filename.toDString;
        if (substitutions.length == 0)
            substitutions ~= BaseLoc(this.filename, 0);

        if (fname.length == 0)
            fname = substitutions[$ - 1].filename;
        substitutions ~= BaseLoc(fname, startLine + line); // cast(int) (line - lines.length + startLine - 2));
    }

    /// Returns: `loc` modified by substitutions from #file / #line directives
    SourceLoc substitute(SourceLoc loc)
    {
        if (substitutions.length == 0)
            return loc;

        const i = 0; // todo: getSubstitutionIndex(loc.fileOffset);
        if (substitutions[i].filename.length > 0)
            loc.filename = substitutions[i].filename;
        return SourceLoc(loc.filename, loc.line + substitutions[i].startLine, loc.column);
    }
    void newLine(uint offset) @safe
    {
		lastLineOffset = offset;
        loc.loc.nextLine();
    }
}

BaseLoc* newBaseLoc(const(char)* filename, const(char)[] fileContent) nothrow
{
    return new BaseLoc(filename.toDString, 0);
}

// for a language server, lowered expression should not reuse the original source location
//  as internal names might get exposed to the user
ref const(Loc) loweredLoc(return ref const Loc loc)
{
    version(LanguageServer)
        return Loc.initial;
    else
        return loc;
}
