// a very basic basic interpreter. and compilers for x64 on Windows and arm64 on Apple Silicon.
// implements a small subset of gw-basic; just enough to run a tic-tac-toe proof of failure app.
// a few of the many limitations:
//    -- based on TRS-80 Model 100 gw-basic.
//    -- only integer variables (4 byte) are supported
//    -- variables can only be two characters long plus a mandatory %
//    -- string values work in PRINT statements and nowhere else
//    -- a new token ELAP$ for PRINT that shows elapsed time including milliseconds
//    -- keywords supported: (see "Operators" below).
//    -- Not supported: DEF, PLAY, OPEN, INKEY$, DATA, READ, and a very long list of others.
//    -- only arrays of 1 and 2 dimensions are supported
//
//  The grammar: (parens are literal and square brackets are to show options)
//
//    expression = term [additive]*
//    additive = [ + | - ] term
//    factor = ( expression ) | variable | constant
//    constant = (0-9)+
//    variable = varname | varname( expression )
//    varname = (a-z)+%
//    term = factor [multiplicative]*
//    multiplicative = [ * | / ] factor
//    relationalexpression = expression [relational]*
//    relational = [ < | > | <= | >= | = ] expression
//    logicalexpression = relationalexpression [logical]*
//    logical = [ AND | OR | XOR ] relationalexpression

#include <stdio.h>
#include <assert.h>

#include <algorithm>
#include <string>
#include <cstring>
#include <sstream>
#include <cctype>
#include <map>
#include <vector>
#include <chrono>

using namespace std;
using namespace std::chrono;

bool g_Tracing = false;
bool g_ExpressionOptimization = true;
int g_pc = 0;
struct LineOfCode;
vector<LineOfCode> g_linesOfCode;
#define g_lineno ( g_linesOfCode[ g_pc ].lineNumber )

//#define ENABLE_EXECUTION_TIME

#ifdef DEBUG
    const bool RangeCheckArrays = true;
    const bool EnableTracing = true;

    #define __makeinline __declspec(noinline)
    //#define __makeinline
#else
    const bool RangeCheckArrays = false;  // oh how I wish C# supported turning off bounds checking
    const bool EnableTracing = false;     // makes eveything 10% slower

    #define __makeinline __forceinline
    //#define __makeinline
#endif

#ifdef __APPLE__
    // __builtin_readcyclecounter() results in an illegal instruction exception at runtime.
    // On an M1 Mac, this yields much faster/better results than on Windows and Linux x64 machines.
 
    uint64_t __rdtsc( void )
    {
        uint64_t val;
        asm volatile("mrs %0, cntvct_el0" : "=r" (val ));
        return val;
    }
#endif

#ifdef _MSC_VER  
    #include <intrin.h>
#else // g++, clang++
    #define __assume( x )
    #undef __makeinline
    #define __makeinline inline
    #define _strnicmp strncasecmp
    #define _stricmp strcasecmp

    #ifndef _countof
        template < typename T, size_t N > size_t _countof( T ( & arr )[ N ] ) { return std::extent< T[ N ] >::value; }
    #endif

    void strcpy_s( char * pto, size_t size, const char * pfrom  )
    {
        strcpy( pto, pfrom );
    }
#endif

enum AssemblyTarget : int { x64Win, arm64Mac, i8080CPM };
AssemblyTarget g_AssemblyTarget = x64Win;

enum Token : int { 
    VARIABLE, GOSUB, GOTO, PRINT, RETURN, END,                     // statements
    REM, DIM, CONSTANT, OPENPAREN, CLOSEPAREN,
    MULT, DIV, PLUS, MINUS, EQ, NE, LE, GE, LT, GT, AND, OR, XOR,  // operators in order of precedence
    FOR, NEXT, IF, THEN, ELSE, LINENUM, STRING, TO, COMMA,
    COLON, SEMICOLON, EXPRESSION, TIME, ELAP, TRON, TROFF,
    ATOMIC, INC, DEC, NOT, INVALID };

const char * Tokens[] = { 
    "VARIABLE", "GOSUB", "GOTO", "PRINT", "RETURN", "END",
    "REM", "DIM", "CONSTANT", "OPENPAREN", "CLOSEPAREN",
    "MULT", "DIV", "PLUS", "MINUS", "EQ", "NE", "LE", "GE", "LT", "GT", "AND", "OR", "XOR",
    "FOR", "NEXT", "IF", "THEN", "ELSE", "LINENUM", "STRING", "TO", "COMMA",
    "COLON", "SEMICOLON", "EXPRESSION", "TIME$", "ELAP$", "TRON", "TROFF",
    "ATOMIC", "INC", "DEC", "NOT", "INVALID" };

const char * Operators[] = { 
    "VARIABLE", "GOSUB", "GOTO", "PRINT", "RETURN", "END",
    "REM", "DIM", "CONSTANT", "(", ")",
    "*", "/", "+", "-", "=", "<>", "<=", ">=", "<", ">", "&", "|", "^", 
    "FOR", "NEXT", "IF", "THEN", "ELSE", "LINENUM", "STRING", "TO", "COMMA",
    "COLON", "SEMICOLON", "EXPRESSION", "TIME$", "ELAP$", "TRON", "TROFF",
    "ATOMIC", "INC", "DEC", "NOT", "INVALID" };

const char * OperatorInstruction[] = { 
    0, 0, 0, 0, 0, 0,                          // filler
    0, 0, 0, 0, 0,                             // filler
    "imul", "idiv", "add", "sub", "sete", "setne", "setle", "setge", "setl", "setg", "and", "or", "xor", };

const char * OperatorInstructionArm64[] = {
    0, 0, 0, 0, 0, 0,                          // filler
    0, 0, 0, 0, 0,                             // filler
    "mul", "sdiv", "add", "sub", "sete", "setne", "setle", "setge", "setl", "setg", "and", "orr", "eor", };

// only the last 3 are used
const char * OperatorInstructioni8080[] = {
    0, 0, 0, 0, 0, 0,                          // filler
    0, 0, 0, 0, 0,                             // filler
    "mul", "sdiv", "add", "sub", "sete", "setne", "setle", "setge", "setl", "setg", "ana", "ora", "xra", };

const char * ConditionsArm64[] = { 
    0, 0, 0, 0, 0, 0,                          // filler
    0, 0, 0, 0, 0,                             // filler
    0, 0, 0, 0, "eq", "ne", "le", "ge", "lt", "gt", 0, 0, 0 };

const char * ConditionsNotArm64[] = { 
    0, 0, 0, 0, 0, 0,                          // filler
    0, 0, 0, 0, 0,                             // filler
    0, 0, 0, 0, "ne", "eq", "gt", "lt", "ge", "le", 0, 0, 0 };

// jump instruction if the condition is true

const char * RelationalInstruction[] = { 
    0, 0, 0, 0, 0, 0,                          // filler
    0, 0, 0, 0, 0,                             // filler
    0, 0, 0, 0, "je", "jne", "jle", "jge", "jl", "jg", 0, 0, 0, };

// jump instruction if the condition is false

const char * RelationalNotInstruction[] = { 
    0, 0, 0, 0, 0, 0,                          // filler
    0, 0, 0, 0, 0,                             // filler
    0, 0, 0, 0, "jne", "je", "jg", "jl", "jge", "jle", 0, 0, 0, };

const char * CMovInstruction[] = { 
    0, 0, 0, 0, 0, 0,                          // filler
    0, 0, 0, 0, 0,                             // filler
    0, 0, 0, 0, "cmove", "cmovne", "cmovle", "cmovge", "cmovl", "cmovg", 0, 0, 0, };

// the most frequently used variables are mapped to these registers

const char * MappedRegistersX64[] = {    "esi", "r9d", "r10d", "r11d", "r12d", "r13d", "r14d", "r15d" };
const char * MappedRegistersX64_64[] = { "rsi",  "r9",  "r10",  "r11",  "r12",  "r13",  "r14",  "r15" };

// Use of x10-x15 is dangerous since these aren't preserved during function calls.
// Whenever a call happens (to printf, time, etc.) use the macros save_volatile_registers and restore_volatile_registers.
// The macros are slow, but calling out is very uncommon and it's generally to slow functions.
// Use of the extra registers results in about a 3% overall benefit for tp.bas.
// Note that x16, x17, x18, x29, and x30 are reserved.

const char * MappedRegistersArm64[] = {    "w10", "w11", "w12", "w13", "w14", "w15", "w19", "w20", "w21", "w22", "w23", "w24", "w25", "w26", "w27", "w28" };
const char * MappedRegistersArm64_64[] = { "x10", "x11", "x12", "x13", "x14", "x15", "x19", "x20", "x21", "x22", "x23", "x24", "x25", "x26", "x27", "x28" };

__makeinline const char * TokenStr( Token i )
{
    if ( i < 0 || i > Token::INVALID )
    {
        printf( "token %d is malformed\n", i );
        return Tokens[ _countof( Tokens ) - 1 ];
    }

    return Tokens[ i ];
} //TokenStr

__makeinline bool isTokenOperator( Token t )
{
    return ( t >= Token::MULT && t <= Token::XOR );
} //isTokenOperator

__makeinline bool isTokenSimpleValue( Token t )
{
    return ( Token::CONSTANT == t || Token::VARIABLE == t );
} //isTokenSimpleValue

__makeinline bool isTokenStatement( Token t )
{
    return ( t >= Token::VARIABLE && t <= Token::END );
} //isTokenStatement

__makeinline bool isOperatorRelational( Token t )
{
    return ( t >= Token::EQ && t <= Token::GT );
} //isOperatorRelational

__makeinline bool isOperatorLogical( Token t )
{
    return ( t >= Token::AND && t <= Token::XOR );
} //isOperatorLogical

__makeinline bool isOperatorAdditive( Token t )
{
    return ( Token::PLUS == t || Token::MINUS == t );
} //isOperatorAdditive

__makeinline bool isOperatorMultiplicative( Token t )
{
    return ( Token::MULT == t || Token::DIV == t );
} //isOperatorMultiplicative

__makeinline bool FailsRangeCheck( int offset, size_t high )
{
    // check if an array access is outside the array. BASIC arrays are 0-based.

    return ( ( offset < 0 ) || ( offset >= high ) );
} //FailsRangeCheck

char * my_strlwr( char * str )
{
    unsigned char *p = (unsigned char *) str;

    while ( *p )
    {
        *p = (unsigned char) tolower( *p );
        p++;
    }
    return str;
}//my_strlwr

void replace_all( string & s, string const & toReplace, string const & replaceWith )
{
    ostringstream oss;
    size_t pos = 0;
    size_t prevPos = 0;

    do
    {
        prevPos = pos;
        pos = s.find( toReplace, pos );
        if (pos == string::npos )
            break;
        oss << s.substr( prevPos, pos - prevPos );
        oss << replaceWith;
        pos += toReplace.size();
    } while( true );

    oss << s.substr( prevPos );
    s = oss.str();
} //replace_all

string UnescapeBASICString( string & s )
{
    string str = s;
    replace_all( str, "\"\"", "\"" );
    return str;
} //UnescapeBASICString

struct Variable
{
    Variable( const char * v )
    {
        memset( this, 0, sizeof *this );
        assert( strlen( v ) <= 3 );
        strcpy_s( name, _countof( name ), v );
        my_strlwr( name );
    }

    int value;           // when a scalar
    char name[4];        // variables can only be 2 chars + type (%) + null
    int dimensions;      // 0 for scalar. 1 or 2 for arrays.
    int dims[ 2 ];       // only support up to 2 dimensional arrays.
    vector<int> array;   // actual array values
    int references;      // when generating assembler: how many references in the basic app?
    string reg;          // when generating assembler: register mapped to this variable, if any
};

struct TokenValue
{
    void Clear()
    {
        token = Token::INVALID;
        pVariable = 0;
        value = 0;
        strValue = "";
        dimensions = 0;
        dims[ 0 ] = 0;
        dims[ 1 ] = 0;
        extra = 0;
    }

    TokenValue( Token t )
    {
        Clear();
        token = t;
    } //TokenValue

    // note: 64 bytes in size, which is good because the compiler can use shl 6 for array lookups

    Token token;
    int value;             // value's definition varies depending on the token. 
    int dimensions;        // 0 for scalar or 1-2 if an array. Only non-0 for DIM statements
    int dims[ 2 ];         // only support up to 2 dimensional arrays. Only used for DIM statements
    int extra;             // filler for now. unused.
    Variable * pVariable;  // pointer to the actual variable where the value is stored
    string strValue;       // strValue's definition varies depending on the token.
#ifdef __APPLE__           // make structure size 64 bytes on mac/clang. Not needed for linux or Windows
    size_t extra2;
#endif
};

// maps to a line of BASIC

struct LineOfCode
{
    LineOfCode( int line, const char * code ) : 
        lineNumber( line ), firstToken( Token::INVALID ), sourceCode( code ), goTarget( false )

    #ifdef ENABLE_EXECUTION_TIME
        , timesExecuted( 0 ), duration( 0 )
    #endif

    {
        tokenValues.reserve( 8 );
    }

    // These tokens will be scattered through memory. I tried making them all contiguous
    // and there was no performance benefit

    Token firstToken;                  // optimization: first token in tokenValues.
    vector<TokenValue> tokenValues;    // vector of tokens on the line of code
    string sourceCode;                 // the original BASIC line of code
    int lineNumber;                    // line number in BASIC
    bool goTarget;                     // true if a goto/gosub points at this line.

    #ifdef ENABLE_EXECUTION_TIME
        uint64_t timesExecuted;       // # of times this line is executed
        uint64_t duration;            // execution time so far on this line of code
    #endif
};

struct ForGosubItem
{
    ForGosubItem( int f, int p )
    {
        isFor = f;
        pcReturn = p;
    }

    int isFor;     // true if FOR, false if GOSUB
    int pcReturn;  // where to return in a NEXT or RETURN statment
};

// this is faster than both <stack> and Stack using <vector> to implement a stack because there are no memory allocations.

const int maxStack = 60;

template <class T> class Stack
{
    int current;
    union { T items[ maxStack ]; };  // avoid constructors and destructors on each T by using a union

    public:
        __makeinline Stack() : current( 0 ) {}
        __makeinline void push( T const & x ) { assert( current < maxStack ); items[ current++ ] = x; }
        __makeinline size_t size() { return current; }
        __makeinline void pop() { assert( current > 0 ); current--; }
        __makeinline T & top() { assert( current > 0 ); return items[ current - 1 ]; }
        __makeinline T & operator[] ( size_t i ) { return items[ i ]; }
};

class CFile
{
    private:
        FILE * fp;

    public:
        CFile( FILE * file ) : fp( file ) {}
        ~CFile() { Close(); }
        FILE * get() { return fp; }
        void Close()
        {
            if ( NULL != fp )
            {
                fclose( fp );
                fp = NULL;
            }
        }
};

static void Usage()
{
    printf( "Usage: ba filename.bas [-a] [-e] [-l] [-m] [-p] [-t] [-x] [-8]\n" );
    printf( "  Basic interpreter\n" );
    printf( "  Arguments:     filename.bas     Subset of TRS-80 compatible BASIC\n" );
    printf( "                 -a               Generate Windows x64 'ml64' compatible assembler code to filename.asm\n" );
    printf( "                 -e               Show execution count and time for each line\n" );
    printf( "                 -l               Show 'pcode' listing\n" );
    printf( "                 -m               Generate Mac 'as -arch arm64' compatible assembler code to filename.s\n" );
    printf( "                 -o               Don't do expression optimization for assembly code\n" );
    printf( "                 -p               Show parse time for input file\n" );
    printf( "                 -r               Don't use registers for variables in assembly code\n" );
    printf( "                 -t               Show debug tracing\n" );
    printf( "                 -x               Parse only; don't execute the code\n" );
    printf( "                 -8               Generate CP/M 2.2 i8080 'asm' compatible assembler code to filename.asm\n" );

    exit( 1 );
} //Usage

long portable_filelen( FILE * fp )
{
    long current = ftell( fp );
    fseek( fp, 0, SEEK_END );
    long len = ftell( fp );
    fseek( fp, current, SEEK_SET );
    return len;
} //portable_filelen

bool isDigit( char c ) { return c >= '0' && c <= '9'; }
bool isAlpha( char c ) { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c < 'Z' ); }
bool isWhite( char c ) { return ' ' == c || 9 /* tab */ == c; }
bool isToken( char c ) { return isAlpha( c ) || ( '%' == c ); }
bool isOperator( char c ) { return '<' == c || '>' == c || '=' == c; }

__makeinline const char * pastNum( const char * p )
{
    while ( isDigit( *p ) )
        p++;
    return p;
} //pastNum

__makeinline void makelower( string & sl )
{
    std::transform( sl.begin(), sl.end(), sl.begin(),
                    [](unsigned char c){ return std::tolower(c); });
} //makelower

Token readTokenInner( const char * p, int & len )
{
    if ( 0 == *p )
    {
        len = 0;
        return Token::INVALID;
    }

    if ( '(' == *p )
    {
        len = 1;
        return Token::OPENPAREN;
    }

    if ( ')' == *p )
    {
        len = 1;
        return Token::CLOSEPAREN;
    }

    if ( ',' == *p )
    {
        len = 1;
        return Token::COMMA;
    }

    if ( ':' == *p )
    {
        len = 1;
        return Token::COLON;
    }

    if ( ';' == *p )
    {
        len = 1;
        return Token::SEMICOLON;
    }

    if ( '*' == *p )
    {
        len = 1;
        return Token::MULT;
    }

    if ( '/' == *p )
    {
        len = 1;
        return Token::DIV;
    }

    if ( '+' == *p )
    {
        len = 1;
        return Token::PLUS;
    }

    if ( '-' == *p )
    {
        len = 1;
        return Token::MINUS;
    }

    if ( '^' == *p )
    {
        len = 1;
        return Token::XOR;
    }

    if ( isDigit( *p ) )
    {
        len = (int) ( pastNum( p ) - p );
        return Token::CONSTANT;
    }

    if ( isOperator( *p ) )
    {
        if ( isOperator( * ( p + 1 ) ) )
        {
            len = 2;
            char c1 = *p;
            char c2 = * ( p + 1 );

            if ( c1 == '<' && c2 == '=' )
                return Token::LE;
            if ( c1 == '>' && c2 == '=' )
                return Token::GE;
            if ( c1 == '<' && c2 == '>' )
                return Token::NE;

            return Token::INVALID;
        }
        else
        {
            len = 1;

            if ( '<' == *p )
                return Token::LT;
            if ( '=' == *p )
                return Token::EQ;
            if ( '>' == *p )
                return Token::GT;

            return Token::INVALID;
        }
    }

    if ( *p == '"' )
    {
        const char * pend = strchr( p + 1, '"' );

        while ( pend && '"' == * ( pend + 1 ) )
            pend = strchr( pend + 2, '"' );

        if ( pend )
        {
            len = 1 + (int) ( pend - p );
            return Token::STRING;
        }

        return Token::INVALID;
    }

    if ( !_strnicmp( p, "TIME$", 5 ) )
    {
       len = 5;
       return Token::TIME;
    }

    if ( !_strnicmp( p, "ELAP$", 5 ) )
    {
        len = 5;
        return Token::ELAP;
    }

    len = 0;
    while ( ( isToken( * ( p + len ) ) ) && len < 10 )
        len++;

    if ( 1 == len && isAlpha( *p ) )
        return Token::VARIABLE; // in the future, this will be true

    if ( 2 == len )
    {
        if ( !_strnicmp( p, "OR", 2 ) )
            return Token::OR;

        if ( !_strnicmp( p, "IF", 2 ) )
            return Token::IF;

        if ( !_strnicmp( p, "TO", 2 ) )
            return Token::TO;

        if ( isAlpha( *p ) && ( '%' == * ( p + 1 ) ) )
            return Token::VARIABLE;
    }
    else if ( 3 == len )
    {
        if ( !_strnicmp( p, "REM", 3 ) )
            return Token::REM;

        if ( !_strnicmp( p, "DIM", 3 ) )
           return Token::DIM;

        if ( !_strnicmp( p, "AND", 3 ) )
           return Token::AND;

        if ( !_strnicmp( p, "FOR", 3 ) )
           return Token::FOR;

        if ( !_strnicmp( p, "END", 3 ) )
           return Token::END;

        if ( isAlpha( *p ) && isAlpha( * ( p + 1 ) ) && ( '%' == * ( p + 2 ) ) )
           return Token::VARIABLE;
    }
    else if ( 4 == len )
    {
        if ( !_strnicmp( p, "GOTO", 4 ) )
           return Token::GOTO;

        if ( !_strnicmp( p, "NEXT", 4 ) )
           return Token::NEXT;

        if ( !_strnicmp( p, "THEN", 4 ) )
           return Token::THEN;

        if ( !_strnicmp( p, "ELSE", 4 ) )
           return Token::ELSE;

        if ( !_strnicmp( p, "TRON", 4 ) )
           return Token::TRON;
    }
    else if ( 5 == len )
    {
        if ( !_strnicmp( p, "GOSUB", 5 ) )
           return Token::GOSUB;

        if ( !_strnicmp( p, "PRINT", 5 ) )
           return Token::PRINT;

        if ( !_strnicmp( p, "TROFF", 5 ) )
           return Token::TROFF;
    }

    else if ( 6 == len )
    {
        if ( !_strnicmp( p, "RETURN", 5 ) )
           return Token::RETURN;
    }

    return Token::INVALID;
} //readTokenInner

__makeinline Token readToken( const char * p, int & len )
{
    Token t = readTokenInner( p, len );

    if ( EnableTracing && g_Tracing )
        printf( "  read token %s from string '%s', length %d\n", TokenStr( t ), p, len );

    return t;
} //readToken

__makeinline int readNum( const char * p )
{
    if ( !isDigit( *p ) )
        return -1;

    return atoi( p );
} //readNum

void Fail( const char * error, size_t line, size_t column, const char * code )
{
    printf( "Error: %s at line %zd column %zd: %s\n", error, line, column, code );
    exit( 1 );
} //Fail

void RuntimeFail( const char * error, size_t line )
{
    printf( "Runtime Error: %s at line %zd\n", error, line );
    exit( 1 );
} //RuntimeFail

__makeinline const char * pastWhite( const char * p )
{
    while ( isWhite( *p ) )
        p++;
    return p;
} //PastWhite

const char * ParseExpression( vector<TokenValue> & lineTokens, const char * pline, const char * line, int fileLine )
{
    if ( EnableTracing && g_Tracing )
        printf( "  parsing expression from '%s'\n", pline );

    bool first = true;
    int parens = 0;
    int tokenCount = 0;
    TokenValue expToken( Token::EXPRESSION );
    expToken.value = 666;
    lineTokens.push_back( expToken );
    size_t exp = lineTokens.size() - 1;
    bool isNegative = false;

    do
    {
        int tokenLen = 0;
        pline = pastWhite( pline );
        Token token = readToken( pline, tokenLen );
        TokenValue tokenValue( token );
        tokenCount++;
        bool resetFirst = false;

        if ( Token::MINUS == token && first )
        {
            isNegative = true;
            pline += tokenLen;
        }
        else if ( Token::CONSTANT == token )
        {
            tokenValue.value = atoi( pline );
            if ( isNegative )
            {
                tokenValue.value = -tokenValue.value;
                tokenCount--;
                isNegative = false;
            }
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
        }
        else if ( Token::VARIABLE == token )
        {
            if ( isNegative )
            {
                TokenValue neg( Token::MINUS );
                lineTokens.push_back( neg );
                isNegative = false;
            }

            tokenValue.strValue.insert( 0, pline, tokenLen );

            if ( '%' != tokenValue.strValue[ tokenValue.strValue.length() - 1 ] )
                Fail( "integer variables must end with a % symbol", fileLine, 0, line );

            makelower( tokenValue.strValue );
            lineTokens.push_back( tokenValue );
            pline = pastWhite( pline + tokenLen );
            token = readToken( pline, tokenLen );
            if ( Token::OPENPAREN == token )
            {
                size_t iVarToken = lineTokens.size() - 1;
                lineTokens[ iVarToken ].dimensions = 1;

                tokenCount++;
                tokenValue.Clear();
                tokenValue.token = token;
                lineTokens.push_back( tokenValue );
                pline += tokenLen;

                size_t expression = lineTokens.size();

                pline = ParseExpression( lineTokens, pline, line, fileLine );
                tokenCount += lineTokens[ expression ].value;

                token = readToken( pline, tokenLen );
                if ( Token::COMMA == token )
                {
                    lineTokens[ iVarToken ].dimensions = 2;
                    tokenCount++;
                    tokenValue.Clear();
                    tokenValue.token = token;
                    lineTokens.push_back( tokenValue );
                    pline = pastWhite( pline + tokenLen );

                    size_t subexpression = lineTokens.size();
                    pline = ParseExpression( lineTokens, pline, line, fileLine );
                    tokenCount += lineTokens[ subexpression ].value;

                    pline = pastWhite( pline );
                    token = readToken( pline, tokenLen );
                }

                if ( Token::CLOSEPAREN != token )
                    Fail( "close parenthesis expected", fileLine, 0, line );

                tokenCount++;

                tokenValue.Clear();
                tokenValue.token = token;
                lineTokens.push_back( tokenValue );
                pline += tokenLen;
            }
        }
        else if ( Token::STRING == token )
        {
            if ( 1 != tokenCount )
                Fail( "string not expected", fileLine, 0, line );

            tokenValue.strValue.insert( 0, pline + 1, tokenLen - 2 );
            tokenValue.strValue = UnescapeBASICString( tokenValue.strValue );
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
        }
        else if ( isTokenOperator( token ) )
        {
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
            resetFirst = true;
        }
        else if ( Token::OPENPAREN == token )
        {
            if ( isNegative )
            {
                TokenValue neg( Token::MINUS );
                lineTokens.push_back( neg );
                isNegative = false;
            }

            parens++;
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
            resetFirst = true;
        }
        else if ( Token::CLOSEPAREN == token )
        {
            if ( 0 == parens )
                break;

            parens--;
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
            resetFirst = true;
            isNegative = false;
        }
        else if ( Token::TIME == token )
        {
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
        }
        else if ( Token::ELAP == token )
        {
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
        }
        else if ( Token::INVALID == token && 0 != tokenLen )
        {
            Fail( "invalid token", fileLine, pline - line, line );
        }
        else
        {
            break;
        }

        pline = pastWhite( pline );

        first = resetFirst;
    } while( true );

    if ( 0 != parens )
        Fail( "unbalanced parenthesis count", fileLine, 0, line );

    // Don't create empty expressions. Well-formed basic programs won't do this,
    // but ancient versions of the interpreter allow it, so I do too.

    if ( 1 == tokenCount )
    {
        TokenValue tokenValue( Token::CONSTANT );
        lineTokens.push_back( tokenValue );
        tokenCount++;
    }

    lineTokens[ exp ].value = tokenCount;

    return pline;
} //ParseExpression

const char * ParseStatements( Token token, vector<TokenValue> & lineTokens, const char * pline, const char * line, int fileLine )
{
    if ( EnableTracing && g_Tracing )
        printf( "  parsing statements from '%s' token %s\n", pline, TokenStr( token ) );

    do
    {
        if ( EnableTracing && g_Tracing )
            printf( "  top of ParseStatements, token %s\n", TokenStr( token ) );

        if ( !isTokenStatement( token ) )
            Fail( "expected statement", fileLine, 1 + pline - line , line );

        TokenValue tokenValue( token );
        int tokenLen = 0;
        token = readToken( pline, tokenLen ); // redundant read to get length

        if ( EnableTracing && g_Tracing )
            printf( "ParseStatements loop read top-level token %s\n", TokenStr( token ) );

        if ( Token::VARIABLE == token )
        {
            tokenValue.strValue.insert( 0, pline, tokenLen );

            if ( '%' != tokenValue.strValue[ tokenValue.strValue.length() - 1 ] )
                Fail( "integer variables must end with a % symbol", fileLine, 0, line );

            makelower( tokenValue.strValue );
            lineTokens.push_back( tokenValue );
            size_t iVarToken = lineTokens.size() - 1;

            pline = pastWhite( pline + tokenLen );
            token = readToken( pline, tokenLen );

            if ( Token::OPENPAREN == token )
            {
                lineTokens[ iVarToken ].dimensions++;

                tokenValue.Clear();
                tokenValue.token = token;
                lineTokens.push_back( tokenValue );

                pline = pastWhite( pline + tokenLen );
                pline = ParseExpression( lineTokens, pline, line, fileLine );

                token = readToken( pline, tokenLen );
                if ( Token::CLOSEPAREN == token )
                {
                    tokenValue.Clear();
                    tokenValue.token = token;
                    lineTokens.push_back( tokenValue );
                }
                else if ( Token::COMMA == token )
                {
                    lineTokens[ iVarToken ].dimensions++;

                    tokenValue.Clear();
                    tokenValue.token = token;
                    lineTokens.push_back( tokenValue );

                    pline = pastWhite( pline + tokenLen );
                    pline = ParseExpression( lineTokens, pline, line, fileLine );

                    pline = pastWhite( pline );
                    token = readToken( pline, tokenLen );

                    if ( Token::CLOSEPAREN == token )
                    {
                        tokenValue.Clear();
                        tokenValue.token = token;
                        lineTokens.push_back( tokenValue );
                    }
                    else
                        Fail( "expected ')' in array access", fileLine, 1 + pline - line , line );
                }
                else
                    Fail( "expected ')' or ',' in array access", fileLine, 1 + pline - line , line );

                pline = pastWhite( pline + tokenLen );
                token = readToken( pline, tokenLen );
            }

            if ( Token::EQ == token )
            {
                tokenValue.Clear();
                tokenValue.token = token;
                lineTokens.push_back( tokenValue );

                pline = pastWhite( pline + tokenLen );
                pline = ParseExpression( lineTokens, pline, line, fileLine );
            }
            else
                Fail( "expected '=' after a variable reference", fileLine, 1 + pline - line , line );
        }
        else if ( Token::GOSUB == token )
        {
            pline = pastWhite( pline + tokenLen );
            token = readToken( pline, tokenLen );
            if ( Token::CONSTANT == token )
            {
                tokenValue.value = atoi( pline );
                lineTokens.push_back( tokenValue );
            }
            else
                Fail( "expected a line number constant with GOSUB", fileLine, 1 + pline - line, line );

            pline += tokenLen;
        }
        else if ( Token::GOTO == token )
        {
            pline = pastWhite( pline + tokenLen );
            token = readToken( pline, tokenLen );
            if ( Token::CONSTANT == token )
            {
                tokenValue.value = atoi( pline );
                lineTokens.push_back( tokenValue );
            }
            else
                Fail( "expected a line number constant with GOTO", fileLine, 1 + pline - line, line );

            pline += tokenLen;
        }
        else if ( Token::END == token )
        {
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
        }
        else if ( Token::RETURN == token )
        {
            lineTokens.push_back( tokenValue );
            pline += tokenLen;
        }
        else if ( Token::PRINT == token )
        {
            lineTokens.push_back( tokenValue );
            pline = pastWhite( pline + tokenLen );

            do
            {
                pline = ParseExpression( lineTokens, pline, line, fileLine );
                pline = pastWhite( pline );
                token = readToken( pline, tokenLen );

                if ( Token::SEMICOLON == token )
                {
                    pline = pastWhite( pline + tokenLen );
                    continue;
                }
                else if ( Token::ELSE == token )
                    break;
                else if ( Token::INVALID != token )
                    Fail( "unexpected PRINT arguments", fileLine, 1 + pline - line, line );
                else
                    break;
            } while( true );
        }

        pline = pastWhite( pline );
        token = readToken( pline, tokenLen );

        if ( Token::COLON == token )
        {
            pline = pastWhite( pline + tokenLen );
            token = readToken( pline, tokenLen );
        }
        else
            break;
    } while( true );

    return pline;
} //ParseStatements

