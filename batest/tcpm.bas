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
304 eq% = a% = b%
306 ne% = a% <> b%
308 le% = a% <= b%
310 ge% = a% >= b%
312 lt% = a% < b%
314 gt% = a% > b%
316 print "  eq "; eq%; ", ne "; ne%; ", le "; le%; ", ge "; ge%; ", lt "; lt%; ", gt "; gt%; ", a "; a%; ", b "; b%
318 next b%

320 a% = -10
322 for b% = 9 to 11
324 eq% = a% = b%
326 ne% = a% <> b%
328 le% = a% <= b%
330 ge% = a% >= b%
332 lt% = a% < b%
334 gt% = a% > b%
336 print "  eq "; eq%; ", ne "; ne%; ", le "; le%; ", ge "; ge%; ", lt "; lt%; ", gt "; gt%; ", a "; a%; ", b "; b%
338 next b%

340 a% = -10
342 for b% = -11 to -9
344 eq% = a% = b%
346 ne% = a% <> b%
348 le% = a% <= b%
350 ge% = a% >= b%
352 lt% = a% < b%
354 gt% = a% > b%
356 print "  eq "; eq%; ", ne "; ne%; ", le "; le%; ", ge "; ge%; ", lt "; lt%; ", gt "; gt%; ", a "; a%; ", b "; b%
358 next b%

360 a% = 10
362 for b% = -11 to -9
364 eq% = a% = b%
366 ne% = a% <> b%
368 le% = a% <= b%
370 ge% = a% >= b%
372 lt% = a% < b%
374 gt% = a% > b%
376 print "  eq "; eq%; ", ne "; ne%; ", le "; le%; ", ge "; ge%; ", lt "; lt%; ", gt "; gt%; ", a "; a%; ", b "; b%
378 next b%

400 a% = 20000
405 b% = 19000
410 for c% = 9 to 11
420 eq% = a% = b%
430 ne% = a% <> b%
440 le% = a% <= b%
450 ge% = a% >= b%
460 lt% = a% < b%
470 gt% = a% > b%
480 print "  eq "; eq%; ", ne "; ne%; ", le "; le%; ", ge "; ge%; ", lt "; lt%; ", gt "; gt%; ", a "; a%; ", b "; b%
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



50000 end

