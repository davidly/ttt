// prove you can't win at tic-tac-toe

using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

class TTT
{
    const bool JustOne = false;

    const bool ABPrune = true;
    const bool WinLosePrune = true;
    const int Iterations = 10000;
    const bool EnableDebug = false;
    const int SCORE_WIN = 6;
    const int SCORE_TIE = 5;
    const int SCORE_LOSE = 4;
    const int SCORE_MAX = 9;
    const int SCORE_MIN = 2;

    enum Piece : byte { blank = 0, X = 1, O = 2 }

    static Piece LookForWinner( Piece [] b )
    {
        // About 8% faster with loops unrolled

        Piece p = b[0];
        if ( Piece.blank != p )
        {
            if ( p == b[1] && p == b[2] )
                return p;
    
            if ( p == b[3] && p == b[6] )
                return p;
        }
    
        p = b[3];
        if ( Piece.blank != p && p == b[4] && p == b[5] )
            return p;

        p = b[6];
        if ( Piece.blank != p && p == b[7] && p == b[8] )
            return p;
    
        p = b[1];
        if ( Piece.blank != p && p == b[4] && p == b[7] )
            return p;

        p = b[2];
        if ( Piece.blank != p && p == b[5] && p == b[8] )
            return p;

        p = b[4];
        if ( Piece.blank != p )
        {
            if ( ( p == b[0] ) && ( p == b[8] ) )
                return p;

            if ( ( p == b[2] ) && ( p == b[6] ) )
                return p;
        }

        return Piece.blank;
    } //LookForWinner

    static Piece pos0func( Piece [] b )
    {
        Piece x = b[0];
        
        if ( ( x == b[1] && x == b[2] ) ||
             ( x == b[3] && x == b[6] ) ||
             ( x == b[4] && x == b[8] ) )
            return x;
        return Piece.blank;
    } //pos0func
    
    static Piece pos1func( Piece [] b )
    {
        Piece x = b[1];
        
        if ( ( x == b[0] && x == b[2] ) ||
             ( x == b[4] && x == b[7] ) )
            return x;
        return Piece.blank;
    } //pos1func
    
    static Piece pos2func( Piece [] b )
    {
        Piece x = b[2];
        
        if ( ( x == b[0] && x == b[1] ) ||
             ( x == b[5] && x == b[8] ) ||
             ( x == b[4] && x == b[6] ) )
            return x;
        return Piece.blank;
    } //pos2func
    
    static Piece pos3func( Piece [] b )
    {
        Piece x = b[3];
        
        if ( ( x == b[4] && x == b[5] ) ||
             ( x == b[0] && x == b[6] ) )
            return x;
        return Piece.blank;
    } //pos3func
    
    static Piece pos4func( Piece [] b )
    {
        Piece x = b[4];
        
        if ( ( x == b[0] && x == b[8] ) ||
             ( x == b[2] && x == b[6] ) ||
             ( x == b[1] && x == b[7] ) ||
             ( x == b[3] && x == b[5] ) )
            return x;
        return Piece.blank;
    } //pos4func
    
    static Piece pos5func( Piece [] b )
    {
        Piece x = b[5];
        
        if ( ( x == b[3] && x == b[4] ) ||
             ( x == b[2] && x == b[8] ) )
            return x;
        return Piece.blank;
    } //pos5func
    
    static Piece pos6func( Piece [] b )
    {
        Piece x = b[6];
        
        if ( ( x == b[7] && x == b[8] ) ||
             ( x == b[0] && x == b[3] ) ||
             ( x == b[4] && x == b[2] ) )
            return x;
        return Piece.blank;
    } //pos6func
    
    static Piece pos7func( Piece [] b )
    {
        Piece x = b[7];
        
        if ( ( x == b[6] && x == b[8] ) ||
             ( x == b[1] && x == b[4] ) )
            return x;
        return Piece.blank;
    } //pos7func
    
    static Piece pos8func( Piece [] b )
    {
        Piece x = b[8];
        
        if ( ( x == b[6] && x == b[7] ) ||
             ( x == b[2] && x == b[5] ) ||
             ( x == b[0] && x == b[4] ) )
            return x;
        return Piece.blank;
    } //pos8func

