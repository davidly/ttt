#include <stdio.h>

#ifdef _MSC_VER

    #include <windows.h>
    #include <time.h>

    #if _MSC_VER > 1200  // not sure when this actually starts working
        #define USE_CHRONO
    #endif

    typedef unsigned __int64 LoopType;

#else // _MSC_VER

    #define USE_CHRONO
    #include <pthread.h>
    #include <thread>
    #include <unistd.h>
    #include <cstring>
    #include <cstdlib>
    #include <sched.h>

    typedef unsigned long long LoopType;

#endif // _MSC_VER

#ifdef USE_CHRONO

    #include <chrono>
    using namespace std::chrono;

    typedef high_resolution_clock::time_point ticktype;
    ticktype GetTicks() { return high_resolution_clock::now(); }
    long GetMilliseconds( ticktype nowTicks, ticktype thenTicks )
    {
        return (long) duration_cast<std::chrono::milliseconds>( nowTicks - thenTicks ).count();
    }

#else // USE_CHRONO

    typedef clock_t ticktype;
    ticktype GetTicks() { return clock(); }
    long GetMilliseconds( ticktype nowTicks, ticktype thenTicks )
    {
        return nowTicks - thenTicks;
    }

#endif // USE_CHRONO

// these are needed when compiling with a recent C++ compiler and an old linker so the binary can target Windows XP

#ifdef OLDSYMBOLS
extern "C" void __scrt_exe_initialize_mta() {}
extern "C" void _filter_x86_sse2_floating_point_exception() {}
#endif

const bool ABPrune = true;
const bool WinLosePrune = true;
const int SCORE_WIN = 6;
const int SCORE_TIE = 5;
const int SCORE_LOSE = 4;
const int SCORE_MAX = 9;
const int SCORE_MIN = 2;
const LoopType Iterations = 100000;
LoopType loopCount = Iterations; 

const char PieceX = 1;
const char PieceO = 2;
const char PieceBlank = 0;

static void Usage()
{
    printf( "  Tic Tac Toe" );

    printf( "Usage: ttt [iterations] [hexAffinityMask]\n" );
    printf( "  e.g.:    ttt 10000 0x3\n" );

    exit( 1 );
} //Usage

char pos0func( char * board )
{
    char x = board[0];
    
    if ( ( x == board[1] && x == board[2] ) ||
         ( x == board[3] && x == board[6] ) ||
         ( x == board[4] && x == board[8] ) )
        return x;
    return PieceBlank;
} //pos0func

char pos1func( char * board )
{
    char x = board[1];
    
    if ( ( x == board[0] && x == board[2] ) ||
         ( x == board[4] && x == board[7] ) )
        return x;
    return PieceBlank;
} //pos1func

char pos2func( char * board )
{
    char x = board[2];
    
    if ( ( x == board[0] && x == board[1] ) ||
         ( x == board[5] && x == board[8] ) ||
         ( x == board[4] && x == board[6] ) )
        return x;
    return PieceBlank;
} //pos2func

char pos3func( char * board )
{
    char x = board[3];
    
    if ( ( x == board[4] && x == board[5] ) ||
         ( x == board[0] && x == board[6] ) )
        return x;
    return PieceBlank;
} //pos3func

char pos4func( char * board )
{
    char x = board[4];
    
    if ( ( x == board[0] && x == board[8] ) ||
         ( x == board[2] && x == board[6] ) ||
         ( x == board[1] && x == board[7] ) ||
         ( x == board[3] && x == board[5] ) )
        return x;
    return PieceBlank;
} //pos4func

char pos5func( char * board )
{
    char x = board[5];
    
    if ( ( x == board[3] && x == board[4] ) ||
         ( x == board[2] && x == board[8] ) )
        return x;
    return PieceBlank;
} //pos5func

char pos6func( char * board )
{
    char x = board[6];
    
    if ( ( x == board[7] && x == board[8] ) ||
         ( x == board[0] && x == board[3] ) ||
         ( x == board[4] && x == board[2] ) )
        return x;
    return PieceBlank;
} //pos6func

