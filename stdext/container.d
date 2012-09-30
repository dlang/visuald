// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module stdext.container;

///////////////////////////////////////////////////////////////////////
struct Queue(T)
{
	T[] data;
	size_t used;

	void append(ref T t)
	{
		if(used >= data.length)
			data.length = data.length * 2 + 1;
		data[used++] = t;
	}
	void remove(size_t idx)
	{
		assert(idx < used);
		for(size_t i = idx + 1; i < used; i++)
			data[i - 1] = data[i];
		data[--used] = T.init;
	}

	@property size_t length()
	{
		return used;
	}

	ref T opIndex(size_t idx)
	{
		assert(idx < used);
		return data[idx];
	}

	ref Queue!T opCatAssign(ref T t)
	{
		append(t);
		return this;
	}
}
