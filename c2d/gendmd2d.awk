BEGIN {
  print("static char* __file__ = \"dmd2d.c\";");
  printf("/////////////////////////////////////////////////////////////////\n");
  printf("// sys include files ////////////////////////////////////////////\n");
  printf("/////////////////////////////////////////////////////////////////\n");
  printf("#define _MT 1\n");
  if(SYSINC)
    printf("#include \"dmd2d.sysinc\"\n");
  else
  {
    printf("#include <dos.h>\n");
    printf("#include <stdio.h>\n");
  }
  printf("\n");
  printf("#undef _ckstack\n");
  printf("#undef assert\n");
  printf("#define TASSERT_H 1\n");
  printf("void assert(bool) {}\n");
  printf("void local_assert(int line) {}\n");
  printf("\n");
  printf("#undef NULL\n");
  printf("#define NULL (((( 0 ))))\n");
  printf("\n");
  printf("#undef INVALID_HANDLE_VALUE\n");
  printf("typedef void* HANDLE;\n");
  printf("static const HANDLE INVALID_HANDLE_VALUE = (HANDLE)-1;\n");
  printf("\n");
  printf("#undef stderr\n");
  printf("#undef stdout\n");
  printf("FILE* stdout = &_iob[1];\n");
  printf("FILE* stderr = &_iob[2];\n");
  printf("\n");
  printf("#undef isalpha\n");
  printf("#undef isdigit\n");
  printf("#undef isalnum\n");
  printf("#undef iswhite\n");
  printf("#undef isspace\n");
  printf("#undef ishex\n");
  printf("#undef isxdigit\n");
  printf("#undef islower\n");
  printf("#undef isupper\n");
  printf("#undef isprint\n");
  #printf("bool isalpha(int ch) { return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z'); }\n");
  #printf("bool isdigit(int ch) { return ch >= '0' && ch <= '9'; }\n");
  #printf("bool isalnum(int ch) { return isalpha(ch) || isdigit(ch); }\n");
  #printf("bool iswhite(int ch) { return ch == ' ' || ch == '\\n' || ch == '\\t' || ch == '\\r' || ch == '\\f'; }\n");
  #printf("bool ishex(int ch)   { return isdigit(ch) || (ch >= 'A' && ch <= 'F') || (ch >= 'a' && ch <= 'f'); }\n");
  printf("\n");
  printf("#undef errno\n");
  printf("#undef ERANGE\n");
  printf("int errno;\n");
  printf("const int ERANGE = 37;\n");
  printf("\n");
  
  printf("/////////////////////////////////////////////////////////////////\n");
  printf("// dmd source files /////////////////////////////////////////////\n");
  printf("/////////////////////////////////////////////////////////////////\n");
  printf("#define ASYNC_H\n");
  printf("#define Escape DocEscape\n");
}
{
  for(i = 1; i <= NF; i++)
  {
    printf("/////////////////////////////////////////////////////////////////\n");
    printf("// File: " $i "\n");
    
    if($i == "ph.cc")
    {
      printf("#define heap ph_heap\n");
      printf("#include \"" $i "\"\n");
      printf("#undef heap\n");
    }
    else if($i == "gother.cc")
    {
      printf("#undef IN\n");
      printf("#include \"" $i "\"\n");
    }
    else if($i == "newman.cc")
    {
      printf("#define CHAR nm_CHAR\n");
      printf("#define mangle nm_mangle\n");
      printf("#include \"" $i "\"\n");
      printf("#undef CHAR\n");
      printf("#undef nm_mangle\n");
    }
    else if($i == "ptrntab.cc")
    {
      printf("#define optab pt_optab\n");
      printf("#include \"" $i "\"\n");
      printf("#undef optab pt_optab\n");
    }
    else
      printf("#include \"" $i "\"\n");
  }
}
END {
  if(SYSINC)
  {
    printf("/////////////////////////////////////////////////////////////////\n");
    printf("// File: dmd2d_miss.cpp\n");
    printf("#include \"dmd2d_miss.cpp\"\n");
  }
}
