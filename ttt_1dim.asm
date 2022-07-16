extern printf: PROC
extern memmove: PROC
extern exit: PROC
extern QueryPerformanceCounter: PROC
extern QueryPerformanceFrequency: PROC
extern GetLocalTime: PROC
data_segment SEGMENT ALIGN( 4096 ) 'DATA'
  align 16
       var_b DD 9 DUP (0)
  align 16
      var_sp DD 10 DUP (0)
  align 16
      var_sv DD 10 DUP (0)
  align 16
      var_sa DD 10 DUP (0)
  align 16
      var_sb DD 10 DUP (0)
    str_23_4   db  ' for 1000 iterations', 0
  align 16
      var_al DD   0
      var_be DD   0
       var_l DD   0
      var_mc DD   0
       var_p DD   0
      var_re DD   0
      var_st DD   0
       var_v DD   0
      var_wi DD   0
  align 16
    explist        dd 256 DUP(0)
  align 16
    gosubcount     dq    0
    startTicks     dq    0
    perfFrequency  dq    0
    currentTicks   dq    0
    currentTime    dq 2  DUP(0)
    errorString    db    'internal error', 10, 0
    startString    db    'running basic', 10, 0
    stopString     db    'done running basic', 10, 0
    newlineString  db    10, 0
    elapString     db    '%lld microseconds (-6)', 0
    timeString     db    '%02d:%02d:%02d', 0
    intString      db    '%d', 0
    strString      db    '%s', 0