__makeinline Variable * FindVariable( map<string, Variable> const & varmap, string const & name )
{
    // cast away const because the iterator requires non-const. yuck.

    map<string, Variable> &vm = ( map<string, Variable> & ) varmap;

    map<string,Variable>::iterator it;
    it = vm.find( name );
    if ( it == vm.end() )
        return 0;

    return & it->second;
} //FindVariable

__makeinline Variable * GetVariablePerhapsCreate( TokenValue & val, map<string, Variable>  & varmap )
{
    Variable *pvar = val.pVariable;
    if ( pvar )
        return pvar;

    if ( !pvar )
    {
        pvar = FindVariable( varmap, val.strValue );
        val.pVariable = pvar;
    }

    if ( !pvar )
    {
        Variable var( val.strValue.c_str() );
        varmap.emplace( var.name, var );
        pvar = FindVariable( varmap, var.name );
        val.pVariable = pvar;
    }

    return pvar;
} //GetVariablePerhapsCreate

__makeinline int GetSimpleValue( TokenValue const & val )
{
    assert( isTokenSimpleValue( val.token ) );

    if ( Token::CONSTANT == val.token )
        return val.value;

    assert( 0 != val.pVariable );

    return val.pVariable->value;
} //GetSimpleValue

__makeinline int run_operator( int a, Token t, int b )
{
    // in order of actual usage when running ttt

    switch( t )
    {
        case Token::EQ    : return ( a == b );
        case Token::AND   : return ( a & b );
        case Token::LT    : return ( a < b );
        case Token::GT    : return ( a > b );
        case Token::GE    : return ( a >= b );
        case Token::MINUS : return ( a - b );
        case Token::LE    : return ( a <= b );
        case Token::OR    : return ( a | b );
        case Token::PLUS  : return ( a + b );
        case Token::NE    : return ( a != b );
        case Token::MULT  : return ( a * b );
        case Token::DIV   : return ( a / b );
        case Token::XOR   : return ( a ^ b );
        default: __assume( false );
    }

    assert( !"invalid operator token" );
    return 0;
} //run_operator

__makeinline int run_operator_logical( int a, Token t, int b )
{
    switch( t )
    {
        case Token::AND   : return ( a & b );
        case Token::OR    : return ( a | b );
        case Token::XOR   : return ( a ^ b );
        default: __assume( false );
    }

    assert( !"invalid logical operator token" );
    return 0;
} //run_operator_p3

__makeinline int run_operator_relational( int a, Token t, int b )
{
    switch( t )
    {
        case Token::EQ    : return ( a == b );
        case Token::LT    : return ( a < b );
        case Token::NE    : return ( a != b );
        case Token::GT    : return ( a > b );
        case Token::GE    : return ( a >= b );
        case Token::LE    : return ( a <= b );
        default: __assume( false );
    }

    assert( !"invalid relational operator token" );
    return 0;
} //run_operator_relational

__makeinline int run_operator_additive( int a, Token t, int b )
{
    switch( t )
    {
        case Token::PLUS  : return ( a + b );
        case Token::MINUS : return ( a - b );
        default: __assume( false );
    }

    assert( !"invalid additive operator token" );
    return 0;
} //run_operator_additive

__makeinline int run_operator_multiplicative( int a, Token t, int b )
{
    switch( t )
    {
        case Token::MULT  : return ( a * b );
        case Token::DIV   : return ( a / b );
        default: __assume( false );
    }

    assert( !"invalid multiplicative operator token" );
    return 0;
} //run_operator_multiplicative

int EvaluateExpression( int & iToken, int beyond, vector<TokenValue> const & vals );
int EvaluateFactor( int & iToken, int beyond, vector<TokenValue> const & vals );
int EvaluateTerm( int & iToken, int beyond, vector<TokenValue> const & vals );

__makeinline int EvaluateMultiplicative( int & iToken, int beyond, vector<TokenValue> const & vals, int leftValue )
{
    assert( iToken < beyond );
    Token op = vals[ iToken ].token;
    iToken++;

    int rightValue = EvaluateFactor( iToken, beyond, vals );

    return run_operator_multiplicative( leftValue, op, rightValue );
} //EvaluateMultiplicative

int EvaluateTerm( int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
        printf( "Evaluate term # %d, %s\n", iToken, TokenStr( vals[ iToken ].token ) );

    int value = EvaluateFactor( iToken, beyond, vals );

    if ( iToken >= beyond )
        return value;

    Token t = vals[ iToken ].token;

    while ( isOperatorMultiplicative( t ) )
    {
        value = EvaluateMultiplicative( iToken, beyond, vals, value );

        if ( iToken >= beyond )
            break;

        t = vals[ iToken ].token;

        if ( EnableTracing && g_Tracing )
            printf( "next token  %d in EvaluateTerm: %d\n", iToken, t );
    }

    if ( EnableTracing && g_Tracing )
        printf( "Evaluate term returning %d\n", value );

    return value;
} //EvaluateTerm

int EvaluateFactor( int & iToken, int beyond, vector<TokenValue> const & vals )
{
    if ( EnableTracing && g_Tracing )
        printf( " Evaluate factor # %d, %s\n", iToken, TokenStr( vals[ iToken ].token ) );

    size_t limit = iToken + vals.size();
    int value = 0;

    if ( iToken < beyond )
    {
        Token t = vals[ iToken ].token;

        if ( Token::EXPRESSION == t )
        {
            iToken++;
            t = vals[ iToken ].token;
        }

        if ( Token::OPENPAREN == t )
        {
            iToken++;
            value = EvaluateExpression( iToken, beyond, vals );
            assert( Token::CLOSEPAREN == vals[ iToken ].token );
            iToken++;
        }
        else if ( Token::VARIABLE == t )
        {
            Variable *pvar = vals[ iToken ].pVariable;

            if ( 0 == pvar->dimensions )
            {
                value = pvar->value;
                iToken++;

                if ( iToken < vals.size() && Token::OPENPAREN == vals[ iToken ].token )
                    RuntimeFail( "scalar variable used as an array", g_lineno );
            }
            else if ( 1 == pvar->dimensions )
            {
                iToken++; // variable

                if ( Token::OPENPAREN != vals[ iToken ].token )
                    RuntimeFail( "open parenthesis expected", g_lineno );

                iToken++; // open paren

                assert( Token::EXPRESSION == vals[ iToken ].token );

                int offset;
                if ( 2 == vals[ iToken ].value && Token::CONSTANT == vals[ iToken + 1 ].token ) // save recursion
                {
                    offset = vals[ iToken + 1 ].value;
                    iToken += vals[ iToken ].value;
                }
                else
                    offset = EvaluateExpression( iToken, iToken + vals[ iToken ].value, vals );

                if ( RangeCheckArrays && FailsRangeCheck( offset, pvar->array.size() ) )
                    RuntimeFail( "access of array beyond end", g_lineno );

                if ( RangeCheckArrays && iToken < limit && Token::COMMA == vals[ t ].token )
                    RuntimeFail( "accessed 1-dimensional array with 2 dimensions", g_lineno );

                value = pvar->array[ offset ];

                iToken++; // closing paren
            }
            else if ( 2 == pvar->dimensions )
            {
                iToken++; // variable

                if ( Token::OPENPAREN != vals[ iToken ].token )
                    RuntimeFail( "open parenthesis expected", g_lineno );

                iToken++; // open paren

                assert( Token::EXPRESSION == vals[ iToken ].token );
                int offset1 = EvaluateExpression( iToken, iToken + vals[ iToken ].value, vals );

                if ( RangeCheckArrays && FailsRangeCheck( offset1, pvar->dims[ 0 ] ) )
                    RuntimeFail( "access of first dimension in 2-dimensional array beyond end", g_lineno );

                if ( Token::COMMA != vals[ iToken ].token )
                    RuntimeFail( "comma expected for 2-dimensional array", g_lineno );

                iToken++; // comma

                assert( Token::EXPRESSION == vals[ iToken ].token );
                int offset2 = EvaluateExpression( iToken, iToken + vals[ iToken ].value, vals );

                if ( RangeCheckArrays && FailsRangeCheck( offset2, pvar->dims[ 1 ] ) )
                    RuntimeFail( "access of second dimension in 2-dimensional array beyond end", g_lineno );

                int arrayoffset = offset1 * pvar->dims[ 1 ] + offset2;
                assert( arrayoffset < pvar->array.size() );

                value = pvar->array[ arrayoffset ];

                iToken++; // closing paren
            }
        }
        else if ( Token::CONSTANT == t )
        {
            value = vals[ iToken ].value;
            iToken++;
        }
        else if ( Token::CLOSEPAREN == t )
        {
            assert( false && "why is there a close paren?" );
            iToken++;
        }
        else if ( Token::NOT == t )
        {
            iToken++;

            assert( Token::VARIABLE == vals[ iToken ].token );

            Variable *pvar = vals[ iToken ].pVariable;
            value = ! ( pvar->value );

            iToken ++;
        }
        else
        {
            printf( "unexpected token in EvaluateFactor %d %s\n", t, TokenStr( t ) );
            RuntimeFail( "unexpected token", g_lineno );
        }
    }

    if ( EnableTracing && g_Tracing )
        printf( " leaving EvaluateFactor, value %d\n", value );

    return value;
} //EvaluateFactor

__makeinline int EvaluateAdditive( int & iToken, int beyond, vector<TokenValue> const & vals, int valueLeft )
{
    if ( EnableTracing && g_Tracing )
        printf( "in Evaluate add, iToken %d\n", iToken );

    Token op = vals[ iToken ].token;
    iToken++;

    int valueRight = EvaluateTerm( iToken, beyond, vals );

    return run_operator_additive( valueLeft, op, valueRight );
} //EvaluateAdditive

int EvaluateExpression( int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
    {
        printf( "Evaluate expression for line %d token # %d %s\n", g_lineno, iToken, TokenStr( vals[ iToken ].token ) );

        for ( int i = iToken; i < vals.size(); i++ )
            printf( "    %d:    %s\n", i, TokenStr( vals[ i ].token ) );
    }

    if ( Token::EXPRESSION == vals[ iToken ].token )
        iToken++;

    // look for a unary + or -
    int value = 0;

    if ( isOperatorAdditive( vals[ iToken ].token ) )
    {
        // make the left side of the operation 0
    }
    else
    {
        value = EvaluateTerm( iToken, beyond, vals );

        if ( iToken >= beyond )
            return value;
    }

    Token t = vals[ iToken ].token;

    while ( isOperatorAdditive( t ) )
    {
        value = EvaluateAdditive( iToken, beyond, vals, value );

        if ( iToken >= beyond )
            break;

        t = vals[ iToken ].token;
    }

    if ( EnableTracing && g_Tracing )
        printf( " leaving EvaluateExpression, value %d\n", value );

    return value;
} //EvaluateExpression

__makeinline int EvaluateRelational( int & iToken, int beyond, vector<TokenValue> const & vals, int leftValue )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
        printf( "in Evaluate relational, iToken %d\n", iToken );

    Token op = vals[ iToken ].token;
    iToken++;

    int rightValue = EvaluateExpression( iToken, beyond, vals );

    int value = run_operator_relational( leftValue, op, rightValue );

    if ( EnableTracing && g_Tracing )
        printf( " leaving EvaluateRelational, value %d\n", value );

    return value;
} //EvaluateRelational

__makeinline int EvaluateRelationalExpression( int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
    {
        printf( "Evaluate relational expression for line %d token # %d %s\n", g_lineno, iToken, TokenStr( vals[ iToken ].token ) );

        for ( int i = iToken; i < beyond; i++ )
            printf( "    %d:    %s\n", i, TokenStr( vals[ i ].token ) );
    }

    // This won't be an EXPRESSION for cases like x = x + ...
    // But it will be EXPRESSION when called from EvaluateLogicalExpression

    if ( Token::EXPRESSION == vals[ iToken ].token )
        iToken++;

    int value = EvaluateExpression( iToken, beyond, vals );

    if ( iToken >= vals.size() )
        return value;

    Token t = vals[ iToken ].token;

    while ( isOperatorRelational( t ) )
    {
        value = EvaluateRelational( iToken, beyond, vals, value );

        if ( iToken >= beyond )
            break;

        t = vals[ iToken ].token;
    }

    if ( EnableTracing && g_Tracing )
        printf( " leaving EvaluateRelationalExpression, value %d\n", value );

    return value;
} //EvaluateRelationalExpression

__makeinline int EvaluateLogical( int & iToken, int beyond, vector<TokenValue> const & vals, int leftValue )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
        printf( "in Evaluate logical, iToken %d\n", iToken );

    Token op = vals[ iToken ].token;
    iToken++;

    int rightValue = EvaluateRelationalExpression( iToken, beyond, vals );

    int value = run_operator_logical( leftValue, op, rightValue );

    if ( EnableTracing && g_Tracing )
        printf( " leaving EvaluateLogical, value %d\n", value );

    return value;
} //EvaluateLogical

__makeinline int EvaluateLogicalExpression( int & iToken, vector<TokenValue> const & vals )
{
    int beyond = iToken + vals[ iToken ].value;

    assert( iToken < beyond );
    assert( beyond <= vals.size() );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
    {
        printf( "Evaluate logical expression for line %d token # %d %s\n", g_lineno, iToken, TokenStr( vals[ iToken ].token ) );

        for ( int i = iToken; i < beyond; i++ )
            printf( "    %d:    %s\n", i, TokenStr( vals[ i ].token ) );
    }

    assert( Token::EXPRESSION == vals[ iToken ].token );

    int value = EvaluateRelationalExpression( iToken, beyond, vals );

    if ( iToken >= beyond )
        return value;

    Token t = vals[ iToken ].token;

    while ( isOperatorLogical( t ) )
    {
        value = EvaluateLogical( iToken, beyond, vals, value );

        if ( iToken >= beyond )
            break;

        t = vals[ iToken ].token;
    }

    if ( EnableTracing && g_Tracing )
        printf( " leaving EvaluateLogicalExpression, value %d\n", value );

    return value;
} //EvaluateLogicalExpression

__makeinline int EvaluateExpressionOptimized( int & iToken, vector<TokenValue> const & vals )
{
    if ( EnableTracing && g_Tracing )
        printf( "EvaluateExpressionOptimized starting at line %d, token %d, which is %s, length %d\n",
                g_lineno, iToken, TokenStr( vals[ iToken ].token ), vals[ iToken ].value );

    assert( Token::EXPRESSION == vals[ iToken ].token );

    int value;
    int tokenCount = vals[ iToken ].value;

    #ifdef DEBUG
        int beyond = iToken + tokenCount;
    #endif

    // implement a few specialized/optimized cases in order of usage

    if ( 2 == tokenCount )
    {
        value = GetSimpleValue( vals[ iToken + 1 ] );
        iToken += tokenCount;
    }
    else if ( 6 == tokenCount &&
              Token::VARIABLE == vals[ iToken + 1 ].token &&
              Token::OPENPAREN == vals[ iToken + 2 ].token )
    {
        // 0 EXPRESSION, value 6, strValue ''
        // 1 VARIABLE, value 0, strValue 'sa%'
        // 2 OPENPAREN, value 0, strValue ''
        // 3 EXPRESSION, value 2, strValue ''
        // 4 VARIABLE, value 0, strValue 'st%'   (this can optionally be a constant)
        // 5 CLOSEPAREN, value 0, strValue ''

        Variable *pvar = vals[ iToken + 1 ].pVariable;
        assert( pvar && "array variable doesn't exist yet somehow" );

        if ( 1 != pvar->dimensions ) // can't be > 1 or tokenCount would be greater
            RuntimeFail( "scalar variable used as an array", g_lineno );

        int offset = GetSimpleValue( vals[ iToken + 4 ] );
        if ( RangeCheckArrays && FailsRangeCheck( offset, pvar->dims[ 0 ] ) )
            RuntimeFail( "index beyond the bounds of an array", g_lineno );

        value = pvar->array[ offset ];
        iToken += tokenCount;
    }
    else if ( 4 == tokenCount )
    {
        assert( isTokenSimpleValue( vals[ iToken + 1 ].token ) );
        assert( isTokenOperator( vals[ iToken + 2 ].token ) );
        assert( isTokenSimpleValue( vals[ iToken + 3 ].token ) );
    
        value = run_operator( GetSimpleValue( vals[ iToken + 1 ] ),
                              vals[ iToken + 2 ].token,
                              GetSimpleValue( vals[ iToken + 3 ] ) );
        iToken += tokenCount;
    }
    else if ( 16 == tokenCount &&
              Token::VARIABLE == vals[ iToken + 1 ].token &&
              Token::OPENPAREN == vals[ iToken + 4 ].token &&
              Token::CONSTANT == vals[ iToken + 6 ].token &&
              Token::VARIABLE == vals[ iToken + 9 ].token &&
              Token::OPENPAREN == vals[ iToken + 12 ].token &&
              Token::CONSTANT == vals[ iToken + 14 ].token &&
              isOperatorLogical( vals[ iToken + 8 ].token ) &&
              isOperatorRelational( vals[ iToken + 2 ].token ) &&
              isOperatorRelational( vals[ iToken + 10 ].token ) )
    {
        //  0 EXPRESSION, value 16, strValue ''
        //  1 VARIABLE, value 0, strValue 'wi%'
        //  2 EQ, value 0, strValue ''
        //  3 VARIABLE, value 0, strValue 'b%'
        //  4 OPENPAREN, value 0, strValue ''
        //  5 EXPRESSION, value 2, strValue ''
        //  6 CONSTANT, value 5, strValue ''
        //  7 CLOSEPAREN, value 0, strValue ''
        //  8 AND, value 0, strValue ''
        //  9 VARIABLE, value 0, strValue 'wi%'
        // 10 EQ, value 0, strValue ''
        // 11 VARIABLE, value 0, strValue 'b%'
        // 12 OPENPAREN, value 0, strValue ''
        // 13 EXPRESSION, value 2, strValue ''
        // 14 CONSTANT, value 8, strValue ''
        // 15 CLOSEPAREN, value 0, strValue ''

        // crazy optimization just for ttt that yields a 10% overall win.
        // this is unlikely to help any other BASIC app.

        if ( RangeCheckArrays )
        {
            if ( FailsRangeCheck( vals[ iToken + 6 ].value, vals[ iToken + 3 ].pVariable->array.size() ) ||
                 FailsRangeCheck( vals[ iToken + 14 ].value, vals[ iToken + 11 ].pVariable->array.size() ) )
                RuntimeFail( "index beyond the bounds of an array", g_lineno );

            if ( ( 1 != vals[ iToken + 3 ].pVariable->dimensions ) ||
                 ( 1 != vals[ iToken + 11 ].pVariable->dimensions ) )
                RuntimeFail( "variable used as if it has one array dimension when it does not", g_lineno );
        }

        value = run_operator_logical( run_operator_relational( vals[ iToken + 1 ].pVariable->value,
                                                               vals[ iToken + 2 ].token,
                                                               vals[ iToken + 3 ].pVariable->array[ vals[ iToken + 6 ].value ] ),
                                      vals[ iToken + 8 ].token,
                                      run_operator_relational( vals[ iToken + 9 ].pVariable->value,
                                                               vals[ iToken + 10 ].token,
                                                               vals[ iToken + 11 ].pVariable->array[ vals[ iToken + 14 ].value ] ) );
        iToken += tokenCount;
    }
    else if ( 3 == tokenCount )
    {
        if ( Token::NOT == vals[ iToken + 1 ].token )
            value = ! ( vals[ iToken + 2 ].pVariable->value );
        else
        {
            assert( Token::MINUS == vals[ iToken + 1 ].token );
            value = - GetSimpleValue( vals[ iToken + 2 ] );
        }
        iToken += tokenCount;
    }
    else
    {
        // for anything not optimized, fall through to the generic implementation

        value = EvaluateLogicalExpression( iToken, vals );
    }

    if ( EnableTracing && g_Tracing )
        printf( "returning expression value %d\n", value );

    assert( iToken == beyond );

    return value;
} //EvaluateExpressionOptimized

void PrintNumberWithCommas( char *pchars, long long n )
{
    if ( n < 0 )
    {
        sprintf( pchars, "-" );
        PrintNumberWithCommas( pchars, -n );
        return;
    }

    if ( n < 1000 )
    {
        sprintf( pchars + strlen( pchars ), "%lld", n );
        return;
    }

    PrintNumberWithCommas( pchars, n / 1000 );
    sprintf( pchars + strlen( pchars ), ",%03lld", n % 1000 );
} //PrintNumberWithCommas

void ShowLocListing( LineOfCode & loc )
{
    printf( "line %d has %zd tokens  ====>> %s\n", loc.lineNumber, loc.tokenValues.size(), loc.sourceCode.c_str() );
    
    for ( size_t t = 0; t < loc.tokenValues.size(); t++ )
    {
        TokenValue & tv = loc.tokenValues[ t ];
        printf( "  token %3zd %s, value %d, strValue '%s'",
                t, TokenStr( tv.token ), tv.value, tv.strValue.c_str() );
    
        if ( Token::DIM == tv.token )
        {
            printf( " dimensions: %d, length: ", tv.dimensions );
            for ( int d = 0; d < tv.dimensions; d++ )
                printf( " %d", tv.dims[ d ] );
        }
    
        printf( "\n" );
    }
} //ShowLocListing

void RemoveREMStatements()
{
    // Also, remove lines with no statements
    // 1st pass: move goto/gosub targets to the first following non-REM statement 

    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];

        for ( size_t t = 0; t < loc.tokenValues.size(); t++ )
        {
            TokenValue & tv = loc.tokenValues[ t ];

            if ( Token::GOTO == tv.token || Token::GOSUB == tv.token )
            {
                for ( size_t lo = 0; lo < g_linesOfCode.size(); lo++ )
                {
                    if ( ( g_linesOfCode[ lo ].lineNumber == tv.value ) &&
                         ( ( 0 == g_linesOfCode[ lo ].tokenValues.size() ) ||
                           ( Token::REM == g_linesOfCode[ lo ].tokenValues[ 0 ].token ) ) )
                    {
                        // look for the next statement that's not REM

                        bool foundOne = false;
                        for ( size_t h = lo + 1; h < g_linesOfCode.size(); h++ )
                        {
                            if ( Token::REM != g_linesOfCode[ h ].tokenValues[ 0 ].token )
                            {
                                foundOne = true;
                                tv.value = g_linesOfCode[ h ].lineNumber;
                                break;
                            }
                        }

                        // There is always an END statement, so we'll find one

                        assert( foundOne );
                        break;
                    }
                }
            }
        }
    }

    // 2nd pass: remove all REM statements

    size_t endloc = g_linesOfCode.size();
    size_t curloc = 0;

    while ( curloc < endloc )
    {
        LineOfCode & loc = g_linesOfCode[ curloc ];

        if ( ( 0 == loc.tokenValues.size() ) || ( Token::REM == loc.tokenValues[ 0 ].token ) )
        {
            g_linesOfCode.erase( g_linesOfCode.begin() + curloc );
            endloc--;
        }
        else
            curloc++;
    }
} //RemoveREMStatements

void AddENDStatement()
{
    bool addEnd = true;

    if ( g_linesOfCode.size() && Token::END == g_linesOfCode[ g_linesOfCode.size() - 1 ].tokenValues[ 0 ].token )
        addEnd = false;

    if ( addEnd )
    {
        int linenumber = 1 + g_linesOfCode[ g_linesOfCode.size() - 1 ].lineNumber;
        LineOfCode loc( linenumber, "2000000000 end" );
        g_linesOfCode.push_back( loc );
        TokenValue tokenValue( Token::END );
        g_linesOfCode[ g_linesOfCode.size() - 1 ].tokenValues.push_back( tokenValue );
    }
} //AddENDStatement

void PatchGotoAndGosubNumbers()
{
    // patch goto/gosub line numbers with actual offsets to remove runtime searches
    // also, pull out the first token for better memory locality

    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];
    
        for ( size_t t = 0; t < loc.tokenValues.size(); t++ )
        {
            TokenValue & tv = loc.tokenValues[ t ];
            bool found = false;

            if ( Token::GOTO == tv.token || Token::GOSUB == tv.token )
            {
                for ( size_t lo = 0; lo < g_linesOfCode.size(); lo++ )
                {
                    if ( g_linesOfCode[ lo ].lineNumber == tv.value )
                    {
                        tv.value = (int) lo;
                        found = true;
                        g_linesOfCode[ lo ].goTarget = true;
                        break;
                    }
                }

                if ( !found )
                {
                    printf( "Error: statement %s referenced undefined line number %d\n", TokenStr( tv.token ), tv.value );
                    exit( 1 );
                }
            }
        }
    }
} //PatchGotoAndGosubNumbers

void OptimizeWithRewrites( bool showListing )
{
    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];
        vector<TokenValue> & vals = loc.tokenValues;
        bool rewritten = false;

        if ( 0 == vals.size() )
            continue;

        // if 0 <> EXPRESSION   ========>>>>>>>>  if EXPRESSION
        // 4180 has 11 tokens
        //   token   0 IF, value 0, strValue ''
        //   token   1 EXPRESSION, value 8, strValue ''
        //   token   2 CONSTANT, value 0, strValue ''
        //   token   3 NE, value 0, strValue ''
        //   token   4 VARIABLE, value 0, strValue 'b%'
        //   token   5 OPENPAREN, value 0, strValue ''
        //   token   6 EXPRESSION, value 2, strValue ''
        //   token   7 VARIABLE, value 0, strValue 'p%'
        //   token   8 CLOSEPAREN, value 0, strValue ''
        //   token   9 THEN, value 0, strValue ''
        //   token  10 GOTO, value 4500, strValue ''

        if ( Token::IF == vals[ 0 ].token &&
             Token::EXPRESSION == vals[ 1 ].token &&
             Token::CONSTANT == vals[ 2 ].token &&
             0 == vals[ 2 ].value &&
             Token::NE == vals[ 3 ].token )
        {
            vals.erase( vals.begin() + 2 );
            vals.erase( vals.begin() + 2 );
            vals[ 1 ].value -= 2;

            rewritten = true;
        }

        // VARIABLE = VARIABLE + 1  =============>  ATOMIC INC VARIABLE
        // 4500 has 6 tokens
        //   token   0 VARIABLE, value 0, strValue 'p%'
        //   token   1 EQ, value 0, strValue ''
        //   token   2 EXPRESSION, value 4, strValue ''
        //   token   3 VARIABLE, value 0, strValue 'p%'
        //   token   4 PLUS, value 0, strValue ''
        //   token   5 CONSTANT, value 1, strValue ''

        else if ( 6 == vals.size() &&
            Token::VARIABLE == vals[ 0 ].token &&
            Token::EQ == vals[ 1 ].token &&
            Token::VARIABLE == vals[ 3 ].token &&
            !vals[ 0 ].strValue.compare( vals[ 3 ].strValue ) &&
            Token::PLUS == vals[ 4 ].token &&
            Token::CONSTANT == vals[ 5 ].token &&
            1 == vals[ 5 ].value )
        {
            string varname = vals[ 3 ].strValue;
            vals.clear();

            TokenValue tval( Token::ATOMIC );
            vals.push_back( tval );

            tval.token = Token::INC;
            tval.strValue = varname;
            vals.push_back( tval );

            rewritten = true;
        }

        // VARIABLE = VARIABLE - 1  =============>  ATOMIC DEC VARIABLE
        // 4500 has 6 tokens
        //   token   0 VARIABLE, value 0, strValue 'p%'
        //   token   1 EQ, value 0, strValue ''
        //   token   2 EXPRESSION, value 4, strValue ''
        //   token   3 VARIABLE, value 0, strValue 'p%'
        //   token   4 MINUS, value 0, strValue ''
        //   token   5 CONSTANT, value 1, strValue ''

        else if ( 6 == vals.size() &&
            Token::VARIABLE == vals[ 0 ].token &&
            Token::EQ == vals[ 1 ].token &&
            Token::VARIABLE == vals[ 3 ].token &&
            !vals[ 0 ].strValue.compare( vals[ 3 ].strValue ) &&
            Token::MINUS == vals[ 4 ].token &&
            Token::CONSTANT == vals[ 5 ].token &&
            1 == vals[ 5 ].value )
        {
            string varname = vals[ 3 ].strValue;
            vals.clear();

            TokenValue tval( Token::ATOMIC );
            vals.push_back( tval );

            tval.token = Token::DEC;
            tval.strValue = varname;
            vals.push_back( tval );

            rewritten = true;
        }

        // IF 0 = VARIABLE  =============>  IF NOT VARIABLE
        // 2410 has 7 tokens
        //   token   0 IF, value 0, strValue ''
        //   token   1 EXPRESSION, value 4, strValue ''
        //   token   2 CONSTANT, value 0, strValue ''
        //   token   3 EQ, value 0, strValue ''
        //   token   4 VARIABLE, value 0, strValue 'wi%'
        //   token   5 THEN, value 0, strValue ''
        //   token   6 GOTO, value 2500, strValue ''

        else if ( 7 == vals.size() &&
                  Token::IF == vals[ 0 ].token &&
                  Token::EXPRESSION == vals[ 1 ].token &&
                  4 == vals[ 1 ].value &&
                  Token::CONSTANT == vals[ 2 ].token &&
                  0 == vals[ 2 ].value &&
                  Token::EQ == vals[ 3 ].token &&
                  Token::VARIABLE == vals[ 4 ].token )
        {
            vals.erase( vals.begin() + 2 );
            vals[ 2 ].token = Token::NOT;
            vals[ 1 ].value = 3;

            rewritten = true;
        }

        // IF VARIABLE = 0  =============>  IF NOT VARIABLE
        // 2410 has 7 tokens
        //   token   0 IF, value 0, strValue ''
        //   token   1 EXPRESSION, value 4, strValue ''
        //   token   2 VARIABLE, value 0, strValue 'wi%'
        //   token   3 EQ, value 0, strValue ''
        //   token   4 CONSTANT, value 0, strValue ''
        //   token   5 THEN, value 0, strValue ''
        //   token   6 GOTO, value 2500, strValue ''

        else if ( 7 == vals.size() &&
                  Token::IF == vals[ 0 ].token &&
                  Token::EXPRESSION == vals[ 1 ].token &&
                  4 == vals[ 1 ].value &&
                  Token::VARIABLE == vals[ 2 ].token &&
                  Token::EQ == vals[ 3 ].token &&
                  Token::CONSTANT == vals[ 4 ].token &&
                  0 == vals[ 4 ].value )
        {
            vals[ 3 ] = vals[ 2 ];
            vals[ 2 ].token = Token::NOT;
            vals[ 2 ].strValue = "";
            vals[ 1 ].value = 3;
            vals.erase( vals.begin() + 4 );

            rewritten = true;
        }

        if ( showListing && rewritten )
        {
            printf( "line rewritten as:\n" );
            ShowLocListing( loc );
        }
    }
} //OptimizeWithRewrites

void SetFirstTokens()
{
    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];
        loc.firstToken = loc.tokenValues[ 0 ].token;
    }
} //SetFirstTokens

void CreateVariables( map<string, Variable> & varmap )
{
    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];
    
        for ( size_t t = 0; t < loc.tokenValues.size(); t++ )
        {
            TokenValue & tv = loc.tokenValues[ t ];

            if ( ( Token::INC == tv.token ) ||
                 ( Token::DEC == tv.token ) ||
                 ( Token::VARIABLE == tv.token ) || // create arrays as singletons until a DIM statement
                 ( Token::FOR == tv.token ) )
            {
                Variable * pvar = GetVariablePerhapsCreate( tv, varmap );
                pvar->references++;
            }
        }
    }
} //CreateVariables

const char * GenVariableName( string const & s )
{
    static char acName[ 100 ];

    assert( s.length() < _countof( acName ) );

    if ( i8080CPM == g_AssemblyTarget )
        strcpy_s( acName, _countof( acName ), "var$" );
    else
        strcpy_s( acName, _countof( acName ), "var_" );

    strcpy_s( acName + strlen( acName ), _countof( acName ) - 4, s.c_str() );
    acName[ strlen( acName ) - 1 ] = 0;
    return acName;
} //GenVariableName

