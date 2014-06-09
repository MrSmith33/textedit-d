/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.gui.editor.textbuffer;

import std.container : DList;
import std.array : array, RefAppender, Appender, appender;
import std.range;
import std.algorithm;
import std.exception : assumeUnique, assertThrown;
import std.typecons;
import std.utf;

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
}

alias PiecePair = Tuple!(Piece*, "prev", Piece*, "piece", size_t, "piecePos");

enum Previous {no, yes};

private struct PieceStorage
{
	Piece* front;
	Piece* back;

	// length in dchars.
	size_t length;

	unittest
	{
		PieceStorage storage;
		
		assert(storage.front == null);
		assert(storage.back == null);
		assert(storage.length == 0);
	}

	auto pieceAt(Previous returnPrev = Previous.no)(size_t index)
	in
	{
		assert(index < length);
	}
	body
	{
		static if (returnPrev == Previous.yes)
			Piece* prev;

		Piece* piece = front;
		size_t textPosition;

		while (index >= textPosition + piece.length)
		{
			static if (returnPrev == Previous.yes)
				prev = piece;

			textPosition += piece.length;
			piece = piece.next;
		}

		static if (returnPrev == Previous.yes)
			return PiecePair(prev, piece, textPosition);
		else
			return piece;
	}

	unittest
	{
		PieceStorage storage;

		auto piece1 = new Piece(10, 2);
		storage.insertBack(piece1);

		auto piece2 = new Piece(5, 2);
		storage.insertBack(piece2);

		auto piece3 = new Piece(1, 2);
		storage.insertBack(piece3);

		assert(storage.pieceAt(0) == piece1);
		assert(storage.pieceAt(1) == piece1);
		assert(storage.pieceAt(2) == piece2);
		assert(storage.pieceAt(3) == piece2);
		assert(storage.pieceAt(4) == piece3);
		assert(storage.pieceAt(5) == piece3);
		assertThrown!AssertError(storage.pieceAt(6));

		assert(storage.pieceAt!(Previous.yes)(0) == PiecePair(null, piece1, 0));
		assert(storage.pieceAt!(Previous.yes)(1) == PiecePair(null, piece1, 0));
		assert(storage.pieceAt!(Previous.yes)(2) == PiecePair(piece1, piece2, 2));
		assert(storage.pieceAt!(Previous.yes)(3) == PiecePair(piece1, piece2, 2));
		assert(storage.pieceAt!(Previous.yes)(4) == PiecePair(piece2, piece3, 4));
		assert(storage.pieceAt!(Previous.yes)(5) == PiecePair(piece2, piece3, 4));
		assertThrown!AssertError(storage.pieceAt!(Previous.yes)(6));
	}

	void insertFront(Piece* piece)
	{
		assert(piece);
		
		length += piece.length;

		// zero elements in list
		if (back is null)
		{
			assert(front is null);

			back = piece;
		}

		piece.next = front;
		front = piece;
	}

	unittest
	{
		PieceStorage storage;

		auto piece1 = new Piece(0, 2);
		storage.insertFront(piece1);

		assert(storage.front == piece1);
		assert(storage.back == piece1);
		assert(storage.length == 2);

		auto piece2 = new Piece(4, 2);
		storage.insertFront(piece2);

		assert(storage.front == piece2);
		assert(storage.back == piece1);
		assert(storage.length == 4);

		assert(piece1.next == null);
		assert(piece2.next == piece1);
	}

	void insertBack(Piece* piece)
	{
		assert(piece);

		length += piece.length;
		
		// zero elements in list
		if (back is null)
		{
			assert(front is null);

			piece.next = front;
			front = piece;
			back = piece;
			return;
		}
		
		assert(back.next is null);

		back.next = piece;
		back = piece;
	}

	unittest
	{
		PieceStorage storage;

		auto piece1 = new Piece(0, 2);
		storage.insertBack(piece1);

		assert(storage.front == piece1);
		assert(storage.back == piece1);
		assert(storage.length == 2);

		auto piece2 = new Piece(4, 2);
		storage.insertBack(piece2);

		assert(storage.front == piece1);
		assert(storage.back == piece2);
		assert(storage.length == 4);
		
		assert(piece1.next == piece2);
		assert(piece2.next == null);
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
		PieceStorage storage;

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

		if (pieceToRemove == front)
		{
			front = pieceToRemove.next;
			
			if (pieceToRemove == back)
			{
				back = null;
			}

			return;
		}

		Piece* prev = front;

		while(prev.next != pieceToRemove)
		{
			prev = prev.next;
		}

		prev.next = pieceToRemove.next;
		
		if (pieceToRemove == back)
		{
			back = prev;
		}
	}

