10 x% = 23456
20 print "hello cp/m!"; " part 2!"; " x: "; x%
30 y% = -30876
40 print "y: "; y%
50 for l% = 0 to 5
60 print "  loop variable: "; l%
70 next l%
80 for l% = -10 to -5
90 print "  loop variable: "; l%
100 next l%
110 for l% = -10000 to -9995
120 print "  loop variable: "; l%
130 next l%
140 for l% = 9995 to 10000
150 print "  loop variable: "; l%
160 next l%

200 s% = x% + y%
210 print "s should be -7420: "; s%

220 m% = 100
230 s% = x% - m%
240 print "s should be 23356: "; s%

290 d% = 7 or 33
291 if d% = 39 then print "d% is 39" else print "BUGBUG 291: "; d%
292 print "d should be 39: "; d%

295 d% = 7 and 2
296 if d% = 2 then print "d% is 2" else print "BUGBUG 296: "; d%
297 print "d should be 2: "; d%

300 a% = 10
302 for b% = 9 to 11
303 gosub 2000
318 next b%

320 a% = -10
322 for b% = 9 to 11
323 gosub 2000
338 next b%

340 a% = -10
342 for b% = -11 to -9
350 gosub 2000
358 next b%

360 a% = 10
362 for b% = -11 to -9
364 gosub 2000
378 next b%

380 a% = -20000
381 b% = -19000
382 for c% = 9 to 11
383 gosub 2000
385 b% = b% - 1000
387 next c%

400 a% = 20000
405 b% = 19000
410 for c% = 9 to 11
420 gosub 2000
485 b% = b% + 1000
490 next c%

500 for j% = 0 to 4
510   gosub 550
520 next j%
530 goto 600

550 print "j in gosub: "; j%
560 return

600 print "after goto"

700 w% = 3
710 if 0 = w% then print "BUGBUG 100" else print "w is not 0"
720 w% = 0
730 if 0 = w% then print "now w is 0" else print "BUGBUG 120"

800 dim aa%( 1000 )
810 aa%( 980 ) = 980
820 print "aa%(980) should be 980: "; aa%(980)
830 if aa%(980) <> 980 then print "BUGBUG line 830"

900 x% = 3 * 9
910 if 27 = x% then print "x is 27" else print "BUGBUG 910, x: "; x%
920 x% = 9 * -3
930 if -27 = x% then print "x is -27" else print "BUGBUG 930, x: "; x%
940 x% = -9 * 3
950 if -27 = x% then print "x is -27" else print "BUGBUG 950, x: "; x%
952 x% = -9 * -3
954 if 27 = x% then print "x is 27" else print "BUGBUG 954, x: "; x%
960 x% = 3000 / 26
970 if 115 = x% then print "x is 115" else print "BUGBUG 970, x: "; x%
980 x% = 3000 / -26
985 if -115 = x% then print "x is -115" else print "BUGBUG 985, x: "; x%
990 x% = -3000 / 26
995 if -115 = x% then print "x is -115" else print "BUGBUG 995, x: "; x%
996 x% = -3000 / -26
997 if 115 = x% then print "x is 115" else print "BUGBUG 997, x: "; x%

1000 dim bb%( 5, 8 )
1010 for x% = 0 to 4
1020   for y% = 0 to 7
1030     bb%( x%, y% ) = x% * y%
1040   next y%
1050 next x%
1060 for x% = 0 to 4
1070   for y% = 0 to 7
1080     print "bb of ( "; x%; ", "; y%;" ) = "; bb%( x%, y% )
1090   next y%
1095 next x%

1100 if 0 = x% then print "bugbug 1100 x isn't 0" else print "x isn't 0"
1101 if x% = 0 then print "bugbug 1100 x isn't 0" else print "x isn't 0"
1102 x% = 0
1103 if 0 = x% then print "x is 0" else print "bugbug 1103"
1104 if x% = 0 then print "x is 0" else print "bugbug 1104"

1105 goto 50000

2000 eq% = a% = b%
2010 ne% = a% <> b%
2020 le% = a% <= b%
2030 ge% = a% >= b%
2040 lt% = a% < b%
2050 gt% = a% > b%
2060 print "eq "; eq%; " ne "; ne%; " le "; le%; " ge "; ge%; " lt "; lt%; " gt "; gt%
2070 rem print "a "; a%; " b "; b%
2080 return

50000 end

