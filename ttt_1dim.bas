1  REM Tic Tac Toe solving app that learns what WOPR learned: you can't win
2  REM Only three starting positions are examined. Others are just reflections of these
3  REM B%   -- The board
4  REM AL%  -- Alpha, for pruning
5  REM BE%  -- Beta, for pruning
6  REM L%   -- Top-level loop iteration
7  REM WI%  -- The winning piece (0 none, 1 X, 2, O )
8  REM RE%  -- Resulting score of 4000/minmax board position. 5 draw, 6 X win, 4 Y win
9  REM SX%  -- Stack array for "recursion"
10 REM V%   -- Value of a board position
11 REM ST%  -- Stack Pointer. Even for alpha/beta pruning Minimize plys, Odd for Maximize
12 REM P%   -- Current position where a new piece is played
14 REM RW%  -- Row in the Winner function (2000)
15 REM CW%  -- Column in the Winner function (2000)
16 REM RP%  -- Row when printing the board (1000)
17 REM CA%, RC%, CC% -- result, row, and column in Cat's game detection (3000) (unused)
18 REM MC%  -- Move count total for debugging
19 REM Note: Can't use real recursion with GOSUB because stack is limited to roughly 5 deep
20 REM       BASIC doesn't support goto/gosub using arrays for target line numbers
30 dim b%(9)
32 dim sp%(10)
34 dim sv%(10)
36 dim sa%(10)
37 dim sb%(10)
38 mc% = 0
39 rem print "start time: "; time$
41 for l% = 1 to 1000
42 al% = 2
43 be% = 9
44 b%(0) = 1
45 gosub 4000
58 al% = 2
59 be% = 9
60 b%(0) = 0
61 b%(1) = 1
62 gosub 4000
68 al% = 2
69 be% = 9
70 b%(1) = 0
71 b%(4) = 1
72 gosub 4000
73 b%(4) = 0
80 next l%
85 rem print "end time for 1000 iterations "; time$
86 print elap$ ; " for 1000 iterations"
87 print "final move count "; mc%
100 end

2000 wi% = b%( 0 )
2010 if 0 = wi% goto 2100
2020 if wi% = b%( 1 ) and wi% = b%( 2 ) then return
2030 if wi% = b%( 3 ) and wi% = b%( 6 ) then return
2100 wi% = b%( 3 )
2110 if 0 = wi% goto 2200
2120 if wi% = b%( 4 ) and wi% = b%( 5 ) then return
2200 wi% = b%( 6 )
2210 if 0 = wi% goto 2300
2220 if wi% = b%( 7 ) and wi% = b%( 8 ) then return
2300 wi% = b%( 1 )
2310 if 0 = wi% goto 2400
2320 if wi% = b%( 4 ) and wi% = b%( 7 ) then return
2400 wi% = b%( 2 )
2410 if 0 = wi% goto 2500
2420 if wi% = b%( 5 ) and wi% = b%( 8 ) then return
2500 wi% = b%( 4 )
2510 if 0 = wi% then return
2520 if wi% = b%( 0 ) and wi% = b%( 8 ) then return
2530 if wi% = b%( 2 ) and wi% = b%( 6 ) then return
2540 wi% = 0
2550 return

3998 rem minmax function to find score of a board position
3999 rem recursion is simulated with gotos
4000 st% = 0
4040 v% = 0
4060 re% = 0
4100 mc% = mc% + 1
4102 if st% < 4 then goto 4150
4105 gosub 2000
4110 if wi% = 1 then re% = 6: goto 4280
4120 if wi% = 2 then re% = 4: goto 4280
4140 if st% = 8 then re% = 5: goto 4280
4150 if st% and 1 then v% = 2 else v% = 9
4160 p% = 0
4180 if 0 <> b%(p%) then goto 4500
4200 if st% and 1 then b%(p%) = 1 else b%(p%) = 2
4210 sp%(st%) = p%
4230 sv%(st%) = v%
4245 sa%(st%) = al%
4246 sb%(st%) = be%
4260 st% = st% + 1
4270 goto 4100
4280 st% = st% - 1
4290 p% = sp%(st%)
4310 v% = sv%(st%)
4325 al% = sa%(st%)
4326 be% = sb%(st%)
4328 b%(p%) = 0
4330 if st% and 1 goto 4340
4332 if re% < v% then v% = re%
4334 if v% < be% then be% = v%
4336 if be% <= al% then goto 4520
4337 if v% = 4 then goto 4520
4338 goto 4500
4340 if re% > v% then v% = re%
4342 if v% > al% then al% = v%
4344 if al% >= be% then goto 4520
4346 if v% = 6 then goto 4520
4500 p% = p% + 1
4505 if p% < 9 then goto 4180
4520 re% = v%
4530 if st% = 0 then return
4540 goto 4280