	unittest
	{
		PieceStorage storage;

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
		assert(storage.front == piece3);
		assert(storage.length == 14);

		// Remove back
		storage.remove(piece4);
		assert(storage.back == piece3);
		assert(piece3.next == null);
		assert(storage.length == 6);

		// Remove last
		storage.remove(piece3);
		assert(storage.front == null);
		assert(storage.back == null);
		assert(storage.length == 0);

		storage.insertBack(piece1);
		storage.remove(piece1);
		assert(storage.front == null);
		assert(storage.back == null);
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
	alias _bufferData = _buffer.data;

	private PieceStorage _sequence;

	this(S)(S initialText)
	{
		_buffer ~= initialText;
		_sequence.insertBack(new Piece(0, initialText.count!char));
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

		private this(Piece* piece, size_t length, string buffer)
		{
			_head = piece;
			_length = length;
			_buffer = buffer;

			if (_head)
			{
				_pieceLength = _head.length;
				_sequence = _buffer[_head.position..$];
			}
		}

		/// Input range primitives.
		@property bool empty() const 
		{
			return !_head && _length > 0;
		}

		@property size_t length()
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

		/// Forward range primitive.
		@property Range save() { return this; }
	}

	unittest
    {
        static assert(isForwardRange!Range);
    }

    Range opSlice()
    {
        return Range(_sequence.front, _sequence.length, cast(string)_buffer.data);
    }

	size_t length() @property
	{
		return _sequence.length;
	}

	/// Remove sequence of text starting at index of length length
	void remove(size_t removePos, size_t removeLength)
	{
		if (removePos >= _sequence.length || removeLength == 0) return;

		auto pair = _sequence.pieceAt!(Previous.yes)(removePos);
		
		if (removePos + removeLength > length)
		{
			removeLength = length - removePos;
		}

		//Piece* prev = pair.prev;
		Piece* piece = pair.piece;
		size_t piecePos = pair.piecePos;

		while(true)
		{
			if (piecePos == removePos)
			{
				if (piece.length > removeLength) // 1 case
				{
					piece.position += charlength(_buffer.data[piece.position..$], removeLength);
					_sequence.length -= removeLength;
					piece.length -= removeLength;
					
					return;
				}
				else // 3, 2 case
				{
					_sequence.remove(piece);

					if (piece.length < removeLength) // 3 case
					{
						piecePos += piece.length;
						removePos += piece.length;
						removeLength -= piece.length;
						//prev = piece;
						piece = piece.next;
						
						continue;
					}

					return; // 2 case
				}
			}
			else // piecePos < removePos
			{
				size_t pieceEnd = piecePos + piece.length - 1; // end of piece
				size_t removeEnd = removePos + removeLength - 1; // end of remove

				if (pieceEnd > removeEnd) // 4 case
				{
					//calculate length of the first piece and removed piece
					size_t firstAndRemoveLength = 
						charlength(_buffer.data[piece.position..$],
							removePos - piecePos + removeLength);

					_sequence.insertAfter(
						new Piece(piece.position + firstAndRemoveLength,
							piece.length - removeEnd - 1),
						piece);

					_sequence.length -= piece.length - piece.next.length + removeLength;
					piece.length = removePos - piecePos;

					return;
				}
				else // 5, 6 case
				{
					auto oldLength = piece.length;
					piece.length = removePos - piecePos;
					_sequence.length -= oldLength - piece.length;

					if (pieceEnd < removeEnd) // 6 case
					{
						piecePos = removeEnd + 1;
						removePos = removeEnd + 1;
						removeLength -= oldLength - piece.length;
						//prev = piece;
						piece = piece.next;

						continue; // case 6
					}

					return; // case 5
				}
			}
		}
	}

	unittest
	{
		PieceTable table = PieceTable("абвгде");

		assert(table.length == 6);
		auto piece1 = table._sequence.front;

		table.remove(0, 1); // case 1
		assert(table.length == 5);
		assert(table._sequence.front == piece1);
		writeln(table[]);
		assert(equal(table[], "бвгде"));

		table.remove(0, 6); // case 2
		assert(table.length == 0);
		assert(table._sequence.front == null);
		assert(table._sequence.back == null);
		assert(equal(table[], ""));

		table = PieceTable("абвгде");

		table.remove(2, 1); // case 4
		assert(table._sequence.front.length == 2);
		assert(table._sequence.front.next.length == 3);
		assert(table.length == 5);
		assert(equal(table[], "абгде"));

		table.remove(0, 5); // case 3 + case 2
		assert(table.length == 0);
		assert(table._sequence.front == null);
		assert(table._sequence.back == null);
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
	}

	void insert(S)(size_t index, S text)
	{
		size_t textLength = text.count!char;
		size_t bufferPos = _buffer.data.length;
		_buffer ~= text;

		Piece* middlePiece = new Piece(bufferPos, textLength);

		if (index == 0) // At the begining of text
		{
			_sequence.insertFront(middlePiece);
			return;
		}
		else if (index == _sequence.length) // At the end of text
		{
			_sequence.insertBack(middlePiece);
			return;
		}

		auto pair = _sequence.pieceAt!(Previous.yes)(index);

		if (index == pair.piecePos) // At the begining of piece
		{
			_sequence.insertAfter(middlePiece, pair.prev);
		}
		else // In the middle of piece
		{
			auto leftPieceLength = index - pair.piecePos;
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
	}
}