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
#include <map>
#include <vector>
#include <chrono>

using namespace std;
using namespace std::chrono;

bool g_Tracing = false;

const bool EnableExecutionTime = false; // makes everything 5% slower

#ifdef DEBUG
    const bool RangeCheckArrays = true;
    const bool EnableTracing = true;

    #define __makeinline __declspec(noinline)
    //#define __makeinline
#else
    const bool RangeCheckArrays = false;
    const bool EnableTracing = false; // makes eveything 10% slower

    #define __makeinline __forceinline
    //#define __makeinline
#endif

#define EXPRESSION_OPTIMIZATIONS

enum Token : int { VARIABLE, GOSUB, GOTO, PRINT, RETURN, END,                     // statements
                   REM, DIM, CONSTANT, OPENPAREN, CLOSEPAREN,
                   MULT, DIV, PLUS, MINUS, EQ, NE, LE, GE, LT, GT, AND, OR, XOR,  // operators in order of precedence
                   FOR, NEXT, IF, THEN, ELSE, LINENUM, STRING, TO, COMMA,
                   COLON, SEMICOLON, EXPRESSION, ENDIF, TIME, ELAP, TRON, TROFF,
                   ATOMIC, INC, DEC, NOT, INVALID };

const char * Tokens[] = { "VARIABLE", "GOSUB", "GOTO", "PRINT", "RETURN", "END",
                          "REM", "DIM", "CONSTANT", "OPENPAREN", "CLOSEPAREN",
                          "MULT", "DIV", "PLUS", "MINUS", "EQ", "NE", "LE", "GE", "LT", "GT", "AND", "OR", "XOR",
                          "FOR", "NEXT", "IF", "THEN", "ELSE", "LINENUM", "STRING", "TO", "COMMA",
                          "COLON", "SEMICOLON", "EXPRESSION", "ENDIF", "TIME$", "ELAP$", "TRON", "TROFF",
                          "ATOMIC", "INC", "DEC", "NOT", "INVALID" };

const char * Operators[] = { "VARIABLE", "GOSUB", "GOTO", "PRINT", "RETURN", "END",
                             "REM", "DIM", "CONSTANT", "(", ")",
                             "*", "/", "+", "-", "=", "<>", "<=", ">=", "<", ">", "&", "|", "^", 
                             "FOR", "NEXT", "IF", "THEN", "ELSE", "LINENUM", "STRING", "TO", "COMMA",
                             "COLON", "SEMICOLON", "EXPRESSION", "ENDIF", "TIME$", "ELAP$", "TRON", "TROFF",
                             "ATOMIC", "INC", "DEC", "NOT", "INVALID" };

const int OperatorPrecedence[] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,           // filler
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

bool isFirstPassOperator( Token t )
{
    return ( t >= Token::EQ && t <= Token::GT );
} //isFirstPassOperator

struct Variable
{
    Variable( const char * v )
    {
        memset( this, 0, sizeof *this );
        strcpy( name, v );
        strlwr( name );
    }

    int value;           // when a scalar
    char name[4];        // variables can only be 2 chars + type + null
    int dimensions;      // 0 for scalar
    short dims[ 2 ];     // only support up to 2 dimensional arrays
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
    }

    TokenValue( Token t )
    {
        Clear();
        token = t;
    } //TokenValue

    Token token;
    int value;
    int dimensions;    // 0 for scalar or 1-2 if an array
    short dims[ 2 ];   // only support up to 2 dimensional arrays
    Variable * pVariable;
    string strValue;
};

// maps to a line of BASIC

struct LineOfCode
{
    LineOfCode( int line ) : lineNumber( line ), timesExecuted( 0 ), duration( 0 )
    {
        tokenValues.reserve( 8 );
    }

    int lineNumber;
    vector<TokenValue> tokenValues;

    long long timesExecuted;
    long long duration;   // execution time so far on this line of code
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
        pc = p;
    }

    int  pc;
    int isFor;  // true if FOR, false if GOSUB
};

// this is faster than both <stack> and Stack using <vector> to implement a stack because there are no memory allocations.

