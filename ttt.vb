Imports System
Imports System.Threading
Imports System.Threading.Tasks
Imports System.Diagnostics

Module Program

    Const piece_x As Integer = 1
    Const piece_o As Integer = 2
    Const piece_blank As Integer = 0

    Const score_win As Integer = 6
    Const score_tie As Integer = 5
    Const score_lose As Integer = 4
    Const score_max As Integer = 9
    Const score_min As Integer = 2

    Const iterations As Integer = 10000

    Dim evaluated = 0

    Function look_for_winner(ByRef b() as integer) As Integer
        Dim p As Integer = b(0)
        If piece_blank <> p Then
            If p = b(1) And p = b(2) Then Return p
            If p = b(3) And p = b(6) Then Return p
        End If

        p = b(3)
        If piece_blank <> p And p = b(4) And p = b(5) Then Return p

        p = b(6)
        If piece_blank <> p And p = b(7) And p = b(8) Then Return p

        p = b(1)
        If piece_blank <> p And p = b(4) And p = b(7) Then Return p

        p = b(2)
        If piece_blank <> p And p = b(5) And p = b(8) Then Return p

        p = b(4)
        If piece_blank <> p Then
            If p = b(0) And p = b(8) Then Return p
            If p = b(2) And p = b(6) Then Return p
        End If

        Return piece_blank
    End Function

    Function min_max(ByRef b() as integer, ByVal alpha As Integer, ByVal beta As Integer, ByVal depth As Integer) As Integer
        'evaluated += 1

        If depth >= 4 Then
            Dim p As Integer = look_for_winner(b)

            If piece_blank <> p Then
                If piece_x = p Then Return score_win

                Return score_lose
            End If

            If 8 = depth Then Return score_tie
        End If

        Dim value As Integer
        Dim pieceMove As Integer

        If 0 <> (depth And 1) Then
            value = score_min
            pieceMove = piece_x
        Else
            value = score_max
            pieceMove = piece_o
        End If

        For x = 0 To 8
            If piece_blank = b(x) Then
                b(x) = pieceMove
                Dim score As Integer = min_max(b, alpha, beta, depth + 1)
                b(x) = piece_blank

                If 0 <> (depth And 1) Then
                    If score_win = score Then Return score_win
                    If score > value Then value = score
                    If value > alpha Then alpha = value
                    If alpha >= beta Then Return value
                Else
                    If score_lose = score Then Return score_lose
                    If score < value Then value = score
                    If value < beta Then beta = value
                    If beta <= alpha Then Return value
                End If
            End If
        Next

        Return value
    End Function

    Sub runBoard(move As Integer)
        Dim b(8) As Integer
        b(move) = piece_x

        For i = 1 To iterations
            Dim score As Integer = min_max(b, score_min, score_max, 0)
            If score <> score_tie Then Console.WriteLine("bogus result!")
        Next

    End Sub

    Sub Main()
        Dim stopWatch As Stopwatch = New Stopwatch()
        stopWatch.Start()

        runBoard(0)
        runBoard(1)
        runBoard(4)

        'Console.WriteLine("moves evaluated: " + Str(evaluated))
        Console.WriteLine("serial elapsed time: " + Str(stopWatch.ElapsedMilliseconds))

        stopWatch.Reset()
        stopWatch.Start()

        Parallel.For( 0, 3,
            Sub ( index as integer )
                if index = 0 then
                    runboard( 0 )
                elseif index = 1 then
                    runboard( 1 )
                elseif index = 2 then
                    runboard( 4 )
                end if
            end sub )

        Console.WriteLine("parallel elapsed time: " + Str(stopWatch.ElapsedMilliseconds))
    End Sub
End Module