char pos7func( char * board )
{
    char x = board[7];
    
    if ( ( x == board[6] && x == board[8] ) ||
         ( x == board[1] && x == board[4] ) )
        return x;
    return PieceBlank;
} //pos7func

char pos8func( char * board )
{
    char x = board[8];
    
    if ( ( x == board[6] && x == board[7] ) ||
         ( x == board[2] && x == board[5] ) ||
         ( x == board[0] && x == board[4] ) )
        return x;
    return PieceBlank;
} //pos8func

typedef char (*winnerfunc)( char * board );

winnerfunc winner_functions[] =
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

char LookForWinner( char * board )
{
    // about 8% faster with loops unrolled

    char p = board[0];
    if ( PieceBlank != p )
    {
        if ( p == board[1] && p == board[2] )
            return p;

        if ( p == board[3] && p == board[6] )
            return p;
    }

    p = board[3];
    if ( PieceBlank != p && p == board[4] && p == board[5] )
        return p;

    p = board[6];
    if ( PieceBlank != p && p == board[7] && p == board[8] )
        return p;

    p = board[1];
    if ( PieceBlank != p && p == board[4] && p == board[7] )
        return p;

    p = board[2];
    if ( PieceBlank != p && p == board[5] && p == board[8] )
        return p;

    p = board[4];
    if ( PieceBlank != p )
    {
        if ( ( p == board[0] ) && ( p == board[8] ) )
            return p;

        if ( ( p == board[2] ) && ( p == board[6] ) )
            return p;
    }

    return PieceBlank;
} //LookForWinner

void Sp( int x )
{
    for ( int i = 0; i < x; i++ )
        printf( " " );
}

unsigned int g_Moves = 0;

