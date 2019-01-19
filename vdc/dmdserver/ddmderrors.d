/**
 * Compiler implementation of the
 * $(LINK2 http://www.dlang.org, D programming language).
 *
 * Copyright:   Copyright (c) 1999-2017 by Digital Mars, All Rights Reserved
 * Authors:     $(LINK2 http://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/src/ddmd/errors.d, _errors.d)
 */

module dmd.errors;

// Online documentation: https://dlang.org/phobos/ddmd_errors.html

import core.stdc.stdarg;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import dmd.globals;
import dmd.root.outbuffer;
import dmd.root.rmem;
import dmd.console;

/**********************
 * Color highlighting to classify messages
 */
enum Classification
{
    error = Color.brightRed,          /// for errors
    gagged = Color.brightBlue,        /// for gagged errors
    warning = Color.brightYellow,     /// for warnings
    deprecation = Color.brightCyan,   /// for deprecations
    supplemental = Color.brightMagenta, /// for supplemental info (e.g. instantiation trace)
}

/**************************************
 * Print error message
 */
extern (C++) void error(const ref Loc loc, const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    verror(loc, format, ap);
    va_end(ap);
}

extern (C++) void error(Loc loc, const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    verror(loc, format, ap);
    va_end(ap);
}

extern (C++) void error(const(char)* filename, uint linnum, uint charnum, const(char)* format, ...)
{
    Loc loc;
    loc.filename = filename;
    loc.linnum = linnum;
    loc.charnum = charnum;
    va_list ap;
    va_start(ap, format);
    verror(loc, format, ap);
    va_end(ap);
}

extern (C++) void errorSupplemental(const ref Loc loc, const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    verrorSupplemental(loc, format, ap);
    va_end(ap);
}

extern (C++) void warning(const ref Loc loc, const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    vwarning(loc, format, ap);
    va_end(ap);
}

extern (C++) void warningSupplemental(const ref Loc loc, const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    vwarningSupplemental(loc, format, ap);
    va_end(ap);
}

extern (C++) void deprecation(const ref Loc loc, const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    vdeprecation(loc, format, ap);
    va_end(ap);
}

extern (C++) void deprecationSupplemental(const ref Loc loc, const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    vdeprecation(loc, format, ap);
    va_end(ap);
}

extern(C++)
void verrorPrint(const ref Loc loc, Color headerColor, const(char)* header,
				 const(char)* format, va_list ap, const(char)* p1 = null, const(char)* p2 = null);

// header is "Error: " by default (see errors.h)
extern (C++) void verror(const ref Loc loc, const(char)* format, va_list ap, const(char)* p1 = null, const(char)* p2 = null, const(char)* header = "Error: ")
{
    global.errors++;
    if (!global.gag)
    {
        verrorPrint(loc, Classification.error, header, format, ap, p1, p2);
        if (global.params.errorLimit && global.errors >= global.params.errorLimit)
            fatal(); // moderate blizzard of cascading messages
    }
    else
    {
        if (global.params.showGaggedErrors)
        {
            fprintf(stderr, "(spec:%d) ", global.gag);
            verrorPrint(loc, Classification.gagged, header, format, ap, p1, p2);
        }
        global.gaggedErrors++;
    }
}

// Doesn't increase error count, doesn't print "Error:".
extern (C++) void verrorSupplemental(const ref Loc loc, const(char)* format, va_list ap)
{
    Color color;
    if (global.gag)
    {
        if (!global.params.showGaggedErrors)
            return;
        color = Classification.gagged;
    }
    else
        color = Classification.supplemental;
    verrorPrint(loc, color, "       ", format, ap);
}

extern (C++) void vwarning(const ref Loc loc, const(char)* format, va_list ap)
{
    if (global.params.warnings && !global.gag)
    {
        verrorPrint(loc, Classification.warning, "Warning: ", format, ap);
        //halt();
        if (global.params.warnings == 1)
            global.warnings++; // warnings don't count if gagged
    }
}

extern (C++) void vwarningSupplemental(const ref Loc loc, const(char)* format, va_list ap)
{
    if (global.params.warnings && !global.gag)
        verrorPrint(loc, Classification.warning, "       ", format, ap);
}

extern (C++) void vdeprecation(const ref Loc loc, const(char)* format, va_list ap, const(char)* p1 = null, const(char)* p2 = null)
{
    static __gshared const(char)* header = "Deprecation: ";
    if (global.params.useDeprecated == 0)
        verror(loc, format, ap, p1, p2, header);
    else if (global.params.useDeprecated == 2 && !global.gag)
        verrorPrint(loc, Classification.deprecation, header, format, ap, p1, p2);
}

extern (C++) void vdeprecationSupplemental(const ref Loc loc, const(char)* format, va_list ap)
{
    if (global.params.useDeprecated == 0)
        verrorSupplemental(loc, format, ap);
    else if (global.params.useDeprecated == 2 && !global.gag)
        verrorPrint(loc, Classification.deprecation, "       ", format, ap);
}

/***************************************
 * Call this after printing out fatal error messages to clean up and exit
 * the compiler.
 */
extern (C++) void fatal()
{
	throw new Exception("fatal");
}

/**************************************
 * Try to stop forgetting to remove the breakpoints from
 * release builds.
 */
extern (C++) void halt()
{
	throw new Exception("halt");
}

/**
* Print a verbose message.
* Doesn't prefix or highlight messages.
* Params:
*      loc    = location of message
*      format = printf-style format specification
*      ...    = printf-style variadic arguments
*/
extern (C++) void message(const ref Loc loc, const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    vmessage(loc, format, ap);
    va_end(ap);
}

/**
* Same as above, but doesn't take a location argument.
* Params:
*      format = printf-style format specification
*      ...    = printf-style variadic arguments
*/
extern (C++) void message(const(char)* format, ...)
{
    va_list ap;
    va_start(ap, format);
    vmessage(Loc.initial, format, ap);
    va_end(ap);
}

/**
* Same as $(D message), but takes a va_list parameter.
* Params:
*      loc       = location of message
*      format    = printf-style format specification
*      ap        = printf-style variadic arguments
*/
extern (C++) void vmessage(const ref Loc loc, const(char)* format, va_list ap)
{
    version(none)
    {
    const p = loc.toChars();
    if (*p)
    {
        fprintf(stdout, "%s: ", p);
        mem.xfree(cast(void*)p);
    }
    OutBuffer tmp;
    tmp.vprintf(format, ap);
    fputs(tmp.peekString(), stdout);
    fputc('\n', stdout);
    fflush(stdout);     // ensure it gets written out in case of compiler aborts
    }
}

