/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module editor.benchmark;

import editor.textbuffer;

import std.stdio;
import std.datetime : StopWatch;
import std.random;

void main()
{
	enum times = 30_000;

	PieceTable table = PieceTable("");

	StopWatch sw;
	auto gen = Random(42);

	sw.start();
	foreach(i; 1..times+1)
	{
		auto position = uniform(0, i, gen);
		table.insert(position, "a");
	}
	sw.stop();
	writefln("Done insert %s times in %10s hnsecs", times, sw.peek.hnsecs);

	sw.reset();

	sw.start();
	foreach(i; 1..times+1)
	{
		table.undo();
	}
	sw.stop();
	writefln("Done   undo %s times in %10s hnsecs", times, sw.peek.hnsecs);

	sw.reset();

	sw.start();
	foreach(i; 1..times+1)
	{
		table.redo();
	}
	sw.stop();
	writefln("Done   redo %s times in %10s hnsecs", times, sw.peek.hnsecs);
}