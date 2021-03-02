// Translated to D from diff.py at https://gist.github.com/tonyg/2361e3bfe4e92a1fc6f7
//
// Copyright (c) 2015 Tony Garnock-Jones <tonyg@leastfixedpoint.com>
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation files
// (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software,
// and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Text diff algorithm after Myers 1986 and Ukkonen 1985, following
// Levente Uzonyi's Squeak Smalltalk implementation at
// http://squeaksource.com/DiffMerge.html
//
// E. W. Myers, "An O(ND) difference algorithm and its variations,"
// Algorithmica, vol. 1, no. 1-4, pp. 251-266, Nov. 1986.
//
// E. Ukkonen, "Algorithms for approximate string matching," Inf.
// Control, vol. 64, no. 1-3, pp. 100-118, Jan. 1985.
//
module stdext.diffmyers;
import std.algorithm : reverse;

struct P
{
	int x;
	int y;
}

struct PChain
{
	P p;
	PChain* next;
}

P[] longest_common_subsequence(T)(T[] xs, T[] ys)
{
	int totallen = cast(int)(xs.length + ys.length);
	int[] frontier = new int[2 * totallen + 1];
	PChain*[] candidates = new PChain*[2 * totallen + 1];
	foreach (d; 0 .. totallen + 1)
	{
		for (int k = -d; k < d+1; k += 2)
		{
			int index;
			int x;
			if (k == -d || (k != d && frontier[totallen + k - 1] < frontier[totallen + k + 1]))
			{
				index = totallen + k + 1;
				x = frontier[index];
			}
			else
			{
				index = totallen + k - 1;
				x = frontier[index] + 1;
			}
			int y = x - k;
			auto chain = candidates[index];
			while (x < xs.length && y < ys.length && xs[x] == ys[y])
			{
				chain = new PChain(P(x, y), chain);
				x = x + 1;
				y = y + 1;
			}
			if (x >= xs.length && y >= ys.length)
			{
				P[] result;
				while (chain)
				{
					result ~= chain.p;
					chain = chain.next;
				}
				result.reverse();
				return result;
			}
			frontier[totallen + k] = x;
			candidates[totallen + k] = chain;
		}
	}
	assert(false);
}

struct R
{
	int xpos;
	int xlen;
	int ypos;
	int ylen;
}

R[] diff(T)(T[] xs, T[] ys)
{
	int i = -1;
	int j = -1;
	auto matches = longest_common_subsequence(xs, ys);
	matches ~= P(cast(int)xs.length, cast(int)ys.length);
	R[] result;
	foreach (m; matches)
	{
		int mi = m.x;
		int mj = m.y;
		if (mi - i > 1 || mj - j > 1)
			result ~= R(i + 1, mi - i - 1, j + 1, mj - j - 1);
		i = mi;
		j = mj;
	}
	return result;
}

unittest
{
	import std.stdio;
	void check(T)(T actual, T expected)
	{
		if (actual != expected)
		{
			writeln("Expected:", expected);
			writeln("Actual:", actual);
		}
	}

	check(diff("The red brown fox jumped over the rolling log",
				"The brown spotted fox leaped over the rolling log"),
			[R(4,4,4,0), R(14,0,10,8), R(18,3,22,3)]);

	struct T { string x; string y; P[] lcs; }
	foreach (test; [T("acbcaca", "bcbcacb", [P(1,1),P(2,2),P(3,3),P(4,4),P(5,5)]),
					T("bcbcacb", "acbcaca", [P(1,1),P(2,2),P(3,3),P(4,4),P(5,5)]),
	T("acba", "bcbb", [P(1,1),P(2,2)]),
	T("abcabba", "cbabac", [P(2,0),P(3,2),P(4,3),P(6,4)]),
	T("cbabac", "abcabba", [P(1,1),P(2,3),P(3,4),P(4,6)]),
	//      ([[1,1,1],[1,1,1],[1,1,1],[1,1,1]],
	//       [[1,1,1],[2,2,2],[1,1,1],[4,4,4]],
	//       [(0,0),(1,2)])
	])
		check(longest_common_subsequence(test.x, test.y), test.lcs);

	check(diff([[1,1,1],[1,1,1],[1,1,1],[1,1,1]],
				[[1,1,1],[2,2,2],[1,1,1],[4,4,4]]),
			[R(1,0,1,1), R(2,2,3,1)]);

	check(longest_common_subsequence("abc", "def"), []);
	check(diff("abc", "def"), [R(0,3,0,3)]);
}

int printByLineDiff(string text1, string text2)
{
	import std.stdio;
	import std.string;
	string[] lines1 = text1.splitLines;
	string[] lines2 = text2.splitLines;

	int changes;
	R[] diffs = diff(lines1, lines2);
	foreach(r; diffs)
	{
		write(r.xpos);
		if (r.xlen > 1)
			write(',', r.xpos + r.xlen);
		if (r.xlen == 0)
			write('a');
		else if (r.ylen == 0)
			write('d');
		else
			write('c');
		write(r.ypos);
		if (r.ylen > 1)
			write(',', r.ypos + r.ylen);
		writeln;

		foreach(x; r.xpos .. r.xpos + r.xlen)
			writeln("< ", lines1[x]);
		if (r.xlen && r.ylen)
			writeln("---");
		foreach(y; r.ypos .. r.ypos + r.ylen)
			writeln("> ", lines2[y]);
		changes += r.xlen + r.ylen;
	}
	return 0;
}

version(None)
int main(string[] args)
{
	import std.file;
	return printByLineDiff(readText(args[1]), readText(args[2]));
}
