/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module editor.textbuffer;


import std.container : DList;
import std.array : array, RefAppender, Appender, appender;
import std.range;
//import std.algorithm;
import std.exception : assumeUnique, assertThrown;
import std.typecons;
import std.utf : count;
import std.uni;
import std.format : format;

import core.exception : AssertError;

template isTextBuffer(T)
{
	enum isTextBuffer = false;
}

// Refers to a piece in a buffer.
private struct Piece
{
	// Offset in code points (bytes for utf-8) from the begining of the buffer.
	size_t position;

	// length in dchars.
	size_t length;

	Piece* next;

	string toString()
	{
		return format("P%s:L%s", position, length);
	}
}

private struct PieceRange
{
	// before pieceRange
	Piece* prev;

	// head of piece range
	Piece* first;

	// length in dchars.
	size_t length;

	// Piece ranges in one group have the same flag.
	bool group;
}

alias PiecePair = Tuple!(Piece*, "prev", Piece*, "piece", size_t, "piecePos");

enum Previous {no, yes};

private PieceStorage pieceStorage()
{
	PieceStorage storage;
	storage.front.next = storage.back;
	return storage;
}

private struct PieceStorage
{
	Piece* back = new Piece;
	Piece* front = new Piece;

	// length in dchars.
	size_t length;

	string toString()
	{
		auto app = appender!string;
		auto piece = front;
		while(piece != null)
		{
			app ~= piece.toString;
			app ~= " ";
			piece = piece.next;
		}

		return app.data;
	}

	unittest
	{
		PieceStorage storage = pieceStorage();
		
		assert(storage.front != storage.back);
		assert((*storage.front).length == 0);
		assert((*storage.back).length == 0);
		assert(storage.length == 0);
	}

	PiecePair pieceAt(size_t index)
	{
		assert(index < length);
		return pieceAt(index, PiecePair(front, front.next, 0));
	}

	PiecePair pieceAt(size_t index, PiecePair pair)
	{
		assert(index < length);

		Piece* prev = pair.prev;
		Piece* piece = pair.piece;
		size_t textPosition = pair.piecePos;

		while (index >= textPosition + piece.length)
		{
			prev = piece;

			textPosition += piece.length;
			piece = piece.next;
		}

		return PiecePair(prev, piece, textPosition);
	}

	unittest
	{
		PieceStorage storage = pieceStorage();

		auto piece1 = new Piece(10, 2);
		storage.insertBack(piece1);

		auto piece2 = new Piece(5, 2);
		storage.insertBack(piece2);

		auto piece3 = new Piece(1, 2);
		storage.insertBack(piece3);

		assert(storage.pieceAt(0) == PiecePair(storage.front, piece1, 0));
		assert(storage.pieceAt(1) == PiecePair(storage.front, piece1, 0));
		assert(storage.pieceAt(2) == PiecePair(piece1, piece2, 2));
		assert(storage.pieceAt(3) == PiecePair(piece1, piece2, 2));
		assert(storage.pieceAt(4) == PiecePair(piece2, piece3, 4));
		assert(storage.pieceAt(5) == PiecePair(piece2, piece3, 4));
		assert(storage.pieceAt(4, storage.pieceAt(2)) == PiecePair(piece2, piece3, 4));
		assertThrown!AssertError(storage.pieceAt(6));
	}

	void insertFront(Piece* piece)
	{
		assert(piece);
		
		length += piece.length;

		piece.next = front.next;
		front.next = piece;
	}

	unittest
	{
		PieceStorage storage = pieceStorage();

		auto piece1 = new Piece(0, 2);
		storage.insertFront(piece1);

		assert(storage.front.next == piece1);
		assert(storage.back == storage.front.next.next);
		assert(storage.length == 2);

		auto piece2 = new Piece(4, 2);
		storage.insertFront(piece2);

		assert(storage.front.next == piece2);
		assert(storage.front.next.next == piece1);
		assert(storage.length == 4);

		assert(piece1.next == storage.back);
		assert(piece2.next == piece1);
	}

	void insertBack(Piece* piece)
	{
		assert(piece);

		length += piece.length;
		
		auto prev = front;

		while(prev.next != back)
		{
			prev = prev.next;
		}

		prev.next = piece;
		piece.next = back;
	}

