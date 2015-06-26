/* Demangler for D/C++ - gcc and MS style mangling

   Copyright (C) 2015 Free Software Foundation, Inc.
   Written by Rainer Schuetze (r.sagitario@gmx.de)

   This file is using part of GNU Binutils, inspired by cxxfilt

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or (at
   your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with GCC; see the file COPYING.  If not, write to the Free
   Software Foundation, 51 Franklin Street - Fifth Floor, Boston, MA
   02110-1301, USA.  */

import core.demangle;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

extern(Windows) uint UnDecorateSymbolName(in char* DecoratedName, char* UnDecoratedName,
                                          uint UndecoratedLength, uint Flags);
extern(C) char* dlang_demangle(const char* mangled_name, uint flags);
extern(C) char* cplus_demangle(const char* mangled_name, uint flags);

enum DMGL_PARAMS  = (1 << 0); /* Include function args */
enum DMGL_ANSI    = (1 << 1); /* Include const, volatile, etc */
enum DMGL_VERBOSE = (1 << 3); /* Include implementation details.  */

uint flags =  DMGL_PARAMS | DMGL_ANSI | DMGL_VERBOSE;
char msvc_buffer[32768];

char* msvc_demangle (char *mangled_name)
{
    if (UnDecorateSymbolName (mangled_name, msvc_buffer.ptr, msvc_buffer.length, 0) == 0)
        return null;
    return msvc_buffer.ptr;
}

char* d_demangle (char[] mangled)
{
    size_t pos = 0;
    string s = decodeDmdString (mangled, pos);
    char[] obuf;
    if (pos == mangled.length)
        obuf = demangle(s, msvc_buffer);
    else
        obuf = demangle(mangled, msvc_buffer);
    if (obuf.ptr != msvc_buffer.ptr)
        return null;
    msvc_buffer[obuf.length] = 0;
    return msvc_buffer.ptr;
}

void print_demangled (char[] mangled)
{
    char *result;
	char[] initial = mangled;

    /* . and $ are sometimes found at the start of function names
    in assembler sources in order to distinguish them from other
    names (eg register names).  So skip them here.  */
    if (mangled[0] == '.' || mangled[0] == '$')
        mangled = mangled[1..$];

    if (mangled.length > 1 && mangled[0] == '_' && mangled[1] == 'D')
        result = d_demangle (mangled);
    else if (mangled.length > 0 && mangled[0] == '?')
        result = msvc_demangle (mangled.ptr);
    else
        result = cplus_demangle (mangled.ptr, flags);

    if (result == null)
        printf ("%s", initial.ptr);
    else
    {
        if (initial.ptr != mangled.ptr)
            putchar (initial[0]);
        printf ("%s", result);
        if (result != msvc_buffer.ptr)
            free (result);
    }
}

bool isAlnum(int c)
{
	return c <= 'z' && c >= '0' && (c <= '9' || c >= 'a' || (c >= 'A' && c <= 'Z'));
}

int main (char[][] argv)
{
    int c;
    const char *valid_symbols = "_$.?@";

	if (argv.length > 1)
	{
		foreach(a; argv[1..$])
		{
			print_demangled(a);
			putchar ('\n');
		}
		return 0;
	}
    for (;;)
    {
        static char mbuffer[32767];
        uint i = 0;

        c = getchar ();
        /* Try to read a mangled name. Assume non-ascii characters to be part of the name */
        while (c != EOF && (isAlnum (c) || strchr (valid_symbols, c) || c >= 128))
        {
            if (i >= mbuffer.length - 1)
                break;
            mbuffer[i++] = cast(char) c;
            c = getchar ();
        }

        if (i > 0)
        {
            mbuffer[i] = 0;
            print_demangled (mbuffer[0..i]);
        }

        if (c == EOF)
            break;

        /* Echo the whitespace characters so that the output looks
        like the input, only with the mangled names demangled.  */
        putchar (c);
        if (c == '\n')
            fflush (stdout);
    }

    fflush (stdout);
    return 0;
}
