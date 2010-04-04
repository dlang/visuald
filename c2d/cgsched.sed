
/__file__/d 

/static unsigned long oprw/,/;/s/\([^,]*\),\([^,]*\),/{\1,\2},/

/static unsigned long grprw/,/;/{
	s/\([^,]*\),\([^,]*\),/{\1,\2},/
	s/\(\/\/ Grp 1\)/{\1/
	s/\(\/\/ Grp [35]\)/}, {\1/
	s/};/} };/
}

/static unsigned long grpf1/,/;/{
	s/\([^,]*\),\([^,]*\),/{\1,\2},/
	s/\(\/\/ 0xD8\)/{\1/
	s/\(\/\/ 0xD[9A-F]\)/}, {\1/
	s/};/} };/
}

/static unsigned char uopsgrpf1/,/;/{
	s/\([^,]*\),\([^,]*\),/{\1,\2},/
	s/\(\/\/ 0xD8\)/{\1/
	s/\(\/\/ 0xD[9A-F]\)/}, {\1/
	s/};/} };/
}
