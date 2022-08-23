10 print "minus 1: "; -1
20 print "minus 3: "; 1 - 4
30 print "eight: "; -3 + 11

100 x% = -1
110 y% = 4 - 40
120 z% = x% + 10

200 print "x should be -1: "; x%
210 print "y should be -36: "; y%
220 print "z should be 9: "; z%

300 dim a%(10)
320 a%( 3 ) = -10
330 a%( x% + 5 ) = -20
340 a%( z% ) = -20 - 30

400 print "a%(3) should be -10 "; a%(3)
410 print "a%(4) should be -20 "; a%(4)
420 print "a%(9) should be -50 "; a%(9)

500 dim b%(10,10)
520 b%( -3+5, 3 ) = -10
530 b%( 100-96, x% + 5 ) = -20
540 b%( 2, z% - 2 ) = -20 - 30
550 c% = 0 - b%(2, z% - 2 )

600 print "b%(2,3) should be -10 "; b%(2,3)
610 print "b%(4,4) should be -20 "; b%(4,4)
620 print "b%(2,7) should be -50 "; b%(2,7)
630 print "c%      should be 50 "; c%

800 z% = 14
810 z% = -z%
820 print "z% should be -14 "; z%


10000 end