	unittest
	{
		PieceStorage storage = pieceStorage();

		auto piece1 = new Piece(0, 2);
		storage.insertBack(piece1);

		assert(storage.front.next == piece1);
		assert(storage.front.next.next == storage.back);
		assert(storage.length == 2);

		auto piece2 = new Piece(4, 2);
		storage.insertBack(piece2);

		assert(storage.front.next == piece1);
		assert(storage.front.next.next == piece2);
		assert(storage.length == 4);
		
		assert(piece1.next == piece2);
		assert(piece2.next == storage.back);
	}

	/// inserts newPiece after prev
	void insertAfter(Piece* newPiece, Piece* prev)
	{
		newPiece.next = prev.next;
		prev.next = newPiece;
		length += newPiece.length;
	}

	unittest
	{
		PieceStorage storage = pieceStorage();

		auto piece1 = new Piece(0, 2);
		storage.insertBack(piece1);
		auto piece2 = new Piece(0, 4);
		storage.insertBack(piece2);

		auto piece3 = new Piece(0, 6);
		storage.insertAfter(piece3, piece1);
		assert(storage.length == 12);
		assert(piece1.next == piece3);
		assert(piece3.next == piece2);
	}

	// Removes Piece that is presented inside storage.
	// Assumes that pieceToRemove is presented. Will Error otherwise.
	// pieceToRemove.next is not changed.
	void remove(Piece* pieceToRemove)
	{
		assert(pieceToRemove);

		scope(success) length -= pieceToRemove.length;

		Piece* prev = front;

		while(prev.next != pieceToRemove)
		{
			prev = prev.next;
		}

		prev.next = pieceToRemove.next;
	}

	unittest
	{
		PieceStorage storage = pieceStorage();

		auto piece1 = new Piece(0, 2);
		storage.insertBack(piece1);
		auto piece2 = new Piece(0, 4);
		storage.insertBack(piece2);
		auto piece3 = new Piece(0, 6);
		storage.insertBack(piece3);
		auto piece4 = new Piece(0, 8);
		storage.insertBack(piece4);

		assert(storage.length == 20);
		import std.stdio;
		
		// Remove in the middle
		storage.remove(piece2);
		assert(piece1.next == piece3);
		assert(storage.length == 16);

		// Remove not present
		assertThrown!Error(storage.remove(piece2)); // Access violation.

		// Remove front
		storage.remove(piece1);
		assert(storage.front.next == piece3);
		assert(storage.length == 14);

		// Remove back
		storage.remove(piece4);
		assert(storage.front.next == piece3);
		assert(piece3.next == storage.back);
		assert(storage.length == 6);

		// Remove last
		storage.remove(piece3);
		assert(storage.front.next == storage.back);
		assert(storage.length == 0);

		storage.insertBack(piece1);
		storage.remove(piece1);
		assert(storage.front.next == storage.back);
	}
}

size_t charlength(S)(S data, size_t dcharLength)
{
	size_t oldLength = data.length;
	size_t newLength = data
		.dropExactly(dcharLength)
		.length;
	
	return oldLength - newLength;
}

import std.stdio;
struct PieceTable
{
	alias E = char;

	// Stores original text followed by inserted text.
	private Appender!(char[]) _buffer;
	private Appender!(PieceRange[]) _undoStack;
	private Appender!(PieceRange[]) _redoStack;
	private bool _isGrouping;
	alias _bufferData = _buffer.data;

	private PieceStorage _sequence;

	private Piece* createPiece(size_t position = 0, size_t length = 0, Piece* next = null)
	{
		return new Piece(position, length, next);
	}

	void beginGroup()
	{
		_isGrouping = true;
	}

	void endGroup()
	{
		_isGrouping = false;
	}

	// Get next group flag for undo range.
	private @property bool nextUndoGroup()
	{
		if (_undoStack.data.length > 0)
		{
			if (_isGrouping)
				return _undoStack.data[$-1].group;
			else
				return !_undoStack.data[$-1].group;
		}
		else
		{
			return false;
		}
	}

	this(S)(S initialText)
	{
		_sequence = pieceStorage();
		_buffer ~= initialText;
		_sequence.insertBack(createPiece(0, initialText.count!char));
	}

	unittest
	{
		PieceTable table = PieceTable("test");
		assert(table.length == 4);
	}

