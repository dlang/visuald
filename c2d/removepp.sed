1,/dmd source files/d

# " #directive /* unfinshed comment " -> "/* unfinshed comment
s/^\([	 ]*#.*\/\*[^\*]*\)$/\/\* \1/

# remove conditional compilation comments
/^[	 ]*#if/d
/^[	 ]*#elif/d
/^[	 ]*#else/d
/^[	 ]*#endif/d

# comment #define and other
s/^\([	 ]*#\)/\/\/ \1/

# translate bitfields
/unsigned rm *: *3;/ s/unsigned.*/mixin(bitfields!(uint, "rm", 3,/
/unsigned reg *: *3;/s/unsigned.*/                 uint, "reg", 3,/
/unsigned mod *: *2;/s/unsigned.*/                 uint, "reg", 2));/

/unsigned base *: *3;/ s/unsigned.*/mixin(bitfields!(uint, "base", 3,/
/unsigned index *: *3;/s/unsigned.*/                 uint, "index", 3,/
/unsigned ss *: *2;/   s/unsigned.*/                 uint, "ss", 2));/

# remove md5 code, because it uses old-c-style prototypes
/md5\.c /,/End of md5\.c/d

# add & to function pointers in array cdxxx
/cdxxx\[OPMAX\]/,/};/{
	s/\(cd[a-wyz0-9][a-wyz0-9]*\)/\&\1/
	s/loaddata/\&loaddata/
}

# add braces to pt_optab initializer
/static OP pt_optab/,/};/{
    /\/\//!{
		/,/i\
{
		/,/a\
},
		s/,\([an\(][^,]*\)/,{ pptb0 : \1.ptr/g
		s/(((( 0 )))).ptr/null/g
		s/, /} }, {/g
		s/aptb1JZ.ptr,/aptb1JZ.ptr },/
		s/aptb2XORPS.ptr,/aptb2XORPS.ptr },/
	}
}

# add braces to regtab initializer
/static REG regtab/,/};/{
	s/\([^,]*\),\([^,]*\),\([^,]*\),/{\1,\2,\3},/
}

# add braces to initializers in cgsched.c
/static unsigned long oprw/,/;/{
	s/\([^,]*\),\([^,]*\),/{\1,\2},/
}

/static unsigned long grprw/,/;/{
	s/\([^,]*\),\([^,]*\),/{\1,\2},/
	s/\(\/\/ Grp 1\)/{\1/
	s/\(\/\/ Grp [35]\)/}, {\1/
	s/};/}, };/
}

/static unsigned long grpf1/,/;/{
	s/\([^,]*\),\([^,]*\),/{\1,\2},/
	s/\(\/\/ 0xD8\)/{\1/
	s/\(\/\/ 0xD[9A-F]\)/}, {\1/
	s/};/}, };/
}

/static unsigned char uopsgrpf1/,/;/{
	s/\([^,]*\),\([^,]*\),/{\1,\2},/
	s/\(\/\/ 0xD8\)/{\1/
	s/\(\/\/ 0xD[9A-F]\)/}, {\1/
	s/};/}, };/
}

# add missing , before closing brace (compiler error?)
/static unsigned char EA16rm/,/};/{
	s/};/, };/
}

# const char[] for member string in OPTABLE, so it is later converted to string
/struct OPTABLE/,/};/{
# if addStringPtr set in dmd2d.d
	s/char *\*string/const char\* string/
	s/char pretty\[5\]/const char\* pretty/
#else
#	s/char *\*string/const char string[]/
}

# if addStringPtr set in dmd2d.d, convert char[N] to pointers
s/char regstr\[6\]/const char* regstr/


# do not use unsigned char for strings
s/static unsigned char ddoc_default/static char ddoc_default/

# HANDLE passed as 0, not NULL
/CreateFileA/,/;/s/,0);/,null);/

# fix Array_sort_compare usage

/Array..tos()/,/ox..compare/{
	s/int/extern (C) int/
	s/const/__in const/g
}
# take adress of function
/qsort/s/Array_sort_compare/\&Array_sort_compare/