data_segment ENDS
code_segment SEGMENT ALIGN( 4096 ) 'CODE'
main PROC
    push     rbp
    mov      rbp, rsp
    sub      rsp, 32 + 8 * 4
    lea      rcx, [startString]
    call     printf
    lea      rcx, [startTicks]
    call     QueryPerformanceCounter
    lea      rcx, [perfFrequency]
    call     QueryPerformanceFrequency
  line_number_0:   ; ===>>> 30 dim b%(9)
  line_number_1:   ; ===>>> 32 dim sp%(10)
  line_number_2:   ; ===>>> 34 dim sv%(10)
  line_number_3:   ; ===>>> 36 dim sa%(10)
  line_number_4:   ; ===>>> 37 dim sb%(10)
  line_number_5:   ; ===>>> 38 mc% = 0
    mov      DWORD PTR [var_mc], 0
  line_number_6:   ; ===>>> 41 for l% = 1 to 1000
    mov      [var_l], 1
  for_loop_6:
    cmp      [var_l], 1000
    jg       after_for_loop_6
  line_number_7:   ; ===>>> 42 al% = 2
    mov      DWORD PTR [var_al], 2
  line_number_8:   ; ===>>> 43 be% = 9
    mov      DWORD PTR [var_be], 9
  line_number_9:   ; ===>>> 44 b%(0) = 1
    lea      r10, [ explist + 0 ]
    mov      DWORD PTR [ r10 + 0 ], 0
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 1
  line_number_10:   ; ===>>> 45 gosub 4000
    inc      [gosubcount]
    call     line_number_47
  line_number_11:   ; ===>>> 58 al% = 2
    mov      DWORD PTR [var_al], 2
  line_number_12:   ; ===>>> 59 be% = 9
    mov      DWORD PTR [var_be], 9
  line_number_13:   ; ===>>> 60 b%(0) = 0
    lea      r10, [ explist + 0 ]
    mov      DWORD PTR [ r10 + 0 ], 0
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 0
  line_number_14:   ; ===>>> 61 b%(1) = 1
    lea      r10, [ explist + 0 ]
    mov      DWORD PTR [ r10 + 0 ], 1
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 1
  line_number_15:   ; ===>>> 62 gosub 4000
    inc      [gosubcount]
    call     line_number_47
  line_number_16:   ; ===>>> 68 al% = 2
    mov      DWORD PTR [var_al], 2
  line_number_17:   ; ===>>> 69 be% = 9
    mov      DWORD PTR [var_be], 9
  line_number_18:   ; ===>>> 70 b%(1) = 0
    lea      r10, [ explist + 0 ]
    mov      DWORD PTR [ r10 + 0 ], 1
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 0
  line_number_19:   ; ===>>> 71 b%(4) = 1
    lea      r10, [ explist + 0 ]
    mov      DWORD PTR [ r10 + 0 ], 4
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 1
  line_number_20:   ; ===>>> 72 gosub 4000
    inc      [gosubcount]
    call     line_number_47
  line_number_21:   ; ===>>> 73 b%(4) = 0
    lea      r10, [ explist + 0 ]
    mov      DWORD PTR [ r10 + 0 ], 4
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 0
  line_number_22:   ; ===>>> 80 next l%
    inc      [var_l]
    jmp      for_loop_6
    align    16
  after_for_loop_6:
  line_number_23:   ; ===>>> 85 print elap$ ; " for 1000 iterations"
    lea      rcx, [currentTicks]
    call     call_QueryPerformanceCounter
    mov      rax, [currentTicks]
    sub      rax, [startTicks]
    mov      rcx, [perfFrequency]
    xor      rdx, rdx
    mov      rbx, 1000000
    mul      rbx
    div      rcx
    lea      rcx, [elapString]
    mov      rdx, rax
    call     call_printf
    lea      rcx, [strString]
    lea      rdx, [str_23_4]
    call     call_printf
    lea      rcx, [newlineString]
    call     call_printf
  line_number_24:   ; ===>>> 100 end
    jmp      end_execution
  line_number_25:   ; ===>>> 2000 wi% = b%( 0 )
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_b + 0]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_wi], eax
  line_number_26:   ; ===>>> 2010 if 0 = wi% goto 2100
    lea      r10, [ explist + 0 ]
    cmp      DWORD PTR [var_wi], 0
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      line_number_29
  line_number_27:   ; ===>>> 2020 if wi% = b%( 1 ) and wi% = b%( 2 ) then return
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_b + 4]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 8 ], eax
    mov      eax, DWORD PTR [var_b + 8]
    mov      DWORD PTR [ r10 + 12 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
; reduce memmove... i 1, expcount 7
    lea      rcx, [ r10 + 4 ]
    lea      rdx, [ r10 + 8 ]
    mov      r8, 8
    call     call_memmove
    mov      eax, DWORD PTR [ r10 + 4 ]
    cmp      eax, DWORD PTR [ r10 + 8 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      label_gosub_return
  line_number_28:   ; ===>>> 2030 if wi% = b%( 3 ) and wi% = b%( 6 ) then return
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_b + 12]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 8 ], eax
    mov      eax, DWORD PTR [var_b + 24]
    mov      DWORD PTR [ r10 + 12 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
; reduce memmove... i 1, expcount 7
    lea      rcx, [ r10 + 4 ]
    lea      rdx, [ r10 + 8 ]
    mov      r8, 8
    call     call_memmove
    mov      eax, DWORD PTR [ r10 + 4 ]
    cmp      eax, DWORD PTR [ r10 + 8 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      label_gosub_return
  line_number_29:   ; ===>>> 2100 wi% = b%( 3 )
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_b + 12]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_wi], eax
  line_number_30:   ; ===>>> 2110 if 0 = wi% goto 2200
    lea      r10, [ explist + 0 ]
    cmp      DWORD PTR [var_wi], 0
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      line_number_32
  line_number_31:   ; ===>>> 2120 if wi% = b%( 4 ) and wi% = b%( 5 ) then return
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_b + 16]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 8 ], eax
    mov      eax, DWORD PTR [var_b + 20]
    mov      DWORD PTR [ r10 + 12 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
; reduce memmove... i 1, expcount 7
    lea      rcx, [ r10 + 4 ]
    lea      rdx, [ r10 + 8 ]
    mov      r8, 8
    call     call_memmove
    mov      eax, DWORD PTR [ r10 + 4 ]
    cmp      eax, DWORD PTR [ r10 + 8 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      label_gosub_return
  line_number_32:   ; ===>>> 2200 wi% = b%( 6 )
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_b + 24]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_wi], eax
  line_number_33:   ; ===>>> 2210 if 0 = wi% goto 2300
    lea      r10, [ explist + 0 ]
    cmp      DWORD PTR [var_wi], 0
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      line_number_35
  line_number_34:   ; ===>>> 2220 if wi% = b%( 7 ) and wi% = b%( 8 ) then return
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_b + 28]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 8 ], eax
    mov      eax, DWORD PTR [var_b + 32]
    mov      DWORD PTR [ r10 + 12 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
; reduce memmove... i 1, expcount 7
    lea      rcx, [ r10 + 4 ]
    lea      rdx, [ r10 + 8 ]
    mov      r8, 8
    call     call_memmove
    mov      eax, DWORD PTR [ r10 + 4 ]
    cmp      eax, DWORD PTR [ r10 + 8 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      label_gosub_return
  line_number_35:   ; ===>>> 2300 wi% = b%( 1 )
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_b + 4]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_wi], eax
  line_number_36:   ; ===>>> 2310 if 0 = wi% goto 2400
    lea      r10, [ explist + 0 ]
    cmp      DWORD PTR [var_wi], 0
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      line_number_38
  line_number_37:   ; ===>>> 2320 if wi% = b%( 4 ) and wi% = b%( 7 ) then return
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_b + 16]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 8 ], eax
    mov      eax, DWORD PTR [var_b + 28]
    mov      DWORD PTR [ r10 + 12 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
; reduce memmove... i 1, expcount 7
    lea      rcx, [ r10 + 4 ]
    lea      rdx, [ r10 + 8 ]
    mov      r8, 8
    call     call_memmove
    mov      eax, DWORD PTR [ r10 + 4 ]
    cmp      eax, DWORD PTR [ r10 + 8 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      label_gosub_return
  line_number_38:   ; ===>>> 2400 wi% = b%( 2 )
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_b + 8]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_wi], eax
  line_number_39:   ; ===>>> 2410 if 0 = wi% goto 2500
    lea      r10, [ explist + 0 ]
    cmp      DWORD PTR [var_wi], 0
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      line_number_41
  line_number_40:   ; ===>>> 2420 if wi% = b%( 5 ) and wi% = b%( 8 ) then return
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_b + 20]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 8 ], eax
    mov      eax, DWORD PTR [var_b + 32]
    mov      DWORD PTR [ r10 + 12 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
; reduce memmove... i 1, expcount 7
    lea      rcx, [ r10 + 4 ]
    lea      rdx, [ r10 + 8 ]
    mov      r8, 8
    call     call_memmove
    mov      eax, DWORD PTR [ r10 + 4 ]
    cmp      eax, DWORD PTR [ r10 + 8 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      label_gosub_return
  line_number_41:   ; ===>>> 2500 wi% = b%( 4 )
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_b + 16]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_wi], eax
  line_number_42:   ; ===>>> 2510 if 0 = wi% then return
    lea      r10, [ explist + 0 ]
    cmp      DWORD PTR [var_wi], 0
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      label_gosub_return
  line_number_43:   ; ===>>> 2520 if wi% = b%( 0 ) and wi% = b%( 8 ) then return
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_b + 0]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 8 ], eax
    mov      eax, DWORD PTR [var_b + 32]
    mov      DWORD PTR [ r10 + 12 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
; reduce memmove... i 1, expcount 7
    lea      rcx, [ r10 + 4 ]
    lea      rdx, [ r10 + 8 ]
    mov      r8, 8
    call     call_memmove
    mov      eax, DWORD PTR [ r10 + 4 ]
    cmp      eax, DWORD PTR [ r10 + 8 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      label_gosub_return
  line_number_44:   ; ===>>> 2530 if wi% = b%( 2 ) and wi% = b%( 6 ) then return
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_b + 8]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 8 ], eax
    mov      eax, DWORD PTR [var_b + 24]
    mov      DWORD PTR [ r10 + 12 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
; reduce memmove... i 1, expcount 7
    lea      rcx, [ r10 + 4 ]
    lea      rdx, [ r10 + 8 ]
    mov      r8, 8
    call     call_memmove
    mov      eax, DWORD PTR [ r10 + 4 ]
    cmp      eax, DWORD PTR [ r10 + 8 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      label_gosub_return
  line_number_45:   ; ===>>> 2540 wi% = 0
    mov      DWORD PTR [var_wi], 0
  line_number_46:   ; ===>>> 2550 return
    jmp      label_gosub_return
  line_number_47:   ; ===>>> 4030 st% = 0
    mov      DWORD PTR [var_st], 0
  line_number_48:   ; ===>>> 4040 v% = 0
    mov      DWORD PTR [var_v], 0
  line_number_49:   ; ===>>> 4060 re% = 0
    mov      DWORD PTR [var_re], 0
  line_number_50:   ; ===>>> 4102 if st% < 4 then goto 4150
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 4
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    setl     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      line_number_57
  line_number_51:   ; ===>>> 4105 gosub 2000
    inc      [gosubcount]
    call     line_number_25
  line_number_52:   ; ===>>> 4106 if 0 = wi% then goto 4140
    lea      r10, [ explist + 0 ]
    cmp      DWORD PTR [var_wi], 0
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      line_number_56
  line_number_53:   ; ===>>> 4110 if wi% = 1 then re% = 6: goto 4280
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_wi]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 1
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    je       line_number_54
    mov      DWORD PTR [var_re], 6
    jmp      line_number_67
  line_number_54:   ; ===>>> 4115 re% = 4
    mov      DWORD PTR [var_re], 4
  line_number_55:   ; ===>>> 4116 goto 4280
    jmp      line_number_67
  line_number_56:   ; ===>>> 4140 if st% = 8 then re% = 5: goto 4280
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 8
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    je       line_number_57
    mov      DWORD PTR [var_re], 5
    jmp      line_number_67
  line_number_57:   ; ===>>> 4150 if st% and 1 then v% = 2 else v% = 9
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 1
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    je       label_else_57
    mov      DWORD PTR [var_v], 2
    jmp      line_number_58
    align    16
  label_else_57:
    mov      DWORD PTR [var_v], 9
  line_number_58:   ; ===>>> 4160 p% = 0
    mov      DWORD PTR [var_p], 0
  line_number_59:   ; ===>>> 4180 if 0 <> b%(p%) then goto 4500
    lea      r10, [ explist + 0 ]
    push     r10
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_p]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    pop      r10
    shl      rax, 2
    lea      rbx, DWORD PTR [var_b]
    add      rax, rbx
    mov      eax, DWORD PTR [rax]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      line_number_83
  line_number_60:   ; ===>>> 4200 if st% and 1 then b%(p%) = 1 else b%(p%) = 2
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 1
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    je       label_else_60
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_p]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 1
    jmp      line_number_61
    align    16
  label_else_60:
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_p]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 2
  line_number_61:   ; ===>>> 4210 sp%(st%) = p%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_sp]
    add      rbx, rax
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_p]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [rbx], eax
  line_number_62:   ; ===>>> 4230 sv%(st%) = v%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_sv]
    add      rbx, rax
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_v]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [rbx], eax
  line_number_63:   ; ===>>> 4245 sa%(st%) = al%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_sa]
    add      rbx, rax
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_al]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [rbx], eax
  line_number_64:   ; ===>>> 4246 sb%(st%) = be%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_sb]
    add      rbx, rax
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_be]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [rbx], eax
  line_number_65:   ; ===>>> 4260 st% = st% + 1
    inc      DWORD PTR [var_st]
  line_number_66:   ; ===>>> 4270 goto 4100
    jmp      line_number_50
  line_number_67:   ; ===>>> 4280 st% = st% - 1
    dec      DWORD PTR [var_st]
  line_number_68:   ; ===>>> 4290 p% = sp%(st%)
    lea      r10, [ explist + 0 ]
    push     r10
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    pop      r10
    shl      rax, 2
    lea      rbx, DWORD PTR [var_sp]
    add      rax, rbx
    mov      eax, DWORD PTR [rax]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_p], eax
  line_number_69:   ; ===>>> 4310 v% = sv%(st%)
    lea      r10, [ explist + 0 ]
    push     r10
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    pop      r10
    shl      rax, 2
    lea      rbx, DWORD PTR [var_sv]
    add      rax, rbx
    mov      eax, DWORD PTR [rax]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_v], eax
  line_number_70:   ; ===>>> 4325 al% = sa%(st%)
    lea      r10, [ explist + 0 ]
    push     r10
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    pop      r10
    shl      rax, 2
    lea      rbx, DWORD PTR [var_sa]
    add      rax, rbx
    mov      eax, DWORD PTR [rax]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_al], eax
  line_number_71:   ; ===>>> 4326 be% = sb%(st%)
    lea      r10, [ explist + 0 ]
    push     r10
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    pop      r10
    shl      rax, 2
    lea      rbx, DWORD PTR [var_sb]
    add      rax, rbx
    mov      eax, DWORD PTR [rax]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_be], eax
  line_number_72:   ; ===>>> 4328 b%(p%) = 0
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_p]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    shl      rax, 2
    lea      rbx, [var_b]
    mov      DWORD PTR [rbx + rax], 0
  line_number_73:   ; ===>>> 4330 if st% and 1 goto 4340
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_st]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 1
    mov      eax, DWORD PTR [ r10 + 0 ]
    and      eax, DWORD PTR [ r10 + 4 ]
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      line_number_79
  line_number_74:   ; ===>>> 4331 if re% = 4 then goto 4530
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_re]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 4
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      line_number_86
  line_number_75:   ; ===>>> 4332 if re% < v% then v% = re%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_re]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_v]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    setl     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    je       line_number_76
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_re]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_v], eax
  line_number_76:   ; ===>>> 4334 if v% < be% then be% = v%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_v]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_be]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    setl     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    je       line_number_77
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_v]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_be], eax
  line_number_77:   ; ===>>> 4336 if be% <= al% then goto 4520
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_be]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_al]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    setle    al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      line_number_85
  line_number_78:   ; ===>>> 4338 goto 4500
    jmp      line_number_83
  line_number_79:   ; ===>>> 4340 if re% = 6 then goto 4530
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_re]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 6
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      line_number_86
  line_number_80:   ; ===>>> 4341 if re% > v% then v% = re%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_re]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_v]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    setg     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    je       line_number_81
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_re]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_v], eax
  line_number_81:   ; ===>>> 4342 if v% > al% then al% = v%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_v]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_al]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    setg     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    je       line_number_82
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_v]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_al], eax
  line_number_82:   ; ===>>> 4344 if al% >= be% then goto 4520
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_al]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [var_be]
    mov      DWORD PTR [ r10 + 4 ], eax
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    setge    al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      line_number_85
  line_number_83:   ; ===>>> 4500 p% = p% + 1
    inc      DWORD PTR [var_p]
  line_number_84:   ; ===>>> 4505 if p% < 9 then goto 4180
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_p]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      DWORD PTR [ r10 + 4 ], 9
    mov      eax, DWORD PTR [ r10 + 0 ]
    cmp      eax, DWORD PTR [ r10 + 4 ]
    setl     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    cmp      rax, 0
    jne      line_number_59
  line_number_85:   ; ===>>> 4520 re% = v%
    lea      r10, [ explist + 0 ]
    mov      eax, DWORD PTR [var_v]
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    mov      DWORD PTR [var_re], eax
  line_number_86:   ; ===>>> 4530 if st% = 0 then return
    lea      r10, [ explist + 0 ]
    cmp      DWORD PTR [var_st], 0
    sete     al
    movzx    rax, al
    mov      DWORD PTR [ r10 + 0 ], eax
    mov      eax, DWORD PTR [ r10 ]
    cmp      rax, 0
    jne      label_gosub_return
  line_number_87:   ; ===>>> 4540 goto 4280
    jmp      line_number_67
  line_number_88:   ; ===>>> END
    jmp      end_execution
