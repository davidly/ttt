5 gosub 10
6 goto 100

10 x% = 1
20 y% = 2
25 dim z%( 4 )
26 z%( 1 ) = 1
27 z%( 2 ) = 2
30 if x% = z%( 1 ) and y% = z%( 2 ) then print "true!" else print "false!"
40 if x% = z%( 1 ) and y% = z%( 2 ) then return
50 print "didn't return yet"
60 return


100 dim b%(9)
110 gosub 3000
120 b%( 1 ) = 666
130 gosub 3000
140 print "b(1) == "; b%(1)
150 o% = 1
160 print "b(o) == "; b%(o%)
170 b%( o% ) = 777
180 print "b(o) == "; b%(o%)

200 b%( 0 ) = 1
201 b%( 1 ) = 2
202 b%( 2 ) = 1
203 b%( 3 ) = 2
204 b%( 4 ) = 1
205 b%( 5 ) = 2
206 b%( 6 ) = 1
207 b%( 7 ) = 2
208 b%( 8 ) = 0
210 gosub 2000
220 print "winner: "; wi%
230 gosub 300
240 print "winner: "; wi%

299 end

300 wi% = b%( 4 )
310 if 0 = wi% then return
311 print "line 311"
320 if wi% = b%( 0 ) and wi% = b%( 8 ) then return
321 print "line 321 "; wi%; " 2 "; b%(2); " 6 "; b%(6)
330 if wi% = b%( 2 ) and wi% = b%( 6 ) then return
331 print "line 331"
340 wi% = 0
350 return



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




2800 end


3000 print b%(0);b%(1);b%(2);b%(3);b%(4);b%(5);b%(6);b%(7);b%(8)
3005 return

