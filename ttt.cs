using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

class TTT
{
    const bool ABPrune = true;
    const bool WinLosePrune = true;
    const int Iterations = 10000;
    const bool EnableDebug = false;
    const bool JustOne = false;
    const int SCORE_WIN = 6;
    const int SCORE_TIE = 5;
    const int SCORE_LOSE = 4;
    const int SCORE_MAX = 9;
    const int SCORE_MIN = 2;

    static void Usage()
    {
        Console.WriteLine( "Usage: ttt" );
        Console.WriteLine( "  Tic Tac Toe" );

        Environment.Exit( 1 );
    } //Usage

    enum Piece : byte { blank = 0, X = 1, O = 2 }

    class Board
    {
        public Piece [] board;

        public Board()
        {
            board = new Piece[9];
        }

        public void Clear()
        {
            for ( int x = 0; x < 9; x++ )
                board[x] = Piece.blank;
        }

        public void Print()
        {
            for ( int r = 0; r < 3; r++ )
            {
                for ( int c = 0; c < 3; c++ )
                {
                    Piece p = board[ r * 3 + c ];
                    Console.Write( "{0} ", Piece.blank == p ? " " : Piece.X == p ? "X" : "O" );
                }

                Console.WriteLine();
            }
        }

        public Piece LookForWinner()
        {
            // About 8% faster with loops unrolled

            Piece p = board[0];
            if ( Piece.blank != p )
            {
                if ( p == board[1] && p == board[2] )
                    return p;
    
                if ( p == board[3] && p == board[6] )
                    return p;
            }
    
            p = board[3];
            if ( Piece.blank != p && p == board[4] && p == board[5] )
                return p;
            p = board[6];
            if ( Piece.blank != p && p == board[7] && p == board[8] )
                return p;
    
            p = board[1];
            if ( Piece.blank != p && p == board[4] && p == board[7] )
                return p;
            p = board[2];
            if ( Piece.blank != p && p == board[5] && p == board[8] )
                return p;

            p = board[4];
            if ( Piece.blank != p )
            {
                if ( ( p == board[0] ) && ( p == board[8] ) )
                    return p;

                if ( ( p == board[2] ) && ( p == board[6] ) )
                    return p;
            }

            return Piece.blank;
        } //LookForWinner

        public bool Cats()
        {
            for ( int r = 0; r < 3; r++ )
                for ( int c = 0; c < 3; c++ )
                    if ( board[ r * 3 + c ] == Piece.blank )
                        return false;

            return true;
        } //Cats
    }
    static Piece pos0func( Board b )
    {
        Piece x = b.board[0];
        
        if ( ( x == b.board[1] && x == b.board[2] ) ||
             ( x == b.board[3] && x == b.board[6] ) ||
             ( x == b.board[4] && x == b.board[8] ) )
            return x;
        return Piece.blank;
    } //pos0func
    
    static Piece pos1func( Board b )
    {
        Piece x = b.board[1];
        
        if ( ( x == b.board[0] && x == b.board[2] ) ||
             ( x == b.board[4] && x == b.board[7] ) )
            return x;
        return Piece.blank;
    } //pos1func
    
    static Piece pos2func( Board b )
    {
        Piece x = b.board[2];
        
        if ( ( x == b.board[0] && x == b.board[1] ) ||
             ( x == b.board[5] && x == b.board[8] ) ||
             ( x == b.board[4] && x == b.board[6] ) )
            return x;
        return Piece.blank;
    } //pos2func
    
    static Piece pos3func( Board b )
    {
        Piece x = b.board[3];
        
        if ( ( x == b.board[4] && x == b.board[5] ) ||
             ( x == b.board[0] && x == b.board[6] ) )
            return x;
        return Piece.blank;
    } //pos3func
    
    static Piece pos4func( Board b )
    {
        Piece x = b.board[4];
        
        if ( ( x == b.board[0] && x == b.board[8] ) ||
             ( x == b.board[2] && x == b.board[6] ) ||
             ( x == b.board[1] && x == b.board[7] ) ||
             ( x == b.board[3] && x == b.board[5] ) )
            return x;
        return Piece.blank;
    } //pos4func
    