const char * GenVariableReg( map<string, Variable> const & varmap, string const & s )
{
    Variable * pvar = FindVariable( varmap, s );
    assert( pvar && "variable must exist in GenVariableReg" );

    return pvar->reg.c_str();
} //GenVariableReg

const char * GenVariableReg64( map<string, Variable> const & varmap, string const & s )
{
    Variable * pvar = FindVariable( varmap, s );
    assert( pvar && "variable must exist in GenVariableReg" );

    const char * r = pvar->reg.c_str();

    if ( x64Win == g_AssemblyTarget )
    {
        for ( int i = 0; i < _countof( MappedRegistersX64 ); i++ )
            if ( !_stricmp( r, MappedRegistersX64[ i ] ) )
                return MappedRegistersX64_64[ i ];
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        for ( int i = 0; i < _countof( MappedRegistersArm64 ); i++ )
            if ( !_stricmp( r, MappedRegistersArm64[ i ] ) )
                return MappedRegistersArm64_64[ i ];
    }
  
    assert( false && "why is there no 64 bit mapping to a register?" );
    return 0;
} //GenVariableReg64

bool IsVariableInReg( map<string, Variable> const & varmap, string const & s )
{
    Variable * pvar = FindVariable( varmap, s );
    assert( pvar && "variable must exist in IsVariableInReg" );

    return ( 0 != pvar->reg.length() );
} //IsVariableInReg

bool fitsIn12Bits( int x )
{
    return ( x >= 0 && x < 4096 );
} //fitsIn12Bits

bool fitsIn8Bits( int x )
{
    return (x >= 0 && x < 256 );
} //fitsIn8Bits

int g_lohCount = 0;

void LoadArm64Address( FILE * fp, const char * reg, string const & varname )
{
    fprintf( fp, "Lloh%d:\n", g_lohCount++ );
    fprintf( fp, "    adrp     %s, %s@PAGE\n", reg, GenVariableName( varname ) );
    fprintf( fp, "Lloh%d:\n", g_lohCount++ );
    fprintf( fp, "    add      %s, %s, %s@PAGEOFF\n", reg, reg, GenVariableName( varname ) );
} //LoadArm64Address

void LoadArm64Address( FILE * fp, const char * reg, map<string, Variable> const varmap, string const & varname )
{
    if ( IsVariableInReg( varmap, varname ) )
        fprintf( fp, "    mov      %s, %s\n", reg, GenVariableReg64( varmap, varname ) );
    else
        LoadArm64Address( fp, reg, varname );
} //LoadArm64Address

void LoadArm64Constant( FILE * fp, const char * reg, int i )
{
    // mov is 1 instruction. The assembler will create multiple instructions for ldr

    if ( 0 == ( i & 0xffffff00 ) )
        fprintf( fp, "    mov      %s, %d\n", reg, i );
    else
        fprintf( fp, "    ldr      %s, =%#x\n", reg, i );
} //LoadArm64Constant

void GenerateOp( FILE * fp, map<string, Variable> const & varmap, vector<TokenValue> const & vals,
                 int left, int right, Token op, int leftArray = 0, int rightArray = 0 )
{
    // optimize for wi% = b%( 0 )

    if ( Token::VARIABLE == vals[ left ].token &&
         IsVariableInReg( varmap, vals[ left ].strValue ) &&
         0 == vals[ left ].dimensions &&
         isOperatorRelational( op ) &&
         Token::VARIABLE == vals[ right ].token &&
         0 != vals[ right ].dimensions )
    {
        if ( x64Win == g_AssemblyTarget )
        {
            fprintf( fp, "    cmp      %s, DWORD PTR [%s + %d]\n", GenVariableReg( varmap, vals[ left ].strValue ),
                    GenVariableName( vals[ right ].strValue ), 4 * vals[ rightArray ].value );

            fprintf( fp, "    %-6s   al\n", OperatorInstruction[ op ] );
            fprintf( fp, "    movzx    rax, al\n" );
        }
        else if ( arm64Mac == g_AssemblyTarget )
        {
            LoadArm64Address( fp, "x1", vals[ right ].strValue );

            int offset = 4 * vals[ rightArray ].value;

            if ( fitsIn8Bits( offset ) )
                fprintf( fp, "    ldr      w0, [x1, %d]\n", offset );
            else
            {
                LoadArm64Constant( fp, "x0", 4 * vals[ rightArray ].value );
                fprintf( fp, "    add      x1, x1, x0\n" );
                fprintf( fp, "    ldr      w0, [x1]\n" );
            }

            fprintf( fp, "    cmp      %s, w0\n", GenVariableReg( varmap, vals[ left ].strValue ) );
            fprintf( fp, "    cset     x0, %s\n", ConditionsArm64[ op ] );
        }
        return;
    }

    // optimize this typical case to save a mov: x% relop CONSTANT

    if ( Token::VARIABLE == vals[ left ].token &&
         0 == vals[ left ].dimensions &&
         isOperatorRelational( op ) &&
         Token::CONSTANT == vals[ right ].token )
    {
        string const & varname = vals[ left ].strValue;

        if ( x64Win == g_AssemblyTarget )
        {
            if ( IsVariableInReg( varmap, varname ) )
                fprintf( fp, "    cmp      %s, %d\n", GenVariableReg( varmap, varname ), vals[ right ].value );
            else
                fprintf( fp, "    cmp      DWORD PTR [%s], %d\n", GenVariableName( varname ), vals[ right ].value );

            fprintf( fp, "    %-6s   al\n", OperatorInstruction[ op ] );
            fprintf( fp, "    movzx    rax, al\n" );
        }
        else if ( arm64Mac == g_AssemblyTarget )
        {
            LoadArm64Constant( fp, "x1", vals[ right ].value );

            if ( IsVariableInReg( varmap, varname ) )
                fprintf( fp, "    cmp      %s, w1\n", GenVariableReg( varmap, varname ) );
            else
            {
                LoadArm64Address( fp, "x2", varname );
                fprintf( fp, "    ldr      w0, [x2]\n" );
                fprintf( fp, "    cmp      w0, w1\n" );
            }

            fprintf( fp, "    cset     x0, %s\n", ConditionsArm64[ op ] );            
        }
        return;
    }

    // general case: left operator right
    // first: load left

    if ( Token::CONSTANT == vals[ left ].token )
    {
        if ( x64Win == g_AssemblyTarget )
            fprintf( fp, "    mov      eax, %d\n", vals[ left ].value );
        else if ( arm64Mac == g_AssemblyTarget )
            LoadArm64Constant( fp, "x0", vals[ left ].value );
    }
    else if ( 0 == vals[ left ].dimensions )
    {
        string const & varname = vals[ left ].strValue;

        if ( IsVariableInReg( varmap, varname ) )
        {
            if ( x64Win == g_AssemblyTarget )
                fprintf( fp, "    mov      eax, %s\n", GenVariableReg( varmap, varname ) );
            else if ( arm64Mac == g_AssemblyTarget )
                fprintf( fp, "    mov      w0, %s\n", GenVariableReg( varmap, varname ) );
        }
        else
        {
            if ( x64Win == g_AssemblyTarget )
                fprintf( fp, "    mov      eax, DWORD PTR [%s]\n", GenVariableName( varname ) );
            else if ( arm64Mac == g_AssemblyTarget )
            {
                LoadArm64Address( fp, "x1", varname );
                fprintf( fp, "    ldr      w0, [x1]\n" );
            }
        }
    }
    else
    {
        if ( x64Win == g_AssemblyTarget )
            fprintf( fp, "    mov      eax, DWORD PTR [%s + %d]\n", GenVariableName( vals[ left ].strValue ),
                     4 * vals[ leftArray ].value );
        else if ( arm64Mac == g_AssemblyTarget )
        {
            LoadArm64Address( fp, "x1", vals[ left ].strValue );

            int offset = 4 * vals[ leftArray ].value;

            if ( fitsIn8Bits( offset ) )
                fprintf( fp, "    ldr      w0, [x1 + %d]\n", offset );
            else
            {
                LoadArm64Constant( fp, "x0", offset );
                fprintf( fp, "    add      x1, x1, x0\n" );
                fprintf( fp, "    ldr      w0, [x1]\n" );
            }
        }
    }

    if ( isOperatorRelational( op ) )
    {
        // relational

        if ( Token::CONSTANT == vals[ right ].token )
        {
            if ( x64Win == g_AssemblyTarget )
                fprintf( fp, "    cmp      eax, %d\n", vals[ right ].value );
            else if ( arm64Mac == g_AssemblyTarget )
            {
                LoadArm64Constant( fp, "x1", vals[ right ].value );
                fprintf( fp, "    cmp      w1, w1\n" );
            }
        }
        else if ( 0 == vals[ right ].dimensions )
        {
            string const & varname = vals[ right ].strValue;
            if ( IsVariableInReg( varmap, varname ) )
            {
                if ( x64Win == g_AssemblyTarget )
                    fprintf( fp, "    cmp      eax, %s\n", GenVariableReg( varmap, varname ) );
                else if ( arm64Mac == g_AssemblyTarget )
                    fprintf( fp, "    cmp      w0, %s\n", GenVariableReg( varmap, varname ) );
            }
            else
            {
                if ( x64Win == g_AssemblyTarget )
                    fprintf( fp, "    cmp      eax, DWORD PTR [%s]\n", GenVariableName( varname ) );
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    LoadArm64Address( fp, "x2", varname );
                    fprintf( fp, "    ldr      w1, [x2]\n" );
                    fprintf( fp, "    cmp      w0, w1\n" );
                }
            }
        }
        else
        {
            if ( x64Win == g_AssemblyTarget )
            {
                fprintf( fp, "    cmp      eax, DWORD PTR [%s + %d]\n", GenVariableName( vals[ right ].strValue ),
                        4 * vals[ rightArray ].value );
            }
            else if ( arm64Mac == g_AssemblyTarget )
            {
                LoadArm64Address( fp, "x1", vals[ right ].strValue );

                int offset = 4 * vals[ rightArray ].value;

                if ( fitsIn8Bits( offset ) )
                    fprintf( fp, "    ldr      w1, [x1, %d]\n", offset );
                else
                {
                    LoadArm64Constant( fp, "x3", offset );
                    fprintf( fp, "    add      x1, x1, x3\n" );
                    fprintf( fp, "    ldr      w1, [x1]\n" );
                }

                fprintf( fp, "    cmp      w0, w1\n" );
            }
        }

        if ( x64Win == g_AssemblyTarget )
        {
            fprintf( fp, "    %-6s   al\n", OperatorInstruction[ op ] );
            fprintf( fp, "    movzx    rax, al\n" );
        }
        else if ( arm64Mac == g_AssemblyTarget )
        {
            fprintf( fp, "    cset     x0, %s\n", ConditionsArm64[ op ] );            
        }
    }
    else
    {
        // arithmetic and logical (which in BASIC is both arithmetic and logical)

        if ( x64Win == g_AssemblyTarget && Token::DIV == op )
        {
            if ( Token::CONSTANT == vals[ right ].token )
                fprintf( fp, "    mov      rbx, %d\n", vals[ right ].value );
            else if ( 0 == vals[ right ].dimensions )
            {
                string const & varname = vals[ right ].strValue;
                if ( IsVariableInReg( varmap, varname ) )
                    fprintf( fp, "    mov      ebx, %s\n", GenVariableReg( varmap, varname ) );
                else
                    fprintf( fp, "    mov      ebx, DWORD PTR [%s]\n", GenVariableName( varname ) );
            }
            else
                fprintf( fp, "    mov      ebx, DWRD PTR [%s + %d]\n", GenVariableName( vals[ right ].strValue ),
                         4 * vals[ rightArray ].value );

            fprintf( fp, "    cdq\n" );
            fprintf( fp, "    idiv     ebx\n" );
        }
        else
        {
            if ( Token::CONSTANT == vals[ right ].token )
            {
                if ( x64Win == g_AssemblyTarget )
                    fprintf( fp, "    %-6s   eax, %d\n", OperatorInstruction[ op ], vals[ right ].value );
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    LoadArm64Constant( fp, "x1", vals[ right ].value );
                    fprintf( fp, "    %-6s   w0, w0, w1\n", OperatorInstructionArm64[ op ] );
                }
            }
            else if ( 0 == vals[ right ].dimensions )
            {
                string const & varname = vals[ right ].strValue;
                if ( IsVariableInReg( varmap, varname ) )
                {
                    if ( x64Win == g_AssemblyTarget )
                        fprintf( fp, "    %-6s   eax, %s\n", OperatorInstruction[ op ], GenVariableReg( varmap, varname ) );
                    else if ( arm64Mac == g_AssemblyTarget )
                        fprintf( fp, "    %-6s   w0, w0, %s\n", OperatorInstructionArm64[ op ], GenVariableReg( varmap, varname ) );
                }
                else
                {
                    if ( x64Win == g_AssemblyTarget )
                        fprintf( fp, "    %-6s   eax, DWORD PTR [%s]\n", OperatorInstruction[ op ], GenVariableName( varname ) );
                    else if ( arm64Mac == g_AssemblyTarget )
                    {
                        LoadArm64Address( fp, "x2", varname );
                        fprintf( fp, "    ldr      w1, [x2]\n" );
                        fprintf( fp, "    %-6s     w0, w0, w1\n", OperatorInstructionArm64[ op ] );
                    }
                }
            }
            else
            {
                if ( x64Win == g_AssemblyTarget )
                    fprintf( fp, "    %-6s   eax, DWORD PTR [%s + %d]\n", OperatorInstruction[ op ], GenVariableName( vals[ right ].strValue ),
                             4 * vals[ rightArray ].value );
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    LoadArm64Address( fp, "x1", vals[ right ].strValue );

                    int offset = 4 * vals[ rightArray ].value;

                    if ( fitsIn8Bits( offset ) )
                        fprintf( fp, "    ldr      w1, [x1, %d]\n", offset );
                    else
                    {
                        LoadArm64Constant( fp, "x3", offset );
                        fprintf( fp, "    add      x3, x1, x3\n" );
                        fprintf( fp, "    ldr      w1, [x3]\n" );
                    }

                    fprintf( fp, "    %-6s     w0, w0, w1\n", OperatorInstructionArm64[ op ] );
                }
            }
        }
    }
} //GenerateOp

void GenerateExpression( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals );
void GenerateFactor( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals );
void GenerateTerm( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals );

void GenerateMultiply( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    iToken++;

    GenerateFactor( fp, varmap, iToken, beyond, vals );

    if ( x64Win == g_AssemblyTarget )
    {
        fprintf( fp, "    pop      rbx\n" );
        fprintf( fp, "    imul     rax, rbx\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, "    ldr      x1, [sp], #16\n" );
        fprintf( fp, "    mul      w0, w0, w1\n" );
    }
    else if ( i8080CPM == g_AssemblyTarget )
    {
        fprintf( fp, "    pop      d\n" );
        fprintf( fp, "    call     imul\n" );
    }
} //GenerateMultiply

void GenerateDivide( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    iToken++;

    GenerateFactor( fp, varmap, iToken, beyond, vals );

    if ( x64Win == g_AssemblyTarget )
    {
        fprintf( fp, "    mov      rbx, rax\n" );
        fprintf( fp, "    pop      rax\n" );
        fprintf( fp, "    cdq\n" );
        fprintf( fp, "    idiv     ebx\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, "    ldr      x1, [sp], #16\n" );
        fprintf( fp, "    sdiv     w0, w1, w0\n" );
        
    }
    else if ( i8080CPM == g_AssemblyTarget )
    {
        fprintf( fp, "    pop      d\n" );
        fprintf( fp, "    call     idiv\n" );
    }
} //GenerateDivide

void GenerateTerm( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
        printf( "generate term iToken %d, %s\n", iToken, TokenStr( vals[ iToken ].token ) );

    GenerateFactor( fp, varmap, iToken, beyond, vals );

    if ( iToken >= beyond )
        return;

    Token t = vals[ iToken ].token;

    while ( isOperatorMultiplicative( t ) )
    {
        if ( x64Win == g_AssemblyTarget )
            fprintf( fp, "    push     rax\n" );
        else if ( arm64Mac == g_AssemblyTarget )
            fprintf( fp, "    str      x0, [sp, #-16]!\n" ); // save 8 bytes in a 16-byte spot
        else if ( i8080CPM == g_AssemblyTarget )
            fprintf( fp, "    push     h\n" );

        if ( Token::MULT == t )
            GenerateMultiply( fp, varmap, iToken, beyond, vals );
        else
            GenerateDivide( fp, varmap, iToken, beyond, vals );

        if ( iToken >= beyond )
            break;

        t = vals[ iToken ].token;

        if ( EnableTracing && g_Tracing )
            printf( "next token  %d in GenerateTerm: %d\n", iToken, t );
    }
} //GenerateTerm

void GenerateFactor( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond,vector<TokenValue> const & vals )
{
    if ( EnableTracing && g_Tracing )
        printf( "GenerateFactor iToken %d, beyond %d, %s\n", iToken, beyond, TokenStr( vals[ iToken ].token ) );

    if ( iToken < beyond )
    {
        Token t = vals[ iToken ].token;

        if ( Token::EXPRESSION == t )
        {
            iToken++;
            t = vals[ iToken ].token;
        }

        if ( Token::OPENPAREN == t )
        {
            iToken++;
            GenerateExpression( fp, varmap, iToken, beyond, vals );
            assert( Token::CLOSEPAREN == vals[ iToken ].token );
            iToken++;
        }
        else if ( Token::VARIABLE == t )
        {
            string const & varname = vals[ iToken ].strValue;

            if ( 0 == vals[ iToken ].dimensions )
            {
                if ( x64Win == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, varname ) )
                        fprintf( fp, "    mov      eax, %s\n", GenVariableReg( varmap, varname ) );
                    else
                        fprintf( fp, "    movsxd   rax, DWORD PTR [%s]\n", GenVariableName( varname ) );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, varname ) )
                        fprintf( fp, "    mov      w0, %s\n", GenVariableReg( varmap, varname ) );
                    else
                    {
                        LoadArm64Address( fp, "x1", varname );
                        fprintf( fp, "    ldr      w0, [x1]\n" );
                    }
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    fprintf( fp, "    lhld     %s\n", GenVariableName( varname ) );
                }
            }
            else if ( 1 == vals[ iToken ].dimensions )
            {
                iToken++; // variable

                if ( Token::OPENPAREN != vals[ iToken ].token )
                    RuntimeFail( "open parenthesis expected", g_lineno );

                iToken++; // open paren

                assert( Token::EXPRESSION == vals[ iToken ].token );
                GenerateExpression( fp, varmap, iToken, iToken + vals[ iToken ].value, vals );

                if ( x64Win == g_AssemblyTarget )
                {
                    fprintf( fp, "    shl      rax, 2\n" );
                    fprintf( fp, "    lea      rbx, [ %s ]\n", GenVariableName( varname ) );
                    fprintf( fp, "    add      rbx, rax\n" );
                    fprintf( fp, "    mov      eax, [ rbx ]\n" );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    fprintf( fp, "    lsl      x0, x0, 2\n" );
                    LoadArm64Address( fp, "x1", varname );
                    fprintf( fp, "    add      x1, x1, x0\n" );
                    fprintf( fp, "    ldr      w0, [x1], 0\n" );
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    // double h because each variable in the array is 2 bytes

                    fprintf( fp, "    dad      h\n" );
                    fprintf( fp, "    lxi      d, %s\n", GenVariableName( varname ) );
                    fprintf( fp, "    dad      d\n" );

                    fprintf( fp, "    mov      e, m\n" );
                    fprintf( fp, "    inx      h\n" );
                    fprintf( fp, "    mov      d, m\n" );
                    fprintf( fp, "    xchg\n" );
                }
            }
            else if ( 2 == vals[ iToken ].dimensions )
            {
                iToken++; // variable

                if ( Token::OPENPAREN != vals[ iToken ].token )
                    RuntimeFail( "open parenthesis expected", g_lineno );

                iToken++; // open paren

                assert( Token::EXPRESSION == vals[ iToken ].token );
                GenerateExpression( fp, varmap, iToken, iToken + vals[ iToken ].value, vals );

                if ( x64Win == g_AssemblyTarget )
                    fprintf( fp, "    push     rax\n" );
                else if ( arm64Mac == g_AssemblyTarget )
                    fprintf( fp, "    str      x0, [sp, #-16]!\n" ); // save 4 bytes in a 16-byte spot
                else if ( i8080CPM == g_AssemblyTarget )
                    fprintf( fp, "    push     h\n" );

                if ( Token::COMMA != vals[ iToken ].token )
                    RuntimeFail( "expected a 2-dimensional array", g_lineno );
                iToken++; // comma

                assert( Token::EXPRESSION == vals[ iToken ].token );
                GenerateExpression( fp, varmap, iToken, iToken + vals[ iToken ].value, vals );

                Variable * pvar = FindVariable( varmap, varname );
                assert( pvar );

                if ( x64Win == g_AssemblyTarget )
                {
                    fprintf( fp, "    pop      rbx\n" );
                    fprintf( fp, "    imul     rbx, %d\n", pvar->dims[ 1 ] );
                    fprintf( fp, "    add      rax, rbx\n" );
                    fprintf( fp, "    shl      rax, 2\n" );
                    fprintf( fp, "    lea      rbx, [ %s ]\n", GenVariableName( varname ) );
                    fprintf( fp, "    add      rbx, rax\n" );
                    fprintf( fp, "    mov      eax, [ rbx ]\n" );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    fprintf( fp, "    ldr      x1, [sp], #16\n" );
                    LoadArm64Constant( fp, "x2", pvar->dims[ 1 ] );
                    fprintf( fp, "    mul      x1, x1, x2\n" );
                    fprintf( fp, "    add      x0, x0, x1\n" );
                    fprintf( fp, "    lsl      x0, x0, 2\n" );
                    LoadArm64Address( fp, "x1", varname );
                    fprintf( fp, "    add      x1, x1, x0\n" );
                    fprintf( fp, "    ldr      w0, [x1], 0\n" );
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    fprintf( fp, "    pop      d\n" );
                    fprintf( fp, "    push     h\n" );
                    fprintf( fp, "    lxi      h, %d\n", pvar->dims[ 1 ] );
                    fprintf( fp, "    call     imul\n" );
                    fprintf( fp, "    pop      d\n" );
                    fprintf( fp, "    dad      d\n" );
                    fprintf( fp, "    dad      h\n" );
                    fprintf( fp, "    lxi      d, %s\n", GenVariableName( varname ) );
                    fprintf( fp, "    dad      d\n" );
                    fprintf( fp, "    mov      e, m\n" );
                    fprintf( fp, "    inx      h\n" );
                    fprintf( fp, "    mov      d, m\n" );
                    fprintf( fp, "    xchg\n" );
                }
            }

            iToken++;
        }
        else if ( Token::CONSTANT == t )
        {
            if ( x64Win == g_AssemblyTarget )
                fprintf( fp, "    mov      rax, %d\n", vals[ iToken ].value );
            else if ( arm64Mac == g_AssemblyTarget )
                LoadArm64Constant( fp, "x0", vals[ iToken ].value );
            else if ( i8080CPM == g_AssemblyTarget )
                fprintf( fp, "    lxi      h, %d\n", vals[ iToken ].value );

            iToken++;
        }
        else if ( Token::CLOSEPAREN == t )
        {
            assert( false && "why is there a close paren?" );
            iToken++;
        }
        else if ( Token::NOT == t )
        {
            iToken++;

            assert( Token::VARIABLE == vals[ iToken ].token );

            string const & varname = vals[ iToken ].strValue;

            if ( x64Win == g_AssemblyTarget )
            {
                if ( IsVariableInReg( varmap, varname ) )
                    fprintf( fp, "    cmp      %s, 0\n", GenVariableReg( varmap, varname ) );
                else
                    fprintf( fp, "    cmp      DWORD PTR [%s], 0\n", GenVariableName( varname ) );

                fprintf( fp, "    sete     al\n" );
                fprintf( fp, "    movzx    rax, al\n" );
            }
            else if ( arm64Mac == g_AssemblyTarget )
            {
                if ( IsVariableInReg( varmap, varname ) )
                    fprintf( fp, "    cmp      %s, 0\n", GenVariableReg( varmap, varname ) );
                else
                {
                    LoadArm64Address( fp, "x1", varname );
                    fprintf( fp, "    ldr      x0, [x1]\n" );
                    fprintf( fp, "    cmp      x0, 0\n" );
                }

                fprintf( fp, "    cset     x0, eq\n" );
            }
            else if ( i8080CPM == g_AssemblyTarget )
            {
                static int s_notLabel = 0;

                fprintf( fp, "    lhld     %s\n", GenVariableName( varname ) );
                fprintf( fp, "    mov      a, h\n" );
                fprintf( fp, "    mvi      h, 0\n" );
                fprintf( fp, "    ora      l\n" );
                fprintf( fp, "    jz       nl$%d\n", s_notLabel );
                fprintf( fp, "    mvi      l, 0\n" );
                fprintf( fp, "    jmp      nl2$%d\n", s_notLabel );
                fprintf( fp, "  nl$%d:\n", s_notLabel );
                fprintf( fp, "    mvi      l, 1\n" );
                fprintf( fp, "  nl2$%d\n", s_notLabel );

                s_notLabel++;
            }

            iToken++;
        }
        else
        {
            printf( "unexpected token in GenerateFactor %d %s\n", t, TokenStr( t ) );
            RuntimeFail( "unexpected token", g_lineno );
        }
    }

    if ( EnableTracing && g_Tracing )
        printf( " leaving GenerateFactor, iToken %d\n", iToken );
} //GenerateFactor

