10 x% = 10
15 x% = x% + 13
20 print "x% should be 23: "; x%
30 y% = 10 + 15 + 20
40 print "y% should be 45: "; y%
50 dim a%( 100 )
60 a%( 4 ) = 88
70 z% = x% + a%( 4 ) + y%
80 print "z% should be 156: "; z%
90 w% = 3
100 if 0 = w% then print "BUGBUG 100" else print "w is not 0"
110 w% = 0
120 if 0 = w% then print "now w is 0" else print "BUGBUG 120"

140 dim aa%( 1000 )
145 dim bb%( 3000 )
150 aa%( 980 ) = 980
155 bb%( 2800 ) = 2800
160 print "aa%(980) should be 980: "; aa%(980); ", bb%(2800) should be 2800: "; bb%(2800)
165 if aa%(980) <> 980 then print "BUGBUG line 165"
170 if bb%(2800) <> 2800 then print "BUGBUG line 170"

200 v% = 100
210 p% = 120
220 if v% < p% then print "v is correct" else print "BUGBUG 220" 
230 if v% <= p% then print "v is correct" else print "BUGBUG 230" 
240 if v% > p% then print  "BUGBUG 240" else print "v is correct"
250 if v% >= p% then print  "BUGBUG 250" else print "v is correct"

260 r% = 10 * 30
261 print "r% should be 300: "; r%

270 d% = 100 / 33
271 if d% = 3 then print "d% is 3" else print "BUGBUG 271"

280 d% = 7 ^ 2
281 if d% = 5 then print "d% is 5" else print "BUGBUG 281: "; d%

290 d% = 7 or 33
291 if d% = 39 then print "d% is 39" else print "BUGBUG 291: "; d%

295 d% = 7 and 2
296 if d% = 2 then print "d% is 2" else print "BUGBUG 296: "; d%

300 a%( 0 ) = 1
310 a%( 1 ) = 1
320 a%( 2 ) = 1
323 a%( 3 ) = 22
330 wi% = a%( 0 )
340 if wi% = a%( 1 ) and wi% = a%( 2 ) then print "winner! " else print "loser"

350 ii% = 10000
360 jj% = 100
370 kk% = 10
380 ll% = ii% / jj% / kk%
390 if 100 = ll% then print "ll% is wrong: BUGBUG 390 "; ll% else print "ll% is correct: "; ll%
391 if 10 = ll% then print "ll% is correct, should be 10: "; ll% else print "BUGBUG 390"

400 c% = 3
410 d% = c% * ( x% + y% ) * ( a%( c% ) + a%( 1 ) )
420 print "d% should be 4692: "; d%

430 d% = c% + 8 * ( x% + 3 + y% ) * ( a%( c% ) + a%( 1 ) ) * c% + ( r% * 10 ) + x%
440 print "d% should be 42218: "; d%

441 d% = c% + 2 * ( x% + 3 + y% ) * ( a%( c% ) + a%( 1 ) ) * c% - ( r% * 3 ) + x%
442 print "d% should be 8924: "; d%

450 rem e% = ( 900 / c% + x% / y% * a%(4) * a%(2 * c% + 19 + 22) * ii% / ( kk% + jj%) - ( ( d% + y% + x% - c% ) / kk% ) ) * kk% + p% / ( c% * 2 )
451 print "c "; c%; " x "; x%; " y "; y%; " d "; d%; " kk "; kk%; " p "; p%
455 e% = ( 900 / c% + 0 - ( ( d% + y% + x% - c% ) / kk% ) ) * kk% + p% / ( c% * 2 )
460 print "e% should be -5960: "; e%

500 d% = 5
510 c% = 3
515 a%( 17 ) = 3333
520 e% = 5 + a%( 1 ) + a%( 2 + d% * c% )
530 if e% = 3339 then print "e% is correct " else print "BUGBUG 530, e%: "; e%

600 e% = -d%
610 if e% = 5 then print "BUGBUG 610" else print "e% is -5: "; e%
620 if e% = -5 then print "e% is correct: "; e% else print "BUGBUG 610"




