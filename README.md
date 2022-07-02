# ttt
tic-tac-toe and its applicability to nuclear war and WOPR

Source code referred to here: https://medium.com/@davidly_33504/tic-tac-toe-and-its-applicability-to-nuclear-war-and-wopr-13be09ec05c9

Aside from tic-tac-toe, this code provides examples of how to do things in various languages (go, Rust, C#, C++, swift, assembly languages) including concurrency, high resolution timing, pointers to functions, passing arguments by reference and value, basic control flow, atomic increments, etc.

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
bit faster). That's call ttt-1dim.bas. As seen in the table below, it was easy to create an interpreter for BASIC that's faster than
Python. BASIC doesn't support function (goto/gosub) pointers. The Python, Julia, and Lua versions without function pointers 
run slower (4.34, 1.48, and 2.31 ms respectively) than with them. The BA version runs in 2.23ms, so it's faster than all but Julia. 
The BA version is faster than Python even when Python is using function pointers.

I'm not really proud of BA -- it was a very quickly written hack. But it shows that Python could benefit from some performance work.

BA.cxx can be built from a CMD prompt initialized with Visual Studio's vcvars64.bat using m.bat (for retail) or mdbg (for debug).

![image](https://user-images.githubusercontent.com/1497921/177012849-80e435cf-d5ca-43b7-9b33-a0c5f40c561f.png)