void GenerateAdd( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    if ( EnableTracing && g_Tracing )
        printf( "in generate add, iToken %d\n", iToken );

    iToken++;

    GenerateTerm( fp, varmap, iToken, beyond, vals );

    if ( x64Win == g_AssemblyTarget )
    {
        fprintf( fp, "    pop      rbx\n" );
        fprintf( fp, "    add      rax, rbx\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, "    ldr      x1, [sp], #16\n" );
        fprintf( fp, "    add      w0, w0, w1\n" );
    }
    else if ( i8080CPM == g_AssemblyTarget )
    {
        fprintf( fp, "    pop      d\n" );
        fprintf( fp, "    dad      d\n" );
    }
} //GenerateAdd

void GenerateSubtract( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    if ( EnableTracing && g_Tracing )
        printf( "in generate subtract, iToken %d\n", iToken );

    iToken++;

    GenerateTerm( fp, varmap, iToken, beyond,  vals );

    if ( x64Win == g_AssemblyTarget )
    {
        fprintf( fp, "    mov      rbx, rax\n" );
        fprintf( fp, "    pop      rax\n" );
        fprintf( fp, "    sub      rax, rbx\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, "    mov      x1, x0\n" );
        fprintf( fp, "    ldr      x0, [sp], #16\n" );
        fprintf( fp, "    sub      w0, w0, w1\n" );
    }
    else if ( i8080CPM == g_AssemblyTarget )
    {
        fprintf( fp, "    pop      d\n" );
        fprintf( fp, "    mov      a, e\n" );
        fprintf( fp, "    sub      l\n" );
        fprintf( fp, "    mov      l, a\n" );
        fprintf( fp, "    mov      a, d\n" );
        fprintf( fp, "    sbb      h\n" );
        fprintf( fp, "    mov      h, a\n" );
    }
} //GenerateSubtract

void GenerateExpression( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
    {
        printf( "generate expression for line %d iToken %d %s\n", g_lineno, iToken, TokenStr( vals[ iToken ].token ) );

        for ( int i = iToken; i < vals.size(); i++ )
            printf( "    %d:    %s\n", i, TokenStr( vals[ i ].token ) );
    }

    // this will be called after an open paren, for example: ( 3 + 4 ) and not be an EXPRESSION in that case.

    if ( Token::EXPRESSION == vals[ iToken ].token )
        iToken++;

    // look for a unary + or -

    if ( isOperatorAdditive( vals[ iToken ].token ) )
    {
        // make the left side of the operation 0

        if ( x64Win == g_AssemblyTarget )
            fprintf( fp, "    xor      rax, rax\n" );
        else if ( arm64Mac == g_AssemblyTarget )
            fprintf( fp, "    mov      x0, 0\n" );
        else if ( i8080CPM == g_AssemblyTarget )
            fprintf( fp, "    lxi      h, 0\n" );
    }
    else
    {
        GenerateTerm( fp, varmap, iToken, beyond, vals );

        if ( iToken >= beyond )
            return;
    }

    Token t = vals[ iToken ].token;

    while ( isOperatorAdditive( t ) )
    {
        if ( x64Win == g_AssemblyTarget )
            fprintf( fp, "    push     rax\n" );
        else if ( arm64Mac == g_AssemblyTarget )
            fprintf( fp, "    str      x0, [sp, #-16]!\n" ); // save 4 bytes in a 16-byte spot
        else if ( i8080CPM == g_AssemblyTarget )
            fprintf( fp, "    push     h\n" );

        if ( Token::PLUS == t )
            GenerateAdd( fp, varmap, iToken, beyond, vals );
        else
            GenerateSubtract( fp, varmap, iToken, beyond, vals );

        if ( iToken >= beyond )
            break;

        t = vals[ iToken ].token;
    }
} //GenerateExpression

void GenerateRelational( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
        printf( "in generate relational, iToken %d\n", iToken );

    Token op = vals[ iToken ].token;
    iToken++;

    GenerateExpression( fp, varmap, iToken, beyond, vals );

    if ( x64Win == g_AssemblyTarget )
    {
        fprintf( fp, "    mov      rbx, rax\n" );
        fprintf( fp, "    pop      rax\n" );
        fprintf( fp, "    cmp      eax, ebx\n" );
        fprintf( fp, "    %-6s   al\n", OperatorInstruction[ op ] );
        fprintf( fp, "    movzx    rax, al\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, "    mov      x2, 1\n" );
        fprintf( fp, "    ldr      x1, [sp], #16\n" );
        fprintf( fp, "    cmp      w1, w0\n" );
        fprintf( fp, "    csel     x0, x2, xzr, %s\n", ConditionsArm64[ op ] );
    }
    else if ( i8080CPM == g_AssemblyTarget )
    {
        static int s_labelVal = 0;

        // "EQ", "NE", "LE", "GE", "LT", "GT"
        // d == lhs, h = rhs

        fprintf( fp, "    pop      d\n" );
        fprintf( fp, "    mov      a, d\n" );
        fprintf( fp, "    cmp      h\n" );

        if ( Token::EQ == op )
        {
            fprintf( fp, "    jnz      fRE%d\n", s_labelVal );
            fprintf( fp, "    mov      a, e\n" );
            fprintf( fp, "    cmp      l\n" );
            fprintf( fp, "    jnz      fRE%d\n", s_labelVal );
        }
        else if ( Token::NE == op )
        {
            fprintf( fp, "    jnz      tRE%d\n", s_labelVal );
            fprintf( fp, "    mov      a, e\n" );
            fprintf( fp, "    cmp      l\n" );
            fprintf( fp, "    jz       fRE%d\n", s_labelVal );
        }
        else if ( Token::LE == op )
        {
            fprintf( fp, "    jz       leRE%d\n", s_labelVal );
            fprintf( fp, "    jm       tRE%d\n", s_labelVal );
            fprintf( fp, "    jmp      fRE%d\n", s_labelVal );

            fprintf( fp, "  leRE%d:\n", s_labelVal );

            fprintf( fp, "    mov      a, e\n" );
            fprintf( fp, "    cmp      l\n" );
            fprintf( fp, "    jz       tRE%d\n", s_labelVal );
            fprintf( fp, "    jm       tRE%d\n", s_labelVal );
            fprintf( fp, "    jmp      fRE%d\n", s_labelVal );
        }
        else if ( Token::GE == op )
        {
            fprintf( fp, "    jm       fRE%d\n", s_labelVal );
            fprintf( fp, "    jz       geRE%d\n", s_labelVal );
            fprintf( fp, "    jp       tRE%d\n", s_labelVal );

            fprintf( fp, "  geRE%d:\n", s_labelVal );

            fprintf( fp, "    mov      a, e\n" );
            fprintf( fp, "    cmp      l\n" );
            fprintf( fp, "    jm       fRE%d\n", s_labelVal );
        }
        else if ( Token::LT == op )
        {
            fprintf( fp, "    jz       ltRE%d\n", s_labelVal );
            fprintf( fp, "    jm       tRE%d\n", s_labelVal );
            fprintf( fp, "    jmp      fRE%d\n", s_labelVal );

            fprintf( fp, "  ltRE%d:\n", s_labelVal );

            fprintf( fp, "    mov      a, e\n" );
            fprintf( fp, "    cmp      l\n" );
            fprintf( fp, "    jp       fRE%d\n", s_labelVal );
        }
        else if ( Token::GT == op )
        {
            fprintf( fp, "    jm       fRE%d\n", s_labelVal );
            fprintf( fp, "    jz       gtRE%d\n", s_labelVal );
            fprintf( fp, "    jmp      tRE%d\n", s_labelVal );

            fprintf( fp, "  gtRE%d:\n", s_labelVal );

            fprintf( fp, "    mov      a, e\n" );
            fprintf( fp, "    cmp      l\n" );
            fprintf( fp, "    jm       fRE%d\n", s_labelVal );
            fprintf( fp, "    jz       fRE%d\n", s_labelVal );
        }

        fprintf( fp, "  tRE%d:\n", s_labelVal );
        fprintf( fp, "    lxi      h, 1\n" );
        fprintf( fp, "    jmp      dRE%d\n", s_labelVal );

        fprintf( fp, "  fRE%d:\n", s_labelVal );
        fprintf( fp, "    lxi      h, 0\n" );
        
        fprintf( fp, "  dRE%d:\n", s_labelVal );

        s_labelVal++;
    }
} //GenerateRelational

void GenerateRelationalExpression( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
    {
        printf( "generate relational expression for line %d iToken %d %s\n", g_lineno, iToken, TokenStr( vals[ iToken ].token ) );

        for ( int i = iToken; i < beyond; i++ )
            printf( "    %d:    %s\n", i, TokenStr( vals[ i ].token ) );
    }

    // This won't be an EXPRESSION for cases like x = x + ...
    // But it will be EXPRESSION when called from GenerateLogicalExpression

    if ( Token::EXPRESSION == vals[ iToken ].token )
        iToken++;

    GenerateExpression( fp, varmap, iToken, beyond, vals );

    if ( iToken >= beyond )
        return;

    Token t = vals[ iToken ].token;

    while ( isOperatorRelational( t ) )
    {
        if ( x64Win == g_AssemblyTarget )
            fprintf( fp, "    push     rax\n" );
        else if ( arm64Mac == g_AssemblyTarget )
            fprintf( fp, "    str      x0, [sp, #-16]!\n" ); // save 4 bytes in a 16-byte spot
        else if ( i8080CPM == g_AssemblyTarget )
            fprintf( fp, "    push     h\n" );

        GenerateRelational( fp, varmap, iToken, beyond, vals );

        if ( iToken >= beyond )
            break;

        t = vals[ iToken ].token;
    }
} //GenerateRelationalExpression

void GenerateLogical( FILE * fp, map<string, Variable> const & varmap, int & iToken, int beyond, vector<TokenValue> const & vals )
{
    assert( iToken < beyond );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
        printf( "in generate logical, iToken %d\n", iToken );

    Token op = vals[ iToken ].token;
    iToken++;

    GenerateRelationalExpression( fp, varmap, iToken, beyond, vals );

    if ( x64Win == g_AssemblyTarget )
    {
        fprintf( fp, "    pop     rbx\n" );
        fprintf( fp, "    %-6s   rax, rbx\n", OperatorInstruction[ op ] );
        //fprintf( fp, "    movzx    rax, al\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, "    ldr     x1, [sp], #16\n" );
        fprintf( fp, "    %-6s   x0, x1, x0\n", OperatorInstructionArm64[ op ] );
    }   
    else if ( i8080CPM == g_AssemblyTarget )
    {
        // lhs in de, rhs in hl

        fprintf( fp, "    pop      d\n" );
        fprintf( fp, "    mov      a, h\n" );
        fprintf( fp, "    %-6s   d\n", OperatorInstructioni8080[ op ] );
        fprintf( fp, "    mov      h, a\n" );
        fprintf( fp, "    mov      a, l\n" );
        fprintf( fp, "    %-6s   e\n", OperatorInstructioni8080[ op ] );
        fprintf( fp, "    mov      l, a\n" );
    }
} //GenerateLogical

void GenerateLogicalExpression( FILE * fp, map<string, Variable> const & varmap, int & iToken, vector<TokenValue> const & vals )
{
    int beyond = iToken + vals[ iToken ].value;

    assert( iToken < beyond );
    assert( beyond <= vals.size() );
    assert( iToken < vals.size() );

    if ( EnableTracing && g_Tracing )
    {
        printf( "generate logical expression for line %d iToken %d %s\n", g_lineno, iToken, TokenStr( vals[ iToken ].token ) );

        for ( int i = iToken; i < beyond; i++ )
            printf( "    %d:    %s\n", i, TokenStr( vals[ i ].token ) );
    }

    assert( Token::EXPRESSION == vals[ iToken ].token );

    GenerateRelationalExpression( fp, varmap, iToken, beyond, vals );

    if ( iToken >= beyond )
        return;

    Token t = vals[ iToken ].token;

    while ( isOperatorLogical( t ) )
    {
        if ( x64Win == g_AssemblyTarget )
            fprintf( fp, "    push     rax\n" );
        else if ( arm64Mac == g_AssemblyTarget )
            fprintf( fp, "    str      x0, [sp, #-16]!\n" ); // save 4 bytes in a 16-byte spot
        else if ( i8080CPM == g_AssemblyTarget )
            fprintf( fp, "    push     h\n" );

        GenerateLogical( fp, varmap, iToken, beyond, vals );

        if ( iToken >= beyond )
            break;

        t = vals[ iToken ].token;
    }
} //GenereateLogicalExpression

void GenerateOptimizedExpression( FILE * fp, map<string, Variable> const & varmap, int & iToken, vector<TokenValue> const & vals )
{
    // generate code to put the resulting expression in rax
    // On x64, only modifies rax, rbx, and rdx (without saving them)
    // On arm64, result is in r0
    // on i8080, result is in HL

    assert( Token::EXPRESSION == vals[ iToken ].token );
    int tokenCount = vals[ iToken ].value;

    #ifdef DEBUG
        int firstToken = iToken;
    #endif

    if ( EnableTracing && g_Tracing )
        printf( "  GenerateOptimizedExpression token %d, which is %s, length %d\n",
                iToken, TokenStr( vals[ iToken ].token ), vals[ iToken ].value );

    if ( i8080CPM == g_AssemblyTarget || !g_ExpressionOptimization )
        goto label_no_expression_optimization;

    if ( 2 == tokenCount )
    {
        if ( Token::CONSTANT == vals[ iToken + 1 ].token )
        {
            if ( x64Win == g_AssemblyTarget )
                fprintf( fp, "    mov      eax, %d\n", vals[ iToken + 1 ].value );
            else if ( arm64Mac == g_AssemblyTarget )
                LoadArm64Constant( fp, "x0", vals[ iToken + 1 ].value );
        }
        else if ( Token::VARIABLE == vals[ iToken + 1 ].token )
        {
            string const & varname = vals[ iToken + 1 ].strValue;

            if ( x64Win == g_AssemblyTarget )
            {   
                if ( IsVariableInReg( varmap, varname ) )
                    fprintf( fp, "    mov      eax, %s\n", GenVariableReg( varmap, varname ) );
                else
                    fprintf( fp, "    mov      eax, [%s]\n", GenVariableName( varname ) );
            }
            else if ( arm64Mac == g_AssemblyTarget )
            {
                if ( IsVariableInReg( varmap, varname ) )
                    fprintf( fp, "    mov      w0, %s\n", GenVariableReg( varmap, varname ) );
                else
                {
                    LoadArm64Address( fp, "x1", varname );
                    fprintf( fp, "    ldr      w0, [x1]\n" );
                }
            }
        }

        iToken += tokenCount;
    }
    else if ( 6 == tokenCount &&
              Token::VARIABLE == vals[ iToken + 1 ].token &&
              Token::OPENPAREN == vals[ iToken + 2 ].token )
    {
        // 0 EXPRESSION, value 6, strValue ''
        // 1 VARIABLE, value 0, strValue 'sa%'
        // 2 OPENPAREN, value 0, strValue ''
        // 3 EXPRESSION, value 2, strValue ''
        // 4 VARIABLE, value 0, strValue 'st%'   (this can optionally be a constant)
        // 5 CLOSEPAREN, value 0, strValue ''

        if ( 1 != vals[ iToken + 1 ].dimensions ) // can't be > 1 or tokenCount would be greater
            RuntimeFail( "scalar variable used as an array", g_lineno );

        if ( Token::CONSTANT == vals[ iToken + 4 ].token )
        {
            string const & varname = vals[ iToken + 1 ].strValue;

            if ( x64Win == g_AssemblyTarget )
                fprintf( fp, "    mov      eax, DWORD PTR[ %s + %d ]\n", GenVariableName( varname ),
                         4 * vals[ iToken + 4 ].value );
            else if ( arm64Mac == g_AssemblyTarget )
            {
                LoadArm64Address( fp, "x1", varname );

                int offset = 4 * vals[ iToken + 4 ].value;

                if ( fitsIn8Bits( offset ) )
                    fprintf( fp, "    ldr      w0, [x1, %d]\n", offset );
                else
                {
                    LoadArm64Constant( fp, "x0", offset );
                    fprintf( fp, "    add      x1, x1, x0\n" );
                    fprintf( fp, "    ldr      w0, [x1]\n" );
                }
            }
        }
        else
        {
            int iStart = iToken + 3;
            GenerateOptimizedExpression( fp, varmap, iStart, vals );
    
            string const & varname = vals[ iToken + 1 ].strValue;

            if ( x64Win == g_AssemblyTarget )
            {
                fprintf( fp, "    lea      rdx, [%s]\n", GenVariableName( varname ) );
                fprintf( fp, "    shl      rax, 2\n" );
                fprintf( fp, "    mov      eax, [rax + rdx]\n" );
            }
            else if ( arm64Mac == g_AssemblyTarget )
            {
                LoadArm64Address( fp, "x1", varname );
                fprintf( fp, "    lsl      x0, x0, 2\n" );
                fprintf( fp, "    add      x1, x1, x0\n" );
                fprintf( fp, "    ldr      w0, [x1]\n" );
            }
        }

        iToken += tokenCount;
    }
    else if ( 4 == tokenCount )
    {
        assert( isTokenSimpleValue( vals[ iToken + 1 ].token ) );
        assert( isTokenOperator( vals[ iToken + 2 ].token ) );
        assert( isTokenSimpleValue( vals[ iToken + 3 ].token ) );

        GenerateOp( fp, varmap, vals, iToken + 1, iToken + 3, vals[ iToken + 2 ].token );

        iToken += tokenCount;
    }
    else if ( x64Win == g_AssemblyTarget && 3 == tokenCount )
    {
        if ( Token::NOT == vals[ iToken + 1 ].token )
        {
            string const & varname = vals[ iToken + 2 ].strValue;
            
            if ( IsVariableInReg( varmap, varname ) )
                fprintf( fp, "    cmp      %s, 0\n", GenVariableReg( varmap, varname ) );
            else
                fprintf( fp, "    cmp      DWORD PTR [%s], 0\n", GenVariableName( varname ) );

            fprintf( fp, "    sete     al\n" );
            fprintf( fp, "    movzx    rax, al\n" );
        }
        else
        {
            assert( Token::MINUS == vals[ iToken + 1 ].token );

            string const & varname = vals[ iToken + 2 ].strValue;
            if ( IsVariableInReg( varmap, varname ) )
                fprintf( fp, "    mov      eax, %s\n", GenVariableReg( varmap, varname ) );
            else
                fprintf( fp, "    mov      eax, [%s]\n", GenVariableName( varname ) );

            fprintf( fp, "    neg      rax\n" );
        }

        iToken += tokenCount;
    }
    else if ( 16 == tokenCount &&
              Token::VARIABLE == vals[ iToken + 1 ].token &&
              Token::OPENPAREN == vals[ iToken + 4 ].token &&
              Token::CONSTANT == vals[ iToken + 6 ].token &&
              Token::VARIABLE == vals[ iToken + 9 ].token &&
              Token::OPENPAREN == vals[ iToken + 12 ].token &&
              Token::CONSTANT == vals[ iToken + 14 ].token &&
              isOperatorRelational( vals[ iToken + 2 ].token ) &&
              isOperatorRelational( vals[ iToken + 10 ].token ) )
    {
        //  0 EXPRESSION, value 16, strValue ''
        //  1 VARIABLE, value 0, strValue 'wi%'
        //  2 EQ, value 0, strValue ''
        //  3 VARIABLE, value 0, strValue 'b%'
        //  4 OPENPAREN, value 0, strValue ''
        //  5 EXPRESSION, value 2, strValue ''
        //  6 CONSTANT, value 5, strValue ''
        //  7 CLOSEPAREN, value 0, strValue ''
        //  8 AND, value 0, strValue ''
        //  9 VARIABLE, value 0, strValue 'wi%'
        // 10 EQ, value 0, strValue ''
        // 11 VARIABLE, value 0, strValue 'b%'
        // 12 OPENPAREN, value 0, strValue ''
        // 13 EXPRESSION, value 2, strValue ''
        // 14 CONSTANT, value 8, strValue ''
        // 15 CLOSEPAREN, value 0, strValue ''

        //value = run_operator( run_operator( vals[ iToken + 1 ].pVariable->value,
        //                                    vals[ iToken + 2 ].token,
        //                                    vals[ iToken + 3 ].pVariable->array[ vals[ iToken + 6 ].value ] ),
        //                      vals[ iToken + 8 ].token,
        //                      run_operator( vals[ iToken + 9 ].pVariable->value,
        //                                    vals[ iToken + 10 ].token,
        //                                    vals[ iToken + 11 ].pVariable->array[ vals[ iToken + 14 ].value ] ) );

        GenerateOp( fp, varmap, vals, iToken + 1, iToken + 3, vals[ iToken + 2 ].token, 0, iToken + 6 );

        if ( Token::AND == vals[ iToken + 8 ].token )
        {
            if ( x64Win == g_AssemblyTarget )
            {
                fprintf( fp, "    test     rax, rax\n" );
                fprintf( fp, "    jz       label_early_out_%d\n", g_pc );
            }
            else if ( arm64Mac == g_AssemblyTarget )
                fprintf( fp, "    cbz      w0, label_early_out_%d\n", g_pc );
        }

        if ( x64Win == g_AssemblyTarget )
            fprintf( fp, "    mov      rdx, rax\n" );
        else if ( arm64Mac == g_AssemblyTarget )
            fprintf( fp, "    mov      x5, x0\n" );
    
        GenerateOp( fp, varmap, vals, iToken + 9, iToken + 11, vals[ iToken + 10 ].token, 0, iToken + 14 );

        Token finalOp = vals[ iToken + 8 ].token;
        if ( isOperatorRelational( finalOp ) )
        {
            if ( x64Win == g_AssemblyTarget )
            {
                fprintf( fp, "    cmp      rax, rdx\n" );
                fprintf( fp, "    %-6s   al\n", OperatorInstruction[ finalOp ] );
                fprintf( fp, "    movzx    rax, al\n" );
            }
            else if ( arm64Mac == g_AssemblyTarget )
            {
                fprintf( fp, "    cmp      w0, w5\n" );
                fprintf( fp, "    cset     x0, %s\n", ConditionsArm64[ finalOp ] );
            }
        }
        else
        {
            if ( x64Win == g_AssemblyTarget )
                fprintf( fp, "    %-6s   rax, rdx\n", OperatorInstruction[ finalOp ] );
            else if ( arm64Mac == g_AssemblyTarget )
                fprintf( fp, "    %-6s   w0, w0, w5\n", OperatorInstructionArm64[ finalOp ] );

            if ( Token::AND == vals[ iToken + 8 ].token )
            {
                if ( arm64Mac == g_AssemblyTarget )
                    fprintf( fp, "  .p2align 3\n" );

                fprintf( fp, "  label_early_out_%d:\n", g_pc );
            }
        }

        iToken += tokenCount;
    }
    else
    {
        label_no_expression_optimization:

        GenerateLogicalExpression( fp, varmap, iToken, vals );
    }

    assert( iToken == ( firstToken + tokenCount ) );
} //GenerateOptimizedExpression

struct VarCount
{
    VarCount() : name( 0 ), refcount( 0 ) {};
    const char * name;
    int refcount;
};

static int CompareVarCount( const void * a, const void * b )
{
    // sort by # of refcounts high to low, so we know which variables are referenced most frequently

    VarCount const * pa = (VarCount const *) a;
    VarCount const * pb = (VarCount const *) b;

    return pb->refcount - pa->refcount;
} //CompareVarCount

string ml64Escape( string & str )
{
    // escape characters in an ml64 string constant. I think just a single-quote is the only one
    // this is remarkably inefficient, but that's OK

    string result( str );
    replace_all( result, "'", "''" );
    return result;
} //ml64Escape

void GenerateASM( const char * outputfile, map<string, Variable> & varmap, bool useRegistersInASM )
{
    CFile fileOut( fopen( outputfile, "w" ) );
    FILE * fp = fileOut.get();
    if ( NULL == fileOut.get() )
    {
        printf( "can't open output file %s\n", outputfile );
        Usage();
    }

    if ( x64Win == g_AssemblyTarget )
    {
        fprintf( fp, "extern printf: PROC\n" );
        fprintf( fp, "extern exit: PROC\n" );
        fprintf( fp, "extern QueryPerformanceCounter: PROC\n" );
        fprintf( fp, "extern QueryPerformanceFrequency: PROC\n" );
        fprintf( fp, "extern GetLocalTime: PROC\n" );
        fprintf( fp, "data_segment SEGMENT ALIGN( 4096 ) 'DATA'\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, ".global _start\n" );
        fprintf( fp, ".data\n" );
        fprintf( fp, ".macro save_volatile_registers\n" );
        fprintf( fp, "    stp      x10, x11, [sp, #-16]!\n" ); 
        fprintf( fp, "    stp      x12, x13, [sp, #-16]!\n" ); 
        fprintf( fp, "    stp      x14, x15, [sp, #-16]!\n" );
        fprintf( fp, "    sub      sp, sp, #32\n" ); // save room for locals and arguments 
        fprintf( fp, ".endmacro\n" );
        fprintf( fp, ".macro restore_volatile_registers\n" );
        fprintf( fp, "    add      sp, sp, #32\n" );
        fprintf( fp, "    ldp      x14, x15, [sp], #16\n" );
        fprintf( fp, "    ldp      x12, x13, [sp], #16\n" );
        fprintf( fp, "    ldp      x10, x11, [sp], #16\n" );
        fprintf( fp, ".endmacro\n" );
    }
    else if ( i8080CPM == g_AssemblyTarget )
    {
        fprintf( fp, "; assemble, load, and run using for test.asm:\n" );
        fprintf( fp, ";   asm test\n" );
        fprintf( fp, ";   load test\n" );
        fprintf( fp, ";   test\n" );
        fprintf( fp, "BDOS equ 5\n" );
        fprintf( fp, "WCONF equ 2\n" );
        fprintf( fp, "PRSTR equ 9\n" );
        fprintf( fp, "    org      100h\n" );
        fprintf( fp, "    jmp      start\n" ); // jump over data
    }

    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];
        vector<TokenValue> & vals = loc.tokenValues;

        if ( Token::DIM == vals[ 0 ].token )
        {
            int cdwords = vals[ 0 ].dims[ 0 ];
            if ( 2 == vals[ 0 ].dimensions )
                cdwords *= vals[ 0 ].dims[ 1 ];

            Variable * pvar = FindVariable( varmap, vals[ 0 ].strValue );

            // If an array is declared but never referenced later (and so not in varmap), ignore it

            if ( 0 != pvar )
            {
                pvar->dimensions = vals[ 0 ].dimensions;
                pvar->dims[ 0 ] = vals[ 0 ].dims[ 0 ];
                pvar->dims[ 1 ] = vals[ 0 ].dims[ 1 ];

                if ( x64Win == g_AssemblyTarget )
                {
                    fprintf( fp, "  align 16\n" );
                    fprintf( fp, "    %8s DD %d DUP (0)\n", GenVariableName( vals[ 0 ].strValue ), cdwords );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    fprintf( fp, "  .p2align 4\n" );
                    fprintf( fp, "    %8s: .space %d\n", GenVariableName( vals[ 0 ].strValue ), cdwords * 4 );
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    fprintf( fp, "    %8s: DS %d\n", GenVariableName( vals[ 0 ].strValue ), cdwords * 2 ); 
                }
            }
        }
        else if ( Token::PRINT == vals[ 0 ].token || Token::IF == vals[ 0 ].token )
        {
            for ( int t = 0; t < vals.size(); t++ )
            {
                if ( Token::STRING == vals[ t ].token )
                {
                    string strEscaped = ml64Escape( vals[ t ].strValue );
                    if ( x64Win == g_AssemblyTarget )
                        fprintf( fp, "    str_%zd_%d   db  '%s', 0\n", l, t , strEscaped.c_str() );
                    else if ( arm64Mac == g_AssemblyTarget )
                        fprintf( fp, "    str_%zd_%d: .asciz \"%s\"\n", l, t, strEscaped.c_str() );
                    else if ( i8080CPM == g_AssemblyTarget )
                        fprintf( fp, "      s$%zd$%d: db '%s', '$'\n", l, t, strEscaped.c_str() );
                }
            }
        }
    }

    vector<VarCount> varscount;

    for ( auto it = varmap.begin(); it != varmap.end(); it++ )
    {
        // enable registers for arm64 arrays since loading addresses via code is slow.
        // it's 5% overall faster this way

        if ( 0 == it->second.dimensions || arm64Mac == g_AssemblyTarget )
        {
            VarCount vc;
            vc.name = it->first.c_str();
            vc.refcount = it->second.references;
            varscount.push_back( vc );
        }
    }

    qsort( varscount.data(), varscount.size(), sizeof( VarCount ), CompareVarCount );

    int availableRegisters = 0;
    if ( useRegistersInASM )
        availableRegisters = ( x64Win == g_AssemblyTarget) ? _countof( MappedRegistersX64 ) : 
                             ( arm64Mac == g_AssemblyTarget ) ? _countof( MappedRegistersArm64 ) :
                             0;

    for ( size_t i = 0; i < varscount.size() && 0 != availableRegisters; i++ )
    {
        Variable * pvar = FindVariable( varmap, varscount[ i ].name );
        assert( pvar );
        availableRegisters--;
        if ( x64Win == g_AssemblyTarget )
            pvar->reg = MappedRegistersX64[ availableRegisters ];
        else if ( arm64Mac == g_AssemblyTarget )
            pvar->reg = MappedRegistersArm64[ availableRegisters ];

        if ( EnableTracing && g_Tracing )
            printf( "variable %s has %d references and is mapped to register %s\n",
                    varscount[ i ].name, varscount[ i ].refcount, pvar->reg.c_str() );

        fprintf( fp, "    ; variable %s (referenced %d times) will use register %s\n", pvar->name,
                 varscount[ i ].refcount, pvar->reg.c_str() );
    }

    if ( x64Win == g_AssemblyTarget )
        fprintf( fp, "  align 16\n" );
    else if ( arm64Mac == g_AssemblyTarget )
        fprintf( fp, "  .p2align 4\n" );

    for ( auto it = varmap.begin(); it != varmap.end(); it++ )
    {
        if ( ( 0 == it->second.dimensions ) && ( 0 == it->second.reg.length() ) )
        {
            if ( x64Win == g_AssemblyTarget )
                fprintf( fp, "    %8s DD   0\n", GenVariableName( it->first ) );
            else if ( arm64Mac == g_AssemblyTarget )
                fprintf( fp, "    %8s: .quad 0\n", GenVariableName( it->first ) );
            else if ( i8080CPM == g_AssemblyTarget )
                fprintf( fp, "    %8s: dw  0\n", GenVariableName( it->first ) );
        }
    }

    varscount.clear();

    if ( x64Win == g_AssemblyTarget )
    {
        fprintf( fp, "  align 16\n" );
        fprintf( fp, "    gosubCount     dq    0\n" ); // count of active gosub calls
        fprintf( fp, "    startTicks     dq    0\n" );
        fprintf( fp, "    perfFrequency  dq    0\n" );
        fprintf( fp, "    currentTicks   dq    0\n" );
        fprintf( fp, "    currentTime    dq 2  DUP(0)\n" ); // SYSTEMTIME is 8 WORDS

        fprintf( fp, "    errorString    db    'internal error', 10, 0\n" );
        fprintf( fp, "    startString    db    'running basic', 10, 0\n" );
        fprintf( fp, "    stopString     db    'done running basic', 10, 0\n" );
        fprintf( fp, "    newlineString  db    10, 0\n" );
        fprintf( fp, "    elapString     db    '%%lld microseconds (-6)', 0\n" );
        fprintf( fp, "    timeString     db    '%%02d:%%02d:%%02d', 0\n" );
        fprintf( fp, "    intString      db    '%%d', 0\n" );
        fprintf( fp, "    strString      db    '%%s', 0\n" );

        fprintf( fp, "data_segment ENDS\n" );

        fprintf( fp, "code_segment SEGMENT ALIGN( 4096 ) 'CODE'\n" );
        fprintf( fp, "main PROC\n" );
        fprintf( fp, "    push     rbp\n" );
        fprintf( fp, "    mov      rbp, rsp\n" );
        fprintf( fp, "    sub      rsp, 32 + 8 * 4\n" );

        fprintf( fp, "    lea      rcx, [startString]\n" );
        fprintf( fp, "    call     printf\n" );
        fprintf( fp, "    lea      rcx, [startTicks]\n" );
        fprintf( fp, "    call     QueryPerformanceCounter\n" );
        fprintf( fp, "    lea      rcx, [perfFrequency]\n" );
        fprintf( fp, "    call     QueryPerformanceFrequency\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, "  .p2align 4\n" );
        fprintf( fp, "    gosubCount:    .quad 0\n" );
        fprintf( fp, "    startTicks:    .quad 0\n" );
        fprintf( fp, "    rawTime:       .quad 0\n" ); // time_t
        fprintf( fp, "    errorString:   .asciz \"internal error\\n\"\n" );
        fprintf( fp, "    startString:   .asciz \"running basic\\n\"\n" );
        fprintf( fp, "    stopString:    .asciz \"done running basic\\n\"\n" );
        fprintf( fp, "    newlineString: .asciz \"\\n\"\n" );
        fprintf( fp, "    elapString:    .asciz \"%%lld microseconds (-6)\"\n" );
        fprintf( fp, "    timeString:    .asciz \"%%02d:%%02d:%%02d\"\n" );
        fprintf( fp, "    intString:     .asciz \"%%d\"\n" );
        fprintf( fp, "    strString:     .asciz \"%%s\"\n" );

        fprintf( fp, ".p2align 4\n" );
        fprintf( fp, ".text\n" );
        fprintf( fp, "_start:\n" );

        fprintf( fp, "    sub      sp, sp, #32\n" );
        fprintf( fp, "    stp      x29, x30, [sp, #16]\n" );
        fprintf( fp, "    add      x29, sp, #16\n" );

        fprintf( fp, "    adrp     x0, startString@PAGE\n" );
        fprintf( fp, "    add      x0, x0, startString@PAGEOFF\n" );
        fprintf( fp, "    bl       call_printf\n" );

        fprintf( fp, "    adrp     x3, startTicks@PAGE\n" );
        fprintf( fp, "    add      x3, x3, startTicks@PAGEOFF\n" );
        fprintf( fp, "    mrs      x0, cntvct_el0\n" );
        fprintf( fp, "    str      x0, [x3]\n" );
    }
    else if ( i8080CPM == g_AssemblyTarget )
    {
        fprintf( fp, "    errorString:    db    'internal error', 10, 13, '$'\n" );
        fprintf( fp, "    startString:    db    'running basic', 10, 13, '$'\n" );
        fprintf( fp, "    stopString:     db    'done running basic', 10, 13, '$'\n" );
        fprintf( fp, "    newlineString:  db    10, 13, '$'\n" );
        fprintf( fp, "    mulTmp:         dw    0\n" ); // temporary for imul and idiv functions
        fprintf( fp, "    divRem:         dw    0\n" ); // idiv remainder

        fprintf( fp, "start:\n" );
        fprintf( fp, "    push     b\n" );
        fprintf( fp, "    push     d\n" );
        fprintf( fp, "    push     h\n" );

        for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
        {
            LineOfCode & loc = g_linesOfCode[ l ];
            vector<TokenValue> & vals = loc.tokenValues;
    
            if ( Token::DIM == vals[ 0 ].token )
            {
                int cdwords = vals[ 0 ].dims[ 0 ];
                if ( 2 == vals[ 0 ].dimensions )
                    cdwords *= vals[ 0 ].dims[ 1 ];
    
                Variable * pvar = FindVariable( varmap, vals[ 0 ].strValue );
    
                if ( 0 != pvar )
                {
                    fprintf( fp, "    lxi      d, %d\n", cdwords * 2 );
                    fprintf( fp, "    lxi      b, %s\n", GenVariableName( vals[ 0 ].strValue ) );
                    fprintf( fp, "    call     zeromem\n" );
                }
            }
        }

        fprintf( fp, "    mvi      c, PRSTR\n" );
        fprintf( fp, "    lxi      d, startString\n" );
        fprintf( fp, "    call     BDOS\n" );
    }

    if ( useRegistersInASM )
    {
        if ( x64Win == g_AssemblyTarget )
            for ( size_t i = 0; i < _countof( MappedRegistersX64 ); i++ )
                fprintf( fp, "    xor      %s, %s\n", MappedRegistersX64[ i ], MappedRegistersX64[ i ] );
        else if ( arm64Mac == g_AssemblyTarget )
            for ( size_t i = 0; i < _countof( MappedRegistersArm64 ); i++ )
                fprintf( fp, "    mov      %s, 0\n", MappedRegistersArm64[ i ] );

        for ( auto it = varmap.begin(); it != varmap.end(); it++ )
        {
            if ( ( 0 != it->second.dimensions ) && ( 0 != it->second.reg.length() ) )
            {
                string const & varname = it->first;

                if ( x64Win == g_AssemblyTarget )
                    fprintf( fp, "    mov      %s, %s\n", GenVariableReg( varmap, varname ), varname.c_str() );
                else if ( arm64Mac == g_AssemblyTarget )
                    LoadArm64Address( fp, GenVariableReg64( varmap, varname ), varname );
            }
        }
    }

    static int s_uniqueLabel = 0;
    static Stack<ForGosubItem> forGosubStack;
    size_t activeIf = -1;

    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];
        g_pc = (int) l;
        vector<TokenValue> & vals = loc.tokenValues;
        Token token = loc.firstToken;
        int t = 0;

        if ( EnableTracing && g_Tracing )
            printf( "generating code for line %zd ====> %s\n", l, loc.sourceCode.c_str() );

        if ( arm64Mac == g_AssemblyTarget && loc.goTarget )
            fprintf( fp, ".p2align 2\n" ); // arm64 branch targets must be 4-byte aligned

        if ( i8080CPM == g_AssemblyTarget )
            fprintf( fp, "  ln$%zd:   ; ===>>> %s\n", l, loc.sourceCode.c_str() );
        else
            fprintf( fp, "  line_number_%zd:   ; ===>>> %s\n", l, loc.sourceCode.c_str() );

        do  // all tokens in the line
        {
            if ( EnableTracing && g_Tracing )
                printf( "generating code for line %zd, token %d %s, valsize %zd\n", l, t, TokenStr( vals[ t ].token ), vals.size() );

            if ( Token::VARIABLE == token )
            {
                int variableToken = t;
                t++;
    
                if ( Token::EQ == vals[ t ].token )
                {
                    t++;
    
                    assert( Token::EXPRESSION == vals[ t ].token );

                    if ( i8080CPM == g_AssemblyTarget || !g_ExpressionOptimization )
                        goto label_no_eq_optimization;

                    if ( Token::CONSTANT == vals[ t + 1 ].token && ( 2 == vals[ t ].value ) )
                    {
                        // e.g.: x% = 3
                        // note: testing for 0 and generating xor resulted in slower generated code. Not sure why.

                        string & varname = vals[ variableToken ].strValue;

                        if ( x64Win == g_AssemblyTarget )
                        {
                            if ( IsVariableInReg( varmap, varname ) )
                                fprintf( fp, "    mov      %s, %d\n", GenVariableReg( varmap, varname ), vals[ t + 1 ].value );
                            else
                                fprintf( fp, "    mov      DWORD PTR [%s], %d\n", GenVariableName( varname ), vals[ t + 1 ].value );
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            int val = vals[ t + 1 ].value;

                            if ( IsVariableInReg( varmap, varname ) )
                            {
                                LoadArm64Constant( fp, GenVariableReg( varmap, varname ), val );
                            }
                            else
                            {
                                LoadArm64Constant( fp, "x0", val );
                                LoadArm64Address( fp, "x1", varname );
                                fprintf( fp, "    str      w0, [x1]\n" );
                            }
                        }

                        t += vals[ t ].value;
                    }
                    else if ( Token::VARIABLE == vals[ t + 1 ].token && 2 == vals[ t ].value &&
                              IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                              IsVariableInReg( varmap, vals[ variableToken ].strValue ) )
                    {
                        // e.g.: x% = y%

                        if ( x64Win == g_AssemblyTarget || arm64Mac == g_AssemblyTarget )
                            fprintf( fp, "    mov      %s, %s\n", GenVariableReg( varmap, vals[ variableToken ].strValue ),
                                                                  GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                        t += vals[ t ].value;
                    }
                    else if ( 6 == vals[ t ].value &&
                              Token::VARIABLE == vals[ t + 1 ].token &&
                              IsVariableInReg( varmap, vals[ variableToken ].strValue ) &&
                              Token::OPENPAREN == vals[ t + 2 ].token &&
                              isTokenSimpleValue( vals[ t + 4 ].token ) &&
                              ( Token::CONSTANT == vals[ t + 4 ].token || IsVariableInReg( varmap, vals[ t + 4 ].strValue ) ) )
                    {
                        // e.g.: p% = sp%( st% ) 
                        //       p% = sp%( 4 )

                        // line 4290 has 8 tokens  ====>> 4290 p% = sp%(st%)
                        // token   0 VARIABLE, value 0, strValue 'p%'
                        // token   1 EQ, value 0, strValue ''
                        // token   2 EXPRESSION, value 6, strValue ''
                        // token   3 VARIABLE, value 0, strValue 'sp%'
                        // token   4 OPENPAREN, value 0, strValue ''
                        // token   5 EXPRESSION, value 2, strValue ''
                        // token   6 VARIABLE, value 0, strValue 'st%'
                        // token   7 CLOSEPAREN, value 0, strValue ''

                        if ( x64Win == g_AssemblyTarget )
                        {
                            if ( Token::CONSTANT == vals[ t + 4 ].token )
                            {
                                fprintf( fp, "    mov      %s, [ %s + %d ]\n", GenVariableReg( varmap, vals[ variableToken ].strValue ),
                                                                               GenVariableName( vals[ t + 1 ].strValue ),
                                                                               4 * vals[ t + 4 ].value );
                            }
                            else
                            {
                                fprintf( fp, "    mov      eax, %s\n", GenVariableReg( varmap, vals[ t + 4 ].strValue ) );
                                fprintf( fp, "    shl      rax, 2\n" );
                                fprintf( fp, "    lea      rbx, [%s]\n", GenVariableName( vals[ t + 1 ].strValue ) );
                                fprintf( fp, "    mov      %s, [ rax + rbx ]\n", GenVariableReg( varmap, vals[ variableToken ].strValue ) );
                            }
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            string & vararray = vals[ t + 1 ].strValue;
                            string & varname = vals[ variableToken ].strValue;

                            //LoadArm64Address( fp, "x1", varmap, vals[ t + 1 ].strValue );

                            if ( Token::CONSTANT == vals[ t + 4 ].token )
                            {
                                if ( 0 != vals[ t + 4 ].value )
                                {
                                    int constant = 4 * vals[ t + 4 ].value;

                                    if ( fitsIn8Bits( constant ) )
                                    {
                                        if ( IsVariableInReg( varmap, vararray ) )
                                            fprintf( fp, "    ldr      %s, [%s, %d]\n", GenVariableReg( varmap, varname ),
                                                                                        GenVariableReg64( varmap, vararray ),
                                                                                        constant );
                                        else
                                        {
                                            LoadArm64Address( fp, "x1", varmap, vals[ t + 1 ].strValue );
                                            fprintf( fp, "    ldr      %s, [x1, %d]\n", GenVariableReg( varmap, varname ),
                                                                                        constant );
                                        }
                                    }
                                    else
                                    {
                                        LoadArm64Address( fp, "x1", varmap, vals[ t + 1 ].strValue );
            
                                        if ( fitsIn12Bits( constant ) )
                                            fprintf( fp, "    add      x1, x1, %d\n", constant );
                                        else
                                        {
                                            LoadArm64Constant( fp, "x2", constant );
                                            fprintf( fp, "    add      x1, x1, x2\n" );
                                        }

                                        fprintf( fp, "    ldr      %s, [x1]\n", GenVariableReg( varmap, varname ) );
                                    }
                                }
                                else
                                   fprintf( fp, "    ldr      %s, [%s]\n", GenVariableReg( varmap, varname ),
                                                                           GenVariableReg64( varmap, vararray ) );
                            }
                            else
                            {
                                if ( IsVariableInReg( varmap, vararray ) )
                                {
                                    fprintf( fp, "    lsl      w2, %s, 2\n", GenVariableReg( varmap, vals[ t + 4 ].strValue ) );
                                    fprintf( fp, "    add      x1, %s, x2\n", GenVariableReg64( varmap, vararray ) );
                                    fprintf( fp, "    ldr      %s, [x1]\n", GenVariableReg( varmap, varname ) );
                                }
                                else
                                {
                                    LoadArm64Address( fp, "x1", varmap, vararray );

                                    fprintf( fp, "    lsl      w2, %s, 2\n", GenVariableReg( varmap, vals[ t + 4 ].strValue ) );
                                    fprintf( fp, "    add      x1, x1, x2\n" );
                                    fprintf( fp, "    ldr      %s, [x1]\n", GenVariableReg( varmap, varname ) );
                                }
                            }
                        }

                        t += vals[ t ].value;
                    }
                    else
                    {
label_no_eq_optimization:
                        GenerateOptimizedExpression( fp, varmap, t, vals );
                        string const & varname = vals[ variableToken ].strValue;
                                                
                        if ( x64Win == g_AssemblyTarget )
                        {
                            if ( IsVariableInReg( varmap, varname ) )
                                fprintf( fp, "    mov      %s, eax\n", GenVariableReg( varmap, varname ) );
                            else
                                fprintf( fp, "    mov      DWORD PTR [%s], eax\n", GenVariableName( varname ) );
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            if ( IsVariableInReg( varmap, varname ) )
                                fprintf( fp, "    mov      %s, w0\n", GenVariableReg( varmap, varname ) );
                            else
                            {
                                LoadArm64Address( fp, "x1", varname );
                                fprintf( fp, "    str      w0, [x1]\n" );
                            }
                        }
                        else if ( i8080CPM == g_AssemblyTarget )
                        {
                            fprintf( fp, "    shld     %s\n", GenVariableName( varname ) );
                        }
                    }
                }
                else if ( Token::OPENPAREN == vals[ t ].token )
                {
                    t++;

                    assert( Token::EXPRESSION == vals[ t ].token );

                    if ( !g_ExpressionOptimization )
                        goto label_no_array_eq_optimization;

                    if ( x64Win == g_AssemblyTarget &&
                         false &&                        // This code is smaller on x64, but overall runtime is 10% slower!?!
                         8 == vals.size() &&
                         Token::CONSTANT == vals[ t + 1 ].token &&
                         Token::EQ == vals[ t + 3 ].token &&
                         Token::CONSTANT == vals[ t + 5 ].token )
                    {
                        // e.g.: b%( 0 ) = 0

                        // line 60 has 8 tokens  ====>> 60 b%(0) = 0
                        //    0 VARIABLE, value 0, strValue 'b%'
                        //    1 OPENPAREN, value 0, strValue ''
                        //    2 EXPRESSION, value 2, strValue ''
                        //    3 CONSTANT, value 0, strValue ''
                        //    4 CLOSEPAREN, value 0, strValue ''
                        //    5 EQ, value 0, strValue ''
                        //    6 EXPRESSION, value 2, strValue ''
                        //    7 CONSTANT, value 0, strValue ''

                        fprintf( fp, "    mov      DWORD PTR [ %s + %d ], %d\n", GenVariableName( vals[ variableToken ].strValue ),
                                                                                 4 * vals[ t + 1 ].value,
                                                                                 vals[ t + 5 ].value );
                        break;
                    }
                    else if ( arm64Mac == g_AssemblyTarget &&
                              8 == vals.size() &&
                              Token::CONSTANT == vals[ t + 1 ].token &&
                              Token::EQ == vals[ t + 3 ].token &&
                              Token::CONSTANT == vals[ t + 5 ].token )
                    {
                        // line 73 has 8 tokens  ====>> 73 b%(4) = 0
                        //   0 VARIABLE, value 0, strValue 'b%'
                        //   1 OPENPAREN, value 0, strValue ''
                        //   2 EXPRESSION, value 2, strValue ''
                        //   3 CONSTANT, value 4, strValue ''
                        //   4 CLOSEPAREN, value 0, strValue ''
                        //   5 EQ, value 0, strValue ''
                        //   6 EXPRESSION, value 2, strValue ''
                        //   7 CONSTANT, value 0, strValue ''

                        char const * arrayReg = "x2";
                        char const * writeReg = "x2";
                        if ( IsVariableInReg( varmap, vals[ variableToken ].strValue ) )
                        {
                            arrayReg = GenVariableReg64( varmap, vals[ variableToken ].strValue );
                            writeReg = arrayReg;
                        }
                        else    
                            LoadArm64Address( fp, "x2", varmap, vals[ variableToken ].strValue );

                        int offset = 4 * vals[ t + 1 ].value;
                        if ( !fitsIn8Bits( offset ) )
                        {
                            LoadArm64Constant( fp, "x1", offset );
                            fprintf( fp, "    add      x1, x1, %s\n", arrayReg );
                            writeReg = "x1";
                            offset = 0;
                        }

                        if ( 0 == vals[ t + 5 ].value )
                            fprintf( fp, "    str      wzr, [%s, %d]\n", writeReg, offset );
                        else
                        {
                            LoadArm64Constant( fp, "x0", vals[ t + 5 ].value );                            
                            fprintf( fp, "    str      w0, [%s, %d]\n", writeReg, offset );
                        }
                        break;
                    }
                    else if ( arm64Mac == g_AssemblyTarget &&
                              8 == vals.size() &&
                              Token::VARIABLE == vals[ t + 1 ].token &&
                              IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                              IsVariableInReg( varmap, vals[ variableToken ].strValue ) &&
                              Token::CONSTANT == vals[ t + 5 ].token )
                    {
                        // line 4328 has 8 tokens  ====>> 4328 b%(p%) = 0
                        //   0 VARIABLE, value 0, strValue 'b%'
                        //   1 OPENPAREN, value 0, strValue ''
                        //   2 EXPRESSION, value 2, strValue ''
                        //   3 VARIABLE, value 0, strValue 'p%'
                        //   4 CLOSEPAREN, value 0, strValue ''
                        //   5 EQ, value 0, strValue ''
                        //   6 EXPRESSION, value 2, strValue ''
                        //   7 CONSTANT, value 0, strValue ''

                        fprintf( fp, "    lsl      w1, %s, 2\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                        fprintf( fp, "    add      x1, %s, x1\n", GenVariableReg64( varmap, vals[ variableToken ].strValue ) );
                        
                        if ( 0 == vals[ t + 5 ].value )
                            fprintf( fp, "    str      wzr, [x1]\n" );
                        else
                        {
                            LoadArm64Constant( fp, "x0", vals[ t + 5 ].value );                            
                            fprintf( fp, "    str      w0, [x1]\n" );
                        }
                        break;
                    }
                    else if ( arm64Mac == g_AssemblyTarget &&
                              8 == vals.size() &&
                              Token::VARIABLE == vals[ t + 1 ].token &&
                              IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                              Token::VARIABLE == vals[ t + 5 ].token &&
                              IsVariableInReg( varmap, vals[ t + 5 ].strValue ) )
                    {
                        // line 4230 has 8 tokens  ====>> 4230 sv%(st%) = v%
                        //   0 VARIABLE, value 0, strValue 'sv%'
                        //   1 OPENPAREN, value 0, strValue ''
                        //   2 EXPRESSION, value 2, strValue ''
                        //   3 VARIABLE, value 0, strValue 'st%'
                        //   4 CLOSEPAREN, value 0, strValue ''
                        //   5 EQ, value 0, strValue ''
                        //   6 EXPRESSION, value 2, strValue ''
                        //   7 VARIABLE, value 0, strValue 'v%'

                        string vararray = vals[ variableToken ].strValue;

                        if ( IsVariableInReg( varmap, vararray ) )
                        {
                            fprintf( fp, "    lsl      w0, %s, 2\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                            fprintf( fp, "    add      x2, %s, x0\n", GenVariableReg64( varmap, vararray ) );
                            fprintf( fp, "    str      %s, [x2]\n", GenVariableReg( varmap, vals[ t + 5 ].strValue ) );
                        }
                        else
                        {
                            LoadArm64Address( fp, "x2", varmap, vals[ variableToken ].strValue );
                            fprintf( fp, "    lsl      w0, %s, 2\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                            fprintf( fp, "    add      x2, x2, x0\n" );
                            fprintf( fp, "    str      %s, [x2]\n", GenVariableReg( varmap, vals[ t + 5 ].strValue ) );
                        }

                        break;
                    }
                    else
                    {
label_no_array_eq_optimization:

                        GenerateOptimizedExpression( fp, varmap, t, vals );

                        if ( Token::COMMA == vals[ t ].token )
                        {
                            Variable * pvar = FindVariable( varmap, vals[ variableToken ].strValue );

                            if ( 2 != pvar->dimensions )
                                RuntimeFail( "using a variable as if it has 2 dimensions.", g_lineno );

                            t++; // comma

                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    push     rax\n" );
                            else if ( arm64Mac == g_AssemblyTarget )
                                fprintf( fp, "    str      x0, [sp, #-16]!\n" );
                            else if ( i8080CPM == g_AssemblyTarget )
                                fprintf( fp, "    push     h\n" );

                            GenerateOptimizedExpression( fp, varmap, t, vals );

                            if ( x64Win == g_AssemblyTarget )
                            {
                                fprintf( fp, "    pop      rbx\n" );
                                fprintf( fp, "    imul     rbx, %d\n", pvar->dims[ 1 ] );
                                fprintf( fp, "    add      rax, rbx\n" );
                            }
                            else if ( arm64Mac == g_AssemblyTarget )
                            {
                                fprintf( fp, "    ldr      x1, [sp], #16\n" );
                                LoadArm64Constant( fp, "x2", pvar->dims[ 1 ] );
                                fprintf( fp, "    mul      w1, w1, w2\n" );
                                fprintf( fp, "    add      w0, w0, w1\n" );
                            }
                            else if ( i8080CPM == g_AssemblyTarget )
                            {
                                fprintf( fp, "    pop      d\n" );
                                fprintf( fp, "    push     h\n" );
                                fprintf( fp, "    lxi      h, %d\n", pvar->dims[ 1 ] );
                                fprintf( fp, "    call     imul\n" );
                                fprintf( fp, "    pop      d\n" );
                                fprintf( fp, "    dad      d\n" );
                            }
                        }
        
                        t += 2; // ) =

                        string const & varname = vals[ variableToken ].strValue;
        
                        if ( x64Win == g_AssemblyTarget )
                        {
                            fprintf( fp, "    shl      rax, 2\n" );
                            fprintf( fp, "    lea      rbx, [%s]\n", GenVariableName( varname ) );
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            fprintf( fp, "    lsl      x0, x0, 2\n" );
                            LoadArm64Address( fp, "x1", varmap, varname );
                            fprintf( fp, "    add      x1, x1, x0\n" );
                        }
                        else if ( i8080CPM == g_AssemblyTarget )
                        {
                            fprintf( fp, "    dad      h\n" );
                            fprintf( fp, "    lxi      d, %s\n", GenVariableName( varname ) );
                            fprintf( fp, "    dad      d\n" );
                            fprintf( fp, "    xchg\n" );
                        }

                        assert( Token::EXPRESSION == vals[ t ].token );
    
                        if ( Token::CONSTANT == vals[ t + 1 ].token && 2 == vals[ t ].value )
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    mov      DWORD PTR [rbx + rax], %d\n", vals[ t + 1 ].value );
                            else if ( arm64Mac == g_AssemblyTarget )
                            {
                                LoadArm64Constant( fp, "x0", vals[ t + 1 ].value );
                                fprintf( fp, "    str      w0, [x1]\n" );
                            }
                            else if ( i8080CPM == g_AssemblyTarget )
                            {
                                fprintf( fp, "    mvi      a, %d\n", ( vals[ t + 1 ].value ) & 0xff );
                                fprintf( fp, "    stax     d\n" );
                                fprintf( fp, "    inx      d\n" );
                                if ( 0 != vals[ t + 1 ].value )
                                    fprintf( fp, "    mvi      a, %d\n", ( ( vals[ t + 1 ].value ) >> 8 ) & 0xff );
                                fprintf( fp, "    stax     d\n" );
                            }

                            t += 2;
                        }
                        else if ( Token::VARIABLE == vals[ t + 1 ].token && 2 == vals[ t ].value &&
                                  IsVariableInReg( varmap, vals[ t + 1 ].strValue ) )
                        {
                            string & varname = vals[ t + 1 ].strValue;

                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    mov      DWORD PTR [rbx + rax], %s\n", GenVariableReg( varmap, varname ) );
                            else if ( arm64Mac == g_AssemblyTarget )
                                fprintf( fp, "    str      %s, [x1]\n", GenVariableReg( varmap, varname ) );

                            t += 2;
                        }
                        else
                        {
                            if ( x64Win == g_AssemblyTarget )
                            {
                                fprintf( fp, "    add      rbx, rax\n" );
                                fprintf( fp, "    push     rbx\n" );
                            }
                            else if ( arm64Mac == g_AssemblyTarget )
                                fprintf( fp, "    str      x1, [sp, #-16]!\n" );
                            else if ( i8080CPM == g_AssemblyTarget )
                                fprintf( fp, "    push     d\n" );
                            
                            GenerateOptimizedExpression( fp, varmap, t, vals );
                            
                            if ( x64Win == g_AssemblyTarget )
                            {
                                fprintf( fp, "    pop      rbx\n" );
                                fprintf( fp, "    mov      DWORD PTR [rbx], eax\n" );
                            }
                            else if ( arm64Mac == g_AssemblyTarget )
                            {
                                fprintf( fp, "    ldr      x1, [sp], #16\n" );
                                fprintf( fp, "    str      w0, [x1]\n" );
                            }
                            else if ( i8080CPM == g_AssemblyTarget )
                            {
                                fprintf( fp, "    pop      d\n" );
                                fprintf( fp, "    mov      a, l\n" );
                                fprintf( fp, "    stax     d\n" );
                                fprintf( fp, "    inx      d\n" );
                                fprintf( fp, "    mov      a, h\n" );
                                fprintf( fp, "    stax     d\n" );
                            }
                        }
                    }
                }

                if ( t == vals.size() )
                    break;
            }
            else if ( Token::END == token )
            {
                if ( x64Win == g_AssemblyTarget )
                    fprintf( fp, "    jmp      end_execution\n" );
                else if ( arm64Mac == g_AssemblyTarget )
                    fprintf( fp, "    bl       end_execution\n" );
                else if ( i8080CPM == g_AssemblyTarget )
                    fprintf( fp, "    jmp      endExecution\n" );
                break;
            }
            else if ( Token::FOR == token )
            {
                string const & varname = vals[ t ].strValue;

                if ( x64Win == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, varname ) )
                        fprintf( fp, "    mov      %s, %d\n", GenVariableReg( varmap, varname ), vals[ t + 2 ].value );
                    else
                        fprintf( fp, "    mov      [%s], %d\n", GenVariableName( varname ), vals[ t + 2 ].value );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, varname ) )
                        fprintf( fp, "    mov      %s, %d\n", GenVariableReg( varmap, varname ), vals[ t + 2 ].value );
                    else
                    {
                        LoadArm64Address( fp, "x0", varname );
                        fprintf( fp, "    mov      w1, %d\n", vals[ t + 2 ].value );
                        fprintf( fp, "    str      w1, [x0]\n" );
                    }
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    fprintf( fp, "    lxi      h, %d\n", vals[ t + 2 ].value );
                    fprintf( fp, "    shld     %s\n", GenVariableName( varname ) );
                    
                }

                ForGosubItem item( true, (int) l );
                forGosubStack.push( item );
    
                if ( arm64Mac == g_AssemblyTarget )
                    fprintf( fp, ".p2align 2\n" );

                if ( i8080CPM == g_AssemblyTarget )
                    fprintf( fp, "  fl$%zd:\n", l ); // fl = for loop
                else
                    fprintf( fp, "  for_loop_%zd:\n", l );

                if ( x64Win == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, varname ) )
                        fprintf( fp, "    cmp      %s, %d\n", GenVariableReg( varmap, varname ), vals[ t + 4 ].value );
                    else
                        fprintf( fp, "    cmp      [%s], %d\n", GenVariableName( varname ), vals[ t + 4 ].value );

                    fprintf( fp, "    jg       after_for_loop_%zd\n", l );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, varname ) )
                    {
                        LoadArm64Constant( fp, "x0", vals[ t + 4 ].value );
                        fprintf( fp, "    cmp      %s, w0\n", GenVariableReg( varmap, varname ) );
                    }
                    else
                    {
                        LoadArm64Address( fp, "x0", varname );
                        fprintf( fp, "    ldr      w1, [x0]\n" );
                        LoadArm64Constant( fp, "x3", vals[ t + 4 ].value );
                        fprintf( fp, "    cmp      x1, x3\n" );
                    }

                    fprintf( fp, "    b.gt       after_for_loop_%zd\n", l );
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    // load 1 + the target due to no good 8080 instruction for jump if > 0

                    fprintf( fp, "    lxi      d, %d\n", 1 + vals[ t + 4 ].value );

                    fprintf( fp, "    mov      a, h\n" );
                    fprintf( fp, "    cmp      d\n" );
                    fprintf( fp, "    jz       flb$%zd\n", l );  // flb = for lower byte
                    fprintf( fp, "    jp       af$%zd\n", l );
                    fprintf( fp, "    jm       fc$%zd\n", l ); // fc == for code

                    fprintf( fp, "  flb$%zd:\n", l );
                    fprintf( fp, "    mov      a, l\n" );
                    fprintf( fp, "    cmp      e\n" );
                    fprintf( fp, "    jp       af$%zd\n", l ); // af == after for

                    fprintf( fp, "  fc$%zd:\n", l );
                }

                break;
            }
            else if ( Token::NEXT == token )
            {
                if ( 0 == forGosubStack.size() )
                    RuntimeFail( "next without for", l );
    
                ForGosubItem & item = forGosubStack.top();
                string const & loopVal = g_linesOfCode[ item.pcReturn ].tokenValues[ 0 ].strValue;

                if ( loopVal.compare( vals[ t ].strValue ) )
                    RuntimeFail( "NEXT statement variable doesn't match current FOR loop variable", l );

                if ( x64Win == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, loopVal ) )
                        fprintf( fp, "    inc      %s\n", GenVariableReg( varmap, loopVal ) );
                    else
                        fprintf( fp, "    inc      [%s]\n", GenVariableName( loopVal ) );

                    fprintf( fp, "    jmp      for_loop_%d\n", item.pcReturn );
                    fprintf( fp, "    align    16\n" );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, loopVal ) )
                        fprintf( fp, "    add      %s, %s, 1\n", GenVariableReg( varmap, loopVal ),
                                                                 GenVariableReg( varmap, loopVal ) );
                    else
                    {
                        LoadArm64Address( fp, "x0", loopVal );
                        fprintf( fp, "    ldr      w1, [x0]\n" );
                        fprintf( fp, "    add      x1, x1, 1\n" );
                        fprintf( fp, "    str      w1, [x0]\n" );
                    }

                    fprintf( fp, "    bl       for_loop_%d\n", item.pcReturn );
                    fprintf( fp, "    .p2align 2\n" );
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    fprintf( fp, "    lhld     %s\n", GenVariableName( loopVal ) );
                    fprintf( fp, "    inx      h\n" );
                    fprintf( fp, "    shld     %s\n", GenVariableName( loopVal ) );
                    fprintf( fp, "    jmp      fl$%d\n", item.pcReturn ); // fl = for loop
                }

                if ( i8080CPM == g_AssemblyTarget )
                    fprintf( fp, "  af$%d:\n", item.pcReturn );
                else
                    fprintf( fp, "  after_for_loop_%d:\n", item.pcReturn );

                forGosubStack.pop();
                break;
            }
            else if ( Token::GOSUB == token )
            {
                // not worth the runtime check for return without gosub?
                //fprintf( fp, "    inc      [gosubCount]\n" );

                if ( x64Win == g_AssemblyTarget)
                    fprintf( fp, "    call     line_number_%d\n", vals[ t ].value );
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    fprintf( fp, "    adr      x0, line_number_%d\n", vals[ t ].value );
                    fprintf( fp, "    bl       label_gosub\n" );
                }
                else if ( i8080CPM == g_AssemblyTarget)
                    fprintf( fp, "    call     ln$%d\n", vals[ t ].value );

                break;
            }
            else if ( Token::GOTO == token )
            {
                if ( x64Win == g_AssemblyTarget)
                    fprintf( fp, "    jmp      line_number_%d\n", vals[ t ].value );
                else if (arm64Mac == g_AssemblyTarget )
                    fprintf( fp, "    bl       line_number_%d\n", vals[ t ].value );
                else if ( i8080CPM == g_AssemblyTarget )
                    fprintf( fp, "    jmp      ln$%d\n", vals[ t ].value );

                break;
            }
            else if ( Token::RETURN == token )
            {
                if ( x64Win == g_AssemblyTarget )
                    fprintf( fp, "    jmp      label_gosub_return\n" );
                else if ( arm64Mac == g_AssemblyTarget )
                    fprintf( fp, "    bl       label_gosub_return\n" );
                else if ( i8080CPM == g_AssemblyTarget )
                    fprintf( fp, "    jmp      gosubReturn\n" );
                break;
            }
            else if ( Token::PRINT == token )
            {
                t++;
    
                while ( t < vals.size() )
                {
                    if ( Token::SEMICOLON == vals[ t ].token )
                    {
                        t++;
                        continue;
                    }
                    else if ( Token::EXPRESSION != vals[ t ].token ) // likely ELSE
                        break;
    
                    assert( Token::EXPRESSION == vals[ t ].token );
    
                    if ( Token::STRING == vals[ t + 1 ].token )
                    {
                        if ( x64Win == g_AssemblyTarget )
                        {
                            fprintf( fp, "    lea      rcx, [strString]\n" );
                            fprintf( fp, "    lea      rdx, [str_%zd_%d]\n", l, t + 1 );
                            fprintf( fp, "    call     call_printf\n" );
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            fprintf( fp, "    adrp     x0, strString@PAGE\n" );
                            fprintf( fp, "    add      x0, x0, strString@PAGEOFF\n" );
                            fprintf( fp, "    adrp     x1, str_%zd_%d@PAGE\n", l, t + 1 );
                            fprintf( fp, "    add      x1, x1, str_%zd_%d@PAGEOFF\n", l, t + 1 );
                            fprintf( fp, "    bl       call_printf\n" );
                        }
                        else if ( i8080CPM == g_AssemblyTarget )
                        {
                            fprintf( fp, "    mvi      c, PRSTR\n" );
                            fprintf( fp, "    lxi      d, s$%zd$%d\n", l, t + 1 );
                            fprintf( fp, "    call     BDOS\n" );
                        }

                        t += vals[ t ].value;
                    }
                    else if ( Token::TIME == vals[ t + 1 ].token )
                    {
                        // HH:MM:SS

                        if ( x64Win == g_AssemblyTarget )
                        {
                            fprintf( fp, "    lea      rcx, [currentTime]\n" );
                            fprintf( fp, "    call     call_GetLocalTime\n" );
                            fprintf( fp, "    lea      rax, [currentTime]\n" );

                            fprintf( fp, "    push     r9\n" ); // r9 may be assigned to a variable; save it
                            fprintf( fp, "    lea      rcx, [timeString]\n" );
                            fprintf( fp, "    movzx    rdx, WORD PTR [currentTime + 8]\n" );
                            fprintf( fp, "    movzx    r8, WORD PTR [currentTime + 10]\n" );
                            fprintf( fp, "    movzx    r9, WORD PTR [currentTime + 12]\n" );
                            fprintf( fp, "    call     call_printf\n" );
                            fprintf( fp, "    pop      r9\n" );
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            // lots of arguments, so call _printf directly

                            fprintf( fp, "    save_volatile_registers\n" );
                            fprintf( fp, "    adrp     x0, rawTime@PAGE\n" );
                            fprintf( fp, "    add      x0, x0, rawTime@PAGEOFF\n" );
                            fprintf( fp, "    bl       _time\n" );
                            fprintf( fp, "    adrp     x0, rawTime@PAGE\n" );
                            fprintf( fp, "    add      x0, x0, rawTime@PAGEOFF\n" );
                            fprintf( fp, "    bl       _localtime\n" );
                            fprintf( fp, "    ldp      w9, w8, [ x0, #4 ]\n" );
                            fprintf( fp, "    ldr      w10, [x0]\n" );
                            fprintf( fp, "    stp      x9, x10, [ sp, #8 ]\n" );
                            fprintf( fp, "    str      x8, [sp]\n" );
                            fprintf( fp, "    adrp     x0, timeString@PAGE\n" );
                            fprintf( fp, "    add      x0, x0, timeString@PAGEOFF\n" );
                            fprintf( fp, "    bl       _printf\n" );
                            fprintf( fp, "    restore_volatile_registers\n" );
                        }

                        t += vals[ t ].value;
                    }
                    else if ( Token::ELAP == vals[ t + 1 ].token )
                    {
                        if ( x64Win == g_AssemblyTarget )
                        {
                            fprintf( fp, "    lea      rcx, [currentTicks]\n" );
                            fprintf( fp, "    call     call_QueryPerformanceCounter\n" );
                            fprintf( fp, "    mov      rax, [currentTicks]\n" );
                            fprintf( fp, "    sub      rax, [startTicks]\n" );
                            fprintf( fp, "    mov      rcx, [perfFrequency]\n" );
                            fprintf( fp, "    xor      rdx, rdx\n" );
                            fprintf( fp, "    mov      rbx, 1000000\n" );
                            fprintf( fp, "    mul      rbx\n" );
                            fprintf( fp, "    div      rcx\n" );

                            fprintf( fp, "    lea      rcx, [elapString]\n" );
                            fprintf( fp, "    mov      rdx, rax\n" );
                            fprintf( fp, "    call     call_printf\n" );
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            fprintf( fp, "    adrp     x3, startTicks@PAGE\n" );
                            fprintf( fp, "    add      x3, x3, startTicks@PAGEOFF\n" );
                            fprintf( fp, "    ldr      x0, [x3]\n" );
                            fprintf( fp, "    mrs      x1, cntvct_el0\n" ); //current time
                            fprintf( fp, "    sub      x1, x1, x0\n" ); // elapsed time
                            fprintf( fp, "    ldr      x4, =%#x\n", 1000000 ); // scale before divide
                            fprintf( fp, "    mul      x1, x1, x4\n" );

                            fprintf( fp, "    mrs      x2, cntfrq_el0\n" ); // frequency
                            fprintf( fp, "    udiv     x1, x1, x2\n" );
                            
                            fprintf( fp, "    adrp     x0, elapString@PAGE\n" );
                            fprintf( fp, "    add      x0, x0, elapString@PAGEOFF\n" );
                            fprintf( fp, "    bl       call_printf\n" );
                        }

                        t += vals[ t ].value;
                    }
                    else if ( Token::CONSTANT == vals[ t + 1 ].token ||
                              Token::VARIABLE == vals[ t + 1 ].token )
                    {
                        assert( Token::EXPRESSION == vals[ t ].token );
                        GenerateOptimizedExpression( fp, varmap, t, vals );

                        if ( x64Win == g_AssemblyTarget )
                        {
                            fprintf( fp, "    lea      rcx, [intString]\n" );
                            fprintf( fp, "    mov      rdx, rax\n" );
                            fprintf( fp, "    call     call_printf\n" );
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            fprintf( fp, "    mov      x1, x0\n" );
                            fprintf( fp, "    adrp     x0, intString@PAGE\n" );
                            fprintf( fp, "    add      x0, x0, intString@PAGEOFF\n" );
                            fprintf( fp, "    bl       call_printf\n" );
                        }
                        else if ( i8080CPM == g_AssemblyTarget )
                        {
                            fprintf( fp, "    call     puthl\n" );
                        }
                    }
                }
    
                if ( x64Win == g_AssemblyTarget )
                {
                    fprintf( fp, "    lea      rcx, [newlineString]\n" );
                    fprintf( fp, "    call     call_printf\n" );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    fprintf( fp, "    adrp     x0, newlineString@PAGE\n" );
                    fprintf( fp, "    add      x0, x0, newlineString@PAGEOFF\n" );
                    fprintf( fp, "    bl       call_printf\n" );
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                     fprintf( fp, "    mvi      c, PRSTR\n" );
                     fprintf( fp, "    lxi      d, newlineString\n" );
                     fprintf( fp, "    call     BDOS\n" );
                }

                if ( t == vals.size() )
                    break;
            }
            else if ( Token::ATOMIC == token )
            {
                string & varname = vals[ t + 1 ].strValue;

                if ( x64Win == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, varname ) )
                    {
                        if ( Token::INC == vals[ t + 1 ].token )
                            fprintf( fp, "    inc      %s\n", GenVariableReg( varmap, varname ) );
                        else
                            fprintf( fp, "    dec      %s\n", GenVariableReg( varmap, varname ) );
                    }
                    else
                    {
                        if ( Token::INC == vals[ t + 1 ].token )
                            fprintf( fp, "    inc      DWORD PTR [%s]\n", GenVariableName( varname ) );
                        else
                            fprintf( fp, "    dec      DWORD PTR [%s]\n", GenVariableName( varname ) );
                    }
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    if ( IsVariableInReg( varmap, varname ) )
                    {
                        if ( Token::INC == vals[ t + 1 ].token )
                            fprintf( fp, "    add      %s, %s, 1\n", GenVariableReg( varmap, varname ),
                                                                     GenVariableReg( varmap, varname ) );
                        else
                            fprintf( fp, "    sub      %s, %s, 1\n", GenVariableReg( varmap, varname ),
                                                                     GenVariableReg( varmap, varname ) );
                    }
                    else
                    {
                        LoadArm64Address( fp, "x0", varname );
                        fprintf( fp, "    ldr      w1, [x0]\n" );
                        if ( Token::INC == vals[ t + 1 ].token )
                            fprintf( fp, "    add      x1, x1, 1\n" );
                        else
                            fprintf( fp, "    sub      x1, x1, 1\n" );
                        fprintf( fp, "    str      w1, [x0]\n" );

                    }
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    fprintf( fp, "    lhld     %s\n", GenVariableName( varname ) );

                    if ( Token::INC == vals[ t + 1 ].token )
                        fprintf( fp, "    inx      h\n" );
                    else
                        fprintf( fp, "    dcx      h\n" );

                    fprintf( fp, "    shld     %s\n", GenVariableName( varname ) );
                }
                break;
            }
            else if ( Token::IF == token )
            {
                activeIf = l;
    
                t++;
                assert( Token::EXPRESSION == vals[ t ].token );

                if ( !g_ExpressionOptimization )
                    goto label_no_if_optimization;

                // Optimize for really simple IF cases like "IF var/constant relational var/constant"

                if ( i8080CPM == g_AssemblyTarget &&
                     19 == vals.size() &&
                     16 == vals[ t ].value &&
                     Token::VARIABLE == vals[ t + 1 ].token &&
                     Token::EQ ==  vals[ t + 2 ].token &&
                     Token::OPENPAREN == vals[ t + 4 ].token &&
                     Token::CONSTANT == vals[ t + 6 ].token &&
                     Token::AND == vals[ t + 8 ].token &&
                     Token::VARIABLE == vals[ t + 9 ].token &&
                     Token::EQ == vals[ t + 10 ].token &&
                     Token::OPENPAREN == vals[ t + 12 ].token &&
                     Token::CONSTANT == vals[ t + 14 ].token &&
                     Token::THEN == vals[ t + 16 ].token &&
                     0 == vals[ t + 16 ].value &&
                     !vals[ t + 3 ].strValue.compare( vals[ t + 11 ].strValue ) &&
                     Token::RETURN == vals[ t + 17 ].token )
                {
                    // line 2020 has 19 tokens  ====>> 2020 if wi% = b%( 1 ) and wi% = b%( 2 ) then return
                    //    0 IF, value 0, strValue ''
                    //    1 EXPRESSION, value 16, strValue ''
                    //    2 VARIABLE, value 0, strValue 'wi%'
                    //    3 EQ, value 0, strValue ''
                    //    4 VARIABLE, value 0, strValue 'b%'
                    //    5 OPENPAREN, value 0, strValue ''
                    //    6 EXPRESSION, value 2, strValue ''
                    //    7 CONSTANT, value 1, strValue ''
                    //    8 CLOSEPAREN, value 0, strValue ''
                    //    9 AND, value 0, strValue ''
                    //   10 VARIABLE, value 0, strValue 'wi%'
                    //   11 EQ, value 0, strValue ''
                    //   12 VARIABLE, value 0, strValue 'b%'
                    //   13 OPENPAREN, value 0, strValue ''
                    //   14 EXPRESSION, value 2, strValue ''
                    //   15 CONSTANT, value 2, strValue ''
                    //   16 CLOSEPAREN, value 0, strValue ''
                    //   17 THEN, value 0, strValue ''
                    //   18 RETURN, value 0, strValue ''

                    fprintf( fp, "    lhld     %s\n", GenVariableName( vals[ t + 1 ].strValue ) );
                    fprintf( fp, "    xchg\n" );
                    fprintf( fp, "    lxi      h, %s\n", GenVariableName( vals[ t + 3 ].strValue ) );
                    fprintf( fp, "    lxi      b, %d\n", 2 * vals[ t + 6 ].value );
                    fprintf( fp, "    dad      b\n" );
                    fprintf( fp, "    mov      a, m\n" );
                    fprintf( fp, "    cmp      e\n" );
                    fprintf( fp, "    jnz      ln$%zd\n", l + 1 );
                    fprintf( fp, "    inx      h\n" );
                    fprintf( fp, "    mov      a, m\n" );
                    fprintf( fp, "    cmp      d\n" );
                    fprintf( fp, "    jnz      ln$%zd\n", l + 1 );

                    fprintf( fp, "    lxi      h, %s\n", GenVariableName( vals[ t + 3 ].strValue ) );
                    fprintf( fp, "    lxi      b, %d\n", 2 * vals[ t + 14 ].value );
                    fprintf( fp, "    dad      b\n" );
                    fprintf( fp, "    mov      a, m\n" );
                    fprintf( fp, "    cmp      e\n" );
                    fprintf( fp, "    jnz      ln$%zd\n", l + 1 );
                    fprintf( fp, "    inx      h\n" );
                    fprintf( fp, "    mov      a, m\n" );
                    fprintf( fp, "    cmp      d\n" );
                    fprintf( fp, "    jz       gosubReturn\n" );

                    break;
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          10 == vals.size() &&
                          4 == vals[ t ].value &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                          isOperatorRelational( vals[ t + 2 ].token ) &&
                          Token::VARIABLE == vals[ t + 3 ].token &&
                          IsVariableInReg( varmap, vals[ t + 3 ].strValue ) &&
                          Token::THEN == vals[ t + 4 ].token &&
                          0 == vals[ t + 4 ].value &&
                          Token::VARIABLE == vals[ t + 5 ].token &&
                          IsVariableInReg( varmap, vals[ t + 5 ].strValue ) &&
                          Token::EQ == vals[ t + 6 ].token &&
                          Token::EXPRESSION == vals[ t + 7 ].token &&
                          2 == vals[ t + 7 ].value &&
                          Token::VARIABLE == vals[ t + 8 ].token &&
                          IsVariableInReg( varmap, vals[ t + 8 ].strValue ) )
                {
                    // line 4342 has 10 tokens  ====>> 4342 if v% > al% then al% = v%
                    //   0 IF, value 0, strValue ''
                    //   1 EXPRESSION, value 4, strValue ''
                    //   2 VARIABLE, value 0, strValue 'v%'
                    //   3 GT, value 0, strValue ''
                    //   4 VARIABLE, value 0, strValue 'al%'
                    //   5 THEN, value 0, strValue ''
                    //   6 VARIABLE, value 0, strValue 'al%'
                    //   7 EQ, value 0, strValue ''
                    //   8 EXPRESSION, value 2, strValue ''
                    //   9 VARIABLE, value 0, strValue 'v%'

                    if ( x64Win == g_AssemblyTarget )
                    {
                        fprintf( fp, "    cmp      %s, %s\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ),
                                                              GenVariableReg( varmap, vals[ t + 3 ].strValue ) );

                        fprintf( fp, "    %-6s   %s, %s\n", CMovInstruction[ vals[ t + 2 ].token ],
                                GenVariableReg( varmap, vals[ t + 5 ].strValue ),
                                GenVariableReg( varmap, vals[ t + 8 ].strValue ) );
                    }
                    else if ( arm64Mac == g_AssemblyTarget )
                    {
                        fprintf( fp, "    cmp      %s, %s\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ),
                                                              GenVariableReg( varmap, vals[ t + 3 ].strValue ) );
                        fprintf( fp, "    csel     %s, %s, %s, %s\n", GenVariableReg( varmap, vals[ t + 5 ].strValue ),
                                                                      GenVariableReg( varmap, vals[ t + 8 ].strValue ),
                                                                      GenVariableReg( varmap, vals[ t + 5 ].strValue ),
                                                                      ConditionsArm64[ vals[ t + 2 ].token ] );
                    }
                    break;
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          19 == vals.size() &&
                          16 == vals[ t ].value &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                          isOperatorRelational( vals[ t + 2 ].token ) &&
                          Token::OPENPAREN == vals[ t + 4 ].token &&
                          Token::CONSTANT == vals[ t + 6 ].token &&
                          Token::AND == vals[ t + 8 ].token &&
                          Token::VARIABLE == vals[ t + 9 ].token &&
                          IsVariableInReg( varmap, vals[ t + 9 ].strValue ) &&
                          isOperatorRelational( vals[ t + 10 ].token ) &&
                          Token::OPENPAREN == vals[ t + 12 ].token &&
                          Token::CONSTANT == vals[ t + 14 ].token &&
                          Token::THEN == vals[ t + 16 ].token &&
                          0 == vals[ t + 16 ].value &&
                          !vals[ t + 3 ].strValue.compare( vals[ t + 11 ].strValue ) &&
                          Token::RETURN == vals[ t + 17 ].token )
                {
                    // line 2020 has 19 tokens  ====>> 2020 if wi% = b%( 1 ) and wi% = b%( 2 ) then return
                    //    0 IF, value 0, strValue ''
                    //    1 EXPRESSION, value 16, strValue ''
                    //    2 VARIABLE, value 0, strValue 'wi%'
                    //    3 EQ, value 0, strValue ''
                    //    4 VARIABLE, value 0, strValue 'b%'
                    //    5 OPENPAREN, value 0, strValue ''
                    //    6 EXPRESSION, value 2, strValue ''
                    //    7 CONSTANT, value 1, strValue ''
                    //    8 CLOSEPAREN, value 0, strValue ''
                    //    9 AND, value 0, strValue ''
                    //   10 VARIABLE, value 0, strValue 'wi%'
                    //   11 EQ, value 0, strValue ''
                    //   12 VARIABLE, value 0, strValue 'b%'
                    //   13 OPENPAREN, value 0, strValue ''
                    //   14 EXPRESSION, value 2, strValue ''
                    //   15 CONSTANT, value 2, strValue ''
                    //   16 CLOSEPAREN, value 0, strValue ''
                    //   17 THEN, value 0, strValue ''
                    //   18 RETURN, value 0, strValue ''

                    if ( x64Win == g_AssemblyTarget )
                    {
                        fprintf( fp, "    cmp      %s, DWORD PTR [ %s + %d ]\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ),
                                                                                 GenVariableName( vals[ t + 3 ].strValue ),
                                                                                 4 * vals[ t + 6 ].value );
                        fprintf( fp, "    %-6s   SHORT line_number_%zd\n", RelationalNotInstruction[ vals[ t + 2 ].token ], l + 1 );

                        fprintf( fp, "    cmp      %s, DWORD PTR [ %s + %d ]\n", GenVariableReg( varmap, vals[ t + 9 ].strValue ),
                                                                                 GenVariableName( vals[ t + 11 ].strValue ),
                                                                                 4 * vals[ t + 14 ].value );
                        fprintf( fp, "    %-6s   label_gosub_return\n", RelationalInstruction[ vals[ t + 10 ].token ] );
                    }
                    else if ( arm64Mac == g_AssemblyTarget )
                    {
                        int offsetA = 4 * vals[ t + 6 ].value;
                        int offsetB = 4 * vals[ t + 14 ].value;
                        string & vararray = vals[ t + 3 ].strValue;
                     
                        if ( IsVariableInReg( varmap, vararray ) && fitsIn8Bits( offsetA ) && fitsIn8Bits( offsetB ) )
                        {
                            fprintf( fp, "    ldr      w0, [%s, %d]\n", GenVariableReg64( varmap, vararray ), offsetA );
                            fprintf( fp, "    cmp      %s, w0\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                            fprintf( fp, "    b.%s     line_number_%zd\n", ConditionsNotArm64[ vals[ t + 2 ].token ], l + 1 );
                            fprintf( fp, "    ldr      w0, [%s, %d]\n", GenVariableReg64( varmap, vararray ), offsetB );
                        }
                        else
                        {
                            LoadArm64Address( fp, "x2", varmap, vals[ t + 3 ].strValue );

                            if ( fitsIn8Bits( offsetA ) )
                            {
                                fprintf( fp, "    ldr      w0, [x2, %d]\n", offsetA );
                            }
                            else
                            {
                                if ( fitsIn12Bits( offsetA ) )
                                    fprintf( fp, "    add      x1, x2, %d\n", offsetA );
                                else
                                {
                                    LoadArm64Constant( fp, "x1", offsetA );
                                    fprintf( fp, "    add      x1, x1, x2\n" );
                                }

                                fprintf( fp, "    ldr      w0, [x1]\n" );
                            }

                            fprintf( fp, "    cmp      %s, w0\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                            fprintf( fp, "    b.%s     line_number_%zd\n", ConditionsNotArm64[ vals[ t + 2 ].token ], l + 1 );

                            if ( fitsIn8Bits( offsetB ) )
                            {
                                fprintf( fp, "    ldr      w0, [x2, %d]\n", offsetB );
                            }
                            else
                            {
                                if ( fitsIn12Bits( offsetB ) )
                                    fprintf( fp, "    add      x1, x2, %d\n", offsetB );
                                else
                                {
                                    LoadArm64Constant( fp, "x1", offsetB );
                                    fprintf( fp, "    add      x1, x1, x2\n" );
                                }

                                fprintf( fp, "    ldr      w0, [x1]\n" );
                            }
                        }

                        fprintf( fp, "    cmp      %s, w0\n", GenVariableReg( varmap, vals[ t + 9 ].strValue ) );
                        fprintf( fp, "    b.%s     label_gosub_return\n", ConditionsArm64[ vals[ t + 10 ].token ] );
                    }
                    break;
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          15 == vals.size() &&
                          4 == vals[ t ].value &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                          Token::AND == vals[ t + 2 ].token  &&
                          Token::CONSTANT == vals[ t + 3 ].token &&
                          1 == vals[ t + 3 ].value &&
                          Token::THEN == vals[ t + 4 ].token &&
                          Token::VARIABLE == vals[ t + 5 ].token &&
                          IsVariableInReg( varmap, vals[ t + 5 ].strValue ) &&
                          Token::EQ == vals[ t + 6 ].token &&
                          2 == vals[ t + 7 ].value &&
                          Token::CONSTANT == vals[ t + 8 ].token &&
                          Token::ELSE == vals[ t + 9 ].token &&
                          Token::VARIABLE == vals[ t + 10 ].token &&
                          IsVariableInReg( varmap, vals[ t + 10 ].strValue ) &&
                          Token::EQ == vals[ t + 11 ].token &&
                          2 == vals[ t + 12 ].value &&
                          !vals[ t + 5 ].strValue.compare( vals[ t + 10 ].strValue ) &&
                          Token::CONSTANT == vals[ t + 13 ].token )
                {
                    // line 4150 has 15 tokens  ====>> 4150 if st% and 1 then v% = 2 else v% = 9
                    // token   0 IF, value 0, strValue ''
                    // token   1 EXPRESSION, value 4, strValue ''
                    // token   2 VARIABLE, value 0, strValue 'st%'
                    // token   3 AND, value 0, strValue ''
                    // token   4 CONSTANT, value 1, strValue ''
                    // token   5 THEN, value 5, strValue ''
                    // token   6 VARIABLE, value 0, strValue 'v%'
                    // token   7 EQ, value 0, strValue ''
                    // token   8 EXPRESSION, value 2, strValue ''
                    // token   9 CONSTANT, value 2, strValue ''
                    // token  10 ELSE, value 0, strValue ''
                    // token  11 VARIABLE, value 0, strValue 'v%'
                    // token  12 EQ, value 0, strValue ''
                    // token  13 EXPRESSION, value 2, strValue ''
                    // token  14 CONSTANT, value 9, strValue ''

                    if ( x64Win == g_AssemblyTarget )
                    {
                        fprintf( fp, "    mov      %s, %d\n", GenVariableReg( varmap, vals[ t + 5 ].strValue ) , vals[ t + 13 ].value );
                        fprintf( fp, "    mov      eax, %d\n", vals[ t + 8 ].value );
                        fprintf( fp, "    test     %s, 1\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                        fprintf( fp, "    cmovnz   %s, eax\n", GenVariableReg( varmap, vals[ t + 5 ].strValue ) );
                    }
                    else if ( arm64Mac == g_AssemblyTarget )
                    {
                        LoadArm64Constant( fp, "x0", vals[ t + 8 ].value );
                        LoadArm64Constant( fp, "x1", vals[ t + 13 ].value );
                        fprintf( fp, "    tst      %s, 1\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                        fprintf( fp, "    csel     %s, w0, w1, ne\n", GenVariableReg( varmap, vals[ t + 5 ].strValue ) );
                    }

                    break;
                }
                else if ( i8080CPM == g_AssemblyTarget &&
                          15 == vals.size() &&
                          4 == vals[ t ].value &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          Token::AND == vals[ t + 2 ].token  &&
                          Token::CONSTANT == vals[ t + 3 ].token &&
                          1 == vals[ t + 3 ].value &&
                          Token::THEN == vals[ t + 4 ].token &&
                          Token::VARIABLE == vals[ t + 5 ].token &&
                          Token::EQ == vals[ t + 6 ].token &&
                          2 == vals[ t + 7 ].value &&
                          Token::CONSTANT == vals[ t + 8 ].token &&
                          Token::ELSE == vals[ t + 9 ].token &&
                          Token::VARIABLE == vals[ t + 10 ].token &&
                          Token::EQ == vals[ t + 11 ].token &&
                          2 == vals[ t + 12 ].value &&
                          !vals[ t + 5 ].strValue.compare( vals[ t + 10 ].strValue ) &&
                          Token::CONSTANT == vals[ t + 13 ].token )
                {
                    // line 4150 has 15 tokens  ====>> 4150 if st% and 1 then v% = 2 else v% = 9
                    // token   0 IF, value 0, strValue ''
                    // token   1 EXPRESSION, value 4, strValue ''
                    // token   2 VARIABLE, value 0, strValue 'st%'
                    // token   3 AND, value 0, strValue ''
                    // token   4 CONSTANT, value 1, strValue ''
                    // token   5 THEN, value 5, strValue ''
                    // token   6 VARIABLE, value 0, strValue 'v%'
                    // token   7 EQ, value 0, strValue ''
                    // token   8 EXPRESSION, value 2, strValue ''
                    // token   9 CONSTANT, value 2, strValue ''
                    // token  10 ELSE, value 0, strValue ''
                    // token  11 VARIABLE, value 0, strValue 'v%'
                    // token  12 EQ, value 0, strValue ''
                    // token  13 EXPRESSION, value 2, strValue ''
                    // token  14 CONSTANT, value 9, strValue ''


                    fprintf( fp, "    lda      %s\n", GenVariableName( vals[ t + 1 ].strValue ) );
                    fprintf( fp, "    ani      %d\n", vals[ t + 3 ].value );
                    fprintf( fp, "    jz       uniq%d\n", s_uniqueLabel );
                    fprintf( fp, "    lxi      h, %d\n", vals[ t + 8 ].value );
                    fprintf( fp, "    jmp      uniq%d\n", s_uniqueLabel + 1 );

                    fprintf( fp, "  uniq%d:\n", s_uniqueLabel );
                    fprintf( fp, "    lxi      h, %d\n", vals[ t + 13 ].value );
                    s_uniqueLabel++;
                    fprintf( fp, "  uniq%d:\n", s_uniqueLabel );
                    fprintf( fp, "    shld     %s\n", GenVariableName( vals[ t + 10 ].strValue ) );

                    s_uniqueLabel++;

                    break;
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          23 == vals.size() &&
                          4 == vals[ t ].value &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                          Token::AND == vals[ t + 2 ].token  &&
                          Token::CONSTANT == vals[ t + 3 ].token &&
                          1 == vals[ t + 3 ].value &&
                          Token::THEN == vals[ t + 4 ].token &&
                          Token::OPENPAREN == vals[ t + 6 ].token &&
                          Token::CONSTANT == vals[ t + 12 ].token &&
                          Token::OPENPAREN == vals[ t + 15 ].token &&
                          Token::CONSTANT == vals[ t + 21 ].token &&
                          Token::VARIABLE == vals[ t + 8 ].token &&
                          Token::VARIABLE == vals[ t + 17 ].token &&
                          IsVariableInReg( varmap, vals[ t + 17 ].strValue ) &&
                          !vals[ t + 5 ].strValue.compare( vals[ t + 14 ].strValue ) &&
                          !vals[ t + 8 ].strValue.compare( vals[ t + 17 ].strValue ) )
                {
                    // line 4200 has 23 tokens  ====>> 4200 if st% and 1 then b%(p%) = 1 else b%(p%) = 2
                    //     0 IF, value 0, strValue ''
                    //     1 EXPRESSION, value 4, strValue ''
                    //     2 VARIABLE, value 0, strValue 'st%'
                    //     3 AND, value 0, strValue ''
                    //     4 CONSTANT, value 1, strValue ''
                    //     5 THEN, value 9, strValue ''
                    //     6 VARIABLE, value 0, strValue 'b%'
                    //     7 OPENPAREN, value 0, strValue ''
                    //     8 EXPRESSION, value 2, strValue ''
                    //     9 VARIABLE, value 0, strValue 'p%'
                    //    10 CLOSEPAREN, value 0, strValue ''
                    //    11 EQ, value 0, strValue ''
                    //    12 EXPRESSION, value 2, strValue ''
                    //    13 CONSTANT, value 1, strValue ''
                    //    14 ELSE, value 0, strValue ''
                    //    15 VARIABLE, value 0, strValue 'b%'
                    //    16 OPENPAREN, value 0, strValue ''
                    //    17 EXPRESSION, value 2, strValue ''
                    //    18 VARIABLE, value 0, strValue 'p%'
                    //    19 CLOSEPAREN, value 0, strValue ''
                    //    20 EQ, value 0, strValue ''
                    //    21 EXPRESSION, value 2, strValue ''
                    //    22 CONSTANT, value 2, strValue ''

                    if ( x64Win == g_AssemblyTarget )
                    {
                        fprintf( fp, "    mov      ecx, %d\n", vals[ t + 21 ].value );
                        fprintf( fp, "    mov      r8d, %d\n", vals[ t + 12 ].value );
                        fprintf( fp, "    test     %s, 1\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                        fprintf( fp, "    cmovnz   ecx, r8d\n" );
                        fprintf( fp, "    lea      rax, %s\n", GenVariableName( vals[ t + 5 ].strValue ) );
                        fprintf( fp, "    mov      ebx, %s\n", GenVariableReg( varmap, vals[ t + 8 ].strValue ) );
                        fprintf( fp, "    shl      ebx, 2\n" );
                        fprintf( fp, "    mov      DWORD PTR [ rbx + rax ], ecx\n" );
                    }
                    else if ( arm64Mac == g_AssemblyTarget )
                    {
                        fprintf( fp, "    lsl      w4, %s, 2\n", GenVariableReg( varmap, vals[ t + 8 ].strValue ) );
                        
                        if ( IsVariableInReg( varmap, vals[ t + 5 ].strValue ) )
                            fprintf( fp, "    add      x3, %s, x4\n", GenVariableReg64( varmap, vals[ t + 5 ].strValue ) );
                        else
                        {
                            LoadArm64Address( fp, "x3", varmap, vals[ t + 5 ].strValue );
                            fprintf( fp, "    add      x3, x3, x4\n" );
                        }

                        LoadArm64Constant( fp, "x0", vals[ t + 12 ].value );
                        LoadArm64Constant( fp, "x1", vals[ t + 21 ].value );
                        fprintf( fp, "    tst      %s, 1\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                        fprintf( fp, "    csel     x4, x0, x1, ne\n" );
                        fprintf( fp, "    str      w4, [x3]\n" );
                    }
                    break;
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          11 == vals.size() &&
                          4 == vals[ t ].value &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                          isOperatorRelational( vals[ t + 2 ].token ) &&
                          Token::CONSTANT == vals[ t + 3 ].token &&
                          Token::THEN == vals[ t + 4 ].token &&
                          0 == vals[ t + 4 ].value &&
                          Token::VARIABLE == vals[ t + 5 ].token &&
                          IsVariableInReg( varmap, vals[ t + 5 ].strValue ) &&
                          Token::CONSTANT == vals[ t + 8 ].token &&
                          Token::GOTO == vals[ t + 9 ].token )
                {
                    // line 4110 has 11 tokens  ====>> 4110 if wi% = 1 then re% = 6: goto 4280
                    //    0 IF, value 0, strValue ''
                    //    1 EXPRESSION, value 4, strValue ''
                    //    2 VARIABLE, value 0, strValue 'wi%'
                    //    3 EQ, value 0, strValue ''
                    //    4 CONSTANT, value 1, strValue ''
                    //    5 THEN, value 0, strValue ''
                    //    6 VARIABLE, value 0, strValue 're%'
                    //    7 EQ, value 0, strValue ''
                    //    8 EXPRESSION, value 2, strValue ''
                    //    9 CONSTANT, value 6, strValue ''
                    //   10 GOTO, value 4280, strValue ''

                    if ( x64Win == g_AssemblyTarget )
                    {
                        fprintf( fp, "    mov      eax, %d\n", vals[ t + 8 ].value );
                        fprintf( fp, "    cmp      %s, %d\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ),
                                                              vals[ t + 3 ].value );
                        fprintf( fp, "    %-6s   %s, eax\n", CMovInstruction[ vals[ t + 2 ].token ],
                                                             GenVariableReg( varmap, vals[ t + 5 ].strValue ) );
                        fprintf( fp, "    %-6s   line_number_%d\n", RelationalInstruction[ vals[ t + 2 ].token ],
                                                                    vals[ t + 9 ].value );
                    }
                    else if ( arm64Mac == g_AssemblyTarget )
                    {
                        LoadArm64Constant( fp, "x1", vals[ t + 3 ].value );
                        LoadArm64Constant( fp, "x0", vals[ t + 8 ].value );
                        fprintf( fp, "    cmp      %s, w1\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ) );
                        fprintf( fp, "    csel     %s, w0, %s, %s\n", GenVariableReg( varmap, vals[ t + 5 ].strValue ),
                                                                      GenVariableReg( varmap, vals[ t + 5 ].strValue ),
                                                                      ConditionsArm64[ vals[ t + 2 ].token ] );
                        fprintf( fp, "    b.%s     line_number_%d\n", ConditionsArm64[ vals[ t + 2 ].token ],
                                                                      vals[ t + 9 ].value );
                    }
                    break;
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          9 == vals.size() &&
                          6 == vals[ t ].value &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          Token::OPENPAREN == vals[ t + 2 ].token &&
                          Token::VARIABLE == vals[ t + 4 ].token &&
                          IsVariableInReg( varmap, vals[ t + 4 ].strValue ) &&
                          Token::THEN == vals[ t + 6 ].token &&
                          0 == vals[ t + 6 ].value &&
                          Token::GOTO == vals[ t + 7 ].token )
                {
                    // line 4180 has 9 tokens  ====>> 4180 if 0 <> b%(p%) then goto 4500
                    //   token   0 IF, value 0, strValue ''
                    //   token   1 EXPRESSION, value 6, strValue ''
                    //   token   2 VARIABLE, value 0, strValue 'b%'
                    //   token   3 OPENPAREN, value 0, strValue ''
                    //   token   4 EXPRESSION, value 2, strValue ''
                    //   token   5 VARIABLE, value 0, strValue 'p%'
                    //   token   6 CLOSEPAREN, value 0, strValue ''
                    //   token   7 THEN, value 0, strValue ''
                    //   token   8 GOTO, value 85, strValue ''

                    if ( x64Win == g_AssemblyTarget )
                    {
                        fprintf( fp, "    mov      ebx, %s\n", GenVariableReg( varmap, vals[ t + 4 ].strValue ) );
                        fprintf( fp, "    shl      rbx, 2\n" );
                        fprintf( fp, "    lea      rcx, %s\n", GenVariableName( vals[ t + 1 ].strValue ) );
                        fprintf( fp, "    mov      eax, DWORD PTR [rbx + rcx]\n" );
                        fprintf( fp, "    test     eax, eax\n" );
                        fprintf( fp, "    jnz      line_number_%d\n", vals[ t + 7 ].value );
                    }
                    else
                    {
                        fprintf( fp, "    lsl      w1, %s, 2\n", GenVariableReg( varmap, vals[ t + 4 ].strValue ) );

                        if ( IsVariableInReg( varmap, vals[ t + 1 ].strValue ) )
                            fprintf( fp, "    add      x1, x1, %s\n", GenVariableReg64( varmap, vals[ t + 1 ].strValue ) );
                        else
                        {
                            LoadArm64Address( fp, "x2", vals[ t + 1 ].strValue );
                            fprintf( fp, "    add      x1, x1, x2\n" );
                        }

                        fprintf( fp, "    ldr      w0, [x1]\n" );
                        fprintf( fp, "    cbnz     w0, line_number_%d\n", vals[ t + 7 ].value );
                    }
                    break;
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          7 == vals.size() &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          IsVariableInReg( varmap, vals[ t + 1 ].strValue ) &&
                          Token::AND == vals[ t + 2 ].token &&
                          Token::CONSTANT == vals[ t + 3 ].token &&
                          vals[ t + 3 ].value < 256 &&  // arm64 requires small values 
                          vals[ t + 3 ].value >= 0 &&
                          Token::THEN == vals[ t + 4 ].token &&
                          0 == vals[ t + 4 ].value &&
                          Token::GOTO == vals[ t + 5 ].token )
                {
                    // line 4330 has 7 tokens  ====>> 4330 if st% and 1 goto 4340
                    //    0 IF, value 0, strValue ''
                    //    1 EXPRESSION, value 4, strValue ''
                    //    2 VARIABLE, value 0, strValue 'st%'
                    //    3 AND, value 0, strValue ''
                    //    4 CONSTANT, value 1, strValue ''
                    //    5 THEN, value 0, strValue ''
                    //    6 GOTO, value 4340, strValue ''

                    if ( x64Win == g_AssemblyTarget )
                    {
                        fprintf( fp, "    test     %s, %d\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ), vals[ t + 3 ].value );
                        fprintf( fp, "    jnz      line_number_%d\n", vals[ t + 5 ].value );
                    }
                    else if ( arm64Mac == g_AssemblyTarget )
                    {
                        fprintf( fp, "    tst      %s, %d\n", GenVariableReg( varmap, vals[ t + 1 ].strValue ), vals[ t + 3 ].value );
                        fprintf( fp, "    b.ne     line_number_%d\n", vals[ t + 5 ].value );
                    }
                }
                else if ( i8080CPM == g_AssemblyTarget &&
                          7 == vals.size() &&
                          Token::VARIABLE == vals[ t + 1 ].token &&
                          Token::AND == vals[ t + 2 ].token &&
                          Token::CONSTANT == vals[ t + 3 ].token &&
                          vals[ t + 3 ].value < 256 &&  // arm64 requires small values 
                          vals[ t + 3 ].value >= 0 &&
                          Token::THEN == vals[ t + 4 ].token &&
                          0 == vals[ t + 4 ].value &&
                          Token::GOTO == vals[ t + 5 ].token )
                {
                    // line 4330 has 7 tokens  ====>> 4330 if st% and 1 goto 4340
                    //    0 IF, value 0, strValue ''
                    //    1 EXPRESSION, value 4, strValue ''
                    //    2 VARIABLE, value 0, strValue 'st%'
                    //    3 AND, value 0, strValue ''
                    //    4 CONSTANT, value 1, strValue ''
                    //    5 THEN, value 0, strValue ''
                    //    6 GOTO, value 4340, strValue ''

                    fprintf( fp, "    lda      %s\n", GenVariableName( vals[ t + 1 ].strValue ) );
                    fprintf( fp, "    ani      1\n" );
                    fprintf( fp, "    jnz      ln$%d\n", vals[ t + 5 ].value );

                    break;
                }
                else if ( arm64Mac == g_AssemblyTarget &&
                          6 == vals.size() &&
                          3 == vals[ t ].value &&
                          Token::NOT == vals[ t + 1 ].token &&
                          Token::VARIABLE == vals[ t + 2 ].token &&
                          IsVariableInReg( varmap, vals[ t + 2 ].strValue ) &&
                          Token::THEN == vals[ t + 3 ].token &&
                          0 == vals[ t + 3 ].value &&
                          Token::GOTO == vals[ t + 4 ].token )
                {
                    // line 2110 has 6 tokens  ====>> 2110 if 0 = wi% goto 2200
                    //  0 IF, value 0, strValue ''
                    //  1 EXPRESSION, value 3, strValue ''
                    //  2 NOT, value 0, strValue ''
                    //  3 VARIABLE, value 0, strValue 'wi%'
                    //  4 THEN, value 0, strValue ''
                    //  5 GOTO, value 33, strValue ''

                    fprintf( fp, "    cbz      %s, line_number_%d\n", GenVariableReg( varmap, vals [ t + 2 ].strValue ),
                                                                      vals[ t + 4 ].value );
                    break;
                }
                else if ( i8080CPM == g_AssemblyTarget &&
                          6 == vals.size() &&
                          3 == vals[ t ].value &&
                          Token::NOT == vals[ t + 1 ].token &&
                          Token::VARIABLE == vals[ t + 2 ].token &&
                          Token::THEN == vals[ t + 3 ].token &&
                          0 == vals[ t + 3 ].value &&
                          Token::GOTO == vals[ t + 4 ].token )
                {
                    // line 2110 has 6 tokens  ====>> 2110 if 0 = wi% goto 2200
                    //  0 IF, value 0, strValue ''
                    //  1 EXPRESSION, value 3, strValue ''
                    //  2 NOT, value 0, strValue ''
                    //  3 VARIABLE, value 0, strValue 'wi%'
                    //  4 THEN, value 0, strValue ''
                    //  5 GOTO, value 33, strValue ''

                    fprintf( fp, "    lhld     %s\n", GenVariableName( vals[ t + 2 ].strValue ) );
                    fprintf( fp, "    mov      a, h\n" );
                    fprintf( fp, "    ora      l\n" );
                    fprintf( fp, "    jz       ln$%d\n", vals[ t + 4 ].value );

                    break;
                }
                else if ( i8080CPM == g_AssemblyTarget &&
                          6 == vals.size() &&
                          3 == vals[ t ].value &&
                          Token::NOT == vals[ t + 1 ].token &&
                          Token::VARIABLE == vals[ t + 2 ].token &&
                          Token::THEN == vals[ t + 3 ].token &&
                          0 == vals[ t + 3 ].value &&
                          Token::RETURN == vals[ t + 4 ].token )
                {
                    // line 2110 has 6 tokens  ===>>> 4530 if st% = 0 then return
                    //  0 IF, value 0, strValue ''
                    //  1 EXPRESSION, value 3, strValue ''
                    //  2 NOT, value 0, strValue ''
                    //  3 VARIABLE, value 0, strValue 'wi%'
                    //  4 THEN, value 0, strValue ''
                    //  5 GOTO, value 33, strValue ''

                    fprintf( fp, "    lhld     %s\n", GenVariableName( vals[ t + 2 ].strValue ) );
                    fprintf( fp, "    mov      a, h\n" );
                    fprintf( fp, "    ora      l\n" );
                    fprintf( fp, "    jz       gosubReturn\n" );

                    break;
                }
                else if ( arm64Mac == g_AssemblyTarget &&
                          6 == vals.size() &&
                          3 == vals[ t ].value &&
                          Token::NOT == vals[ t + 1 ].token &&
                          Token::VARIABLE == vals[ t + 2 ].token &&
                          IsVariableInReg( varmap, vals[ t + 2 ].strValue ) &&
                          Token::THEN == vals[ t + 3 ].token &&
                          0 == vals[ t + 3 ].value &&
                          Token::RETURN == vals[ t + 4 ].token )
                {
                    // line 4530 has 6 tokens  ====>> 4530 if st% = 0 then return
                    //  0 IF, value 0, strValue ''
                    //  1 EXPRESSION, value 3, strValue ''
                    //  2 NOT, value 0, strValue ''
                    //  3 VARIABLE, value 0, strValue 'st%'
                    //  4 THEN, value 0, strValue ''
                    //  5 RETURN, value 0, strValue ''

                    fprintf( fp, "    cbz      %s, label_gosub_return\n", GenVariableReg( varmap, vals [ t + 2 ].strValue ) );
                    break;
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          4 == vals[ t ].value && 
                          isOperatorRelational( vals[ t + 2 ].token ) )
                {
                    // e.g.: if p% < 0 then goto 4180
                    //       if p% < r% then return else x% = x% + 1 

                    // line 4505 has 7 tokens  ====>> 4505 if p% < 9 then goto 4180
                    //    0 IF, value 0, strValue ''
                    //    1 EXPRESSION, value 4, strValue ''
                    //    2 VARIABLE, value 0, strValue 'p%'
                    //    3 LT, value 0, strValue ''
                    //    4 CONSTANT, value 9, strValue ''
                    //    5 THEN, value 0, strValue ''
                    //    6 GOTO, value 4180, strValue ''

                    Token ifOp = vals[ t + 2 ].token;

                    if ( Token::VARIABLE == vals[ 2 ].token && Token::CONSTANT == vals[ 4 ].token )
                    {
                        string & varname = vals[ 2 ].strValue;
                        if ( IsVariableInReg( varmap, varname ) )
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    cmp      %s, %d\n", GenVariableReg( varmap, varname ), vals[ 4 ].value );
                            else if ( arm64Mac == g_AssemblyTarget )
                            {
                                int constant = vals[ 4 ].value;
                                if ( fitsIn12Bits( constant ) )
                                    fprintf( fp, "    cmp      %s, %d\n", GenVariableReg( varmap, varname ), constant );
                                else
                                {
                                    LoadArm64Constant( fp, "x1", constant );
                                    fprintf( fp, "    cmp      %s, w1\n", GenVariableReg( varmap, varname ) );
                                }
                            }
                        }
                        else
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    cmp      DWORD PTR [%s], %d\n", GenVariableName( varname ), vals[ 4 ].value );
                            else if ( arm64Mac == g_AssemblyTarget )
                            {
                                LoadArm64Address( fp, "x2", varname );
                                fprintf( fp, "    ldr      w0, [x2]\n" );
                                LoadArm64Constant( fp, "x1", vals[ 4 ].value );
                                fprintf( fp, "    cmp      w0, w1\n" );
                            }
                        }
                    }
                    else if ( ( Token::VARIABLE == vals[ 2 ].token && Token::VARIABLE == vals[ 4 ].token ) &&
                              ( IsVariableInReg( varmap, vals[ 2 ].strValue ) || IsVariableInReg( varmap, vals[ 4 ].strValue ) ) )
                    {
                        string & varname2 = vals[ 2 ].strValue;
                        string & varname4 = vals[ 4 ].strValue;
                        if ( IsVariableInReg( varmap, varname2 ) )
                        {
                            if ( IsVariableInReg( varmap, varname4 ) )
                            {
                                if ( x64Win == g_AssemblyTarget || arm64Mac == g_AssemblyTarget )
                                    fprintf( fp, "    cmp      %s, %s\n", GenVariableReg( varmap, varname2 ), GenVariableReg( varmap, varname4 ) );
                            }
                            else
                            {
                                if ( x64Win == g_AssemblyTarget )
                                    fprintf( fp, "    cmp      %s, DWORD PTR [%s]\n", GenVariableReg( varmap, varname2 ), GenVariableName( varname4 ) );
                                else
                                {
                                    LoadArm64Address( fp, "x2", varname4 );
                                    fprintf( fp, "    ldr      w1, [x2]\n" );
                                    fprintf( fp, "    cmp      %s, w1\n", GenVariableReg( varmap, varname2 ) );
                                }
                            }
                        }
                        else
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    cmp      DWORD PTR[%s], %s\n", GenVariableName( varname2 ), GenVariableReg( varmap, varname4 ) );
                            else if ( arm64Mac == g_AssemblyTarget )
                            {
                                LoadArm64Address( fp, "x2", varname2 );
                                fprintf( fp, "    ldr    w0, [x2]\n" );
                                fprintf( fp, "    cmp      w0, %s\n", GenVariableReg( varmap, varname4 ) );
                            }
                        }
                    }
                    else
                    {
                        if ( Token::CONSTANT == vals[ 2 ].token )
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    mov      eax, %d\n", vals[ 2 ].value );
                            else
                                LoadArm64Constant( fp, "x0", vals[ 2 ].value );
                        }
                        else
                        {
                            string & varname = vals[ 2 ].strValue;
                            if ( IsVariableInReg( varmap, varname ) )
                            {
                                if ( x64Win == g_AssemblyTarget )
                                    fprintf( fp, "    mov      eax, %s\n", GenVariableReg( varmap, varname ) );
                                else
                                    fprintf( fp, "    mov      x0, %s\n", GenVariableReg( varmap, varname ) );
                            }
                            else
                            {
                                if ( x64Win == g_AssemblyTarget )
                                    fprintf( fp, "    mov      eax, DWORD PTR [%s]\n", GenVariableName( varname ) );
                                else
                                {
                                    LoadArm64Address( fp, "x2", varname );
                                    fprintf( fp, "    ldr      x0, [x2]\n" );
                                }
                            }
                        }
    
                        if ( Token::CONSTANT == vals[ 4 ].token )
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    cmp      eax, %d\n", vals[ 4 ].value );
                            else
                            {
                                LoadArm64Constant( fp, "x1", vals[ 4 ].value );
                                fprintf( fp, "    cmp      x0, x1\n" );
                            }
                        }
                        else
                        {
                            string & varname = vals[ 4 ].strValue;
                            if ( IsVariableInReg( varmap, varname ) )
                            {
                                if ( x64Win == g_AssemblyTarget )
                                    fprintf( fp, "    cmp      eax, %s\n", GenVariableReg( varmap, varname ) );
                                else if ( arm64Mac == g_AssemblyTarget )
                                    fprintf( fp, "    cmp      w0, %s\n", GenVariableReg( varmap, varname ) );
                            }
                            else
                            {
                                if ( x64Win == g_AssemblyTarget )
                                    fprintf( fp, "    cmp      eax, DWORD PTR [%s]\n", GenVariableName( varname ) );
                                else if ( arm64Mac == g_AssemblyTarget )
                                {
                                    LoadArm64Address( fp, "x2", varname );
                                    fprintf( fp, "    ldr      w1, [x2]\n" );
                                    fprintf( fp, "    cmp      x0, x1\n" );
                                }
                            }
                        }
                    }

                    t += vals[ t ].value;
                    assert( Token::THEN == vals[ t ].token );
                    t++;

                    if ( Token::GOTO == vals[ t ].token )
                    {
                        if ( x64Win == g_AssemblyTarget )
                            fprintf( fp, "    %-6s   line_number_%d\n", RelationalInstruction[ ifOp ], vals[ t ].value );
                        else if ( arm64Mac == g_AssemblyTarget )
                            fprintf( fp, "    b.%s     line_number_%d\n", ConditionsArm64[ ifOp ], vals[ t ].value );
                        break;
                    }
                    else if ( Token::RETURN == vals[ t ].token )
                    {
                        if ( x64Win == g_AssemblyTarget )
                            fprintf( fp, "    %-6s   label_gosub_return\n", RelationalInstruction[ ifOp ] );
                        else if ( arm64Mac == g_AssemblyTarget )
                            fprintf( fp, "    b.%s      label_gosub_return\n", ConditionsArm64[ ifOp ] );

                        break;
                    }
                    else
                    {
                        if ( vals[ t - 1 ].value ) // is there an else clause?
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    %-6s   SHORT label_else_%zd\n", RelationalNotInstruction[ ifOp ], l );
                            else if ( arm64Mac == g_AssemblyTarget )
                                fprintf( fp, "    b.%s      label_else_%zd\n", ConditionsNotArm64[ ifOp ], l );
                        }
                        else
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    %-6s   SHORT line_number_%zd\n", RelationalNotInstruction[ ifOp ], l + 1 );
                            else if ( arm64Mac == g_AssemblyTarget )
                                fprintf( fp, "    b.%s    line_number_%zd\n", ConditionsNotArm64[ ifOp ], l + 1 );
                        }
                    }
                }
                else if ( i8080CPM != g_AssemblyTarget &&
                          3 == vals[ t ].value && 
                          Token::NOT == vals[ t + 1 ].token && 
                          Token::VARIABLE == vals[ t + 2 ].token )
                {
                    // line 4530 has 6 tokens  ====>> 4530 if st% = 0 then return
                    // token   0 IF, value 0, strValue ''
                    // token   1 EXPRESSION, value 3, strValue ''
                    // token   2 NOT, value 0, strValue ''
                    // token   3 VARIABLE, value 0, strValue 'st%'
                    // token   4 THEN, value 0, strValue ''
                    // token   5 RETURN, value 0, strValue ''

                    string & varname = vals[ t + 2 ].strValue;
                    if ( IsVariableInReg( varmap, varname ) )
                    {
                        if ( x64Win == g_AssemblyTarget )
                            fprintf( fp, "    test     %s, %s\n", GenVariableReg( varmap, varname ), GenVariableReg( varmap, varname ) );
                        else if ( arm64Mac == g_AssemblyTarget )
                            fprintf( fp, "    cmp      %s, 0\n", GenVariableReg( varmap, varname ) );
                    }
                    else
                    {
                        if ( x64Win == g_AssemblyTarget )
                            fprintf( fp, "    cmp      DWORD PTR [%s], 0\n", GenVariableName( varname ) );
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            LoadArm64Address( fp, "x1", varname );
                            fprintf( fp, "    ldr      w0, [x1]\n" );
                            fprintf( fp, "    cmp      w0, 0\n" );
                        }
                    }

                    t += vals[ t ].value;
                    assert( Token::THEN == vals[ t ].token );
                    t++;

                    if ( Token::GOTO == vals[ t ].token )
                    {
                        if ( x64Win == g_AssemblyTarget )
                            fprintf( fp, "    je       line_number_%d\n", vals[ t ].value );
                        else if ( arm64Mac == g_AssemblyTarget )
                            fprintf( fp, "    b.eq     line_number_%d\n", vals[ t ].value );
                        break;
                    }
                    else if ( Token::RETURN == vals[ t ].token )
                    {
                        if ( x64Win == g_AssemblyTarget )
                            fprintf( fp, "    je       label_gosub_return\n" );
                        else if ( arm64Mac == g_AssemblyTarget )
                            fprintf( fp, "    b.eq     label_gosub_return\n" );
                        break;
                    }
                    else
                    {
                        if ( vals[ t - 1 ].value ) // is there an else clause?
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    jne      SHORT label_else_%zd\n", l );
                            else if ( arm64Mac == g_AssemblyTarget )
                                fprintf( fp, "    b.ne     label_else_%zd\n", l );
                        }
                        else
                        {
                            if ( x64Win == g_AssemblyTarget )
                                fprintf( fp, "    jne      SHORT line_number_%zd\n", l + 1 );
                            else if ( arm64Mac == g_AssemblyTarget )
                                fprintf( fp, "    b.ne     line_number_%zd\n", l + 1 );
                        }
                    }
                }
                else
                {
label_no_if_optimization:

                    // This general case will work for all the cases above, if with worse generated code

                    GenerateOptimizedExpression( fp, varmap, t, vals );
                    assert( Token::THEN == vals[ t ].token );
                    t++;

                    if ( x64Win == g_AssemblyTarget )                                                                                                            
                        fprintf( fp, "    cmp      rax, 0\n" );
                    else if ( arm64Mac == g_AssemblyTarget )
                        fprintf( fp, "    cmp      x0, 0\n" );
                    else if ( i8080CPM == g_AssemblyTarget )
                    {
                        fprintf( fp, "    mov      a, h\n" );
                        fprintf( fp, "    ora      l\n" );
                    }

                    if ( Token::GOTO == vals[ t ].token )
                    {
                        if ( x64Win == g_AssemblyTarget )
                            fprintf( fp, "    jne      line_number_%d\n", vals[ t ].value );
                        else if ( arm64Mac == g_AssemblyTarget )
                            fprintf( fp, "    b.ne     line_number_%d\n", vals[ t ].value );
                        else if ( i8080CPM == g_AssemblyTarget )
                            fprintf( fp, "    jnz      ln$%d\n", vals[ t ].value );
                        break;
                    }
                    else if ( Token::RETURN == vals[ t ].token )
                    {
                        if ( x64Win == g_AssemblyTarget )
                            fprintf( fp, "    jne      label_gosub_return\n" );
                        else if ( arm64Mac == g_AssemblyTarget )
                            fprintf( fp, "    b.ne     label_gosub_return\n" );
                        else if ( i8080CPM == g_AssemblyTarget )
                            fprintf( fp, "    jnz      gosubReturn\n" );
                        break;
                    }
                    else
                    {
                        if ( x64Win == g_AssemblyTarget )
                        {
                            if ( vals[ t - 1 ].value ) // is there an else clause?
                                fprintf( fp, "    je       label_else_%zd\n", l );
                            else
                                fprintf( fp, "    je       line_number_%zd\n", l + 1 );
                        }
                        else if ( arm64Mac == g_AssemblyTarget )
                        {
                            if ( vals[ t - 1 ].value )
                                fprintf( fp, "    b.eq     label_else_%zd\n", l );
                            else
                                fprintf( fp, "    b.eq     line_number_%zd\n", l + 1 );
                        }
                        else if ( i8080CPM == g_AssemblyTarget )
                        {
                            if ( vals[ t - 1 ].value ) // is there an else clause?
                                fprintf( fp, "    jz       els$%zd\n", l );
                            else
                                fprintf( fp, "    jz       ln$%zd\n", l + 1 );
                        }
                    }
                }
            }
            else if ( Token::ELSE == token )
            {
                assert( -1 != activeIf );
                if ( x64Win == g_AssemblyTarget )
                {
                    fprintf( fp, "    jmp      line_number_%zd\n", l + 1 );
                    fprintf( fp, "    align    16\n" );
                }
                else if ( arm64Mac == g_AssemblyTarget )
                {
                    fprintf( fp, "    bl       line_number_%zd\n", l + 1 );
                    fprintf( fp, "  .p2align 2\n" );
                }
                else if ( i8080CPM == g_AssemblyTarget )
                {
                    fprintf( fp, "    jmp      ln$%zd\n", l + 1 );
                }

                if ( i8080CPM == g_AssemblyTarget )
                    fprintf( fp, "  els$%zd:\n", activeIf );
                else
                    fprintf( fp, "  label_else_%zd:\n", activeIf );

                activeIf = -1;
                t++;
            }
            else
            {
                break;
            }

            token = vals[ t ].token;
        } while( true );

        if ( -1 != activeIf )
            activeIf = -1;
    }

    if ( x64Win == g_AssemblyTarget )
    {
        // validate there is an active GOSUB before returning (or not)

        fprintf( fp, "label_gosub_return:\n" );
        // fprintf( fp, "    dec      [gosubCount]\n" );   // should we protect against return without gosub?
        // fprintf( fp, "    cmp      [gosubCount], 0\n" );
        // fprintf( fp, "    jl       error_exit\n" );
        fprintf( fp, "    ret\n" );

        fprintf( fp, "  error_exit:\n" );
        fprintf( fp, "    lea      rcx, [errorString]\n" );
        fprintf( fp, "    call     call_printf\n" );
        fprintf( fp, "    jmp      leave_execution\n" );

        fprintf( fp, "  end_execution:\n" );
        fprintf( fp, "    lea      rcx, [stopString]\n" );
        fprintf( fp, "    call     call_printf\n" );

        fprintf( fp, "  leave_execution:\n" );
        fprintf( fp, "    xor      rcx, rcx\n" );
        fprintf( fp, "    call     call_exit\n" );
        fprintf( fp, "    ret\n" ); // should never get here...
        fprintf( fp, "main ENDP\n" );

        // These stubs are required to setup stack frame spill locations for printf when in a gosub/return statement.
        // They are also required so that volatile registers are persisted (r9, r10, r11).

        fprintf( fp, "align 16\n" );
        fprintf( fp, "call_printf PROC\n" );
        fprintf( fp, "    push     r9\n" );
        fprintf( fp, "    push     r10\n" ); 
        fprintf( fp, "    push     r11\n" ); 
        fprintf( fp, "    push     rbp\n" );
        fprintf( fp, "    mov      rbp, rsp\n" );
        fprintf( fp, "    sub      rsp, 32\n" );
        fprintf( fp, "    call     printf\n" );
        fprintf( fp, "    leave\n" );
        fprintf( fp, "    pop      r11\n" );
        fprintf( fp, "    pop      r10\n" );
        fprintf( fp, "    pop      r9\n" );
        fprintf( fp, "    ret\n" );
        fprintf( fp, "call_printf ENDP\n" );

        fprintf( fp, "align 16\n" );
        fprintf( fp, "call_exit PROC\n" );
        fprintf( fp, "    push     rbp\n" );
        fprintf( fp, "    mov      rbp, rsp\n" );
        fprintf( fp, "    sub      rsp, 32\n" );
        fprintf( fp, "    call     exit\n" );
        fprintf( fp, "    leave\n" );
        fprintf( fp, "    ret\n" );
        fprintf( fp, "call_exit ENDP\n" );

        fprintf( fp, "align 16\n" );
        fprintf( fp, "call_QueryPerformanceCounter PROC\n" );
        fprintf( fp, "    push     r9\n" );   
        fprintf( fp, "    push     r10\n" ); 
        fprintf( fp, "    push     r11\n" ); 
        fprintf( fp, "    push     rbp\n" );
        fprintf( fp, "    mov      rbp, rsp\n" );
        fprintf( fp, "    sub      rsp, 32\n" );
        fprintf( fp, "    call     QueryPerformanceCounter\n" );
        fprintf( fp, "    leave\n" );
        fprintf( fp, "    pop      r11\n" );
        fprintf( fp, "    pop      r10\n" );
        fprintf( fp, "    pop      r9\n" );
        fprintf( fp, "    ret\n" );
        fprintf( fp, "call_QueryPerformanceCounter ENDP\n" );

        fprintf( fp, "align 16\n" );
        fprintf( fp, "call_GetLocalTime PROC\n" );
        fprintf( fp, "    push     r9\n" );   
        fprintf( fp, "    push     r10\n" ); 
        fprintf( fp, "    push     r11\n" ); 
        fprintf( fp, "    push     rbp\n" );
        fprintf( fp, "    mov      rbp, rsp\n" );
        fprintf( fp, "    sub      rsp, 32\n" );
        fprintf( fp, "    call     GetLocalTime\n" );
        fprintf( fp, "    leave\n" );
        fprintf( fp, "    pop      r11\n" );
        fprintf( fp, "    pop      r10\n" );
        fprintf( fp, "    pop      r9\n" );
        fprintf( fp, "    ret\n" );
        fprintf( fp, "call_GetLocalTime ENDP\n" );

        // end of the code segment and program

        fprintf( fp, "code_segment ENDS\n" );
        fprintf( fp, "END\n" );
    }
    else if ( arm64Mac == g_AssemblyTarget )
    {
        fprintf( fp, ".p2align 2\n" );
        fprintf( fp, "label_gosub:\n" );
        fprintf( fp, "    str      x30, [sp, #-16]!\n" );
        fprintf( fp, "    br       x0\n" );

        fprintf( fp, ".p2align 2\n" );
        fprintf( fp, "label_gosub_return:\n" );
        fprintf( fp, "    ldr      x30, [sp], #16\n" );
        fprintf( fp, "    ret\n" );

        fprintf( fp, ".p2align 2\n" );
        fprintf( fp, "error_exit:\n" );
        fprintf( fp, "    adrp     x0, errorString@PAGE\n" );
        fprintf( fp, "    add      x0, x0, errorString@PAGEOFF\n" );
        fprintf( fp, "    bl       call_printf\n" ); 
        fprintf( fp, "    bl       leave_execution\n" );

        fprintf( fp, ".p2align 2\n" );
        fprintf( fp, "end_execution:\n" );
        fprintf( fp, "    adrp     x0, stopString@PAGE\n" );
        fprintf( fp, "    add      x0, x0, stopString@PAGEOFF\n" );
        fprintf( fp, "    bl       call_printf\n" ); 
        fprintf( fp, "    bl       leave_execution\n" );
        
        fprintf( fp, ".p2align 2\n" );
        fprintf( fp, "call_exit:\n" );
        fprintf( fp, "leave_execution:\n" );
        fprintf( fp, "    ; OS system call to exit the app\n" );
        fprintf( fp, "    mov      x0, 0\n" );
        fprintf( fp, "    mov      x16, 1\n" );
        fprintf( fp, "    svc      0x80\n" );

        fprintf( fp, ".p2align 2\n" );
        fprintf( fp, "call_printf:\n" );
        fprintf( fp, "    save_volatile_registers\n" );
        fprintf( fp, "    sub      sp, sp, #32\n" );
        fprintf( fp, "    stp      x29, x30, [sp, #16]\n" );
        fprintf( fp, "    add      x29, sp, #16\n" );
        fprintf( fp, "    str      x1, [sp]\n" );
        fprintf( fp, "    bl       _printf\n" );
        fprintf( fp, "    ldp      x29, x30, [sp, #16]\n" );
        fprintf( fp, "    add      sp, sp, #32\n" );
        fprintf( fp, "    restore_volatile_registers\n" );
        fprintf( fp, "    ret\n" );

        for ( int i = 0; i < g_lohCount; i += 2 )
            fprintf( fp, ".loh AdrpAdd   Lloh%d, Lloh%d\n", i, i + 1 );
    }
    else if ( i8080CPM == g_AssemblyTarget )
    {
        fprintf( fp, "    jmp      0\n" );

        fprintf( fp, "gosubReturn:\n" );
        fprintf( fp, "    ret\n" );

        fprintf( fp, "errorExit:\n" );
        fprintf( fp, "    mvi      c, PRSTR\n" );
        fprintf( fp, "    lxi      d, errorString\n" );
        fprintf( fp, "    call     BDOS\n" );
        fprintf( fp, "    jmp      leaveExecution\n" );

        fprintf( fp, "endExecution:\n" );
        fprintf( fp, "    mvi      c, PRSTR\n" );
        fprintf( fp, "    lxi      d, stopString\n" );
        fprintf( fp, "    call     BDOS\n" );

        fprintf( fp, "leaveExecution:\n" );
        fprintf( fp, "    pop      h\n" );
        fprintf( fp, "    pop      d\n" );
        fprintf( fp, "    pop      b\n" );
        fprintf( fp, "    jmp      0\n" );

        /////////////////////////////////////////
        // zeros memory. byte count in de, starting at address bc

        fprintf( fp, "zeromem:\n" );
        fprintf( fp, "    mvi      a, 0\n" );
        fprintf( fp, "  zmAgain:\n" );
        fprintf( fp, "    cmp      d\n" );
        fprintf( fp, "    jnz      zmWrite\n" );
        fprintf( fp, "    cmp      e\n" );
        fprintf( fp, "    rz\n" );
        fprintf( fp, "  zmWrite:\n" );
        fprintf( fp, "    stax     b\n" );
        fprintf( fp, "    inx      b\n" );
        fprintf( fp, "    dcx      d\n" );
        fprintf( fp, "    jmp      zmAgain\n" );

        /////////////////////////////////////////

        /////////////////////////////////////////
        // negate the de register pair. handy for idiv and imul
        // negate using complement then add 1

        fprintf( fp, "neg$de:\n" );
        fprintf( fp, "    mov      a, d\n" );
        fprintf( fp, "    cma\n" );
        fprintf( fp, "    mov      d, a\n" );
        fprintf( fp, "    mov      a, e\n" );
        fprintf( fp, "    cma\n" );
        fprintf( fp, "    mov      e, a\n" );
        fprintf( fp, "    inx      d\n" );
        fprintf( fp, "    ret\n" );

        /////////////////////////////////////////

        /////////////////////////////////////////
        // negate the hl register pair. handy for idiv and imul
        // negate using complement then add 1

        fprintf( fp, "neg$hl:\n" );
        fprintf( fp, "    mov      a, h\n" );
        fprintf( fp, "    cma\n" );
        fprintf( fp, "    mov      h, a\n" );
        fprintf( fp, "    mov      a, l\n" );
        fprintf( fp, "    cma\n" );
        fprintf( fp, "    mov      l, a\n" );
        fprintf( fp, "    inx      h\n" );
        fprintf( fp, "    ret\n" );

        /////////////////////////////////////////

        /////////////////////////////////////////
        // multiply de by hl, result in hl
        // incredibly slow iterative addition.

        fprintf( fp, "imul:\n" );
        fprintf( fp, "    mvi      b, 80h\n" );
        fprintf( fp, "    mov      a, h\n" );
        fprintf( fp, "    ana      b\n" );
        fprintf( fp, "    jz       mul$notneg\n" );
        fprintf( fp, "    call     neg$hl\n" );
        fprintf( fp, "    call     neg$de\n" );
        fprintf( fp, "  mul$notneg:\n" );
        fprintf( fp, "    push     h\n" );
        fprintf( fp, "    pop      b\n" );
        fprintf( fp, "    lxi      h, 0\n" );
        fprintf( fp, "    shld     mulTmp\n" );
        fprintf( fp, "  mul$loop:\n" );
        fprintf( fp, "    dad      d\n" );
        fprintf( fp, "    jnc      mul$done\n" );
        fprintf( fp, "    push     h\n" );
        fprintf( fp, "    lhld     mulTmp\n" );
        fprintf( fp, "    inx      h\n" );
        fprintf( fp, "    shld     mulTmp\n" );
        fprintf( fp, "    pop      h\n" );
        fprintf( fp, "  mul$done:\n" );
        fprintf( fp, "    dcx      b\n" );
        fprintf( fp, "    mov      a, b\n" );
        fprintf( fp, "    ora      c\n" );
        fprintf( fp, "    jnz      mul$loop\n" );
        fprintf( fp, "    ret\n" );

        /////////////////////////////////////////

        /////////////////////////////////////////
        // divide de by hl, result in hl
        // incredibly slow iterative subtraction

        fprintf( fp, "idiv:\n" );
        fprintf( fp, "    xchg\n" ); // now it's hl / de
        fprintf( fp, "    mvi      c, 0\n" );
        fprintf( fp, "    mvi      b, 80h\n" );
        fprintf( fp, "    mov      a, d\n" );
        fprintf( fp, "    ana      b\n" );
        fprintf( fp, "    jz       div$denotneg\n" );
        fprintf( fp, "    inr      c\n" );
        fprintf( fp, "    call     neg$de\n" );
        fprintf( fp, "  div$denotneg:\n" );
        fprintf( fp, "    mov      a, h\n" );
        fprintf( fp, "    ana      b\n" );
        fprintf( fp, "    jz       div$hlnotneg\n" );
        fprintf( fp, "    inr      c\n" );
        fprintf( fp, "    call     neg$hl\n" );
        fprintf( fp, "  div$hlnotneg:\n" );
        fprintf( fp, "    push     b\n" );    // save c -- count of negatives
        fprintf( fp, "    lxi      b, 0\n" );
        fprintf( fp, "  div$loop:\n" );
        fprintf( fp, "    mov      a, l\n" );
        fprintf( fp, "    sub      e\n" );
        fprintf( fp, "    mov      l, a\n" );
        fprintf( fp, "    mov      a, h\n" );
        fprintf( fp, "    sbb      d\n" );
        fprintf( fp, "    mov      h, a\n" );
        fprintf( fp, "    jc       div$done\n" );
        fprintf( fp, "    inx      b\n" );
        fprintf( fp, "    jmp      div$loop\n" );
        fprintf( fp, "  div$done:\n" );
        fprintf( fp, "    dad      d\n" );
        fprintf( fp, "    shld     divRem\n" );
        fprintf( fp, "    mov      l, c\n" );
        fprintf( fp, "    mov      h, b\n" );
        fprintf( fp, "    pop      b\n" );
        fprintf( fp, "    mov      a, c\n" );
        fprintf( fp, "    ani      1\n" );
        fprintf( fp, "    cnz      neg$hl\n" ); // if 1 of the inputs was negative, negate
        fprintf( fp, "    ret\n" );

        /////////////////////////////////////////

        /////////////////////////////////////////
        // function I found in the internet to print the integer in hl

        fprintf( fp, "puthl:  mov     a,h     ; Get the sign bit of the integer,\n" );
        fprintf( fp, "        ral             ; which is the top bit of the high byte\n" );
        fprintf( fp, "        sbb     a       ; A=00 if positive, FF if negative\n" );
        fprintf( fp, "        sta     negf    ; Store it as the negative flag\n" );
        fprintf( fp, "        cnz     neg$hl  ; And if HL was negative, make it positive\n" );
        fprintf( fp, "        lxi     d,num   ; Load pointer to end of number string\n" );
        fprintf( fp, "        push    d       ; Onto the stack\n" );
        fprintf( fp, "        lxi     b,-10   ; Divide by ten (by trial subtraction)\n" );
        fprintf( fp, "digit:  lxi     d,-1    ; DE = quotient. There is no 16-bit subtraction,\n" );
        fprintf( fp, "dgtdiv: dad     b       ; so we just add a negative value,\n" );
        fprintf( fp, "        inx     d\n" );
        fprintf( fp, "        jc      dgtdiv  ; while that overflows.\n" );
        fprintf( fp, "        mvi     a,'0'+10        ; The loop runs once too much so we're 10 out\n" );
        fprintf( fp, "        add     l       ; The remainder (minus 10) is in L\n" );
        fprintf( fp, "        xthl            ; Swap HL with top of stack (i.e., the string pointer)\n" );
        fprintf( fp, "        dcx     h       ; Go back one byte\n" );
        fprintf( fp, "        mov     m,a     ; And store the digit\n" );
        fprintf( fp, "        xthl            ; Put the pointer back on the stack\n" );
        fprintf( fp, "        xchg            ; Do all of this again with the quotient\n" );
        fprintf( fp, "        mov     a,h     ; If it is zero, we're done\n" );
        fprintf( fp, "        ora     l\n" );
        fprintf( fp, "        jnz     digit   ; But if not, there are more digits\n" );
        fprintf( fp, "        mvi     c, PRSTR  ; Prepare to call CP/M and print the string\n" );
        fprintf( fp, "        pop     d       ; Put the string pointer from the stack in DE\n" );
        fprintf( fp, "        lda     negf    ; See if the number was supposed to be negative\n" );
        fprintf( fp, "        inr     a\n" );
        fprintf( fp, "        jnz     bdos    ; If not, print the string we have and return\n" );
        fprintf( fp, "        dcx     d       ; But if so, we need to add a minus in front\n" );
        fprintf( fp, "        mvi     a,'-'\n" );
        fprintf( fp, "        stax    d\n" );
        fprintf( fp, "        jmp     bdos    ; And only then print the string\n" );
        fprintf( fp, "negf:   db      0       ; Space for negative flag\n" );
        fprintf( fp, "        db      '-00000'\n" );
        fprintf( fp, "num:    db      '$'     ; Space for number\n" );

        /////////////////////////////////////////

        fprintf( fp, "    end\n" );
    }

    printf( "created assembler file %s\n", outputfile );
} //GenerateASM

