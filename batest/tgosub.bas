5 s% = 0
10 for i% = 1 to 10
20   for j% = 1 to 20
30     gosub 2000
40   next j%
50 next i%
55 print "same count (should be 290): "; s%
60 end

2000 for a% = 1 to 10
2010   for b% = 1 to 30
2020       gosub 3000
2030   next b%
2035   if i% = j% then return
2040 next a%
2050 return

3000 if a% = b% then return
3010 if i% = j% then s% = s% + 1 : print "i and j are the same"
3020 return