	struct Range
	{
		private Piece* _head;
		private string _buffer;
		private string _sequence;
		private size_t _pieceLength;
		private size_t _length;

		private this(Piece* piece, size_t piecePos, size_t length, string buffer)
		{
			_head = piece;
			_length = length;
			_buffer = buffer;

			if (_head)
			{
				_pieceLength = _head.length;
				_sequence = _buffer[piecePos..$];
			}
		}

		/// Input range primitives.
		@property bool empty() const 
		{
			return !_head || _length == 0;
		}

		@property size_t length()
		{
			return _length;
		}

		size_t opDollar()
		{
			return _length;
		}

		/// ditto
		@property dchar front()
		{
			assert(!empty);
			return _sequence.front;
		}

		/// ditto
		void popFront()
		{
			assert(!empty);

			_sequence.popFront;
			--_pieceLength;
			--_length;

			if (_pieceLength == 0)
			{
				_head = _head.next;
				if (_head)
				{
					_pieceLength = _head.length;
					_sequence = _buffer[_head.position..$];
				}
			}
		}

		Range opSlice(size_t x, size_t y)
	    {
	    	assert(y - x > 0);
	    	assert(x < y);
	    	
	    	if (y > _length)
	    	{
	    		y = _length;
	    	}

	    	if (x >= _length || y - x < 1)
	    	{
	    		return Range(null, 0, 0, null);
	    	}

	    	auto newRange = save;

	    	//newRange.drop(x);
	    	foreach(_; 0..x)
	    		newRange.popFront;

	    	newRange._length = y - x;
	    	return newRange;
	    }

		/// Forward range primitive.
		@property Range save() { return this; }
	}

	unittest
    {
        static assert(isForwardRange!Range);
        static assert(hasSlicing!Range);
    }

    Range opSlice()
    {
    	if (!_sequence.length)
    		return Range(null, 0, 0, null);

        return Range(_sequence.front.next, _sequence.front.next.position,
        	_sequence.length, cast(string)_buffer.data);
    }

    Range opSlice(size_t x, size_t y)
    {
    	assert(y - x > 0);
    	assert(x < y);
    	
    	if (y > length)
    	{
    		y = length;
    	}

    	if (x >= _sequence.length || y - x < 1)
    	{
    		return Range(null, 0, 0, null);
    	}

    	auto pair = _sequence.pieceAt(x);
        return Range(pair.piece,
        	pair.piece.position + charlength(_buffer.data[pair.piece.position..$], x-pair.piecePos),
        	y - x,
        	cast(string)_buffer.data);
    }

	size_t opDollar()
	{
		return length;
	}

	unittest
	{
		PieceTable table = PieceTable("абвгде");

		assert(table[0..1].length == 1);

		assert(table[0..$].equal(table[]));
		assert(table[3..$].equal("где"));
		assert(table[0..3].equal("абв"));
		assertThrown!AssertError(table[3..1]);
		assert(table[0..100].equal(table[]));

		auto range = table[0..$];
		assert(range.equal(range.save[0..$]));
		assert((table[2..4])[0..1].length == 1);
		assert((table[2..4])[0..1].equal("в"));
	}

	size_t length() @property
	{
		return _sequence.length;
	}

	/// Remove sequence of text starting at index of length length
	/*
	 *    |---------| - Piece
	 *
	 * 1. |XXXXX----| - Remove from begining to the middle
	 *
	 * 2. |XXXXXXXXX| - Remove whole piece
	 *
	 * 3. |XXXXXXXXX|XXX... - Remove whole piece and past piece
	 *
	 * 4. |--XXXXX--| - Remove in the middle of piece
	 *
	 * 5. |--XXXXXXX| - Remove from middle to the end of piece
	 *
	 * 6. |--XXXXXXX|XXX... - Remove from middle and past piece
	 */
	void remove(size_t removePos, size_t removeLength)
	{
		if (removePos >= _sequence.length || removeLength == 0) return;

		if (removePos + removeLength > length)
		{
			removeLength = length - removePos;
		}

		size_t removeEnd = removePos + removeLength - 1;

		// First piece in the sequence.
		auto first = _sequence.pieceAt(removePos);
		auto last = _sequence.pieceAt(removeEnd, first);
		size_t lastEnd = last.piecePos + last.piece.length - 1;

		Piece* newPieces = first.prev;

		// handle cases 4, 5 and 6.
		if (removePos > first.piecePos)
		{
			newPieces.next = createPiece(first.piece.position, removePos - first.piecePos);
			newPieces = newPieces.next;
		}

		// Handle cases 1 and 4
		if (removeEnd < lastEnd)
		{
			auto offset = charlength(_buffer.data[last.piece.position..$],
				removeEnd - last.piecePos + 1);
			newPieces.next = createPiece(last.piece.position + offset,
				lastEnd - removeEnd);
			newPieces = newPieces.next;
		}

		newPieces.next = last.piece.next;

		_undoStack ~= PieceRange(first.prev, first.piece, removeLength);

		_sequence.length -= removeLength;
	}