void ParseInputFile( const char * inputfile )
{
    CFile fileInput( fopen( inputfile, "rb" ) );
    if ( NULL == fileInput.get() )
    {
        printf( "can't open input file %s\n", inputfile );
        Usage();
    }

    printf( "parsing input file %s\n", inputfile );

    long filelen = portable_filelen( fileInput.get() );
    vector<char> input( filelen + 1 );
    size_t lread = fread( input.data(), filelen, 1, fileInput.get() );
    if ( 1 != lread )
    {
        printf( "unable to read input file\n" );
        Usage();
    }

    fileInput.Close();
    input.data()[ filelen ] = 0;

    char * pbuf = input.data();
    char * pbeyond = pbuf + filelen;
    char line[ 300 ];
    const int MaxLineLen = _countof( line ) - 1;
    int fileLine = 0;
    int prevLineNum = 0;

    while ( pbuf < pbeyond )
    {
        int len = 0;
        while ( ( pbuf < pbeyond ) && ( ( *pbuf != 10 ) && ( *pbuf != 13 ) ) && ( len < MaxLineLen ) )
            line[ len++ ] = *pbuf++;

        while ( ( pbuf < pbeyond ) && ( *pbuf == 10 || *pbuf == 13 ) )
            pbuf++;

        fileLine++;

        if ( 0 != len )
        {
            line[ len ] = 0;
            if ( EnableTracing && g_Tracing )
                printf( "read line %d: %s\n", fileLine, line );

            int lineNum = readNum( line );
            if ( -1 == lineNum )
                Fail( "expected a line number", fileLine, 0, line );

            if ( lineNum <= prevLineNum )
                Fail( "line numbers are out of order", fileLine, 0, line );

            prevLineNum = lineNum;

            const char * pline = pastNum( line );
            pline = pastWhite( pline );

            int tokenLen = 0;
            Token token = readToken( pline, tokenLen );

            if ( Token::INVALID == token )
                Fail( "invalid token", fileLine, 0, line );

            LineOfCode loc( lineNum, line );
            g_linesOfCode.push_back( loc );

            TokenValue tokenValue( token );
            vector<TokenValue> & lineTokens = g_linesOfCode[ g_linesOfCode.size() - 1 ].tokenValues;

            if ( isTokenStatement( token ) )
            {
                pline = ParseStatements( token, lineTokens, pline, line, fileLine );
            }
            else if ( Token::FOR == token )
            {
                pline = pastWhite( pline + tokenLen );
                token = readToken( pline, tokenLen );
                if ( Token::VARIABLE == token )
                {
                    tokenValue.strValue.insert( 0, pline, tokenLen );
                    makelower( tokenValue.strValue );
                    lineTokens.push_back( tokenValue );
                }
                else
                    Fail( "expected a variable after FOR statement", fileLine, 1 + pline - line, line );

                pline = pastWhite( pline + tokenLen );
                token = readToken( pline, tokenLen );
                if ( Token::EQ != token )
                    Fail( "expected an equal sign in FOR statement", fileLine, 1 + pline - line, line );

                pline = pastWhite( pline + tokenLen );
                pline = ParseExpression( lineTokens, pline, line, fileLine );

                pline = pastWhite( pline );
                token = readToken( pline, tokenLen );
                if ( Token::TO != token )
                    Fail( "expected a TO in FOR statement", fileLine, 1 + pline - line, line );

                pline = pastWhite( pline + tokenLen );
                pline = ParseExpression( lineTokens, pline, line, fileLine );
            }
            else if ( Token::IF == token )
            {
                lineTokens.push_back( tokenValue );
                pline = pastWhite( pline + tokenLen );
                pline = ParseExpression( lineTokens, pline, line, fileLine );
                if ( Token::EXPRESSION == lineTokens[ lineTokens.size() - 1 ].token )
                    Fail( "expected an expression after an IF statement", fileLine, 1 + pline - line, line );

                pline = pastWhite( pline );
                token = readToken( pline, tokenLen );
                if ( Token::THEN == token )
                {
                    // THEN is optional in the source code but manditory in p-code

                    pline = pastWhite( pline + tokenLen );
                    token = readToken( pline, tokenLen );
                }

                tokenValue.Clear();
                tokenValue.token = Token::THEN;
                size_t thenOffset = lineTokens.size();
                lineTokens.push_back( tokenValue );

                pline = ParseStatements( token, lineTokens, pline, line, fileLine );

                if ( Token::THEN == lineTokens[ lineTokens.size() - 1 ].token )
                    Fail( "expected a statement after a THEN", fileLine, 1 + pline - line, line );

                pline = pastWhite( pline );
                token = readToken( pline, tokenLen );
                if ( Token::ELSE == token )
                {
                    tokenValue.Clear();
                    tokenValue.token = token;
                    lineTokens.push_back( tokenValue );
                    lineTokens[ thenOffset ].value = (int) ( lineTokens.size() - thenOffset - 1 );
                    
                    pline = pastWhite( pline + tokenLen );
                    token = readToken( pline, tokenLen );
                    pline = ParseStatements( token, lineTokens, pline, line, fileLine );
                    if ( Token::ELSE == lineTokens[ lineTokens.size() - 1 ].token )
                        Fail( "expected a statement after an ELSE", fileLine, 1 + pline - line, line );
                }
            }
            else if ( Token::REM == token )
            {
                // can't just throw out REM statements yet because a goto/gosub may reference them

                lineTokens.push_back( tokenValue );
            }
            else if ( Token::TRON == token )
            {
                lineTokens.push_back( tokenValue );
            }
            else if ( Token::TROFF == token )
            {
                lineTokens.push_back( tokenValue );
            }
            else if ( Token::NEXT == token )
            {
                pline = pastWhite( pline + tokenLen );
                token = readToken( pline, tokenLen );
                if ( Token::VARIABLE == token )
                {
                    tokenValue.strValue.insert( 0, pline, tokenLen );
                    makelower( tokenValue.strValue );
                    lineTokens.push_back( tokenValue );
                }
                else
                    Fail( "expected a variable with NEXT statement", fileLine, 1 + pline - line, line );
            }
            else if ( Token::DIM == token )
            {
                pline = pastWhite( pline + tokenLen );
                token = readToken( pline, tokenLen );
                if ( Token::VARIABLE == token )
                {
                    tokenValue.strValue.insert( 0, pline, tokenLen );
                    makelower( tokenValue.strValue );
                    pline = pastWhite( pline + tokenLen );
                    token = readToken( pline, tokenLen );

                    if ( Token::OPENPAREN != token )
                        Fail( "expected open paren for DIM statment", fileLine, 1 + pline - line, line );

                    pline = pastWhite( pline + tokenLen );
                    token = readToken( pline, tokenLen );

                    if ( Token::CONSTANT != token )
                        Fail( "expected a numeric constant first dimension", fileLine, 1 + pline - line, line );

                    tokenValue.dims[ 0 ] = atoi( pline );
                    if ( tokenValue.dims[ 0 ] <= 0 )
                        Fail( "array dimension isn't positive", fileLine, 1 + pline - line, line );

                    pline = pastWhite( pline + tokenLen );
                    token = readToken( pline, tokenLen );
                    tokenValue.dimensions = 1;

                    if ( Token::COMMA == token )
                    {
                        pline = pastWhite( pline + tokenLen );
                        token = readToken( pline, tokenLen );

                        if ( Token::CONSTANT != token )
                            Fail( "expected a numeric constant second dimension", fileLine, 1 + pline - line, line );

                        tokenValue.dims[ 1 ] = atoi( pline );
                        if ( tokenValue.dims[ 1 ] <= 0 )
                            Fail( "array dimension isn't positive", fileLine, 1 + pline - line, line );

                        pline = pastWhite( pline + tokenLen );
                        token = readToken( pline, tokenLen );
                        tokenValue.dimensions = 2;
                    }

                    if ( Token::CLOSEPAREN == token )
                        lineTokens.push_back( tokenValue );
                    else
                        Fail( "expected close paren or next dimension", fileLine, 1 + pline - line, line );
                }
                else
                    Fail( "expected a variable after DIM", fileLine, 1 + pline - line, line );
            }
        }
    }
} //ParseInputFile

