(* Logitech Modula-2 version of proving you can't win at tic-tac-toe if the opponent is competent
   To build from the Modula-2 install directory:

      ntvdm -r:. -e:m2sym=m2lib\sym m2exe\M2C.EXE %1
      rem the qbx linker works fine
      ntvdm -r:. -e:lib=m2lib\lib link %1,,,m2lib m2rts.lib;
*)

MODULE ttt;

FROM SYSTEM IMPORT WORD, BYTE, ADDRESS;
FROM NumberConversion IMPORT StringToCard;
FROM Strings IMPORT Assign;
FROM DOS3 IMPORT GetProgramSegmentPrefix;
FROM InOut IMPORT WriteLn, WriteInt, WriteCard, WriteString;
FROM TimeDate IMPORT Time, GetTime;

CONST
    scoreWin = 6;
    scoreTie = 5;
    scoreLose = 4;
    scoreMax = 9;
    scoreMin = 2;
    scoreInvalid = 0;
  
    pieceBlank = 0;
    pieceX = 1;
    pieceO = 2;

    defaultIterations = 1;

TYPE
    boardType = ARRAY[ 0..8 ] OF CARDINAL;
    scoreProc = PROCEDURE() : CARDINAL;

VAR
    evaluated: CARDINAL;
    board: boardType;
    procs : ARRAY[ 0..8 ] OF scoreProc;

PROCEDURE lookForWinner() : CARDINAL;
VAR t : CARDINAL;
BEGIN
    t := board[ 0 ];
    IF pieceBlank <> t THEN
        IF ( ( ( t = board[1] ) AND ( t = board[2] ) ) OR
           ( ( t = board[3] ) AND ( t = board[6] ) ) ) THEN
            RETURN t;
        END;
    END;

    t := board[1];
    IF ( t = board[4] ) AND ( t = board[7] ) THEN RETURN t; END;

    t := board[2];
    IF ( t = board[5] ) AND ( t = board[8] ) THEN RETURN t; END;

    t := board[3];
    IF ( t = board[4] ) AND ( t = board[5] ) THEN RETURN t; END;

    t := board[6];
    IF ( t = board[7] ) AND ( t = board[8] ) THEN RETURN t; END;

    t := board[4];
    IF pieceBlank <> t THEN
        IF ( ( ( t = board[0] ) AND ( t = board[8] ) ) OR
           ( ( t = board[2] ) AND ( t = board[6] ) ) ) THEN
                RETURN t;
        END;
    END;

    RETURN pieceBlank;
END lookForWinner;

