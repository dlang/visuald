module stdext.denseset;
import core.memory;

struct DenseSet(T, ALLOC = GC)
{
	static assert(is(T == class)); // only reference objects

	~this()
	{
		if (entries)
			ALLOC.free(entries);
	}

	bool contains(T p)
	{
		return findSlot(cast(S)cast(void*)p) !is null;
	}

	bool insert(T p)
	{
		if (dim == 0)
			rehash(16);
		return findSlotInsert(cast(S)cast(void*)p) !is null;
	}

	bool remove(T p)
	{
		auto pp = findSlot(cast(S)cast(void*)p);
		if (!pp)
			return false;
		*pp = entryDeleted;
		deleted++;
		return true;
	}

private:
	S* findSlot(S p)
	{
		if (dim == 0)
			return null;
		else if (used >= dim / 2)
			rehash(dim * 2);

		size_t off = calcHash(p) & (dim - 1);
		for (int j = 1;; ++j)
		{
			if (entries[off] == p)
				return entries + off;
			if (!entries[off])
				return null;
			off = (off + j) & (dim - 1);
		}
	}

	S* findSlotInsert(S p)
	{
		S* del = null;
		size_t off = calcHash(p) & (dim - 1);
		for (int j = 1;; ++j)
		{
			if (entries[off] == p)
				return entries + off;

			if (!del && entries[off] == entryDeleted)
				// remember the first deleted entry
				del = entries + off;

			if (!entries[off])
			{
				if (del)
				{
					*del = p;
					deleted--;
					return del;
				}
				entries[off] = p;
				used++;
				return entries + off;
			}
			off = (off + j) & (dim - 1);
		}
	}

	size_t calcHash(S p)
	{
		size_t addr = p; //cast(size_t) cast(void*) p;
		return addr ^ (addr >>> 4);
	}

	void rehash(size_t sz)
	{
		assert((sz & (sz - 1)) == 0);
		assert(sz > used - deleted);
		S* oentries = entries;
		entries = cast(S*) ALLOC.calloc(sz * S.sizeof);
		size_t odim = dim;

		dim = sz;
		used = 0;
		deleted = 0;
		for (int i = 0; i < odim; i++)
		{
			if (oentries[i] && oentries[i] != entryDeleted)
				findSlotInsert(oentries[i]);
		}
		ALLOC.free(oentries);
	}

	alias S = size_t;
	enum entryDeleted = cast(S) ~0;

	size_t dim;
	size_t used;
	size_t deleted;

	S* entries;
}
