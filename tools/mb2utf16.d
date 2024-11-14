import std.file;
import std.utf;
import std.windows.charset;
import core.sys.windows.winuser;

pragma(lib, "user32");

void main(string[] argv)
{
	int cp = GetKBCodePage();
	string input = argv[1];
	string output = (argv.length > 2 ? argv[2] : input);

	void[] content = std.file.read(input);
	string str8 = fromMBSz((cast(string)content ~ '\0').ptr, cp);
	wstring str16 = toUTF16(str8);
	ubyte[2] bom = [ 0xff, 0xfe ];
	std.file.write(output, bom ~ cast(ubyte[])str16);
}
