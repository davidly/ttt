// a very basic basic interpreter.
// implements a small subset of gw-basic; just enough to run a tic-tac-toe proof of failure app.
// a few limitations:
//    -- based on TRS-80 Model 100 gw-basic.
//    -- only integer variables (4 byte) are supported
//    -- variables can only be two characters long plus a mandatory %
//    -- string values work in PRINT statements and nowhere else
//    -- a new token ELAP$ for PRINT that shows elapsed time including milliseconds
//    -- keywords supported: (see "Operators" below).
//    -- Not supported: DEF, PLAY, OPEN, INKEY$, DATA, READ, and a very long list of others.
//    -- only arrays of 1 and 2 dimensions are supported

#include <stdio.h>
#include <assert.h>

#include <algorithm>
#include <string>
#include <cstring>
#include <cctype>
#include <map>
#include <vector>
#include <chrono>

using namespace std;
using namespace std::chrono;

bool g_Tracing = false;
int g_pc = 0;
struct LineOfCode;
vector<LineOfCode> g_linesOfCode;
#define g_lineno ( g_linesOfCode[ g_pc ].lineNumber )

//#define ENABLE_EXECUTION_TIME
#define EXPRESSION_OPTIMIZATIONS

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
#else
    #include <intrin.h>
#endif

#ifndef _MSC_VER  // g++, clang++
    #define __assume( x )
    #undef __makeinline
    #define __makeinline inline
    #define _strnicmp strncasecmp

    #ifndef _countof
        template < typename T, size_t N > size_t _countof( T ( & arr )[ N ] ) { return std::extent< T[ N ] >::value; }
    #endif
#endif

enum Token : int { VARIABLE, GOSUB, GOTO, PRINT, RETURN, END,                     // statements
                   REM, DIM, CONSTANT, OPENPAREN, CLOSEPAREN,
                   MULT, DIV, PLUS, MINUS, EQ, NE, LE, GE, LT, GT, AND, OR, XOR,  // operators in order of precedence
                   FOR, NEXT, IF, THEN, ELSE, LINENUM, STRING, TO, COMMA,
                   COLON, SEMICOLON, EXPRESSION, TIME, ELAP, TRON, TROFF,
                   ATOMIC, INC, DEC, NOT, INVALID };

const char * Tokens[] = { "VARIABLE", "GOSUB", "GOTO", "PRINT", "RETURN", "END",
                          "REM", "DIM", "CONSTANT", "OPENPAREN", "CLOSEPAREN",
                          "MULT", "DIV", "PLUS", "MINUS", "EQ", "NE", "LE", "GE", "LT", "GT", "AND", "OR", "XOR",
                          "FOR", "NEXT", "IF", "THEN", "ELSE", "LINENUM", "STRING", "TO", "COMMA",
                          "COLON", "SEMICOLON", "EXPRESSION", "TIME$", "ELAP$", "TRON", "TROFF",
                          "ATOMIC", "INC", "DEC", "NOT", "INVALID" };

const char * Operators[] = { "VARIABLE", "GOSUB", "GOTO", "PRINT", "RETURN", "END",
                             "REM", "DIM", "CONSTANT", "(", ")",
                             "*", "/", "+", "-", "=", "<>", "<=", ">=", "<", ">", "&", "|", "^", 
                             "FOR", "NEXT", "IF", "THEN", "ELSE", "LINENUM", "STRING", "TO", "COMMA",
                             "COLON", "SEMICOLON", "EXPRESSION", "TIME$", "ELAP$", "TRON", "TROFF",
                             "ATOMIC", "INC", "DEC", "NOT", "INVALID" };

const int OperatorPrecedence[] = { 0, 0, 0, 0, 0, 0,                          // filler
                                   0, 0, 0, 0, 0,                             // filler
                                   0, 0, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3 };   // actual operators

__makeinline const char * TokenStr( Token i )
{
    if ( i < 0 || i > Token::INVALID )
        printf( "token %d is malformed\n", i );

    return Tokens[ i ];
} //TokenStr

__makeinline const char * OperatorStr( Token t )
{
    return Operators[ t ];
} //OperatorStr

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

__makeinline bool isFirstPassOperator( Token t )
{
    return ( t >= Token::EQ && t <= Token::GT );
} //isFirstPassOperator

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
        *p = tolower( *p );
        p++;
    }
    return str;
}//my_strlwr

