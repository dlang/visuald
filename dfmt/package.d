// integration of https://github.com/dlang-community/dfmt

module dfmt;
import dfmt.config : Config;

pragma(mangle,"dfmt_format")
pragma(inline, false) // could prevent semantic analysis with -inine, but does not
bool dfmt_format(string source_desc, string buffer, ref string output)
{

	Config* formatterConfig;
	Config config;
	if (!formatterConfig)
	{
		import dfmt.editorconfig;

		config.initializeWithDefaults();
		Config fileConfig = getConfigFor!Config(source_desc);
		fileConfig.pattern = "*.d";
		config.merge(fileConfig, source_desc);
		formatterConfig = &config;
	}

	try
	{
		import std.array;
		Appender!(char[]) app;
		app.reserve(buffer.length);
		bool rc = _format(source_desc, cast(ubyte[])buffer, app, formatterConfig);
		output = cast(string) app.data;
		return rc;
	}
	catch(Exception e)
	{
		output = buffer;
		return false;
	}
}

// same as dfmt.formatter.format, but with parser errors nuked
bool _format(OutputRange)(string source_desc, ubyte[] buffer, OutputRange output, Config* formatterConfig)
{
	import dparse.lexer;
	import dparse.parser;
	import dparse.rollback_allocator;
	import dfmt.formatter;
	import dfmt.ast_info;
	import dfmt.indentation;
	import dfmt.tokens;
	import dfmt.wrapping;
	import std.array;

    LexerConfig config;
    config.stringBehavior = StringBehavior.source;
    config.whitespaceBehavior = WhitespaceBehavior.skip;
    LexerConfig parseConfig;
    parseConfig.stringBehavior = StringBehavior.source;
    parseConfig.whitespaceBehavior = WhitespaceBehavior.skip;
    StringCache cache = StringCache(StringCache.defaultBucketCount);
    ASTInformation astInformation;
    RollbackAllocator allocator;
    auto parseTokens = getTokensForParser(buffer, parseConfig, &cache);
    auto mod = parseModule(parseTokens, source_desc, &allocator, &dump_message);
    auto visitor = new FormatVisitor(&astInformation);
    visitor.visit(mod);
    astInformation.cleanup();
    auto tokenRange = byToken(buffer, config, &cache);
    auto app = appender!(Token[])();
    for (; !tokenRange.empty(); tokenRange.popFront())
        app.put(tokenRange.front());
    auto tokens = app.data;
    if (!tokenRange.messages.empty)
        return false;
    auto depths = generateDepthInfo(tokens);
    auto tokenFormatter = TokenFormatter!OutputRange(buffer, tokens, depths,
													 output, &astInformation, formatterConfig);
    tokenFormatter.format();
    return true;
}

void dump_message(string fileName , size_t line, size_t column, string message, bool isError)
{
}