void InterpretCode( map<string, Variable> & varmap )
{
    // The cost of this level of indirection is 15% in NDEBUG interpreter performance.
    // So it's not worth it to control the behavior at runtime except for testing / debug

    #ifdef DEBUG
        typedef int ( * EvaluateProc )( int & iToken, vector<TokenValue> const & vals );
        EvaluateProc evalProc = EvaluateLogicalExpression;
        if ( g_ExpressionOptimization )
            evalProc = EvaluateExpressionOptimized;
    #else
        #define evalProc EvaluateExpressionOptimized
    #endif

    static Stack<ForGosubItem> forGosubStack;
    bool basicTracing = false;
    g_pc = 0;  // program counter

    #ifdef ENABLE_EXECUTION_TIME
        int pcPrevious = 0;
        g_linesOfCode[ 0 ].timesExecuted--; // avoid off by 1 on first iteration of loop
        uint64_t timePrevious = __rdtsc();
    #endif

    steady_clock::time_point timeBegin = steady_clock::now();

    do
    {
        label_next_pc:

        // The overhead of tracking execution time makes programs run ~ 2x slower.
        // As a result, about half of the times shown in the report are just overhead of tracking the data.
        // Look for relative differences when determining where to optimize.

        #ifdef ENABLE_EXECUTION_TIME
            if ( showExecutionTime )
            {
                // __rdtsc makes the app run 2x slower.
                // steady_clock makes the app run 5x slower. I'm probably doing something wrong?
                // The M1 mac implementation has nearly 0 overhead.

                uint64_t timeNow = __rdtsc();
                g_linesOfCode[ pcPrevious ].duration += ( timeNow - timePrevious );
                g_linesOfCode[ pcPrevious ].timesExecuted++;
                timePrevious = timeNow;
                pcPrevious = g_pc;
            }
        #endif //ENABLE_EXECUTION_TIME

        vector<TokenValue> const & vals = g_linesOfCode[ g_pc ].tokenValues;
        Token token = g_linesOfCode[ g_pc ].firstToken;
        int t = 0;

        if ( EnableTracing && basicTracing )
            printf( "executing line %d\n", g_lineno );

        do
        {
            if ( EnableTracing && g_Tracing )
                printf( "executing pc %d line number %d ==> %s\n", g_pc, g_lineno, g_linesOfCode[ g_pc ].sourceCode.c_str() );

            // MSC doesn't support goto jump tables like g++. MSC will optimize switch statements if the default has
            // an __assume(false), but the generated code for the lookup table is complex and slower than if/else if...
            // If more tokens are added to the list below then at some point the lookup table will be faster.
            // Note that g++ and clang++ generate slower code overall than MSC, and use of a goto jump table
            // with those compilers is still slower than MSC without a jump table.
            // A table of function pointers is much slower.
            // The order of the tokens is based on usage in the ttt app.

            if ( Token::IF == token )
            {
                t++;
                int val = evalProc( t, vals );
                assert( Token::THEN == vals[ t ].token );

                if ( val )
                {
                    t++;
                }
                else
                {
                    // offset of ELSE token from THEN or 0 if there is no ELSE

                    if ( 0 == vals[ t ].value )
                    {
                        g_pc++;
                        goto label_next_pc;
                    }
                    else
                    {
                        int elseOffset = vals[ t ].value;
                        assert( Token::ELSE == vals[ t + elseOffset ].token );
                        t += ( elseOffset + 1 );
                    }
                }
            }
            else if ( Token::VARIABLE == token )
            {
                Variable *pvar = vals[ t ].pVariable;
                assert( pvar && "variable hasn't been declared or cached" );

                t++;

                if ( Token::OPENPAREN == vals[ t ].token )
                {
                    if ( 0 == pvar->dimensions )
                        RuntimeFail( "variable used as array isn't an array", g_lineno );

                    t++;
                    int arrayIndex = evalProc( t, vals );

                    if ( RangeCheckArrays && FailsRangeCheck( arrayIndex, pvar->dims[ 0 ] ) )
                        RuntimeFail( "array offset out of bounds", g_lineno );

                    if ( Token::COMMA == vals[ t ].token )
                    {
                        t++;

                        if ( 2 != pvar->dimensions )
                            RuntimeFail( "single-dimensional array used with 2 dimensions", g_lineno );

                        int indexB = evalProc( t, vals );

                        if ( RangeCheckArrays && FailsRangeCheck( indexB, pvar->dims[ 1 ] ) )
                            RuntimeFail( "second dimension array offset out of bounds", g_lineno );

                        arrayIndex *= pvar->dims[ 1 ];
                        arrayIndex +=  indexB;
                    }

                    assert( Token::CLOSEPAREN == vals[ t ].token );
                    assert( Token::EQ == vals[ t + 1 ].token );

                    t += 2; // past ) and =
                    int val = evalProc( t, vals );

                    pvar->array[ arrayIndex ] = val;
                }
                else
                {
                    assert( Token::EQ == vals[ t ].token );

                    t++;
                    int val = evalProc( t, vals );

                    if ( RangeCheckArrays && ( 0 != pvar->dimensions ) )
                        RuntimeFail( "array used as if it's a scalar", g_lineno );

                    pvar->value = val;
                }

                // have we consumed all tokens in the instruction?

                if ( t == vals.size() )
                {
                    g_pc++;
                    goto label_next_pc;
                }
            }
            else if ( Token::GOTO == token )
            {
                g_pc = vals[ t ].value;
                goto label_next_pc;
            }
            else if ( Token::ATOMIC == token )
            {
                Variable * pvar = vals[ t + 1 ].pVariable;
                assert( pvar && "atomic variable hasn't been declared or cached" );

                if ( Token::INC == vals[ t + 1 ].token )
                {
                    pvar->value++;
                }
                else
                {
                    assert( Token::DEC == vals[ t + 1 ].token );
                    pvar->value--;
                }

                g_pc++;
                goto label_next_pc;
            }
            else if ( Token::GOSUB == token )
            {
                ForGosubItem fgi( false, g_pc + 1 );
                forGosubStack.push( fgi );

                g_pc = vals[ t ].value;
                goto label_next_pc;
            }
            else if ( Token::RETURN == token )
            {
                do 
                {
                    if ( 0 == forGosubStack.size() )
                        RuntimeFail( "return without gosub", g_lineno );

                    // remove any active FOR items to get to the next GOSUB item and return

                    ForGosubItem & item = forGosubStack.top();
                    forGosubStack.pop();
                    if ( !item.isFor )
                    {
                        g_pc = item.pcReturn;
                        break;
                    }
                } while( true );

                goto label_next_pc;
            }
            else if ( Token::FOR == token )
            {
                bool continuation = false;

                if  ( forGosubStack.size() >  0 )
                {
                    ForGosubItem & item = forGosubStack.top();
                    if ( item.isFor && item.pcReturn == g_pc )
                        continuation = true;
                }

                Variable * pvar = vals[ 0 ].pVariable;

                if ( continuation )
                    pvar->value += 1;
                else
                {
                    int teval = t + 1;
                    pvar->value = evalProc( teval, vals );
                }

                int tokens = vals[ t + 1 ].value;
                int tokenStart = t + 1 + tokens;
                int endValue = evalProc( tokenStart, vals );

                if ( EnableTracing && g_Tracing )
                    printf( "for loop for variable %s current %d, end value %d\n", vals[ 0 ].strValue.c_str(), pvar->value, endValue );

                if ( !continuation )
                {
                    ForGosubItem item( true, g_pc );
                    forGosubStack.push( item );
                }

                if ( pvar->value > endValue )
                {
                    // find NEXT and set g_pc to one beyond it.

                    forGosubStack.pop();

                    do
                    {
                        g_pc++;

                        if ( g_pc >= g_linesOfCode.size() )
                            RuntimeFail( "no matching NEXT found for FOR", g_lineno );

                        if ( g_linesOfCode[ g_pc ].tokenValues.size() > 0 &&
                             Token::NEXT == g_linesOfCode[ g_pc ].tokenValues[ 0 ].token &&
                             ! g_linesOfCode[ g_pc ].tokenValues[ 0 ].strValue.compare( vals[ 0 ].strValue ) )
                            break;
                    } while ( true );
                }

                g_pc++;
                goto label_next_pc;
            }
            else if ( Token::NEXT == token )
            {
                if ( 0 == forGosubStack.size() )
                    RuntimeFail( "NEXT without FOR", g_lineno );

                ForGosubItem & item = forGosubStack.top();
                if ( !item.isFor )
                    RuntimeFail( "NEXT without FOR", g_lineno );

                string & loopVal = g_linesOfCode[ item.pcReturn ].tokenValues[ 0 ].strValue;

                if ( loopVal.compare( vals[ t ].strValue ) )
                    RuntimeFail( "NEXT statement variable doesn't match current FOR loop variable", g_lineno );

                g_pc = item.pcReturn;
                goto label_next_pc;
            }
            else if ( Token::PRINT == token )
            {
                g_pc++;
                t++;

                while ( t < vals.size() )
                {
                    if ( Token::SEMICOLON == vals[ t ].token )
                    {
                        t++;
                        continue;
                    }
                    else if ( Token::EXPRESSION != vals[ t ].token ) // ELSE is typical
                    {
                        break;
                    }

                    assert( Token::EXPRESSION == vals[ t ].token );

                    if ( Token::STRING == vals[ t + 1 ].token )
                    {
                        printf( "%s", vals[ t + 1 ].strValue.c_str() );
                        t += 2;
                    }
                    else if ( Token::TIME == vals[ t + 1 ].token )
                    {
                        auto now = system_clock::now();
                        auto ms = duration_cast<milliseconds>( now.time_since_epoch() ) % 1000;
                        auto timer = system_clock::to_time_t( now );
                        std::tm bt = * /*std::*/ localtime( &timer );
                        printf( "%d:%d:%d", bt.tm_hour, bt.tm_min, bt.tm_sec );
                        t += 2;
                    }
                    else if ( Token::ELAP == vals[ t + 1 ].token )
                    {
                        steady_clock::time_point timeNow = steady_clock::now();
                        long long duration = duration_cast<std::chrono::milliseconds>( timeNow - timeBegin ).count();
                        static char acElap[ 100 ];
                        acElap[ 0 ] = 0;
                        PrintNumberWithCommas( acElap, duration );
                        printf( "%s ms", acElap );
                        t += 2;
                    }
                    else
                    {
                        int val = evalProc( t, vals );
                        printf( "%d", val );
                    }
                }

                printf( "\n" );
                goto label_next_pc;
            }
            else if ( Token::ELSE == token )
            {
                g_pc++;
                goto label_next_pc;
            }
            else if ( Token::END == token )
            {
                #ifdef ENABLE_EXECUTION_TIME
                    if ( showExecutionTime )
                    {
                        uint64_t timeNow = __rdtsc();
                        g_linesOfCode[ g_pc ].duration += ( timeNow - timePrevious );
                        g_linesOfCode[ g_pc ].timesExecuted++;
                    }
                #endif
                goto label_exit_execution;
            }
            else if ( Token::DIM == token )
            {
                // if the variable has already been defined, delete it first.

                Variable * pvar = FindVariable( varmap, vals[ 0 ].strValue );
                if ( pvar )
                {
                    pvar = 0;
                    varmap.erase( vals[ 0 ].strValue.c_str() );
                }

                Variable var( vals[ 0 ].strValue.c_str() );

                var.dimensions = vals[ 0 ].dimensions;
                var.dims[ 0 ] = vals[ 0 ].dims[ 0 ];
                var.dims[ 1 ] = vals[ 0 ].dims[ 1 ];
                int items = var.dims[ 0 ];
                if ( 2 == var.dimensions )
                    items *= var.dims[ 1 ];
                var.array.resize( items );
                varmap.emplace( var.name, var );

                // update all references to this array

                pvar = FindVariable( varmap, vals[ 0 ].strValue );

                for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
                {
                    LineOfCode & lineOC = g_linesOfCode[ l ];
    
                    for ( size_t z = 0; z < lineOC.tokenValues.size(); z++ )
                    {
                        TokenValue & tv = lineOC.tokenValues[ z ];
                        if ( Token::VARIABLE == tv.token && !tv.strValue.compare( vals[ 0 ].strValue ) )
                            tv.pVariable = pvar;
                    }
                }

                g_pc++;
                goto label_next_pc;
            }
            else if ( Token::TRON == token )
            {
                basicTracing = true;
                g_pc++;
                goto label_next_pc;
            }
            else if ( Token::TROFF == token )
            {
                basicTracing = false;
                g_pc++;
                goto label_next_pc;
            }
            else
            {
                printf( "unexpected token %s\n", TokenStr( token ) );
                RuntimeFail( "internal error: unexpected token in top-level interpreter loop", g_lineno );
            }

            token = vals[ t ].token;
        } while( true );
    } while( true );

    label_exit_execution:

    #ifdef ENABLE_EXECUTION_TIME
        if ( showExecutionTime )
        {
            static char acTimes[ 100 ];
            static char acDuration[ 100 ];
            printf( "execution times in rdtsc hardware ticks:\n" );
            printf( "   line #          times           duration         average\n" );
            for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
            {
                LineOfCode & loc = g_linesOfCode[ l ];

                // if the END statment added to the end was never executed then ignore it

                if ( ( l == ( g_linesOfCode.size() - 1 ) ) && ( 0 == loc.timesExecuted ) )
                    continue;
    
                acTimes[ 0 ] = 0;
                acDuration[ 0 ] = 0;
                PrintNumberWithCommas( acTimes, loc.timesExecuted );

                long long duration = loc.duration;
                PrintNumberWithCommas( acDuration, duration );

                double average = loc.timesExecuted ? ( (double) duration / (double) loc.timesExecuted ) : 0.0;
                printf( "  %7d  %13s    %15s    %12.3lf", loc.lineNumber, acTimes, acDuration, average );
                printf( "\n" );
            }
        }
    #endif //ENABLE_EXECUTION_TIME

    printf( "exiting the basic interpreter\n" );
} //InterpretCode

