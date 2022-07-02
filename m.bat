@echo off
del ba.exe
del ba.pdb
@echo on

cl /nologo ba.cxx /MT /Ox /Qpar /O2 /Oi /Ob2 /EHac /Zi /Gy /DNDEBUG /D_AMD64_ /link ntdll.lib /OPT:REF

