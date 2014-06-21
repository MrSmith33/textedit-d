/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module textedit.benchmark;

import textedit.textbuffer;

import std.stdio : writefln;
import std.file : write, append;
import std.datetime : StopWatch, TickDuration;
import std.random;

void main()
{
	enum times = 30_000;

	PieceTable table = PieceTable("");

	StopWatch sw;
	auto gen = Random(42);

	write("insert.txt", "Testing inserts\ni\tavg\ttotal\n");
	TickDuration last = sw.peek;

	foreach(i; 1..times+1)
	{
		auto position = uniform(0, i, gen);

		sw.start();
		table.insert(position, "abcde");
		sw.stop();
		if (i % 1000 == 0)
		{
			auto time = sw.peek - last;
			append("insert.txt", format("%s\t%s\t%s\n", i, time.hnsecs / 1000, time.hnsecs));
			last = sw.peek;
		}
	}
	writefln("Done insert %s times in %10s hnsecs", times, sw.peek.hnsecs);

	sw.reset();
	write("undo.txt", "Testing undo\ni\tavg\ttotal\n");
	last = sw.peek;

	foreach(i; 1..times+1)
	{
		sw.start();
		table.undo();
		sw.stop();
		if (i % 1000 == 0)
		{
			auto time = sw.peek - last;
			append("undo.txt", format("%s\t%s\t%s\n", times-i, time.hnsecs / 1000, time.hnsecs));
			last = sw.peek;
		}
	}
	writefln("Done   undo %s times in %10s hnsecs", times, sw.peek.hnsecs);

	sw.reset();

	table = PieceTable("");
	gen = Random(42);

	foreach(i; 1..times+1)
	{
		auto position = uniform(0, i, gen);
		table.insert(position, "abcde");
	}

	write("redo.txt", "Testing undo\ni\tavg\ttotal\n");
	last = sw.peek;

	foreach(i; 1..times+1)
	{
		sw.start();
		table.undo();
		sw.stop();
		if (i % 1000 == 0)
		{
			auto time = sw.peek - last;
			append("redo.txt", format("%s\t%s\t%s\n", times-i, time.hnsecs / 1000, time.hnsecs));
			last = sw.peek;
		}
	}
	writefln("Done   redo %s times in %10s hnsecs", times, sw.peek.hnsecs);
}