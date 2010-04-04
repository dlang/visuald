BEGIN{
  braces = 0;
}
{
  len=length($0);
  closing = "";
  for(p = 1; p <= len; p++)
  {
    if (substr($0,p,1) == "{")
    {
      braces++;
      open[braces] = NR;
    }
    if (substr($0,p,1) == "}")
    {
      closing = closing " " open[braces];
      braces--;
    }
  }
  printf("%d %s", braces, $0);
  if(closing != "")
    printf(" // closing %s", closing);
  printf("\n");
}
