/*
  How to build and run ttt.lua with LuaJit on 64-bit Windows:

    - Comment out run_app() in ttt.lua so the global app doesn't run. Code below calls run_board directly.
    - Git clone luajit -- start here: https://luajit.org/
    - In the src directory, run msvcbuild.bat in a vc64 bit window
    - Compile lua to an .obj file: luajit -b ttt.lua ttt.obj
    - Put lua in the include and lib paths, for example:
         set include=S:\luajit\luajit\src;%include%
         set lib=S:\luajit\luajit\src;%lib%
    - Build the c++ app, linking ttt.obj and lua51.lib:
        cl /nologo ttt_lj.cxx /Fa /I.\ /EHac /Zi /Gy /D_AMD64_ /link ntdll.lib lua51.lib ttt.obj /OPT:REF
    - Copy lua51.dll from the luajit src directory or put it in your path
    - Run ttt_lj.exe
    - Performance is about 6x faster than interpreted Lua and 4x slower than a real compiler.
    - LuaJit produces native code, but it's native code that emulates the Lua VM, unlike a real compiler.
*/

#include <windows.h>
#include <chrono>
#include <stdio.h>

using namespace std;
using namespace std::chrono;

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

LONG g_Moves = 0;

DWORD WINAPI TTTThreadProc( LPVOID param )
{
    size_t move = (size_t) param;

    lua_State * luaState = luaL_newstate();
    luaL_openlibs( luaState );
    lua_getglobal( luaState , "require" );
    lua_pushliteral( luaState, "ttt" );

    // set the state by running the global app first (if there is anything to run)
    // note: comment out the run_app() call at the bottom of ttt.lua, before
    // generating ttt.obj since run_board() is called here directly.

    int status = lua_pcall( luaState, 1, 0, 0 );
    if ( 0 != status )
    {
        printf( "Error: %s\n", lua_tostring( luaState, -1 ) );
        return 1;
    }

    lua_getglobal( luaState, "run_board" );
    lua_pushnumber( luaState, (lua_Number) move );
    status = lua_pcall( luaState, 1, 1, 0 );
    if ( 0 != status )
    {
        printf( "2nd location, Error: %s\n", lua_tostring( luaState, -1 ) );
        return 1;
    }

    int evaluated = lua_tonumber( luaState, -1 );
    InterlockedAdd( &g_Moves, evaluated );

    lua_close( luaState );
    return 0;
} //TTTThreadProc

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

int main( int argc, char * argv[] )
{
    high_resolution_clock::time_point tStart = high_resolution_clock::now();

    // Arrays start at 1 by default in Lua, so unique board positions are 1, 2, and 5

    HANDLE aHandles[ 2 ];
    aHandles[ 0 ] = CreateThread( 0, 0, TTTThreadProc, (LPVOID) 1, 0, 0 );
    aHandles[ 1 ] = CreateThread( 0, 0, TTTThreadProc, (LPVOID) 5, 0, 0 );

    TTTThreadProc( (LPVOID) 2 );

    WaitForMultipleObjects( _countof( aHandles ), aHandles, TRUE, INFINITE );

    for ( size_t i = 0; i < _countof( aHandles ); i++ )
        CloseHandle( aHandles[ i ] );

    high_resolution_clock::time_point tAfterMultiThreaded = high_resolution_clock::now();
    long long mtTime = duration_cast<std::chrono::milliseconds>( tAfterMultiThreaded - tStart ).count();
    printf( "multi-threaded:  " ); PrintNumberWithCommas( mtTime ); printf( " milliseconds\n" );
    printf( "parallel moves evaluated: %d\n", g_Moves );
    g_Moves = 0;

    high_resolution_clock::time_point tBeforeSingleThreaded = high_resolution_clock::now();

    TTTThreadProc( (LPVOID) 1 );
    TTTThreadProc( (LPVOID) 2 );
    TTTThreadProc( (LPVOID) 5 );

    high_resolution_clock::time_point tAfterSingleThreaded = high_resolution_clock::now();
    long long stTime = duration_cast<std::chrono::milliseconds>( tAfterSingleThreaded - tBeforeSingleThreaded ).count();
    printf( "single-threaded: " ); PrintNumberWithCommas( stTime ); printf( " milliseconds\n" );
    printf( "serial moves evaluated: %d\n", g_Moves );

    return 0;
} //main