    static Piece pos5func( Board b )
    {
        Piece x = b.board[5];
        
        if ( ( x == b.board[3] && x == b.board[4] ) ||
             ( x == b.board[2] && x == b.board[8] ) )
            return x;
        return Piece.blank;
    } //pos5func
    
    static Piece pos6func( Board b )
    {
        Piece x = b.board[6];
        
        if ( ( x == b.board[7] && x == b.board[8] ) ||
             ( x == b.board[0] && x == b.board[3] ) ||
             ( x == b.board[4] && x == b.board[2] ) )
            return x;
        return Piece.blank;
    } //pos6func
    
    static Piece pos7func( Board b )
    {
        Piece x = b.board[7];
        
        if ( ( x == b.board[6] && x == b.board[8] ) ||
             ( x == b.board[1] && x == b.board[4] ) )
            return x;
        return Piece.blank;
    } //pos7func
    
    static Piece pos8func( Board b )
    {
        Piece x = b.board[8];
        
        if ( ( x == b.board[6] && x == b.board[7] ) ||
             ( x == b.board[2] && x == b.board[5] ) ||
             ( x == b.board[0] && x == b.board[4] ) )
            return x;
        return Piece.blank;
    } //pos8func

    delegate Piece winnerfunc( Board b );
    
    static winnerfunc [] winner_functions =
    {
        pos0func,
        pos1func,
        pos2func,
        pos3func,
        pos4func,
        pos5func,
        pos6func,
        pos7func,
        pos8func,
    };

    static void State( int depth, Board b )
    {
        Console.Write("D{0} ", depth );
        for ( int r = 0; r < 3; r++ )
            for ( int c = 0; c < 3; c++ )
                Console.Write( "{0}", b.board[ r * 3 + c ] == Piece.X ? 1 : b.board[ r * 3 + c ] == Piece.O ? 2 : 0);
    }

    static long evaluated = 0;

    static int MinMax( Board b, int alpha, int beta, int depth, int move )
    {
        if ( JustOne )
        {
            // this increment is very slow on multi-core runs and it's just needed for testing/validation
            Interlocked.Increment( ref evaluated );
        }

        // scores are always with respect to X.
        // maximize on X moves; minimize on O moves
        // # of pieces on board = 1 + depth

        if ( depth >= 4 )
        {
            // using the function lookup table is a little faster than LookForWinner

            //Piece p = b.LookForWinner();
            Piece p = winner_functions[ move ]( b );

            if ( Piece.X == p )
               return SCORE_WIN;

            if ( Piece.O == p )
                return SCORE_LOSE;

            if ( 8 == depth )
                return SCORE_TIE;
        }

        int value;
        Piece pieceMove;

        if ( 0 != ( depth & 1 ) ) //maximize
        {
            value = SCORE_MIN;
            pieceMove = Piece.X;
        }
        else
        {
            value = SCORE_MAX;
            pieceMove = Piece.O;
        }

        for ( int x = 0; x < 9; x++ )
        {
            if ( Piece.blank == b.board[x] )
            {
                b.board[x] = pieceMove;

                int score = MinMax( b, alpha, beta, depth + 1, x );

                b.board[x] = Piece.blank;

                if ( 0 != ( depth & 1 ) ) //maximize
                {
                    value = Math.Max( value, score );

                    if ( ABPrune )
                    {
                        alpha = Math.Max( alpha, value );
                        if ( alpha >= beta )
                            return value;
                    }

                    // can't do better than this

                    if ( WinLosePrune && ( SCORE_WIN == value ) )
                        return value;
                }
                else
                {
                    value = Math.Min( value, score );
                    if ( ABPrune )
                    {
                        beta = Math.Min( value, beta );
                        if ( beta <= alpha )
                            return value;
                    }

                    // can't do worse than this

                    if ( WinLosePrune && ( SCORE_LOSE == value ) )
                        return SCORE_LOSE;
                }
            }
        }


        Debug.Assert( ( 100 != Math.Abs( value ) ), "value is somehow +/- 100!" );

        return value;
    } //MinMax