extern int main( int argc, char *argv[] )
{
    steady_clock::time_point timeAppStart = steady_clock::now();

    // validate the parallel arrays and enum are actually parallel

    assert( ( Token::INVALID + 1 ) == _countof( Tokens ) );
    assert( ( Token::INVALID + 1 ) == _countof( Operators ) );
    assert( 11 == Token::MULT );

    // not critical, but interpreted performance is faster if it's a multiple of 2.

    if ( 64 != sizeof( TokenValue ) )
        printf( "sizeof tokenvalue: %zd\n", sizeof( TokenValue ) );
    assert( 64 == sizeof( TokenValue ) );

    bool showListing = false;
    bool executeCode = true;
    bool showExecutionTime = false;
    bool showParseTime = false;
    bool generateASM = false;
    bool useRegistersInASM = true;
    static char inputfile[ 300 ] = {0};
    static char asmfile[ 300 ] = {0};

    for ( int i = 1; i < argc; i++ )
    {
        char * parg = argv[ i ];
        char c0 = parg[ 0 ];
        char c1 = (char) tolower( parg[ 1 ] );

        if ( '-' == c0 || '/' == c0 )
        {
            if ( 'a' == c1 )
            {
                g_AssemblyTarget = x64Win;
                generateASM = true;
            }
            else if ( 'e' == c1 )
                showExecutionTime = true;
            else if ( 'l' == c1 )
                showListing = true;
            else if ( 'm' == c1 )
            {
                g_AssemblyTarget = arm64Mac;
                generateASM = true;
            }
            else if ( 'o' == c1 )
                g_ExpressionOptimization = false;
            else if ( 'p' == c1 )
                showParseTime = true;
            else if ( 'r' == c1 )
                useRegistersInASM = false;
            else if ( 't' == c1 )
                g_Tracing = true;
            else if ( 'x' == c1 )
                executeCode = false;
            else if ( '8' == c1 )
            {
                g_AssemblyTarget = i8080CPM;
                generateASM = true;
            }
            else
                Usage();
        }
        else
        {
            if ( strlen( argv[1] ) >= _countof( inputfile ) )
                Usage();

            strcpy_s( inputfile, _countof( inputfile ), argv[ i ] );
        }
    }

    if ( !inputfile[0] )
    {
        printf( "input file not specified\n" );
        Usage();
    }

    ParseInputFile( inputfile );

    AddENDStatement();

    RemoveREMStatements();

    if ( showListing )
    {
        printf( "lines of code: %zd\n", g_linesOfCode.size() );
    
        for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
            ShowLocListing( g_linesOfCode[ l ] );
    }

    PatchGotoAndGosubNumbers();

    OptimizeWithRewrites( showListing );

    SetFirstTokens();

    // Create all non-array variables and update references so lookups are always fast later

    map<string, Variable> varmap;
    CreateVariables( varmap );

    if ( showParseTime )
    {
        steady_clock::time_point timeParseComplete = steady_clock::now();      
        long long durationParse = duration_cast<std::chrono::nanoseconds>( timeParseComplete - timeAppStart ).count();
        double parseInMS = (double) durationParse / 1000000.0;
        printf( "Time to parse %s: %lf ms\n", inputfile, parseInMS );
    }

    if ( generateASM )
    {
        strcpy_s( asmfile, _countof( asmfile ), inputfile );
        char * dot = strrchr( asmfile, '.' );
        if ( !dot )
            dot = asmfile + strlen( asmfile );

        if ( arm64Mac == g_AssemblyTarget )
            strcpy_s( dot, _countof( asmfile) - ( dot - asmfile ), ".s" );
        else
            strcpy_s( dot, _countof( asmfile) - ( dot - asmfile ), ".asm" );

        GenerateASM( asmfile, varmap, useRegistersInASM );
    }

    if ( executeCode )
        InterpretCode( varmap );
} //main