PROCEDURE proc0() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[0];
    IF ( ( ( x = board[1] ) AND ( x = board[2] ) ) OR
         ( ( x = board[3] ) AND ( x = board[6] ) ) OR
         ( ( x = board[4] ) AND ( x = board[8] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc0;

PROCEDURE proc1() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[1];
    IF ( ( ( x = board[0] ) AND ( x = board[2] ) ) OR
         ( ( x = board[4] ) AND ( x = board[7] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc1;

PROCEDURE proc2() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[2];
    IF ( ( ( x = board[0] ) AND ( x = board[1] ) ) OR
         ( ( x = board[5] ) AND ( x = board[8] ) ) OR
         ( ( x = board[4] ) AND ( x = board[6] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc2;

PROCEDURE proc3() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[3];
    IF ( ( ( x = board[4] ) AND ( x = board[5] ) ) OR
         ( ( x = board[0] ) AND ( x = board[6] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc3;

PROCEDURE proc4() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[4];
    IF ( ( ( x = board[0] ) AND ( x = board[8] ) ) OR
         ( ( x = board[2] ) AND ( x = board[6] ) ) OR
         ( ( x = board[1] ) AND ( x = board[7] ) ) OR
         ( ( x = board[3] ) AND ( x = board[5] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc4;

PROCEDURE proc5() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[5];
    IF ( ( ( x = board[3] ) AND ( x = board[4] ) ) OR
         ( ( x = board[2] ) AND ( x = board[8] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc5;

PROCEDURE proc6() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[6];
    IF ( ( ( x = board[7] ) AND ( x = board[8] ) ) OR
         ( ( x = board[0] ) AND ( x = board[3] ) ) OR
         ( ( x = board[4] ) AND ( x = board[2] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc6;

PROCEDURE proc7() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[7];
    IF ( ( ( x = board[6] ) AND ( x = board[8] ) ) OR
         ( ( x = board[1] ) AND ( x = board[4] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc7;

PROCEDURE proc8() : CARDINAL;
VAR x : CARDINAL;
BEGIN
    x := board[8];
    IF ( ( ( x = board[6] ) AND ( x = board[7] ) ) OR
         ( ( x = board[2] ) AND ( x = board[5] ) ) OR
         ( ( x = board[0] ) AND ( x = board[4] ) ) )
        THEN RETURN x; END;
    RETURN pieceBlank;
END proc8;

PROCEDURE minmax( alpha: CARDINAL; beta: CARDINAL; move: CARDINAL; depth: CARDINAL ): CARDINAL;
VAR p, value, pieceMove, score : CARDINAL;
BEGIN
    evaluated := evaluated + 1;
    value := scoreInvalid;
    IF depth >= 4 THEN
        (* lookForWinner is >14% slower than using scoring procs, unlike Turbo Modula-2 on CP/M *)
        (* p := lookForWinner(); *)
        p := procs[ move ]();
          
        IF p <> pieceBlank THEN
            IF p = pieceX THEN
                RETURN scoreWin;
            ELSE
                RETURN scoreLose;
            END;
        ELSIF depth = 8 THEN
            RETURN scoreTie;
        END;
    END;

    IF ODD( depth ) THEN
        value := scoreMin;
        pieceMove := pieceX;
    ELSE
        value := scoreMax;
        pieceMove := pieceO;
    END;

    p := 0;
    REPEAT
        IF board[ p ] = pieceBlank THEN
            board[ p ] := pieceMove;
            score := minmax( alpha, beta, p, depth + 1 );
            board[ p ] := pieceBlank;
      
            IF ODD( depth ) THEN
                IF ( score = scoreWin ) THEN RETURN scoreWin; END;
                IF ( score > value ) THEN
                    value := score;
                    IF ( value >= beta ) THEN RETURN value; END;
                    IF ( value > alpha ) THEN alpha := value; END;
                END;
            ELSE
                IF ( score = scoreLose ) THEN RETURN scoreLose; END;
                IF ( score < value ) THEN
                    value := score;
                    IF ( value <= alpha ) THEN RETURN value; END;
                    IF ( value < beta ) THEN beta := value; END;
                END;
            END;
        END;
        p := p + 1
    UNTIL p > 8;

    RETURN value;
END minmax;

PROCEDURE TimeStamp() : CARDINAL;
VAR
    t : Time;
    hour, minute, second, hs: CARDINAL;
BEGIN
    GetTime( t );

    hs := ( t.millisec DIV 10 ) MOD 100;
    second := t.millisec DIV 1000;
    minute := t.minute MOD 60;
    hour := t.minute DIV 60;

    RETURN hs + second * 100 + minute * 60 * 100; (* hundredths of a second *)
END TimeStamp;

PROCEDURE runit( move : CARDINAL );
VAR score : CARDINAL;
BEGIN
    board[move] := pieceX;
    score := minmax( scoreMin, scoreMax, move, 0 );
    board[move] := pieceBlank;
END runit;

(* Exhibits #327, 328, and 329 of why Modula-2 never took off *)
PROCEDURE CommandTail( VAR s: ARRAY OF CHAR );
VAR
    PSPSegment, w, wch : WORD;
    a : ADDRESS;
    i : CARDINAL;
BEGIN
    PSPSegment := WORD( 0 );
    s[ 0 ] := 0c;
    GetProgramSegmentPrefix( PSPSegment );

    IF ( WORD( 0 ) <> PSPSegment ) THEN
        a.SEGMENT := CARDINAL( PSPSegment );
        a.OFFSET := CARDINAL( 128 );
        w := a^; (* can only read WORDs, not BYTEs *)
        w := WORD( BITSET( w ) * BITSET( 255 ) );

        IF ( w > WORD( 1 ) ) THEN
            FOR i := 0 TO CARDINAL( w ) - 2 DO
                a.OFFSET := CARDINAL( 128 ) + CARDINAL( 2 ) + CARDINAL( i );
                wch := a^;
                wch := WORD( BITSET( wch ) * BITSET( 255 ) );
                s[ i ] := CHAR( VAL( BYTE, INTEGER( wch ) ) ); (* is there a better cast? *)
            END;
            s[ CARDINAL( w ) - 1 ] := 0c;
        END;
    END;
END CommandTail;

VAR
    i, loops : CARDINAL;
    result : BOOLEAN;
    cmd : ARRAY[0..127] OF CHAR;
    done : BOOLEAN;
    tsstart, tsend : CARDINAL;
BEGIN
    loops := 0;
    CommandTail( cmd );
    StringToCard( cmd, loops, done );
    IF ( loops = 0 ) THEN loops := defaultIterations; END;

    procs[ 0 ] := proc0;
    procs[ 1 ] := proc1;
    procs[ 2 ] := proc2;
    procs[ 3 ] := proc3;
    procs[ 4 ] := proc4;
    procs[ 5 ] := proc5;
    procs[ 6 ] := proc6;
    procs[ 7 ] := proc7;
    procs[ 8 ] := proc8;

    FOR i := 0 TO 8 DO
        board[i] := pieceBlank;
    END;

    tsstart := TimeStamp();

    FOR i := 1 TO loops DO
        evaluated := 0;  (* once per loop to prevent overflow *)
        runit( 0 );
        runit( 1 );
        runit( 4 );
    END;

    tsend := TimeStamp();

    WriteString( "elapsed hundredths of a second: " ); WriteCard( tsend - tsstart, 8 ); WriteLn;
    WriteString( "moves evaluated:                " ); WriteInt( evaluated, 8 ); WriteLn;
    WriteString( "iterations:                     " ); WriteInt( loops, 8 ); WriteLn;
END ttt.

