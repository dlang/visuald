// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

// simple double linked list

module c2d.dlist;

struct DListNode(T)
{
	T data;

	DListNode!(T)* _next;
	DListNode!(T)* _prev;
}

class DList(T)
{
	DListNode!(T) root;

	this()
	{
		root._next = &root;
		root._prev = &root;
	}

	bool empty()
	{
		return root._next == &root;
	}

	int count()
	{
		int cnt = 0;
		for(auto p = root._next; p != &root; p = p._next)
			cnt++;
		return cnt;
	}

	void append(T item)
	{
		insertBefore(item, &root);
	}

	void prepend(T item)
	{
		insertAfter(item, &root);
	}

	DListNode!(T)* insertBefore(T data, DListNode!(T)* ins)
	{
		DListNode!(T) *node = new DListNode!(T);
		node.data = data;
		insertBefore(node, ins);
		return node;
	}

	DListNode!(T)* insertAfter(T data, DListNode!(T)* ins)
	{
		DListNode!(T) *node = new DListNode!(T);
		node.data = data;
		insertAfter(node, ins);
		return node;
	}

	void insertAfter(DListNode!(T)* node, DListNode!(T)* ins)
	{
		insertBefore(node, ins._next);
	}

	void insertBefore(DListNode!(T) *node, DListNode!(T)* ins)
	{
		node._next = ins;
		node._prev = ins._prev;
		ins._prev._next = node;
		ins._prev = node;
	}

	void remove(DListNode!(T)* node)
	{
		node._prev._next = node._next;
		node._next._prev = node._prev;
		node._next = null;
		node._prev = null;
	}

	// removes entries from list
	void appendList(DList!(T) list)
	{
		insertListAfter(root._prev, list);
	}

	// removes entries from list
	void insertListAfter(DListNode!(T)* node, DList!(T) list)
	{
		if(list.empty())
			return;

		DListNode!(T)* first = list.root._next;
		DListNode!(T)* last  = list.root._prev;
		
		// wipe the list
		list.root._next = &list.root;
		list.root._prev = &list.root;

		node._next._prev = last;
		last._next = node._next;
		first._prev = node;
		node._next = first;
	}

	// insert entries to list, return node to beginning of inserted list
	DListNode!(T)* insertListBefore(DListNode!(T)* node, DList!(T) list)
	{
		if(node is &root)
		{
			insertListAfter(node._prev, list);
			return &root;
		}
		else
		{
			DListNode!(T)* _prev = node._prev;
			insertListAfter(node._prev, list);
			return _prev._next;
		}
	}

	void insertListAfter(ref DListIterator!(T) it, DList!(T) list)
	{
		assert(it._list is this);
		insertListAfter(it._pos, list);
	}

	void insertListBefore(ref DListIterator!(T) it, DList!(T) list)
	{
		assert(it._list is this);
		insertListBefore(it._pos, list);
	}

	DList!(T) remove(DListNode!(T)* from, DListNode!(T)* to)
	{
		DList!(T) list = new DList!(T);
		if (from is to)
			return list;
		
		assert(from != &root);

		DListNode!(T)* last = to._prev;

		from._prev._next = to;
		to._prev = from._prev;
		
		list.root._next = from;
		list.root._prev = last;

		from._prev = &list.root;
		last._next = &list.root;

		return list;
	}

	DList!(T) remove(ref DListIterator!(T) from, ref DListIterator!(T) to)
	{
		DList!(T) list = remove(from._pos, to._pos);
		from._pos = to._pos;
		return list;
	}

	DListIterator!(T) find(T data)
	{
		DListIterator!(T) it = begin();
		while(!it.atEnd())
		{
			if(*it == data)
				break;
			it.advance();
		}
		return it;
	}

	DListIterator!(T) begin()
	{
		DListIterator!(T) it = DListIterator!(T)(this);
		it._pos = root._next;
		return it;
	}

	DListIterator!(T) end()
	{
		DListIterator!(T) it = DListIterator!(T)(this);
		it._pos = &root;
		return it;
	}

	ref T opIndex(int idx)
	{
		DListIterator!(T) it = begin();
		it += idx;
		return *it;
	}
}

struct DListIterator(T)
{
	DListNode!(T)* _pos;
	DList!(T) _list;

	this(DList!(T) list)
	{
		_list = list;
	}

	bool valid() const 
	{
		return _list !is null;
	}

	void setList(DList!(T) list)
	{
		_list = list;
	}