label_gosub_return:
    ret
  error_exit:
    lea      rcx, [errorString]
    call     call_printf
    jmp      leave_execution
  end_execution:
    lea      rcx, [stopString]
    call     call_printf
  leave_execution:
    xor      rcx, rcx
    call     call_exit
    ret
main ENDP
align 16
call_printf PROC
    push     r9
    push     r10
    push     r11
    push     rbp
    mov      rbp, rsp
    sub      rsp, 32
    call     printf
    leave
    pop      r11
    pop      r10
    pop      r9
    ret
call_printf ENDP
align 16
call_exit PROC
    push     rbp
    mov      rbp, rsp
    sub      rsp, 32
    call     exit
    leave
    ret
call_exit ENDP
align 16
call_QueryPerformanceCounter PROC
    push     r9
    push     r10
    push     r11
    push     rbp
    mov      rbp, rsp
    sub      rsp, 32
    call     QueryPerformanceCounter
    leave
    pop      r11
    pop      r10
    pop      r9
    ret
call_QueryPerformanceCounter ENDP
align 16
call_GetLocalTime PROC
    push     r9
    push     r10
    push     r11
    push     rbp
    mov      rbp, rsp
    sub      rsp, 32
    call     GetLocalTime
    leave
    pop      r11
    pop      r10
    pop      r9
    ret
call_GetLocalTime ENDP
align 16
call_memmove PROC
    push     r9
    push     r10
    push     r11
    push     rbp
    mov      rbp, rsp
    sub      rsp, 32
    call     memmove
    leave
    pop      r11
    pop      r10
    pop      r9
    ret
call_memmove ENDP
code_segment ENDS
END