const int maxStack = 100;

template <class T> class Stack
{
    int current;
    union { T items[ maxStack ]; };  // avoid constructors and destructors on each T
    // T items[ maxStack ];

    public:
        Stack() : current( 0 ) {}
        void push( T & x ) { assert( current < maxStack ); items[ current++ ] = x; }
        size_t size() { return current; }
        void pop() { assert( current > 0 ); current--; }
        T & top() { assert( current > 0 ); return items[ current - 1 ]; }
        T & operator[] ( size_t i ) { return items[ i ]; }
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
    printf( "Usage: ba filename.bas%s [-l]%s [-x]\n",
            EnableExecutionTime ? " [e]" : "",
            EnableTracing ? " [t]" : "" );
    printf( "  Basic interpreter\n" );
    printf( "  Arguments:     filename.bas     Subset of TRS-80 compatible BASIC\n" );
    if ( EnableExecutionTime )
        printf( "                 -e               Show execution count and time for each line\n" );
    printf( "                 -l               Show 'pcode' listing\n" );
    if ( EnableTracing )
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

    if ( !strnicmp( p, "TIME$", 5 ) )
    {
       len = 5;
       return Token::TIME;
    }

    if ( !strnicmp( p, "ELAP$", 5 ) )
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
        if ( !strnicmp( p, "OR", 2 ) )
            return Token::OR;

        if ( !strnicmp( p, "IF", 2 ) )
            return Token::IF;

        if ( !strnicmp( p, "TO", 2 ) )
            return Token::TO;

        if ( isAlpha( *p ) && ( '%' == * ( p + 1 ) ) )
            return Token::VARIABLE;
    }
    else if ( 3 == len )
    {
        if ( !strnicmp( p, "REM", 3 ) )
            return Token::REM;

        if ( !strnicmp( p, "DIM", 3 ) )
           return Token::DIM;

        if ( !strnicmp( p, "AND", 3 ) )
           return Token::AND;

        if ( !strnicmp( p, "FOR", 3 ) )
           return Token::FOR;

        if ( !strnicmp( p, "END", 3 ) )
           return Token::END;

        if ( !strnicmp( p, "XOR", 3 ) )
            return Token::XOR;

        if ( isAlpha( *p ) && isAlpha( * ( p + 1 ) ) && ( '%' == * ( p + 2 ) ) )
           return Token::VARIABLE;
    }
    else if ( 4 == len )
    {
        if ( !strnicmp( p, "GOTO", 4 ) )
           return Token::GOTO;

        if ( !strnicmp( p, "NEXT", 4 ) )
           return Token::NEXT;

        if ( !strnicmp( p, "THEN", 4 ) )
           return Token::THEN;

        if ( !strnicmp( p, "ELSE", 4 ) )
           return Token::ELSE;

        if ( !strnicmp( p, "TRON", 4 ) )
           return Token::TRON;
    }
    else if ( 5 == len )
    {
        if ( !strnicmp( p, "GOSUB", 5 ) )
           return Token::GOSUB;

        if ( !strnicmp( p, "PRINT", 5 ) )
           return Token::PRINT;

        if ( !strnicmp( p, "TROFF", 5 ) )
           return Token::TROFF;
    }

    else if ( 6 == len )
    {
        if ( !strnicmp( p, "RETURN", 5 ) )
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

void ListVariables( vector<Variable> & variables )
{
    for ( size_t i = 0; i < variables.size(); i++ )
    {
        Variable v = variables[ i ];

        printf( "variable %zd, name '%s', value %d\n", i, v.name, v.value );
    }
} //ListVariables

__makeinline Variable * FindVariable( map<string, Variable> & varmap, string const & name )
{
    map<string,Variable>::iterator it;
    it = varmap.find( name );
    if ( it == varmap.end() )
        return 0;

    return & it->second;
} //FindVariable

__makeinline Variable * FindKnownVariable( TokenValue & val, map<string, Variable> & varmap )
{
    Variable *pvar = val.pVariable;
    if ( pvar )
        return pvar;

    pvar = FindVariable( varmap, val.strValue );
    if ( !pvar )
        RuntimeFail( "array variable used but not declared with a DIM", 0 );
    val.pVariable = pvar;

    return pvar;
} //FindKnownVariable

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

__makeinline int GetVariableValue( TokenValue & val, map<string, Variable> & varmap )
{
    assert( Token::VARIABLE == val.token );

    Variable * pvar = GetVariablePerhapsCreate( val, varmap );
    return val.pVariable->value;
} //GetVariableValue

__makeinline int GetKnownVariableValue( TokenValue & val, map<string, Variable> & varmap )
{
    assert( Token::VARIABLE == val.token );

    Variable * pvar = FindKnownVariable( val, varmap );
    return val.pVariable->value;
} //GetKnownVariableValue

__makeinline int GetSimpleValue( TokenValue & val, map<string, Variable> & varmap )
{
    assert( isTokenSimpleValue( val.token ) );

    if ( Token::CONSTANT == val.token )
        return val.value;

    return GetVariableValue( val, varmap );
} //GetSimpleValue

__makeinline int run_operator( int a, Token t, int b )
{
    switch( t )
    {
        case Token::EQ    : return ( a == b );
        case Token::AND   : return ( a & b );
        case Token::LT    : return ( a < b );
        case Token::PLUS  : return ( a + b );
        case Token::NE    : return ( a != b );
        case Token::GT    : return ( a > b );
        case Token::GE    : return ( a >= b );
        case Token::MINUS : return ( a - b );
        case Token::OR    : return ( a | b );
        case Token::LE    : return ( a <= b );
        case Token::MULT  : return ( a * b );
        case Token::DIV   : return ( a / b );
        case Token::XOR   : return ( a ^ b );
    }

    assert( !"invalid operator token" );
    return 0;
} //run_operator

__makeinline int run_operator_p3( int a, Token t, int b )
{
    switch( t )
    {
        case Token::AND   : return ( a & b );
        case Token::OR    : return ( a | b );
        case Token::XOR   : return ( a ^ b );
    }

    assert( !"invalid p3 operator token" );
    return 0;
} //run_operator_p3

__makeinline int run_operator_p2( int a, Token t, int b )
{
    switch( t )
    {
        case Token::EQ    : return ( a == b );
        case Token::LT    : return ( a < b );
        case Token::NE    : return ( a != b );
        case Token::GT    : return ( a > b );
        case Token::GE    : return ( a >= b );
        case Token::OR    : return ( a | b );
        case Token::LE    : return ( a <= b );
    }

    assert( !"invalid p2 operator token" );
    return 0;
} //run_operator_p2

__makeinline int run_operator_p1( int a, Token t, int b )
{
    switch( t )
    {
        case Token::PLUS  : return ( a + b );
        case Token::MINUS : return ( a - b );
    }

    assert( !"invalid p1 operator token" );
    return 0;
} //run_operator_p1

__makeinline int run_operator_p0( int a, Token t, int b )
{
    switch( t )
    {
        case Token::MULT  : return ( a * b );
        case Token::DIV   : return ( a / b );
    }

    assert( !"invalid p0 operator token" );
    return 0;
} //run_operator_p0

typedef int (*operator_func)( int a, Token t, int b );

//
// precedence: in parens first (not implemented yet)
//         0    multiplication and division left to right
//         1    addition and subtraction left to right
//         2    relational > < >= <= = left to right
//         3    and and or left to right
//           

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
        expcount = Reduce( run_operator_p0, 0, explist, expcount );
        expcount = Reduce( run_operator_p1, 1, explist, expcount );
        expcount = Reduce( run_operator_p2, 2, explist, expcount );
        expcount = Reduce( run_operator_p3, 3, explist, expcount );

        assert( 1 == expcount );
    }

    if ( EnableTracing && g_Tracing )
        printf( "Eval returning %d\n", explist[ 0 ] );

    return explist[ 0 ];
} //Eval