struct Variable
{
    Variable( const char * v )
    {
        memset( this, 0, sizeof *this );
        assert( strlen( name ) <= 3 );
        strcpy( name, v );
        my_strlwr( name );
    }

    int value;           // when a scalar
    char name[4];        // variables can only be 2 chars + type + null
    int dimensions;      // 0 for scalar
    int dims[ 2 ];       // only support up to 2 dimensional arrays
    vector<int> array;
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
    int value;
    int dimensions;        // 0 for scalar or 1-2 if an array. Only non-0 for DIM statements
    int dims[ 2 ];         // only support up to 2 dimensional arrays. Only used for DIM statements
    int extra;
    Variable * pVariable;
    string strValue;
};

// maps to a line of BASIC

struct LineOfCode
{
    LineOfCode( int line ) : lineNumber( line ), firstToken( Token::INVALID )

    #ifdef ENABLE_EXECUTION_TIME
        , timesExecuted( 0 ), duration( 0 )
    #endif

    {
        tokenValues.reserve( 8 );
    }

    // These tokens will be scattered through memory. I tried making them all contiguous
    // and there was no performance benefit

    Token firstToken;
    vector<TokenValue> tokenValues;

    int lineNumber;

    #ifdef ENABLE_EXECUTION_TIME
        uint64_t timesExecuted;       // # of times this line is executed
        uint64_t duration;            // execution time so far on this line of code
    #endif
};

struct ParenItem
{
    ParenItem( int op, int off ) : open( op ), offset( off ) {}

    int open;
    int offset;
};

struct ForGosubItem
{
    ForGosubItem( int f, int p )
    {
        isFor = f;
        pcReturn = p;
    }

    int isFor;  // true if FOR, false if GOSUB
    int  pcReturn;
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
    printf( "Usage: ba filename.bas [-e] [-l] [-p] [-t] [-x]\n" );
    printf( "  Basic interpreter\n" );
    printf( "  Arguments:     filename.bas     Subset of TRS-80 compatible BASIC\n" );
    printf( "                 -e               Show execution count and time for each line\n" );
    printf( "                 -l               Show 'pcode' listing\n" );
    printf( "                 -p               Show parse time for input file\n" );
    printf( "                 -t               Show debug tracing\n" );
    printf( "                 -x               Parse only; don't execute the code\n" );

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