	DList!(T) getList()
	{
		return _list;
	}

version(none) // opDot deprecated
{
	alias opStar this;

	// https://issues.dlang.org/show_bug.cgi?id=16657 need to define opEquals with alias this
	bool opEquals(const typeof(this) other) const
	{
		return _pos == other._pos; // no need to compare lists, nodes belong to only one list
	}
}
else version(all) // alias this too broken with operator overloads
{
	ref auto opDispatch(string op, ARGS...)(auto ref ARGS args) if (ARGS.length == 0)
	{
		enum sym = "_pos.data." ~ op;
		return mixin(sym);
	}
	auto opDispatch(string op, ARGS...)(auto ref ARGS args) if (ARGS.length == 1) // could be field = value
	{
		enum sym = "_pos.data." ~ op;
		static if (__traits(compiles, mixin(sym) = args[0]))
			return mixin(sym) = args[0];
		else
			return mixin(sym)(args);
	}
	auto opDispatch(string op, ARGS...)(auto ref ARGS args) if (ARGS.length > 1)
	{
		enum sym = "_pos.data." ~ op;
		return mixin(sym)(args);
	}
}
else
{
	ref T opDot()
	{
		return _pos.data;
	}
}

	ref T opUnary(string op)() if(op == "*")
	{
		return _pos.data;
	}

	void opUnary(string op)() if(op == "++")
	{
		advance();
	}

	void opUnary(string op)() if(op == "--")
	{
		retreat();
	}

	ref T opIndex(int idx)
	{
		DListIterator!(T) it = this;
		it += idx;
		return *it;
	}

	DListIterator!(T) opBinary(string op)(int cnt) if(op == "+")
	{
		DListIterator!(T) it = this;
		it += cnt;
		return it;
	}

	DListIterator!(T) opBinary(string op)(int cnt) if(op == "-")
	{
		DListIterator!(T) it = this;
		it += -cnt;
		return it;
	}

	void advance()
	{
		assert(_pos !is &_list.root);
		_pos = _pos._next;
	}
	void retreat()
	{
		_pos = _pos._prev;
		assert(_pos !is &_list.root);
	}

	bool atEnd()
	{
		return _pos is &_list.root;
	}
	bool atBegin()
	{
		return _pos is _list.root._next;
	}

	void opOpAssign(string op)(int cnt) if(op == "+")
	{
		while(cnt > 0)
		{
			advance();
			cnt--;
		}
		while(cnt < 0)
		{
			retreat();
			cnt++;
		}
	}
	void opOpAssign(string op)(int cnt) if(op == "-")
	{
		opOpAssign!"+"(-cnt);
	}

	void insertAfter(T data)
	{
		_list.insertAfter(data, _pos);
	}
	void insertBefore(T data)
	{
		_list.insertBefore(data, _pos);
	}

	// insert entries to list, return iterator to beginning of inserted list
	DListIterator!(T) insertListBefore(DList!(T) list)
	{
		DListNode!(T)* beg = _list.insertListBefore(_pos, list);
		DListIterator!(T) begIt = DListIterator!(T)(_list);
		begIt._pos = beg;
		return begIt;
	}

	// moves iterator to _next entry
	void erase()
	{
		assert(_pos !is &_list.root);
	
		DListNode!(T)* pos = _pos;
		advance();
		_list.remove(pos);
	}

	DList!(T) eraseUntil(DListIterator!(T) end)
	{
		assert(_pos !is &_list.root);
		assert(_list is end._list);
	
		DListNode!(T)* pos = _pos;
		_pos = end._pos;
		return _list.remove(pos, _pos);
	}
}

unittest
{
	DList!(int) list = new DList!(int);

	list.append(1);
	list.append(2);
	list.prepend(0);
	list.append(3);

	DListIterator!(int) it = list.begin();
	assert(*it == 0);
	assert(it[2] == 2);
	it.advance();
	assert(*it == 1);
	it.advance();
	assert(*it == 2);
	it.advance();
	assert(*it == 3);
	assert(it[-1] == 2);
	++it;
	assert(it == list.end());
	--it;
	it.retreat();
	assert(*it == 2);
	it.erase();
	assert(*it == 3);
	--it;
	assert(*it == 1);
}

unittest
{
	DList!(int) list = new DList!(int);

	list.append(1);
	list.append(2);
	list.prepend(0);
	list.append(3);

	DListIterator!(int) it1 = list.begin();
	it1 += 1;
	DListIterator!(int) it2 = it1;
	it2 += 2;

	DList!(int) slice = list.remove(it1, it2);
	assert(*it1 == 3);
	--it1;
	assert(*it1 == 0);

	assert(*slice.begin() == 1);
	DListIterator!(int) it3 = slice.end();
	--it3;
	assert(*it3 == 2);
	--it3;
	assert(*it3 == 1);

}
