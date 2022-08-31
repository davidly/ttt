//
// SS: Slow Send
// Tool to reliably send program files over a serial port to an Apple 1 clone and run them.
// Specifically, the RetroTechLyfe Apple 1 clone.
//
// They can be binary files of the form:
// 1000: 4C 71 10 66 69 6E 61 6C
// 1008: 20 6D 6F 76 65 20 63 6F
// 1010: 75 6E 74 20 00 00 00 00
// 1018: 00 00 00 00 00 00 00 00
// 1020: 00 00 00 00 00 00 00 33
// 1028: 32 37 36 38 00 69 6E 74
// 1030: 65 72 6E 61 6C 20 65 72
// 
// or Apple Basic files like:
// 
// 1 rem Apple 1 Basic version of app to prove you can't win at tic-tac-toe
// 30 dim b0(9), s1(10), s2(10), s4(10), s8(10), s6(10)
// 38 m1 = 0
// 39 gosub 1000
// 40 for l = 1 to 1
// 41 m1 = 0 : a1 = 2 : b1 = 9 : b0(1) = 1
// 45 gosub 4000
// ...

#include <stdio.h>

#include <chrono>
#include <vector>

using namespace std;
using namespace std::chrono;

#include <windows.h>

// 20ms is reliable, but it's right on the edge of failing (15ms fails often)

const DWORD msWait = 20;            // delay between sending characters
const DWORD msTimeouts = 20;        // timeouts when reading/writing to the COM port

static void Usage()
{
    printf( "Usage: ss\n" );
    printf( "  Send Slow -- sends commands to an Apple 1 over a serial port\n" );
    printf( "  arguments:\n" );
    printf( "      -b                     -- Transfer a BASIC program; 'E000 R' is invoked for BASIC when -s specified.\n" );
    printf( "      -p:x                   -- Select the PC's COM port, 1-9. Default is 4\n" );
    printf( "      -r:x                   -- Send a run command and time exectution.\n" );
    printf( "                                Default for assembly apps is to start execution at 0x1000\n" );
    printf( "                                Default for BASIC is just to invoke RUN\n" );
    printf( "      -s:filename            -- Sends the text in filename to the Apple 1\n" );
//    printf( "      -d:xxxx.xxxx,filename  -- Downloads the memory range to a local file\n" );
    printf( "  examples:\n" );
    printf( "      ss /p:3 /s:myfile.hex         (send myfile.hex over com3\n" );
    printf( "      ss /s:myfile.hex /r           (send then run the app at address 1000\n" );
    printf( "      ss /r                         (run the app already in RAM at address 1000\n" );
    printf( "      ss /b /r                      (run the BASIC app already in RAM with BASIC loaded\n" );
    printf( "      ss /s:myfile.bas /b /r        (start basic, transfer the basic app, and run it\n" );
    printf( "      ss /r:2000                    (run the app already in RAM at address 2000\n" );
//    printf( "      ss /p:1 /d:1000.1100,out.hex  (dump memory from 1000 to 1100 to the file out.hex\n" );
    printf( "  notes:\n" );
    printf( "      -- uploaded files should be in the format you'd type on the Apple 1; machine code or BASIC\n" );
    printf( "      -- execution time is approximate given how slow communication is. Run benchmarks multiple times\n" );
    printf( "      -- close terminal apps with the com port held open, or this app will fail with error 5\n" );
    printf( "      -- when running an app, SS will exit when it reads a $ from the app. Otherwise, ^c to exit\n" );
    printf( "         So, update any apps you want to time to print a '$' when it's done. It's a hack I know.\n" );

    exit( 1 );
} //Usage

void SendBytes( HANDLE serialHandle, const char * str )
{
    size_t len = strlen( str );

    for ( size_t i = 0; i < len; i++ )
    {
        DWORD dwWritten;
        BOOL ok = WriteFile( serialHandle, str + i, 1, &dwWritten, 0 );
        if ( !ok )
        {
            printf( "can't write in SendBytes, error %d\n", GetLastError() );
            exit( 1 );
        }

        Sleep( msWait );
    }
} //SendBytes

void PrintResponse( const char * response, DWORD dwRead )
{
    static bool prevNewline = false;

    for ( DWORD i = 0; i < dwRead; i++ )
    {
        char c = response[ i ];

        // ignore \r since \n will expand to \r\n in printf.
        // don't show consecutive \n characters to save screen real estate.

        if ( '\r' != c )
        {
            if ( '\n' == c )
            {
                if ( prevNewline )
                    continue;
                else
                    prevNewline = true;
            }
            else
                prevNewline = false;

            printf( "%c", response[ i ] );

            if ( '\\' == response[ i ] )
            {
                printf( "\nerror -- returned to monitor unexpectedly; bad RAM or line too long.\n" );
                exit( 1 );
            }
        }
    }
} //PrintResponse

