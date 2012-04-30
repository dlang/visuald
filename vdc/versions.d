// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.versions;

__gshared int[string] predefinedVersions;

static int[string] sPredefinedVersions()
{
	if(!predefinedVersions)
	{
		predefinedVersions = 
		[
			"DigitalMars" : 1,
			"GNU" : -1,
			"LDC" : -1,
			"SDC" : -1,
			"D_NET" : -1,

			"Windows" : 1,
			"Win32" : 1,
			"Win64" : -1,
			"linux" : -1,
			"OSX" : -1,
			"FreeBSD" : -1,
			"OpenBSD" : -1,
			"BSD" : -1,
			"Solaris" : -1,
			"Posix" : -1,
			"AIX" : -1,
			"SkyOS" : -1,
			"SysV3" : -1,
			"SysV4" : -1,
			"Hurd" : -1,
			"Cygwin" : -1,
			"MinGW" : -1,

			"X86" : 1,
			"X86_64" : -1,
			"ARM" : -1,
			"PPC" : -1,
			"PPC64" : -1,
			"IA64" : -1,
			"MIPS" : -1,
			"MIPS64" : -1,
			"SPARC" : -1,
			"SPARC64" : -1,
			"S390" : -1,
			"S390X" : -1,
			"HPPA" : -1,
			"HPPA64" : -1,
			"SH" : -1,
			"SH64" : -1,
			"Alpha" : -1,

			"LittleEndian" : 1,
			"BigEndian" : -1,

			"D_Coverage" : -1,
			"D_Ddoc" : -1,
			"D_InlineAsm_X86" : 1,
			"D_InlineAsm_X86_64" : -1,
			"D_LP64" : -1,
			"D_PIC" : -1,

			"D_Version2" : 1,
			"none" : -1,
			"all" : 1,
		];
	}
	return predefinedVersions;
}
