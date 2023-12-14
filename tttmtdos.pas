{ App to prove you can't win at Tic-Tac-Toe }
{ Written to target MT+86 - Pascal   V3.1.1 }

program ttt;

const
  scoreWin = 6;
  scoreTie = 5;
  scoreLose = 4;
  scoreMax = 9;
  scoreMin = 2;
  scoreInvalid = 0;

  pieceBlank = 0;
  pieceX = 1;
  pieceO = 2;

  iterations = 1;

type
  boardType = array[ 0..8 ] of integer;
  PSTRING = ^STRING;

var
  evaluated: integer;
  board: boardType;

var
  i, loops, code: integer;
  startTicks, endTicks, elapsedTicks : longint;

external function @cmd : PSTRING;
external procedure @GETTIME( var hour,minute,second,hund : integer );

procedure dumpBoard;
var
  i : integer;
begin
  Write( '{' );
  for i := 0 to 8 do
    Write( board[i] );
  Write( '}' );
end;

function lookForWinner : integer;
var
  t, p : integer;
begin
  {dumpBoard;}
  p := pieceBlank;
  t := board[ 0 ];
  if pieceBlank <> t then
  begin
    if ( ( ( t = board[1] ) and ( t = board[2] ) ) or
         ( ( t = board[3] ) and ( t = board[6] ) ) ) then
      p := t;
  end;

  if pieceBlank = p then
  begin
    t := board[1];
    if ( t = board[4] ) and ( t = board[7] ) then
      p := t
    else
    begin
      t := board[2];
      if ( t = board[5] ) and ( t = board[8] ) then
        p := t
      else
      begin
        t := board[3];
        if ( t = board[4] ) and ( t = board[5] ) then
          p := t
        else
        begin
          t := board[6];
          if ( t = board[7] ) and ( t = board[8] ) then
            p := t
          else
          begin
            t := board[4];
            if ( ( ( t = board[0] ) and ( t = board[8] ) ) or
                 ( ( t = board[2] ) and ( t = board[6] ) ) ) then
              p := t
          end;
        end;
      end;
    end;
  end;

  lookForWinner := p;
end;

function minmax( alpha: integer; beta: integer; depth: integer ): integer;
var
  p, value, pieceMove, score : integer;
begin
  evaluated := evaluated + 1;
  value := scoreInvalid;
  if depth >= 4 then
  begin
    p := lookForWinner;
    if p <> pieceBlank then
    begin
      if p = pieceX then
        value := scoreWin
      else
        value := scoreLose
    end
    else if depth = 8 then
      value := scoreTie;
  end;

  if value = scoreInvalid then
  begin
    if Odd( depth ) then
    begin
      value := scoreMin;
      pieceMove := pieceX;
    end
    else
    begin
      value := scoreMax;
      pieceMove := pieceO;
    end;

    p := 0;
    repeat
      if board[ p ] = pieceBlank then
      begin
        board[ p ] := pieceMove;
        score := minmax( alpha, beta, depth + 1 );
        board[ p ] := pieceBlank;

        if Odd( depth ) then
        begin
          if ( score > value ) then
          begin
            value := score;
            if ( value = scoreWin ) or ( value >= beta ) then p := 10
            else if ( value > alpha ) then alpha := value;
          end;
        end
        else
        begin
          if ( score < value ) then
          begin
            value := score;
            if ( value = scoreLose ) or ( value <= alpha ) then p := 10
            else if ( value < beta ) then beta := value;
          end;
        end;
      end;
      p := p + 1;
    until p > 8;
  end;

  minmax := value;
end;

function argAsInt : integer;
var
    offset, x, len, result : integer;
    CommandString : STRING[ 127 ];
    PTR : PSTRING;
begin
    result := 0;
    PTR := @CMD;
    CommandString := PTR^;
    len := ORD( CommandString[ 0 ] );
    if 0 <> len then
    begin
        offset := 2;
        x := ORD( CommandString[ 2 ] );
        while ( ( x >= 48 ) and ( x <= 57 ) ) do
        begin
            result := result * 10;
            result := result + x - 48;
            offset := offset + 1;
            x := ORD( CommandString[ offset ] );
        end;
    end;
  
    argAsInt := result;
end;

function tickCount : longint;
var
  h, m, s, hu : integer;
  lh, lm, ls, lhu, result : longint;
begin
  @gettime( h, m, s, hu );
  lh := long( h );
  lm := long( m );
  ls := long( s );
  lhu := long( hu );
  result := lhu + ( ls * #100 ) + ( lm * #6000 ) + ( lh * #360000 );
  tickCount := result;
end;

procedure runit( move : integer );
var
  score: integer;
begin
  board[move] := pieceX;
  score := minmax( scoreMin, scoreMax, 0 );
  board[move] := pieceBlank;
end;

begin
  loops := argAsInt;
  if 0 = loops then loops := Iterations;

  WriteLn( 'begin' );

  for i := 0 to 8 do
    board[i] := pieceBlank;

  startTicks := tickCount;

  for i := 1 to loops do
  begin
    evaluated := 0;  { once per loop to prevent overflow }
    runit( 0 );
    runit( 1 );
    runit( 4 );
  end;

  endTicks := tickCount;
  elapsedTicks := endTicks - startTicks;
  WriteLn( 'hundredths of a second: ', short( elapsedTicks ) );
  WriteLn( 'moves evaluated:        ', evaluated );
  WriteLn( 'iterations:             ', loops );
end.