    static void Main( string[] args )
    {
        Stopwatch stopWatch = new Stopwatch();
        stopWatch.Start();

        try
        {
            if ( JustOne )
            {
                Console.WriteLine( "running once" );
    
                Board b1 = new Board();
                b1.board[0] = Piece.X;
                int score = MinMax( b1, SCORE_MIN, SCORE_MAX, 0, 0 );
                if ( EnableDebug && SCORE_TIE != score )
                    Console.WriteLine( "invalid 0 result {0}", score );
                Console.WriteLine( "moves evaluated: {0}", evaluated );
    
                Board b2 = new Board();
                b2.board[1] = Piece.X;
                score = MinMax( b2, SCORE_MIN, SCORE_MAX, 0, 1 );
                if ( EnableDebug && SCORE_TIE != score )
                    Console.WriteLine( "invalid 2 result {0}", score );
                Console.WriteLine( "moves evaluated: {0}", evaluated );
    
                Board b3 = new Board();
                b3.board[4] = Piece.X;
                score = MinMax( b3, SCORE_MIN, SCORE_MAX, 0, 4 );
                if ( EnableDebug && SCORE_TIE != score )
                    Console.WriteLine( "invalid 3 result {0}", score );
                Console.WriteLine( "moves evaluated: {0}", evaluated );
            }
            else
            {
                // Only 3 starting moves aren't transpositions and/or mirrors of other moves.
    
                long start = stopWatch.ElapsedMilliseconds;
    
                Parallel.For( 0, 3, i =>
                {
                    if ( 0 == i )
                    {
                        Board b = new Board();
                        b.board[0] = Piece.X;
    
                        for ( int l = 0; l < Iterations; l++ )
                        {
                            int score = MinMax( b, SCORE_MIN, SCORE_MAX, 0, 0 );
                            if ( EnableDebug && SCORE_TIE != score )
                                Console.WriteLine( "invalid 0 result {0}", score );
                        }
                    }
                    else if ( 1 == i )
                    {
                        Board b = new Board();
                        b.board[1] = Piece.X;
    
                        for ( int l = 0; l < Iterations; l++ )
                        {
                            int score = MinMax( b, SCORE_MIN, SCORE_MAX, 0, 1 );
                            if ( EnableDebug && SCORE_TIE != score )
                                Console.WriteLine( "invalid 2 result {0}", score );
                        }
                    }
                    else if ( 2 == i )
                    {
                        Board b = new Board();
                        b.board[4] = Piece.X;
    
                        for ( int l = 0; l < Iterations; l++ )
                        {
                            int score = MinMax( b, SCORE_MIN, SCORE_MAX, 0, 4 );
                            if ( EnableDebug && SCORE_TIE != score )
                                Console.WriteLine( "invalid 3 result {0}", score );
                        }
                    }
                } );
    
                long parallelEnd = stopWatch.ElapsedMilliseconds;
    
                long parallelEvaluated = evaluated;
                evaluated = 0;
    
                Board b1 = new Board();
                b1.board[0] = Piece.X;
        
                Board b2 = new Board();
                b2.board[1] = Piece.X;
        
                Board b3 = new Board();
                b3.board[4] = Piece.X;
    
                for ( int l = 0; l < Iterations; l++ )
                {
                    int score = MinMax( b1, SCORE_MIN, SCORE_MAX, 0, 0 );
                    if ( EnableDebug && SCORE_TIE != score )
                        Console.WriteLine( "invalid 1 result {0}", score );
        
                    score = MinMax( b2, SCORE_MIN, SCORE_MAX, 0, 1 );
                    if ( EnableDebug && SCORE_TIE != score )
                        Console.WriteLine( "invalid 2 result {0}", score );
        
                    score = MinMax( b3, SCORE_MIN, SCORE_MAX, 0, 4 );
                    if ( EnableDebug && SCORE_TIE != score )
                        Console.WriteLine( "invalid 3 result {0}", score );
                }
    
                long end = stopWatch.ElapsedMilliseconds;

                if ( 0 != parallelEvaluated || 0 != evaluated )
                    Console.WriteLine( "moves evaluated, parallel {0} serial {1}", parallelEvaluated, evaluated );

                Console.WriteLine( "elapsed milliseconds for 10k runs, serial: {0,5}", end - parallelEnd );
                Console.WriteLine( "                                 parallel: {0,5}", parallelEnd - start );
            }
        }
        catch (Exception e)
        {
            Console.WriteLine( "ttt.exe caught an exception {0}", e.ToString() );
            Usage();
        }
    } //Main
} //HexDump

