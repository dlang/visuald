// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details
//
///////////////////////////////////////////////////////////////////////
//
// idl2d - convert IDL or header files to D
module c2d.idl2d_main;
import c2d.idl2d;

int main(string[] argv)
{
	idl2d inst = new idl2d;
	return inst.main(argv);
}


