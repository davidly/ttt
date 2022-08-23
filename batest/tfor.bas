40 dim a%( 3, 4 )
50 for x% = 0 to 2
60 for y% = 0 to 3
70 a%(x%,y%) = x% * y%
80 next y%
90 next x%

150 for x% = 0 to 2
160 for y% = 0 to 3
170 print "x "; x%; " y "; y%; " a%(x%,y%) "; a%(x%,y%)
180 next y%
190 next x%


