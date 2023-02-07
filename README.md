# ttt
tic-tac-toe and its applicability to nuclear war and WOPR

Source code referred to here: https://medium.com/@davidly_33504/tic-tac-toe-and-its-applicability-to-nuclear-war-and-wopr-13be09ec05c9

In short, this repo contains various implementations of code to prove that you can't win at tic-tac-toe if the opponent is competent.

Aside from tic-tac-toe, this code provides examples of how to do things in various languages (go, Python, Lua, Julia, Rust, Visual Basic, Pascal, C#, C++, Swift, assembly language for 6502, 8080, 8086, 32-bit x86, Arm32, x64, and Arm64) including concurrency, high resolution timing, pointers to functions, passing arguments by reference and value, basic control flow, atomic increments, etc.

To build:

    - go: go build ttt.go
    - Rust: rustc -O ttt.rs
    - MSVC: cl /nologo ttt.cxx /Ox /Qpar /Ob2 /O2i /EHac /Zi /D_AMD64_ /link ntdll.lib
    - GNU: g++ -DNDEBUG ttt.cxx -o ttt -O3 -fopenmp
    - Lua: lua54 ttt.lua
    - LuaJit: read instructions in ttt_lj.cxx for how to build and run
    - 6502 on the Apple 1: sbasm30306\sbasm.py ttt_6502.s
    	- this generates a .h file that can be transferred to the Apple 1
    - Julia: julia -q --optimize=3 --check-bounds=no -t auto ttt.jl
    - Python: python3 ttt.py
    - MacOS clang: clang++ -DNDEBUG -Xpreprocessor -fopenmp -lomp -std=c++11 -Wc++11-extensions -I"$(brew --prefix libomp)/include" -L"$(brew --prefix libomp)/lib" ttt.cxx -O3 -o ttt
    - x64 ASM: ml64 /nologo ttt_x64.asm /Flx.lst /Zd /Zf /Zi /link /OPT:REF /nologo ^
                                        /subsystem:console /defaultlib:kernel32.lib ^
                                        /defaultlib:user32.lib ^
                                        /defaultlib:libucrt.lib ^
                                        /defaultlib:libcmt.lib ^
                                        /entry:mainCRTStartup
    - .net 4: c:\windows\microsoft.net\framework64\v4.0.30319\csc.exe /checked- /nologo /o+ /nowarn:0168 /nowarn:0162 ttt.cs
    - .net 6 on Windows: dotnet publish ttt.csproj --configuration Release -r win10-x64 -f net6.0 --no-self-contained -p:PublishSingleFile=true -p:PublishReadyToRun=true -o .\ -nologo
    - .net 6 on MAC: same as Windows, but use -r osx.12-arm64
    - Visual Basic (ttt.vb) using .net6: use mvb.bat (vbc.exe /nologo /optimize+ ttt.vb)
    - Turbo Pascal -- load and build in the app
    - Building for Virtualt TRS80 Model 100 emulator (and use the output for the physical TRS80 Model 100)
		      ○ Ttta.asm
		      ○ Fixed app origin is 0xc738 == 51000
		      ○ Reserve the RAM in BASIC with Clear 256, 50000    (this clears 50000 and above)
		      ○ The IDE will install the ttta.co app when it's built
		      ○ Run it in BASIC with runm "ttta"
		      ○ Or like this:
			      § 10 print time$
			      § 20 runm "ttta"
			      § 30 print "  ";time$
          ○ I put code and data all in one segment because trying other ways caused VirtualT to crash.

I was curious about the relative performance of the Python, Julia, and Lua interpreters. Why is Python almost 2x slower than the others?
How hard is it to implement a faster interpreter? Since I couldn't find a reputable BASIC interpreter that runs on x64, I wrote one 
called BA. The code is here in ba.cxx. It runs just enough BASIC for TTT (see the source file for limitations). I updated the BASIC 
app for TTT to use a 1-dimensional array for the board instead of 2 so it'd be in line with other implementations (and quite a
bit faster). That's called ttt-1dim.bas. As seen in the table below, it was easy to create an interpreter for BASIC that's faster than
Python. BASIC doesn't support function (goto/gosub) pointers. The Python, Julia, and Lua versions without function pointers 
run slower (4.34, 1.48, and 2.31 ms respectively) than with them. The BA version runs in 2.23ms, so it's faster than all but Julia. 
The BA version is faster than Python even when Python is using function pointers.

