// function declared but not implemented 

char* OutBuffer::extractString()
{
	assert(!"not implemented");
	return NULL;
}

Lstring *Lstring::clone()
{
	assert(!"not implemented");
	return NULL;
}

#ifdef _DH
char *Dsymbol::toHChars()
{
	assert(!"not implemented");
	return NULL;
}
#endif

void Token::print()
{
	assert(!"not implemented");
}

unsigned Lexer::wchar(unsigned u)
{
	assert(!"not implemented");
	return u;
}

char* Identifier::toHChars()
{
	assert(!"not implemented");
	return NULL;
}

//StringExp::StringExp(Loc loc, void *s, size_t len)
//StringExp::StringExp(Loc loc, void *s, size_t len, byte postfix)
BinAssignExp::BinAssignExp(Loc loc, enum TOK op, int size, Expression *e1, Expression *e2)
: BinExp(loc, op, size, e1, e2)
{
	assert(!"not implemented");
}

int BinAssignExp::checkSideEffect(int flag)
{
	assert(!"not implemented");
	return 0;
}

int TypeBasic::isbit()
{
	assert(!"not implemented");
	return 0;
}

int TypeTypedef::isbit()
{
	assert(!"not implemented");
	return 0;
}

void Argument::argsCppMangle(OutBuffer *buf, CppMangleState *cms, Arguments *arguments, int varargs)
{
	assert(!"not implemented");
}

//AliasDeclaration::AliasDeclaration(Loc loc, Identifier *ident, Type *type)
//AliasDeclaration::AliasDeclaration(Loc loc, Identifier *ident, Dsymbol *s)

/* filtered out
void FuncDeclaration::varArgs(Scope *sc, TypeFunction*, VarDeclaration *&, VarDeclaration *&)
{
	assert(!"not implemented");
}
*/

IdentifierExp::IdentifierExp(Loc loc, Declaration *var)
{
	assert(!"not implemented");
}

Scope::Scope(Module *d2d_module)
{
	assert(!"not implemented");
}

void DebugCondition::addPredefinedGlobalIdent(const char *ident)
{
	assert(!"not implemented");
}

void token_t::setSymbol(symbol *s)
{
	assert(!"not implemented");
}

void token_t::print()
{
	assert(!"not implemented");
}

int Symbol::needThis()
{
	assert(!"not implemented");
	return 0;
}

void PARAM::print()
{
	assert(!"not implemented");
}

void PARAM::print_list()
{
	assert(!"not implemented");
}

void code::print()
{
	assert(!"not implemented");
}

#ifndef DEBUG
char* regm_str(regm_t rm)
{
	assert(!"not implemented");
	return NULL;
}
#endif

#ifndef DEBUG
void WRcodlst(code *c )
{
	assert(!"not implemented");
}
#endif

// fltused(void)

#if !0
int code_match(code *c1,code *c2)
{
	assert(!"not implemented");
	return 0;
}
#endif

#if !HYDRATE
void code_hydrate(code **pc)
{
	assert(!"not implemented");
}
#endif

#if !DEHYDRATE
void code_dehydrate(code **pc)
{
	assert(!"not implemented");
}
#endif

// cat(code *c1 , code *c2 )

code *gencsi(code *c , unsigned op , unsigned rm , unsigned FL2 , SYMIDX si )
{
	assert(!"not implemented");
	return NULL;
}

int Html::namedEntity(unsigned char *p, int length)
{
	assert(!"not implemented");
	return 0;
}

void BLKLST::print()
{
	assert(!"not implemented");
}

//void(*_new_handler)(void)
//if((mdContext.i[0] + ((UINT4)inLen << 3)) < mdContext.i[0])

// c-style prototype: MD5Update(mdContext, PADDING, padLen)
// c-style prototype: Transform(mdContext.buf, in)

void* Mem::operator new(size_t m_size)
{
	assert(!"not implemented");
	return NULL;
}
void* Mem::operator new(size_t m_size, Mem *mem)
{
	assert(!"not implemented");
	return NULL;
}
void* Mem::operator new(size_t m_size, GC *gc)
{
	assert(!"not implemented");
	return NULL;
}
void Mem::operator delete(void *p)
{
	assert(!"not implemented");
}
void* Mem::operator new[](size_t m_size)
{
	assert(!"not implemented");
	return NULL;
}
void Mem::operator delete[](void *p)
{
	assert(!"not implemented");
}

void* Mem::malloc_uncollectable(size_t size)
{
	assert(!"not implemented");
	return NULL;
}
void Mem::free_uncollectable(void *p)
{
	assert(!"not implemented");
}
void Mem::check(void *p)
{
	assert(!"not implemented");
}
void Mem::fullcollectNoStack()
{
	assert(!"not implemented");
}
void Mem::addroots(char* pStart, char* pEnd)
{
	assert(!"not implemented");
}
void Mem::removeroots(char* pStart)
{
	assert(!"not implemented");
}
void Mem::setFinalizer(void* pObj, FINALIZERPROC pFn, void* pClientData)
{
	assert(!"not implemented");
}
void Mem::setStackBottom(void *bottom)
{
	assert(!"not implemented");
}
GC* Mem::getThreadGC()
{
	assert(!"not implemented");
	return NULL;
}