int MinMax( char * board, int alpha, int beta, int depth, int move )
{
    //InterlockedIncrement( &g_Moves );
    //g_Moves++;

    // scores are always with respect to X.
    // maximize on X moves; minimize on O moves
    // # of chars on board = 1 + depth
    // maximize and X moves are on odd depths.

    if ( depth >= 4 )
    {
        //char p = LookForWinner( board );
        char p = winner_functions[ move ]( board );

        if ( PieceBlank != p )
        {
            if ( PieceX == p )
                return SCORE_WIN;

            return SCORE_LOSE;
        }

        if ( 8 == depth )
            return SCORE_TIE;
    }

    int value;
    char pieceMove;

    if ( depth & 1 ) //maximize
    {
        value = SCORE_MIN;
        pieceMove = PieceX;
    }
    else
    {
        value = SCORE_MAX;
        pieceMove = PieceO;
    }

    for ( int p = 0; p < 9; p++ )
    {
        if ( PieceBlank == board[ p ] )
        {
            board[p] = pieceMove;
            int score = MinMax( board, alpha, beta, depth + 1, p );
            board[p] = PieceBlank;

            if ( depth & 1 ) //maximize 
            {
                if ( WinLosePrune && SCORE_WIN == score )
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
                if ( WinLosePrune && SCORE_LOSE == score )
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
} //MinMax

#ifdef _MSC_VER
    DWORD WINAPI
#else
    void * 
#endif

TTTThreadProc( void * param )
{
    size_t position = (size_t) param;
    char board[ 9 ];
    memset( board, 0, sizeof board );
    board[ position ] = PieceX;

    for ( LoopType times = 0; times < loopCount; times++ )
        MinMax( board, SCORE_MIN, SCORE_MAX, 0, position );

    return 0;
} //TTTThreadProc

int main( int argc, char * argv[] )
{
    if ( argc > 3 )
        Usage();

    if ( argc >= 2 )
    {
        #if _MSC_VER == 1200 
            loopCount = _atoi64( argv[ 1 ] );
        #else
            loopCount = strtoull( argv[ 1 ], 0, 10 );
        #endif
    }

#ifdef _MSC_VER
    #if _WIN32
        DWORD mask = 0;
    #else
        DWORD_PTR mask = 0;
    #endif

    if ( argc >= 3 )
    {
        #if _WIN32
            mask = strtoul( argv[2], 0, 16 );
        #else
            mask =_strtoui64( argv[2], 0, 16 );
        #endif
    }

    if ( 0 != mask )
    {
        printf( "affinity mask: %#llx\n", (ULONGLONG) mask );
        BOOL ok = SetProcessAffinityMask( GetCurrentProcess(), mask ); // sq3: 0x7 efficiency cores, 0x70 performance cores

        if ( !ok )
        {
            printf( "call to SetProcessAffinityMask failed with error %d\n", GetLastError() );
            exit( 0 );
        }
    }

#elif !defined(__APPLE__)

    //{
    //    cpu_set_t mask;
    //    long nproc, i;
    //    if ( sched_getaffinity( 0, sizeof( mask ), &mask ) == -1 )
    //        printf( "can't get affinity, errno %d\n", errno );
    //    else
    //    {
    //        long nproc = sysconf( _SC_NPROCESSORS_ONLN );
    //        printf( "sched_getaffinity = " );
    //        for ( long i = 0; i < nproc; i++ )
    //            printf( "%d ", CPU_ISSET( i, &mask ) );
    //        printf( "\n" );
    //    }
    //}

    unsigned long long affinity = 0;

    if ( argc >= 3 )
        affinity = strtoull( argv[ 2 ], 0, 16 );

    if ( 0 != affinity )
    {
        printf( "affinity mask: %#llx\n", affinity );

        cpu_set_t mask;
        CPU_ZERO( &mask );

        for ( long l = 0; l < 32; l++ )
        {
            int b = ( 1 << l );
            if ( 0 != ( b & affinity ) )
                CPU_SET( l, &mask );
        }

        int status = sched_setaffinity( 0, sizeof( mask ), &mask );
        if ( 0 != status )
        {
            printf( "can't set affinity, errno %d\n", errno );
            exit( -1 );
        }
    }
#endif //_MSC_VER

    ticktype startParallel = GetTicks();
    bool parallelRan = true;
    
#ifdef _MSC_VER
    HANDLE aHandles[ 2 ];
    DWORD dwID = 0; // required for Win98. On NT you can pass 0.
    aHandles[ 0 ] = CreateThread( 0, 0, TTTThreadProc, (void *) 0, 0, &dwID );
    aHandles[ 1 ] = CreateThread( 0, 0, TTTThreadProc, (void *) 4, 0, &dwID );
#else
    pthread_t threads[ 2 ];
    int ret = pthread_create( &threads[ 0 ], 0, TTTThreadProc, (void *) 0 ); 
    if ( 0 != ret )
    {
        // some environments like RVOS don't support threads
        parallelRan = false;
        goto no_threads;
    }
    pthread_create( &threads[ 1 ], 0, TTTThreadProc, (void *) 4 );
#endif

    TTTThreadProc( (void *) 1 );

#ifdef _MSC_VER
    WaitForMultipleObjects( 2, aHandles, TRUE, INFINITE );
    CloseHandle( aHandles[ 0 ] );
    CloseHandle( aHandles[ 1 ] );
#else
    pthread_join( threads[ 0 ], 0 );
    pthread_join( threads[ 1 ], 0 );
#endif

no_threads:

    ticktype endParallel = GetTicks();
    int parallelMoves = g_Moves;
    g_Moves = 0;
    
    ticktype startSerial = GetTicks();

    TTTThreadProc( (void *) 0 );
    TTTThreadProc( (void *) 1 );
    TTTThreadProc( (void *) 4 );

    ticktype endSerial = GetTicks();

    if ( 0 != g_Moves )
        printf( "moves examined: %d, parallel %d\n", g_Moves, parallelMoves );

    printf( "ran %llu iterations\n", loopCount );

    if ( parallelRan )
        printf( "parallel milliseconds: %ld\n", GetMilliseconds( endParallel, startParallel ) );
    
    printf( "serial   milliseconds: %ld\n", GetMilliseconds( endSerial, startSerial ) );

    return 0;
} //main


