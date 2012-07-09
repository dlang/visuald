module largeadr;

import std.file;

void main(string[] argv)
{
	foreach(f; argv[1 .. $])
	{
		ubyte[] image = cast(ubyte[]) std.file.read(f);
		if(image[0x76] == 0xAE)
			throw new Exception("File " ~ f ~ " already large address aware");
		if(image[0x76] != 0x8E)
			throw new Exception("File " ~ f ~ " not a dmd generated executable");
		image[0x76] = 0xAE;
		std.file.write(f, image);
	}
}