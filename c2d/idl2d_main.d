// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt
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