void SendFile( HANDLE serialHandle, const char * acIn, bool isBASIC )
{
    DWORD dwWritten = 0;

    HANDLE hIn = CreateFile( acIn, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, 0, OPEN_EXISTING, 0, 0 );
    if ( INVALID_HANDLE_VALUE == hIn )
    {
        printf( "can't open input file, error %d\n", GetLastError() );
        exit( 1 );
    }

    LARGE_INTEGER liSize;
    GetFileSizeEx( hIn, &liSize );
    __int64 length = liSize.QuadPart;

    vector<char> input( length );
    DWORD dwRead = 0;
    BOOL ok = ReadFile( hIn, input.data(), (DWORD) length, &dwRead, 0 );
    if ( !ok )
    {
        printf( "can't read input file, error %d\n", GetLastError() );
        exit( 1 );
    }

    printf( "input file has %d bytes\n", dwRead );

    CloseHandle( hIn );

    // Read whatever the Apple 1 may want to send.
    // It may just be the Arduino serial port banner.

    char response[ 100 ];
    ok = ReadFile( serialHandle, response, sizeof response, &dwRead, 0 );
    if ( !ok )
    {
        printf( "can't read from COM port, error %d\n", GetLastError() );
        exit( 1 );
    }

    PrintResponse( response, dwRead );

    // Send something to warm up the connection

    SendBytes( serialHandle, "1000\r" );

    // Again, read what may be there

    ok = ReadFile( serialHandle, response, sizeof response, &dwRead, 0 );
    if ( !ok )
    {
        printf( "can't read from COM port, error %d\n", GetLastError() );
        exit( 1 );
    }

    PrintResponse( response, dwRead );

    if ( isBASIC )
    {
        SendBytes( serialHandle, "E000 R\r" );
    
        // read what may be there
    
        ok = ReadFile( serialHandle, response, sizeof response, &dwRead, 0 );
        if ( !ok )
        {
            printf( "can't read from COM port, error %d\n", GetLastError() );
            exit( 1 );
        }
    
        PrintResponse( response, dwRead );
    }

    for ( size_t i = 0; i < length; i++ )
    {
        char c = * ( input.data() + i );

        if ( 0x80 & c )
            printf( "why is the high bit on for an input character?\n" );

        // don't send \n since \r is sent and that's sufficient

        if ( '\n' != c )
        {
            ok = WriteFile( serialHandle, &c, 1, &dwWritten, 0 );
            if ( !ok || 1 != dwWritten )
            {
                printf( "can't write to COM port at offset %zd, error %d, written %d\n", i, GetLastError(), dwWritten );
                exit( 1 );
            }
    
            Sleep( msWait );
    
            dwRead = 0;
            ok = ReadFile( serialHandle, response, sizeof response, &dwRead, 0 );
            if ( !ok )
            {
                printf( "can't read from COM port, error %d\n", GetLastError() );
                exit( 1 );
            }
    
            PrintResponse( response, dwRead );
        }
    }

    // be sure to send the last line in case it doesn't have a newline at the end

    ok = WriteFile( serialHandle, "\r", 1, &dwWritten, 0 );
    if ( !ok )
    {
        printf( "can't write trailing \\r to COM port, error %d\n", GetLastError() );
        exit( 1 );
    }

    Sleep( msWait );

    ok = ReadFile( serialHandle, response, sizeof response, &dwRead, 0 );
    if ( !ok )
    {
        printf( "can't read after trailing \\r written to COM port, error %d\n", GetLastError() );
        exit( 1 );
    }

    PrintResponse( response, dwRead );
} //SendFile

void PrintNumberWithCommas( long long n )
{
    if ( n < 0 )
    {
        printf( "-" );
        PrintNumberWithCommas( -n );
        return;
    }
   
    if ( n < 1000 )
    {
        printf( "%lld", n );
        return;
    }

    PrintNumberWithCommas( n / 1000 );
    printf( ",%03lld", n % 1000 );
} //PrintNumberWithCommas