        if ( pend )
        {
            len = (int) 1 + ( pend - p );
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
        return Token::VARIABLE;

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

        if ( !_strnicmp( p, "XOR", 3 ) )
            return Token::XOR;

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

void Fail( const char * error, int line, int column, const char * code )
{
    printf( "Error: %s at line %d column %d: %s\n", error, line, column, code );
    exit( 1 );
} //Fail

void RuntimeFail( const char * error, int line )
{
    printf( "Runtime Error: %s at line %d\n", error, line );
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
    int exp = lineTokens.size() - 1;
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
            makelower( tokenValue.strValue );
            lineTokens.push_back( tokenValue );
            pline = pastWhite( pline + tokenLen );
            token = readToken( pline, tokenLen );
            if ( Token::OPENPAREN == token )
            {
                tokenCount++;
                tokenValue.Clear();
                tokenValue.token = token;
                lineTokens.push_back( tokenValue );
                pline += tokenLen;

                int expression = lineTokens.size();

                pline = ParseExpression( lineTokens, pline, line, fileLine );
                tokenCount += lineTokens[ expression ].value;

                token = readToken( pline, tokenLen );
                if ( Token::COMMA == token )
                {
                    tokenCount++;
                    tokenValue.Clear();
                    tokenValue.token = token;
                    lineTokens.push_back( tokenValue );
                    pline = pastWhite( pline + tokenLen );

                    int subexpression = lineTokens.size();
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
            makelower( tokenValue.strValue );
            lineTokens.push_back( tokenValue );

            pline = pastWhite( pline + tokenLen );
            token = readToken( pline, tokenLen );

            if ( Token::OPENPAREN == token )
            {
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

__makeinline Variable * FindVariable( map<string, Variable> & varmap, string const & name )
{
    map<string,Variable>::iterator it;
    it = varmap.find( name );
    if ( it == varmap.end() )
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

template<class T> __makeinline int Reduce( T op_func, int precedence, int * explist, int expcount )
{
    if ( EnableTracing && g_Tracing )
    {
        printf( "Reduce before prec %d count %d ==", precedence, expcount );
        for ( int j = 0; j < expcount; j++ )
            if ( j & 1 )
                printf( " %s(%d)", TokenStr( (Token) explist[ j ] ), explist[ j ] );
            else
                printf( " %d", explist[ j ] );
        printf( "\n" );
    }

    int i = 1;
    while ( i < expcount )
    {
        assert( isTokenOperator( (Token) explist[ i ] ) );

        if ( precedence == OperatorPrecedence[ (Token) explist[ i ] ] )
        {
            explist[ i - 1 ] = op_func( explist[ i - 1 ], (Token) explist[ i ], explist[ i + 1 ] );
            if ( expcount > 3 )
                memmove( &explist[ i ], &explist[ i + 2 ], sizeof( int ) * ( expcount - 3 ) );
            expcount -= 2;
        }
        else
            i += 2;
    }

    if ( EnableTracing && g_Tracing )
    {
        printf( "Reduce after prec %d count %d == ", precedence, expcount );
        for ( int j = 0; j < expcount; j++ )
            if ( j & 1 )
                printf( " %s(%d)", TokenStr( (Token) explist[ j ] ), explist[ j ] );
            else
                printf( " %d", explist[ j ] );
        printf( "\n" );
    }

    return expcount;
} //Reduce

__makeinline int Eval( int * explist, int expcount )
{
    if ( EnableTracing && g_Tracing )
    {
        printf( "Eval expression length %d == ", expcount );
        for ( int j = 0; j < expcount; j++ )
            if ( j & 1 )
                printf( " %s(%d)", TokenStr( (Token) explist[ j ] ), explist[ j ] );
            else
                printf( " %d", explist[ j ] );
        printf( "\n" );
    }

#ifdef EXPRESSION_OPTIMIZATIONS
    if ( 1 == expcount )
    {
        // we're done here
    }
    else if ( 3 == expcount )
    {
        explist[ 0 ] = run_operator( explist[ 0 ], (Token) explist[ 1 ], explist[ 2 ] );
    }
    else if ( 7 == expcount && Token::AND == (Token) explist[ 3 ] )
    {
        explist[ 0 ] = run_operator( explist[ 0 ], (Token) explist[ 1 ], explist[ 2 ] );
        explist[ 4 ] = run_operator( explist[ 4 ], (Token) explist[ 5 ], explist[ 6 ] );
        explist[ 0 ] = explist[ 0 ] & explist[ 4 ];
    }
    else
#endif
    {
        // BASIC doesn't distinguish between logical and bitwise operators. they are the same.

        expcount = Reduce( run_operator_multiplicative, 0, explist, expcount );   // * /
        expcount = Reduce( run_operator_additive,       1, explist, expcount );   // + -
        expcount = Reduce( run_operator_relational,     2, explist, expcount );   // > >= <= < = <>
        expcount = Reduce( run_operator_logical,        3, explist, expcount );   // and or xor

        assert( 1 == expcount );
    }

    if ( EnableTracing && g_Tracing )
        printf( "Eval returning %d\n", explist[ 0 ] );

    return explist[ 0 ];
} //Eval

__makeinline int EvaluateExpression( int iToken, vector<TokenValue> const & vals )
{
    if ( EnableTracing && g_Tracing )
        printf( "evaluateexpression starting at line %d, token %d, which is %s, length %d\n",
                g_lineno, iToken, TokenStr( vals[ iToken ].token ), vals[ iToken ].value );

    assert( Token::EXPRESSION == vals[ iToken ].token );

    int value;
    int tokenCount = vals[ iToken ].value;

    // implement a few specialized/optimized cases in order of usage

#ifdef EXPRESSION_OPTIMIZATIONS
    if ( 2 == tokenCount )
    {
        value = GetSimpleValue( vals[ iToken + 1 ] );
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

        if ( 1 != pvar->dimensions ) // can't be > 1 or tokenCount would be greater
            RuntimeFail( "scalar variable used as an array", g_lineno );

        int offset = GetSimpleValue( vals[ iToken + 4 ] );
        if ( RangeCheckArrays && FailsRangeCheck( offset, pvar->dims[ 0 ] ) )
            RuntimeFail( "index beyond the bounds of an array", g_lineno );

        value = pvar->array[ offset ];
    }
    else if ( 4 == tokenCount )
    {
        assert( isTokenSimpleValue( vals[ iToken + 1 ].token ) );
        assert( isTokenOperator( vals[ iToken + 2 ].token ) );
        assert( isTokenSimpleValue( vals[ iToken + 3 ].token ) );
    
        value = run_operator( GetSimpleValue( vals[ iToken + 1 ] ),
                              vals[ iToken + 2 ].token,
                              GetSimpleValue( vals[ iToken + 3 ] ) );
    }
    else if ( 16 == tokenCount &&
              Token::VARIABLE == vals[ iToken + 1 ].token &&
              Token::OPENPAREN == vals[ iToken + 4 ].token &&
              Token::CONSTANT == vals[ iToken + 6 ].token &&
              Token::VARIABLE == vals[ iToken + 9 ].token &&
              Token::OPENPAREN == vals[ iToken + 12 ].token &&
              Token::CONSTANT == vals[ iToken + 14 ].token &&
              isFirstPassOperator( vals[ iToken + 2 ].token ) &&
              isFirstPassOperator( vals[ iToken + 10 ].token ) )
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
        // this is unlikely to help any other basic app.

        if ( RangeCheckArrays )
        {
            if ( FailsRangeCheck( vals[ iToken + 6 ].value, vals[ iToken + 3 ].pVariable->array.size() ) ||
                 FailsRangeCheck( vals[ iToken + 14 ].value, vals[ iToken + 11 ].pVariable->array.size() ) )
                RuntimeFail( "index beyond the bounds of an array", g_lineno );

            if ( ( 1 != vals[ iToken + 3 ].pVariable->dimensions ) ||
                 ( 1 != vals[ iToken + 11 ].pVariable->dimensions ) )
                RuntimeFail( "variable used as if it has one array dimension when it does not", g_lineno );
        }

        value = run_operator( run_operator( vals[ iToken + 1 ].pVariable->value,
                                            vals[ iToken + 2 ].token,
                                            vals[ iToken + 3 ].pVariable->array[ vals[ iToken + 6 ].value ] ),
                              vals[ iToken + 8 ].token,
                              run_operator( vals[ iToken + 9 ].pVariable->value,
                                            vals[ iToken + 10 ].token,
                                            vals[ iToken + 11 ].pVariable->array[ vals[ iToken + 14 ].value ] ) );
    }
    else if ( 3 == tokenCount )
    {
        if ( Token::NOT == vals[ iToken + 1 ].token )
            value = ! ( vals[ iToken + 2 ].pVariable->value );
        else
        {
            assert( Token::MINUS == vals[ iToken + 1 ].token );
            return - GetSimpleValue( vals[ iToken + 2 ] );
        }
    }
    else
#endif
    {
        // arbitrary expression cases

        const int maxExpression = 60; // given the maximum line length, this is excessive
        int explist[ maxExpression ]; // values even and operators odd
        int expcount = 0;
        Stack<ParenItem> parenStack;
        int tokenCount = vals[ iToken ].value;
        int limit = iToken + tokenCount;
        bool negActive = false;

        for ( int t = iToken + 1; t < limit; t++ )
        {
            TokenValue const & val = vals[ t ];
        
            if ( Token::VARIABLE == val.token )
            {
                Variable *pvar = val.pVariable;
    
                if ( 0 == pvar->dimensions )
                    explist[ expcount++ ] = pvar->value;
                else if ( 1 == pvar->dimensions )
                {
                    t += 2; // variable and openparen

                    int offset;
                    if ( 2 == vals[ t ].value && Token::CONSTANT == vals[ t + 1 ].token ) // save recursion
                        offset = vals[ t + 1 ].value;
                    else
                        offset = EvaluateExpression( t, vals );

                    t += vals[ t ].value;

                    if ( RangeCheckArrays && FailsRangeCheck( offset, pvar->array.size() ) )
                        RuntimeFail( "access of array beyond end", g_lineno );

                    if ( RangeCheckArrays && t < limit && Token::COMMA == vals[ t ].token )
                        RuntimeFail( "accessed 1-dimensional array with 2 dimensions", g_lineno );

                    explist[ expcount++ ] = pvar->array[ offset ];
                }
                else if ( 2 == pvar->dimensions )
                {
                    t += 2; // variable and openparen
                    int offset1 = EvaluateExpression( t, vals );
                    t += vals[ t ].value;

                    if ( RangeCheckArrays && FailsRangeCheck( offset1, pvar->dims[ 0 ] ) )
                        RuntimeFail( "access of first dimension in 2-dimensional array beyond end", g_lineno );

                    assert( Token::COMMA == vals[ t ].token );
                    t++; // comma

                    int offset2 = EvaluateExpression( t, vals );
                    t += vals[ t ].value;

                    if ( RangeCheckArrays && FailsRangeCheck( offset2, pvar->dims[ 1 ] ) )
                        RuntimeFail( "access of second dimension in 2-dimensional array beyond end", g_lineno );

                    int arrayoffset = offset1 * pvar->dims[ 1 ] + offset2;
                    assert( arrayoffset < pvar->array.size() );

                    explist[ expcount++ ] = pvar->array[ arrayoffset ];
                }

                if ( negActive )
                {
                    explist[ expcount - 1 ] = -explist[ expcount - 1 ];
                    negActive = false;
                }
            }
            else if ( isTokenOperator( val.token ) )
            {
                if ( ( Token::MINUS == val.token ) && ( t == ( iToken + 1 ) ) )
                    negActive = true;
                else
                    explist[ expcount++ ] = val.token;
            }
            else if ( Token::EXPRESSION == val.token )
            {
                explist[ expcount++ ] = EvaluateExpression( t, vals );
                t += ( val.value - 1 );
            }
            else if ( Token::CONSTANT == val.token )
            {
                explist[ expcount++ ] = val.value;
            }
            else if ( Token::NOT == val.token )
            {
                explist[ expcount++ ] = ! ( vals[ t + 1 ].pVariable->value );
                t++;
            }
            else if ( Token::OPENPAREN == val.token )
            {
                // point open paren at the first item after the paren

                ParenItem item( true, expcount );
                parenStack.push( item );
            }
            else if ( Token::CLOSEPAREN == val.token )
            {
                // point close parent at the last item before the paren

                ParenItem item( false, expcount - 1 );
                parenStack.push( item );
            }
            else
            {
                printf( "unexpected token: %s\n", TokenStr( val.token ) );
                RuntimeFail( "unexpected token in arbitrary expression evaluation", g_lineno );
            }

            // basic lines can only be so long, so expressions can only be so complex

            assert( expcount < _countof( explist ) );
        }

        // collapse portions with parenthesis to a single constant right to left

        assert( "expression count should be odd" && ( expcount & 1 ) );

        if ( EnableTracing && g_Tracing )
            printf( "parenStack.size(): %zd, expcount %d\n", parenStack.size(), expcount );

        if ( 0 != parenStack.size() )
        {
            Stack<ParenItem> closeStack;

            do
            {
                ParenItem & item = parenStack.top();
    
                if ( item.open )
                {
                    if ( 0 == closeStack.size() )
                        RuntimeFail( "mismatched parenthesis; too many opens", g_lineno );
    
                    ParenItem & closed = closeStack.top();
                    int closeLocation = closed.offset;
                    int length = closed.offset - item.offset + 1;

                    if ( EnableTracing && g_Tracing )
                        printf( "  closed.offset %d, open.offset = %d, length = %d, expcount %d\n", closed.offset, item.offset, length, expcount );
    
                    closeStack.pop();
    
                    Eval( explist + item.offset, length );
    
                    int numToCopy = ( expcount - closeLocation - 1 );

                    if ( EnableTracing && g_Tracing )
                        printf( "  numtocopy %d\n", numToCopy );
    
                    if ( numToCopy )
                        memmove( explist + item.offset + 1,
                                 explist + item.offset + length,
                                 sizeof( int ) * ( numToCopy ) );
    
                    int removed = length - 1;
                    for ( int i = 0; i < closeStack.size(); i++ )
                        closeStack[ i ].offset -= removed;
    
                    expcount -= removed;
                }
                else
                {
                    closeStack.push( item );
                }
    
                parenStack.pop();
            } while ( 0 != parenStack.size() );
    
            if ( 0 != closeStack.size() )
                RuntimeFail( "mismatched parenthesis; too many closes", g_lineno );
        }

        assert( "expression count should be odd" && ( expcount & 1 ) );

        // Everything left is "constant (operator constant)*"

        value = Eval( explist, expcount );
    }

    if ( EnableTracing && g_Tracing )
        printf( "returning expression value %d, tokens consumed %d\n", value, tokenCount );

    return value;
} //EvaluateExpression

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
    printf( "line %d has %zd tokens\n", loc.lineNumber, loc.tokenValues.size() );
    
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
    // 1st pass: move goto/gosub targets to the first following non-REM statement 

    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];

        for ( size_t t = 0; t < loc.tokenValues.size(); t++ )
        {
            TokenValue & tv = loc.tokenValues[ t ];
            bool found = false;

            if ( Token::GOTO == tv.token || Token::GOSUB == tv.token )
            {
                int reference = tv.value;

                for ( size_t lo = 0; lo < g_linesOfCode.size(); lo++ )
                {
                    if ( ( g_linesOfCode[ lo ].lineNumber == tv.value ) &&
                         ( Token::REM == g_linesOfCode[ lo ].tokenValues[ 0 ].token ) )
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

    int endloc = g_linesOfCode.size();
    size_t curloc = 0;

    while ( curloc < endloc )
    {
        LineOfCode & loc = g_linesOfCode[ curloc ];

        if ( Token::REM == loc.tokenValues[ 0 ].token ) 
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
        LineOfCode loc( linenumber );
        g_linesOfCode.push_back( loc );
        TokenValue tokenValue( Token::END );
        g_linesOfCode[ g_linesOfCode.size() - 1 ].tokenValues.push_back( tokenValue );
    }
} //AddENDStatement

void PatchGOTOGOSUBNumbers()
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
                        tv.value = lo;
                        found = true;
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
} //PatchGOTOGOSUBNumbers

void OptimizeWithRewrites( bool showListing )
{
    for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
    {
        LineOfCode & loc = g_linesOfCode[ l ];
        vector<TokenValue> & vals = loc.tokenValues;
        bool rewritten = false;

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
                 ( Token::VARIABLE == tv.token && 0 == tv.dimensions ) || // wait for arrays to be defined at runtime with DIM
                 ( Token::FOR == tv.token ) )
                GetVariablePerhapsCreate( tv, varmap );
        }
    }
} //CreateVariables

extern int main( int argc, char *argv[] )
{
    steady_clock::time_point timeAppStart = steady_clock::now();

    // validate the parallel arrays and enum are actually parallel

    assert( ( Token::INVALID + 1 ) == _countof( Tokens ) );
    assert( ( Token::INVALID + 1 ) == _countof( Operators ) );
    assert( 3 == OperatorPrecedence[ Token::AND ] );
    assert( 3 == OperatorPrecedence[ Token::OR ] );
    assert( 3 == OperatorPrecedence[ Token::XOR ] );
    assert( 0 == OperatorPrecedence[ Token::MULT ] );
    assert( 0 == OperatorPrecedence[ Token::DIV ] );

    assert( 64 == sizeof( TokenValue ) );

    bool showListing = false;
    bool executeCode = true;
    bool showExecutionTime = false;
    bool showParseTime = false;
    static char inputfile[ 300 ] = {0};

    for ( int i = 1; i < argc; i++ )
    {
        char * parg = argv[ i ];
        int arglen = strlen( parg );
        char c0 = parg[ 0 ];
        char c1 = tolower( parg[ 1 ] );

        if ( '-' == c0 || '/' == c0 )
        {
            if ( 'e' == c1 )
                showExecutionTime = true;
            else if ( 'l' == c1 )
                showListing = true;
            else if ( 'p' == c1 )
                showParseTime = true;
            else if ( 't' == c1 )
                g_Tracing = true;
            else if ( 'x' == c1 )
                executeCode = false;
            else
                Usage();
        }
        else
        {
            if ( strlen( argv[1] ) >= _countof( inputfile ) )
                Usage();

            strcpy( inputfile, argv[ i ] );
        }
    }

    if ( !inputfile[0] )
    {
        printf( "input file not specified\n" );
        Usage();
    }

    CFile fileInput( fopen( inputfile, "rb" ) );
    if ( NULL == fileInput.get() )
    {
        printf( "can't open file %s\n", inputfile );
        Usage();
    }

    printf( "running input file %s\n", inputfile );

    long filelen = portable_filelen( fileInput.get() );
    vector<char> input( filelen + 1 );
    long lread = fread( input.data(), filelen, 1, fileInput.get() );
    if ( 1 != lread )
    {
        printf( "unable to read input file\n" );
        return 0;
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

            LineOfCode loc( lineNum );
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
                int ifOffset = lineTokens.size() - 1;
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
                int thenOffset = lineTokens.size();
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
                    lineTokens[ thenOffset ].value = lineTokens.size() - thenOffset - 1;
                    
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

    AddENDStatement();
    RemoveREMStatements();

    if ( showListing )
    {
        printf( "lines of code: %zd\n", g_linesOfCode.size() );
    
        for ( size_t l = 0; l < g_linesOfCode.size(); l++ )
            ShowLocListing( g_linesOfCode[ l ] );
    }

    PatchGOTOGOSUBNumbers();
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

    if ( !executeCode )
        exit( 0 );

    // interpret the code

    static Stack<ForGosubItem> forGosubStack;
    int pcPrevious = 0;
    int countOfLines = g_linesOfCode.size();
    bool basicTracing = false;
    g_pc = 0;  // program counter

    #ifdef ENABLE_EXECUTION_TIME
        g_linesOfCode[ 0 ].timesExecuted--; // avoid off by 1 on first iteration of loop
    #endif

    uint64_t timePrevious = __rdtsc();
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
        #endif

        vector<TokenValue> const & vals = g_linesOfCode[ g_pc ].tokenValues;
        Token token = g_linesOfCode[ g_pc ].firstToken;
        int t = 0;

        if ( EnableTracing && basicTracing )
            printf( "executing line %d\n", g_lineno );

        do
        {
            if ( EnableTracing && g_Tracing )
                printf( "executing pc %d line number %d, token %d: %s\n", g_pc, g_lineno, t, TokenStr( token ) );

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
                int val = EvaluateExpression( t, vals );
                t += vals[ t ].value;
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
                    assert( ( 0 != pvar ) && "array variable not defined yet" );

                    if ( 0 == pvar->dimensions )
                        RuntimeFail( "variable used as array isn't an array", g_lineno );

                    t++;
                    int arrayIndex = EvaluateExpression( t, vals );
                    t += vals[ t ].value;

                    if ( RangeCheckArrays && FailsRangeCheck( arrayIndex, pvar->dims[ 0 ] ) )
                        RuntimeFail( "array offset out of bounds", g_lineno );

                    if ( Token::COMMA == vals[ t ].token )
                    {
                        t++;

                        if ( 2 != pvar->dimensions )
                            RuntimeFail( "single-dimensional array used with 2 dimensions", g_lineno );

                        int indexB = EvaluateExpression( t, vals );
                        t += vals[ t ].value;

                        if ( RangeCheckArrays && FailsRangeCheck( indexB, pvar->dims[ 1 ] ) )
                            RuntimeFail( "second dimension array offset out of bounds", g_lineno );

                        arrayIndex *= pvar->dims[ 1 ];
                        arrayIndex +=  indexB;
                    }

                    assert( Token::CLOSEPAREN == vals[ t ].token );
                    assert( Token::EQ == vals[ t + 1 ].token );

                    t += 2; // past ) and =
                    int val = EvaluateExpression( t, vals );
                    t += vals[ t ].value;

                    pvar->array[ arrayIndex ] = val;
                }
                else
                {
                    assert( Token::EQ == vals[ t ].token );

                    t++;
                    int val = EvaluateExpression( t, vals );
                    t += vals[ t ].value;

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
                    pvar->value = EvaluateExpression( t + 1, vals );

                int tokens = vals[ t + 1 ].value;
                int endValue = EvaluateExpression( t + 1 + tokens, vals );

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
                        int val = EvaluateExpression( t, vals );
                        t += vals[ t ].value;
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
    
                    for ( size_t t = 0; t < lineOC.tokenValues.size(); t++ )
                    {
                        TokenValue & tv = lineOC.tokenValues[ t ];
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
    #endif

    printf( "exiting the basic interpreter\n" );
} //main
