110 dim a%( 200 )
120 hi% = 200
140 n% = hi% - 1
150 for x% = 2 to n%
160 a%( x% ) = 1
170 next x%
180 x% = 0
200 a%( 1 ) = 2
210 a%( 0 ) = 0
230 hi% = hi% - 1
235 n% = hi%
244 rem no MOD so compute division then MOD manually
245 qu% = x% / n%
246 a%( n% ) = x% - ( n% * qu% )
250 n% = n% - 1
260 x% = ( a%( n% ) * 10 ) + qu%
261 rem print "x, n, qu: "; x%; " "; n%; " "; qu%
280 if 0 <> n% then goto 245
300 print x%
330 if 10 <= hi% then goto 230
400 print " "
410 print "done"
420 system


