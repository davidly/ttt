# ttt
tic-tac-toe and its applicability to nuclear war and WOPR

Source code referred to here: https://medium.com/@davidly_33504/tic-tac-toe-and-its-applicability-to-nuclear-war-and-wopr-13be09ec05c9

Aside from tic-tac-toe, this code provides examples of how to do things in various languages (go, Python, Lua, Julia, Rust, Visual Basic, Pascal, C#, C++, Swift, x64 and 8080 assembly languages) including concurrency, high resolution timing, pointers to functions, passing arguments by reference and value, basic control flow, atomic increments, etc.

To build:

    - go: go build ttt.go
    - Rust: rustc -O ttt.rs
    - MSVC: cl /nologo ttt.cxx /Ox /Qpar /Ob2 /O2i /EHac /Zi /D_AMD64_ /link ntdll.lib
    - GNU: g++ -DNDEBUG ttt.cxx -o ttt -O3 -fopenmp
    - Lua: lua54 ttt.lua
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

I added minimal support in BA to compile BASIC apps to x64 .asm files which can then be assembled into a Windows .exe file. Use the -a flag in BA
to generate the .asm file, and ma.bat to create the .exe. For example:

    ba ttt_1dim.bas /x /a
    ma.bat ttt_1dim
    ttt_1dim.exe
    
To compile code and run on an 8080/Z80 CP/M 2.2 machine:

    ba app.bas /x /8
    (copy app.asm to a CP/M machine)
    asm app
    load app
    app
    
To commpile code and run on an arm64 Mac:

    ba ttt_1dim.bas /x /m
    ./ma.sh ttt_1dim
    ./ttt_1dim
    
The compiler generates code that's in the middle of the pack of most real compilers on both x64 Windows and arm64 Mac. The 8080 code
generated for CP/M 2.2 systems is about 3x as fast as Turbo Pascal 3.01A and 2x slower than hand-written assembler code (mostly due
to using 16-bit integers and lack of global optimizations).

To build BA:

    On Windows in CMD with Visual Studio's vcvars64.bat use m.bat (for retail) or mdbg (for debug).
    On Linux with gnu: g++ -DNDEBUG ba.cxx -o ba -O3
    On Linux with clang: clang++ -DNDEBUG ba.cxx -o ba -O3
    On Windows with clang: "c:\program files\llvm\bin\clang++.exe" ba.cxx -D_CRT_SECURE_NO_WARNINGS -DNDEBUG -o ba.exe -O3 -Ofast
    On a Mac: mmac.sh or this: clang++ ba.cxx -DNDEBUG -o ba -O3 -std=c++11
	
![image](https://user-images.githubusercontent.com/1497921/183231243-44d981f1-5881-4576-b3ee-384bf828be87.png)





