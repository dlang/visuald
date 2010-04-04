BEGIN {
   sysindent = 0;
}

{
   if(substr($1,1,1) == "'")
   {
      indent = 0;
      while(substr($0,indent,1) == " ")
         indent++;

      if(sysindent == 0 || indent <= sysindent)
      {
         sysindent = 0;
         if(substr($1,2,length(DMC)) == DMC)
         {
            sysindent = indent;
            print "#include \"" substr($1,2,length($1) - 2) "\"";
         }
      }
   }
}