	unittest
	{
		PieceTable table = PieceTable("абвгде");

		assert(table.length == 6);
		auto piece1 = table._sequence.front.next;

		table.remove(0, 1); // case 1
		assert(table.length == 5);
		assert(equal(table[], "бвгде"));

		table.remove(0, 6); // case 2
		assert(table.length == 0);
		assert(equal(table[], ""));

		table = PieceTable("абвгде");

		table.remove(2, 1); // case 4
		assert(table._sequence.front.next.length == 2);
		assert(table._sequence.front.next.next.length == 3);
		assert(table.length == 5);
		assert(equal(table[], "абгде"));

		table.remove(0, 5); // case 3 + case 2
		assert(table.length == 0);
		assert(equal(table[], ""));

		table = PieceTable("абвгде");

		table.remove(2, 4); // case 5
		assert(table.length == 2);
		assert(equal(table[], "аб"));

		table = PieceTable("абвгде");

		table.remove(2, 1);
		table.remove(1, 5); // case 6 + case 2
		assert(table.length == 1);
		assert(equal(table[], "а"));

		table = PieceTable("аб");
		table.insert("вг");
		table.insert("де");
		table.remove(2, 2);
		assert(table[].equal("абде"));
	}

	void insert(S)(S text)
		if (isSomeString!S || (isInputRange!S && isSomeChar!(ElementType!S)))
	{
		insert(length, text);
	}

	void insert(S)(size_t insertPos, S text)
		if (isSomeString!S || (isInputRange!S && isSomeChar!(ElementType!S)))
	{
		size_t textLength = text.byGrapheme.walkLength;//text.count!char;
		size_t bufferPos = _buffer.data.length;
		_buffer ~= text;

		Piece* middlePiece = new Piece(bufferPos, textLength);

		if (insertPos == 0) // At the begining of text
		{
			_sequence.insertFront(middlePiece);
			return;
		}
		else if (insertPos == _sequence.length) // At the end of text
		{
			_sequence.insertBack(middlePiece);
			return;
		}

		auto pair = _sequence.pieceAt(insertPos);

		if (insertPos == pair.piecePos) // At the begining of piece
		{
			_sequence.insertAfter(middlePiece, pair.prev);
		}
		else // In the middle of piece
		{
			auto leftPieceLength = insertPos - pair.piecePos;
			auto rightPiecePos = pair.piece.position + 
				charlength(_buffer.data[pair.piece.position..$], leftPieceLength);
			
			Piece* rightPiece = new Piece(rightPiecePos, pair.piece.length - leftPieceLength);
			
			pair.piece.length = leftPieceLength;
			_sequence.length -= rightPiece.length;

			_sequence.insertAfter(middlePiece, pair.piece);
			_sequence.insertAfter(rightPiece, middlePiece);
		}
	}

	unittest
	{
		PieceTable table = PieceTable("абвгде");

		table.insert(0, "абв");
		assert(table.length == 9);
		assert(equal(table[], "абвабвгде"));

		table.insert(9, "абв");
		assert(table.length == 12);
		assert(equal(table[], "абвабвгдеабв"));

		table = PieceTable("абвгде");
		table.insert(3, "ggg");
		assert(table.length == 9);
		assert(equal(table[], "абвgggгде"));

		//table.insert(0, 'a'.repeat(3));
		//assert(table[].equal("aaaабвgggгде"));
		//assert(is(isRandomAccessRange!('a'.repeat(3))));
		//table.insert(0, "abc".byCodePoint);
		//assert(equal(table[], "abcaaaабвgggгде"));
	}
}