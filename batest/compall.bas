8 rem can't go to 32767 because that'll be an infinite loop
10 for i% = -32768 to 32766
20     gosub 40
30 next i%

32 print "i is now "; i%

35 end

40 h% = i% - 1
50 j% = i% + 1
59 rem line 60 will trigger on the first iteration because -32768 - 1 is an underflow
60 if h% > i% print "h is greater than i: h "; h%; " i "; i%
70 if i% > j% print "i is greater than j: i "; i%; " j "; j%
72 if i% = -32768 print "low"
75 if i% = 0 print "i is 0 now"
77 if i% = 32766 print "high"
80 return