__makeinline int EvaluateExpression( int iToken, vector<TokenValue> & vals, map<string, Variable> & varmap, int line )
{
    if ( EnableTracing && g_Tracing )
        printf( "evaluateexpression starting at line %d, token %d, which is %s, length %d\n",
                line, iToken, TokenStr( vals[ iToken ].token ), vals[ iToken ].value );

    assert( Token::EXPRESSION == vals[ iToken ].token );

    int value;
    int tokenCount = vals[ iToken ].value;

    // implement a few specialized/optimized cases, but most are general

#ifdef EXPRESSION_OPTIMIZATIONS
    if ( 2 == tokenCount )
        value = GetSimpleValue( vals[ iToken + 1 ], varmap );
    else if ( 3 == tokenCount )
    {
        if ( Token::NOT == vals[ iToken + 1 ].token )
            value = ! GetVariableValue( vals[ iToken + 2 ], varmap );
        else
        {
            assert( Token::MINUS == vals[ iToken + 1 ].token );
            return - GetSimpleValue( vals[ iToken + 2 ], varmap );
        }
    }
    else if ( 4 == tokenCount )
    {
        assert( isTokenSimpleValue( vals[ iToken + 1 ].token ) );
        assert( isTokenOperator( vals[ iToken + 2 ].token ) );
        assert( isTokenSimpleValue( vals[ iToken + 3 ].token ) );
    
        value = run_operator( GetSimpleValue( vals[ iToken + 1 ], varmap ),
                              vals[ iToken + 2 ].token,
                              GetSimpleValue( vals[ iToken + 3 ], varmap ) );
    }
    else if ( 6 == tokenCount &&
              Token::VARIABLE == vals[ iToken + 1 ].token &&
              Token::OPENPAREN == vals[ iToken + 2 ].token )
    {
        // 0 token EXPRESSION, value 6, strValue ''
        // 1 token VARIABLE, value 0, strValue 'sa%'
        // 2 token OPENPAREN, value 0, strValue ''
        // 3 token EXPRESSION, value 2, strValue ''
        // 4 token VARIABLE, value 0, strValue 'st%'   (this can optionally be a constant)
        // 5 token CLOSEPAREN, value 0, strValue ''

        Variable *pvar = FindKnownVariable( vals[ iToken + 1 ], varmap );
        if ( 1 != pvar->dimensions )
            RuntimeFail( "expecting a 1-dimensional array", line );

        int offset = GetSimpleValue( vals[ iToken + 4 ], varmap );
        if ( RangeCheckArrays && offset >= pvar->array.size() )
            RuntimeFail( "index beyond the bounds of an array", line );

        value = pvar->array[ offset ];
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
            TokenValue & val = vals[ t ];
        
            if ( Token::VARIABLE == val.token )
            {
                Variable *pvar = FindKnownVariable( val, varmap );
    
                if ( 0 == pvar->dimensions )
                    explist[ expcount++ ] = pvar->value;
                else if ( 1 == pvar->dimensions )
                {
                    t += 2; // variable and openparen

                    int offset;
                    if ( 2 == vals[ t ].value && Token::CONSTANT == vals[ t + 1 ].token ) // save recursion
                        offset = vals[ t + 1 ].value;
                    else
                        offset = EvaluateExpression( t, vals, varmap, line );

                    t += vals[ t ].value;

                    if ( RangeCheckArrays && offset >= pvar->array.size() )
                        RuntimeFail( "access of array beyond end", line );

                    if ( RangeCheckArrays && t < limit && Token::COMMA == vals[ t ].token )
                        RuntimeFail( "accessed 1-dimensional array with 2 dimensions", line );

                    explist[ expcount++ ] = pvar->array[ offset ];
                }
                else if ( 2 == pvar->dimensions )
                {
                    t += 2; // variable and openparen
                    int offset1 = EvaluateExpression( t, vals, varmap, line );
                    t += vals[ t ].value;

                    if ( RangeCheckArrays && offset1 > pvar->dims[ 0 ] )
                        RuntimeFail( "access of first dimension in 2-dimensional array beyond end", line );

                    assert( Token::COMMA == vals[ t ].token );
                    t++; // comma

                    int offset2 = EvaluateExpression( t, vals, varmap, line );
                    t += vals[ t ].value;

                    if ( RangeCheckArrays && offset2 > pvar->dims[ 1 ] )
                        RuntimeFail( "access of second dimension in 2-dimensional array beyond end", line );

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
                explist[ expcount++ ] = EvaluateExpression( t, vals, varmap, line );
                t += ( val.value - 1 );
            }
            else if ( Token::CONSTANT == val.token )
            {
                explist[ expcount++ ] = val.value;
            }
            else if ( Token::NOT == val.token )
            {
                explist[ expcount++ ] = ! GetVariableValue( vals[ t + 1 ], varmap );
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
                RuntimeFail( "unexpected token in arbitrary expression evaluation", line );
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
                        RuntimeFail( "mismatched parenthesis; too many opens", line );
    
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
                RuntimeFail( "mismatched parenthesis; too many closes", line );
        }

        assert( "expression count should be odd" && ( expcount & 1 ) );

        // Everything left is "constant (operator constant)*"

        value = Eval( explist, expcount );
    }

    if ( EnableTracing && g_Tracing )
        printf( "returning expression value %d, tokens consumed %d\n", value, tokenCount );

    return value;
} //EvaluateExpression

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

void ShowLocListing( LineOfCode & loc )
{
    printf( "%d has %zd tokens\n", loc.lineNumber, loc.tokenValues.size() );
    
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

extern "C" int __cdecl main( int argc, char *argv[] )
{
    assert( ( Token::INVALID + 1 ) == _countof( Tokens ) );
    assert( ( Token::INVALID + 1 ) == _countof( Operators ) );

    bool showListing = false;
    bool executeCode = true;
    bool showExecutionTime = false;
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
    const int MaxDictionaryLineLen = _countof( line ) - 1;
    int fileLine = 0;
    vector<LineOfCode> linesOfCode;
    int prevLineNum = 0;

    while ( pbuf < pbeyond )
    {
        int len = 0;
        while ( ( pbuf < pbeyond ) && ( ( *pbuf != 10 ) && ( *pbuf != 13 ) ) && ( len < MaxDictionaryLineLen ) )
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

            //printf( "line: %s\n", line );
            //printf( "first token: %d %s\n", token, TokenStr( token ) );
            LineOfCode loc( lineNum );
            linesOfCode.push_back( loc );

            TokenValue tokenValue( token );
            vector<TokenValue> & lineTokens = linesOfCode[ linesOfCode.size() - 1 ].tokenValues;

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
                    //lineTokens[ thenOffset ].value = lineTokens.size() - 1;
                    lineTokens[ thenOffset ].value = lineTokens.size() - thenOffset - 1;
                    
                    pline = pastWhite( pline + tokenLen );
                    token = readToken( pline, tokenLen );
                    pline = ParseStatements( token, lineTokens, pline, line, fileLine );
                    if ( Token::ELSE == lineTokens[ lineTokens.size() - 1 ].token )
                        Fail( "expected a statement after an ELSE", fileLine, 1 + pline - line, line );
                }

                tokenValue.Clear();
                tokenValue.token = Token::ENDIF;
                lineTokens.push_back( tokenValue );
            }
            else if ( Token::REM == token )
            {
                // can't just throw out REM statements because a goto/gosub may reference it

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

    if ( showListing )
    {
        printf( "lines of code: %zd\n", linesOfCode.size() );
    
        for ( size_t l = 0; l < linesOfCode.size(); l++ )
        {
            LineOfCode & loc = linesOfCode[ l ];

            ShowLocListing( loc );
        }
    }

    // patch goto/gosub line numbers with actual offsets to remove runtime searches

    for ( size_t l = 0; l < linesOfCode.size(); l++ )
    {
        LineOfCode & loc = linesOfCode[ l ];
    
        for ( size_t t = 0; t < loc.tokenValues.size(); t++ )
        {
            TokenValue & tv = loc.tokenValues[ t ];
            bool found = false;

            if ( Token::GOTO == tv.token || Token::GOSUB == tv.token )
            {
                for ( size_t lo = 0; lo < linesOfCode.size(); lo++ )
                {
                    if ( linesOfCode[ lo ].lineNumber == tv.value )
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

    // optimize the code

    for ( size_t l = 0; l < linesOfCode.size(); l++ )
    {
        LineOfCode & loc = linesOfCode[ l ];
        vector<TokenValue> & vals = loc.tokenValues;
        bool rewritten = false;

        // if 0 <> EXPRESSION   ========>>>>>>>>  if EXPRESSION
        // 4180 has 12 tokens
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
        //   token  11 ENDIF, value 0, strValue ''

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

        // VARIABLE = VARIABLE - 1  =============>  ATOMIC INC VARIABLE
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
        // 2410 has 8 tokens
        //   token   0 IF, value 0, strValue ''
        //   token   1 EXPRESSION, value 4, strValue ''
        //   token   2 CONSTANT, value 0, strValue ''
        //   token   3 EQ, value 0, strValue ''
        //   token   4 VARIABLE, value 0, strValue 'wi%'
        //   token   5 THEN, value 0, strValue ''
        //   token   6 GOTO, value 2500, strValue ''
        //   token   7 ENDIF, value 0, strValue ''
        else if ( 8 == vals.size() &&
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

    if ( !executeCode )
        exit( 0 );

    // interpret the code

    high_resolution_clock::time_point timeBegin = high_resolution_clock::now();      

    map<string, Variable> varmap;
    Stack<ForGosubItem> forGosubStack;
    int pc = 0;
    int pcPrevious = 0;
    int countOfLines = linesOfCode.size();
    bool basicTracing = false;
    high_resolution_clock::time_point timePrevious = timeBegin;

    do
    {
        if ( EnableExecutionTime && showExecutionTime )
        {
            high_resolution_clock::time_point timeNow = high_resolution_clock::now();
            linesOfCode[ pcPrevious ].duration += duration_cast<std::chrono::nanoseconds>( timeNow - timePrevious ).count();
            linesOfCode[ pcPrevious ].timesExecuted++;
            timePrevious = timeNow;
            pcPrevious = pc;
        }

        if ( pc >= countOfLines )
            break;

        LineOfCode & loc = linesOfCode[ pc ];
        vector<TokenValue> & vals = loc.tokenValues;
        int line = loc.lineNumber;
        int t = 0;

        if ( EnableTracing && basicTracing )
            printf( "executing line %d\n", line );

        do
        {
            Token token = vals[ t ].token;

            if ( EnableTracing && g_Tracing )
                printf( "executing pc %d line number %d, token %d: %s\n", pc, line, t, TokenStr( vals[ t ].token ) );

            if ( Token::IF == token )
            {
                t++;
                int val = EvaluateExpression( t, vals, varmap, line );
                t += vals[ t ].value;
                assert( Token::THEN == vals[ t ].token );

                if ( val )
                {
                    t++;
                }
                else
                {
                    int elseOffset = vals[ t ].value;

                    if ( 0 == elseOffset )
                    {
                        pc++;
                        break;
                    }
                    else
                    {
                        assert( Token::ELSE == vals[ t + elseOffset ].token );
                        t += ( elseOffset + 1 );
                    }
                }
            }
            else if ( Token::VARIABLE == token )
            {
                t++;

                if ( Token::OPENPAREN == vals[ t ].token )
                {
                    Variable *pvar = vals[ t - 1 ].pVariable;
                    if ( !pvar )
                    {
                        pvar = FindVariable( varmap, vals[ t - 1 ].strValue );
                        vals[ t - 1 ].pVariable = pvar;
                    }

                    if ( 0 == pvar )
                        RuntimeFail( "array usage without DIM", line );

                    if ( 0 == pvar->dimensions )
                        RuntimeFail( "variable used as array isn't an array", line );

                    t++;
                    int indexA = EvaluateExpression( t, vals, varmap, line );
                    t += vals[ t ].value;

                    if ( RangeCheckArrays && indexA >= pvar->dims[ 0 ] )
                        RuntimeFail( "array offset out of bounds", line );

                    int arrayIndex;

                    if ( Token::COMMA == vals[ t ].token )
                    {
                        t++;

                        if ( 2 != pvar->dimensions )
                            RuntimeFail( "single-dimensional array used with 2 dimensions", line );

                        int indexB = EvaluateExpression( t, vals, varmap, line );
                        t += vals[ t ].value;

                        if ( RangeCheckArrays && indexB >= pvar->dims[ 1 ] )
                            RuntimeFail( "second dimension array offset out of bounds", line );

                        arrayIndex = indexA * pvar->dims[ 1 ] + indexB;
                    }
                    else
                        arrayIndex = indexA;

                    t += 2; // past ) and =
                    int val = EvaluateExpression( t, vals, varmap, line );
                    t += vals[ t ].value;

                    pvar->array[ arrayIndex ] = val;
                }
                else if ( Token::EQ == vals[ t ].token )
                {
                    t++;
                    int val = EvaluateExpression( t, vals, varmap, line );

                    Variable * pvar = GetVariablePerhapsCreate( vals[ t - 2 ], varmap );

                    if ( RangeCheckArrays && ( 0 != pvar->dimensions ) )
                        RuntimeFail( "array used as if it's a scalar", line );

                    t += vals[ t ].value;

                    pvar->value = val;
                }
                else
                    RuntimeFail( "( or = expected after a variable", line );

                // have we consumed all tokens in the instruction?

                if ( t == vals.size() )
                {
                    pc++;
                    break;
                }
            }
            else if ( Token::ELSE == token || Token::ENDIF == token )
            {
                pc++;
                break;
            }
            else if ( Token::GOSUB == token )
            {
                ForGosubItem fgi( false, pc + 1 );
                forGosubStack.push( fgi );

                pc = loc.tokenValues[ t ].value;
                break;
            }
            else if ( Token::GOTO == token )
            {
                pc = loc.tokenValues[ t ].value;
                break;
            }
            else if ( Token::RETURN == token )
            {
                do 
                {
                    if ( 0 == forGosubStack.size() )
                        RuntimeFail( "return without gosub", line );

                    // remove any active FOR items to get to the next GOSUB item and return

                    ForGosubItem & item = forGosubStack.top();
                    forGosubStack.pop();
                    if ( !item.isFor )
                    {
                        pc = item.pc;
                        break;
                    }
                } while( true );

                break;
            }
            else if ( Token::FOR == token )
            {
                bool continuation = false;

                if  ( forGosubStack.size() >  0 )
                {
                    ForGosubItem & item = forGosubStack.top();
                    if ( item.isFor && item.pc == pc )
                        continuation = true;
                }

                Variable * pvar = GetVariablePerhapsCreate( vals[ 0 ], varmap );

                if ( continuation )
                    pvar->value += 1;
                else
                    pvar->value = EvaluateExpression( t + 1, vals, varmap, line );

                int tokens = vals[ t + 1 ].value;
                int endValue = EvaluateExpression( t + 1 + tokens, vals, varmap, line );

                if ( EnableTracing && g_Tracing )
                    printf( "for loop for variable %s current %d, end value %d\n", vals[ 0 ].strValue.c_str(), pvar->value, endValue );

                if ( !continuation )
                {
                    ForGosubItem item( true, pc );
                    forGosubStack.push( item );
                }

                if ( pvar->value > endValue )
                {
                    // find NEXT and set pc to one beyond it.

                    forGosubStack.pop();

                    do
                    {
                        pc++;

                        if ( pc >= linesOfCode.size() )
                            RuntimeFail( "no matching NEXT found for FOR", line );

                        if ( linesOfCode[ pc ].tokenValues.size() > 0 &&
                             Token::NEXT == linesOfCode[ pc ].tokenValues[ 0 ].token )
                            break;
                    } while ( true );
                }

                pc++;
                break; // done processing tokens for FOR
            }
            else if ( Token::NEXT == token )
            {
                if ( 0 == forGosubStack.size() )
                    RuntimeFail( "NEXT without FOR", line );

                ForGosubItem & item = forGosubStack.top();
                if ( !item.isFor )
                    RuntimeFail( "NEXT without FOR", line );

                pc = item.pc;
                break;
            }
            else if ( Token::ATOMIC == token )
            {
                if ( Token::INC == vals[ t + 1 ].token )
                {
                    Variable * pvar = FindKnownVariable( vals[ t + 1 ], varmap );
                    pvar->value++;
                }
                else if ( Token::DEC == vals[ t + 1 ].token )
                {
                    Variable * pvar = FindKnownVariable( vals[ t + 1 ], varmap );
                    pvar->value--;
                }

                pc++;
                break;
            }
            else if ( Token::PRINT == token )
            {
                pc++;
                t++;

                while ( t < vals.size() )
                {
                    if ( Token::SEMICOLON == vals[ t ].token )
                    {
                        t++;
                        continue;
                    }
                    else if ( Token::EXPRESSION != vals[ t ].token ) // ENDIF, ELSE are typical
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
                        std::tm bt = *std::localtime( &timer );
                        printf( "%d:%d:%d", bt.tm_hour, bt.tm_min, bt.tm_sec );
                        t += 2;
                    }
                    else if ( Token::ELAP == vals[ t + 1 ].token )
                    {
                        high_resolution_clock::time_point timeNow = high_resolution_clock::now();
                        long long duration = duration_cast<std::chrono::milliseconds>( timeNow - timeBegin ).count();
                        PrintNumberWithCommas( duration );
                        printf( " ms" );
                        t += 2;
                    }
                    else
                    {
                        int val = EvaluateExpression( t, vals, varmap, line );
                        t += vals[ t ].value;
                        printf( "%d", val );
                    }
                }

                printf( "\n" );
                break;
            }
            else if ( Token::END == token )
            {
                pc = countOfLines;
                break;
            }
            else if ( Token::DIM == token )
            {
                // if the variable has already been defined, delete it first.

                Variable * pvar = FindVariable( varmap, vals[ 0 ].strValue );
                if ( pvar )
                    varmap.erase( vals[ 0 ].strValue.c_str() );

                Variable var( vals[ 0 ].strValue.c_str() );

                var.dimensions = vals[ 0 ].dimensions;
                var.dims[ 0 ] = vals[ 0 ].dims[ 0 ];
                var.dims[ 1 ] = vals[ 0 ].dims[ 1 ];
                int items = var.dims[ 0 ];
                if ( 2 == var.dimensions )
                    items *= var.dims[ 1 ];
                var.array.resize( items );
                varmap.emplace( var.name, var );
                pc++;
                break;
            }
            else if ( Token::REM == token )
            {
                pc++;
                break;
            }
            else if ( Token::TRON == token )
            {
                basicTracing = true;
                pc++;
                break;
            }
            else if ( Token::TROFF == token )
            {
                basicTracing = false;
                pc++;
                break;
            }
            else
            {
                // it's expected to hit these two, since execution continues until they are hit

                if ( Token::ELSE != token && Token::ENDIF != token )
                    RuntimeFail( "unexpected token during execution", line );

                assert( Token::ELSE == token || Token::ENDIF == token );

                pc++;
                break;
            }
        } while( true );
    } while( true );

    if ( EnableExecutionTime && showExecutionTime )
    {
        printf( "execution times in hundred nanoseconds (10 microsecends):\n" );
        printf( "   line #       times      duration\n" );
        for ( size_t l = 0; l < linesOfCode.size(); l++ )
        {
            LineOfCode & loc = linesOfCode[ l ];

            printf( "  %7d  %10lld  %12lld", loc.lineNumber, loc.timesExecuted, loc.duration / 100 );
            printf( "\n" );
        }
    }

    printf( "exiting the basic interpreter\n" );
} //main


