2 j% = 33
3 dim v%( 3, 5 )
4 dim a%( 10 )
5 for i% = 1 to 5
10   print "hello world, i is " ; i%
11   gosub 100
12   a%( i% ) = j%
15 next i%
16 gosub 60
17 gosub 100
18 gosub 1000
19 gosub 2000

20 v%( 1, 3 ) = 13
21 print "v% range 0 13 0: "; v%(1,2) ; " "; v%(1,3); " "; v%(1,4)

22 if j% > 33 then print "j is > 33!"
23 if 4444 > j% then print "j is < 4444"

24 if 77 and 1 then print "77 is odd" else print "77 is even"
25 if 78 and 1 then print "78 is odd" else print "78 is even"
26 if 77 and 1 then va% = -100 else va% = 100
27 print "va% as -100: "; va%
28 if 78 and 1 then va% = -100 else va% = 100
29 print "va% as 100: "; va%

30 dim b%( 3, 3 )
31 b%( 0, 0 ) = 1
32 b%( 0, 1 ) = 1
33 b%( 0, 2 ) = 1
34 rw% = 0
35 wi% = b%( rw%, 0 )
36 print "wi% "; wi%; " rw% "; rw%
40 if wi% <> 0 and wi% = b%( rw%, 1 ) and wi% = b%( rw%, 2 ) then print "match" else print "no match"
41 if wi% <> 0 and wi% = b%( rw%, 1 ) and wi% = b%( 2, 2 ) then print "match" else print "no match"

42 goto 48
43 print "never print this!!!!"
48 rem continue on
50 a%( 2 ) = z%
51 print "a%( 2 ) from newly created variable: "; a%( 2 )
52 print "yy% is a new variable that should be 0 "; yy%
55 goto 10000

60 st% = 10
61 st% = st% - 1
62 print "st%: "; st%
63 if st% = 0 then return
64 goto 61

100 j% = j% + 3
105 print "  sub hello, j is " ; j%; " a[2] is " ; a%( 2 )
110 return

1000 print "in 1000 gosub function"
1005 aa% = 1
1010 if aa% = 1 then re% = 1: goto 1050
1020 if aa% = 2 then re% = 2: goto 1060
1030 goto 1090
1050 print "line 1050, re: "; re%
1060 print "line 1060, re: "; re%
1090 print "returning now"
1100 return

2000 tron
2004 x% = 13 ^ 42
2010 print "x% is 13 ^ 42, which is 39: "; x%
2015 troff
2016 if 0 <> 4 then print "0 <> 4" else print "bugbugbug 2016"
2017 if 4 then print "0 <> 4" else print "bugbugbug 2017"
2020 return

10000 end