    delegate Piece winnerfunc( Piece [] b );
    
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

    static long evaluated = 0;

    static int MinMax( Piece [] b, int alpha, int beta, int depth, int move )
    {
        if ( JustOne )
        {
            // this increment is very slow on multi-core runs and it's just needed for testing/validation
            Interlocked.Increment( ref evaluated );
        }

//Console.Write( "{0}, {1}, {2}, {3}, ", alpha, beta, depth, move );
//for ( int i = 0; i < 9; i++ )
//{
//    Piece p = b[ i ];
//    Console.Write( "{0}", p == Piece.blank ? 0 : p == Piece.X ? 1 : 2  );
//}
//Console.WriteLine();

        // scores are always with respect to X.
        // maximize on X moves; minimize on O moves
        // # of pieces on board = 1 + depth

        if ( depth >= 4 )
        {
            // using the function lookup table is a little faster than LookForWinner

            //Piece p = LookForWinner( b );
            Piece p = winner_functions[ move ]( b );
//Console.WriteLine( "{0}", p == Piece.blank ? 0 : p == Piece.X ? 1 : 2 );

            if ( Piece.blank != p )
            {
                if ( Piece.X == p )
                   return SCORE_WIN;

                return SCORE_LOSE;
            }

            if ( 8 == depth )
                return SCORE_TIE;
        }

        int value;
        Piece pieceMove;

        if ( 0 != ( depth & 1 ) ) // maximize
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
            if ( Piece.blank == b[x] )
            {
                b[x] = pieceMove;
                int score = MinMax( b, alpha, beta, depth + 1, x );
                b[x] = Piece.blank;

                if ( 0 != ( depth & 1 ) ) // maximize
                {
                    if ( WinLosePrune && ( SCORE_WIN == score ) )
                        return SCORE_WIN;

                    if ( score > value )
                    {
                        value = score;

                        if ( ABPrune )
                        {
                            if ( value >= beta )
                                return value;
                            if ( value > alpha )
                                alpha = value;
                        }
                    }
                }
                else
                {
                    if ( WinLosePrune && ( SCORE_LOSE == score ) )
                        return SCORE_LOSE;

                    if ( score < value )
                    {
                        value = score;

                        if ( ABPrune )
                        {
                            if ( value <= alpha )
                                return value;
                            if ( value < beta )
                                beta = value;
                        }
                    }
                }
            }
        }

        return value;
    } //MinMaxAlphaBeta

    static void RunBoard( int move, int iterations = Iterations )
    {
        Piece [] b = new Piece[ 9 ];
        b[ move ] = Piece.X;
        int score;

        for ( int i = 0; i < iterations; i++ )
        {
           score = MinMax( b, SCORE_MIN, SCORE_MAX, 0, move );
           if ( SCORE_TIE != score )
               Console.WriteLine( "score isn't tie!" );
        }
    } //RunBoard

    static void Main( string[] args )
    {
        Stopwatch stopWatch = new Stopwatch();
        stopWatch.Start();

        try
        {
            if ( JustOne )
            {
                Console.WriteLine( "running once" );

                RunBoard( 0, 1 );
                Console.WriteLine( "moves evaluated: {0}", evaluated );

                RunBoard( 1, 1 );
                Console.WriteLine( "moves evaluated: {0}", evaluated );
    
                RunBoard( 4, 1 );
                Console.WriteLine( "moves evaluated: {0}", evaluated );
            }
            else
            {
                // Only 3 starting moves aren't transpositions and/or mirrors of other moves.
    
                long start = stopWatch.ElapsedMilliseconds;
    
                Parallel.For( 0, 3, i =>
                {
                    if ( 0 == i )
                        RunBoard( 0 );
                    else if ( 1 == i )
                        RunBoard( 1 );
                    else if ( 2 == i )
                        RunBoard( 4 );
                } );
    
                long parallelEnd = stopWatch.ElapsedMilliseconds;
                long parallelEvaluated = evaluated;
                evaluated = 0;

                RunBoard( 0 );
                RunBoard( 1 );
                RunBoard( 4 );
    
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
        }
    } //Main
} //HexDump