I'm not really proud of BA -- it was a very quickly written hack. But it shows that Python could benefit from some performance work.

I added minimal support in BA to compile BASIC apps to x64 .asm files which can then be assembled into a Windows .exe file. 
Afterwards I added codegen for Arm64 on Macs, Arm64 for Windows, Arm32 on Linux, MOS 6502 on the Apple 1, Intel 8080 on CP/M 2.2, 
8086 on DOS, and 32-bit x86 on Windows. Use the -a:x flag in BA to generate the x64 .asm file, and ma.bat to create the .exe. 
For example:

    ba ttt_1dim.bas /x /a:x
    ma.bat ttt_1dim
    ttt_1dim.exe
    
To compile code and run on an 8080/Z80 CP/M 2.2 machine:

    ba app.bas /x /a:8
    (copy app.asm to a CP/M machine)
    asm app
    load app
    app
    
To commpile code and run on an arm64 Mac:

    ba ttt_1dim.bas /x /a:m
    ./ma.sh ttt_1dim
    ./ttt_1dim
    
To compile code and run on an arm32 Raspberry PI 3:

    ba ttt_1dim.bas /x /a:3
    gcc -o ttt_1dim ttt_1dim.s -march=armv8-a
    ./ttt_1dim
    
To compile and run on a MOS 6502 Apple 1

    ba foo.bas /x /a:6
    sbasm.py foo.s
    copy foo.h to the Apple 1, then on that machine:
    1000 r    
        
The compiler generates code that's in the middle of the pack of most real compilers on both x64 Windows and arm64 Mac. The 8080 code
generated for CP/M 2.2 systems is about 3x as fast as Turbo Pascal 3.01A and 3x slower than hand-written assembler code (mostly due
to using 16-bit integers and lack of global optimizations). 6502 code generation is OK given that's it's such a hard target for
compilers and working with 16 bit integers is so cumbersome. The arm32 and 32 bit x86 code is mostly unoptimized but working.

To build BA:

    On Windows in CMD with Visual Studio's vcvars64.bat use m.bat (for retail) or mdbg (for debug).
    On Linux with gnu: g++ -DNDEBUG ba.cxx -o ba -O3
    On Linux with clang: clang++ -DNDEBUG ba.cxx -o ba -O3
    On Windows with clang: "c:\program files\llvm\bin\clang++.exe" ba.cxx -D_CRT_SECURE_NO_WARNINGS -DNDEBUG -o ba.exe -O3 -Ofast
    On a Mac: mmac.sh or this: clang++ ba.cxx -DNDEBUG -o ba -O3 -std=c++11

To run ttt_trs80.asm on a TRS-80. (renamed as ttt.asm)

    Use Virtual T in TRS-80 Model 100 emulation mode and speed set to 2.4Mhz
    In the integrated IDE, create a project for ttt.asm
    Assemble and link it, which copies ttt.co to the emulator, then invoke on the emulator with something like:
    
        Clear 256, 50000
        10 print time$
        20 runm "ttt"
        30 print "  ";time$
	
    To run on an actual TRS-80:
    
        Hd /d /n ttt.co >t.do   -- this creates a 7-bit ascii file that can be transferred. HD is another repo on my github
        Use PuTTY or similar app to connect to the serial port and configure for 9600 baud, 8 bits, even parity, 1 stop bit, and xon/xoff enable. 
        Exit putty so it frees the com port for the command below.
	
        Transfer lt.ba, which translates the assembly code back to a .co file and run the binary:
	
            In basic (only basic can transfer .ba files and only TELCOM can copy .DO files)
            Load "com:88E1E"
            On the pc, copy lt.ba com3
            After the transfer, hit Break on the trs-80
            Save the code to the RAM filesystem as lt.ba using F3 (save)
	
        Load, process, and execute t.do:
	
            On the trs-80, go into Telcom and configure serial to the same settings as above.
            Start terminal and press f2 for download. Specify t.do
            On the pc, copy t.do com3
            On the trs-80, F8 to exit and say yes Y to disconnect, then f8 to go back to the root menu
            Run lt.ba, which loads t.do, converts it to binary in RAM, and executes the app


![runtimes_notes](https://user-images.githubusercontent.com/1497921/217294406-cdd2420f-9a34-4d11-bb53-8a679c9bd9e3.png)
![runtimes](https://user-images.githubusercontent.com/1497921/217294287-c8c00be1-cc54-438b-9ebe-f0287c717bb6.png)