void RunApple1( HANDLE serialHandle, int startAddress, bool isBASIC )
{
    char response[ 100 ];
    DWORD dwRead;
    BOOL ok = ReadFile( serialHandle, response, sizeof response, &dwRead, 0 );
    if ( !ok )
    {
        printf( "can't read at start of RunApple1, error %d\n", GetLastError() );
        exit( 1 );
    }

    PrintResponse( response, dwRead );

    char acRunCommand[ 50 ];
    if ( isBASIC )
        strcpy( acRunCommand, "run\r" );
    else
        sprintf( acRunCommand, "%X R\r", startAddress );
    SendBytes( serialHandle, acRunCommand );

    // Timing won't be precise, in part because the response read is included in the time.
    // But there is a race condition otherwise; execution may complete before timing would start.
    // Run any benchmark multiple times so it completes in > 20 seconds to remove noise.

    high_resolution_clock::time_point tStart = high_resolution_clock::now();

    do
    {
        char response[ 100 ];
        ok = ReadFile( serialHandle, response, sizeof response, &dwRead, 0 );
        if ( !ok )
        {
            printf( "can't read in loop of RunApple1, error %d\n", GetLastError() );
            exit( 1 );
        }

        if ( 0 != dwRead )
        {
            PrintResponse( response, dwRead );

            for ( DWORD i = 0; i < dwRead; i++ )
            {
                // $ is a signal from my Apple 1 apps that indicate they are done.
                // This is a hack since there is no other way to know an app
                // is done running.

                if ( '$' == response[ i ] )
                    goto alldone;
            }
        }
    } while ( true );

alldone:
    high_resolution_clock::time_point tAfter = high_resolution_clock::now();
    long long runtime = duration_cast<std::chrono::milliseconds>( tAfter - tStart ).count();

    printf( "app run is complete; runtime was " );
    PrintNumberWithCommas( runtime );
    printf( " milliseconds\n" );
} //RunApple1

extern "C" int __cdecl main( int argc, char *argv[] )
{
    bool sendFile = false;
    bool runApple1 = false;
    bool downloadFile = false;
    bool isBASIC = false;
    int comPort = 4;
    int runAddress = 0x1000;

    char acIn[ MAX_PATH ] = {0};
    char acOut[ MAX_PATH ] = {0};

    for ( int i = 1; i < argc; i++ )
    {
        char * parg = argv[ i ];
        int arglen = strlen( parg );
        char c0 = parg[ 0 ];
        char c1 = tolower( parg[ 1 ] );

        if ( '-' == c0 || '/' == c0 )
        {
            if ( 'b' == c1 )
                isBASIC = true;
            else if ( 'p' == c1 )
            {
                if ( ':' != parg[2] != arglen < 4 )
                {
                    printf( "invalid COM port specified\n" );
                    Usage();
                }

                comPort = atoi( parg + 3 );
                if ( comPort < 1 || comPort > 9 )
                {
                    printf( "invalid COM port specified\n" );
                    Usage();
                }
            }
            else if ( 'r' == c1 )
            {
                runApple1 = true;
                if ( ':' == parg[ 2 ] )
                {
                    runAddress = strtol( parg + 3, 0, 16 );

                    if ( runAddress < 0 || runAddress > 0xffff )
                    {
                        printf( "invalid run address\n" );
                        Usage();
                    }
                }
            }
            else if ( 's' == c1 )
            {
                sendFile = true;

                if ( ':' != parg[2] != arglen < 4 )
                {
                    printf( "filename to send is invalid\n" );
                    Usage();
                }

                strcpy( acIn, parg + 3 );
            }
            else
                Usage();
        }
        else
        {
            Usage();
        }
    }

    if ( !sendFile && !runApple1 && !downloadFile )
    {
        printf( "no command specified\n" );
        Usage();
    }

    char acComPort[ 20 ];
    sprintf( acComPort, "\\\\.\\COM%d", comPort );
    HANDLE serialHandle = CreateFile( acComPort, GENERIC_READ | GENERIC_WRITE, 0, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0 );
    if ( INVALID_HANDLE_VALUE == serialHandle )
    {
        printf( "can't open COM port, error %d\n", GetLastError() );
        exit( 1 );
    }

    // The Arduino serial port on the RetroTechLyfe Apple 1 clone is configured with these parameters.
    // But the Apple 1 can't keep up with writes at this speed. Hence this app to slow things down.

    DCB serialParams = { 0 };
    serialParams.DCBlength = sizeof( serialParams );
    
    GetCommState( serialHandle, &serialParams );
    serialParams.BaudRate = 115200;
    serialParams.ByteSize = 8;
    serialParams.StopBits = 1;
    serialParams.Parity = NOPARITY;
    SetCommState( serialHandle, &serialParams );
    
    COMMTIMEOUTS timeout = { 0 };
    timeout.ReadIntervalTimeout = msTimeouts;
    timeout.ReadTotalTimeoutConstant = msTimeouts;
    timeout.ReadTotalTimeoutMultiplier = msTimeouts;
    timeout.WriteTotalTimeoutConstant = msTimeouts;
    timeout.WriteTotalTimeoutMultiplier = msTimeouts;
    
    SetCommTimeouts( serialHandle, &timeout );

    if ( sendFile )
        SendFile( serialHandle, acIn, isBASIC );

    if ( runApple1 )
        RunApple1( serialHandle, runAddress, isBASIC );

    CloseHandle( serialHandle );
    return 0;
} //Main

