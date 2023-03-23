@echo off
del ba.exe
del ba.pdb
@echo on

rem cl /nologo ba.cxx /MT /Ot /Ox /Ob2 /Oi /Qpar /O2 /EHac /Zi /favor:AMD64 /DNDEBUG /D_AMD64_ /link ntdll.lib /OPT:REF
cl /nologo ba.cxx /MT /Ot /Ox /Ob2 /Oi /Qpar /O2 /EHac /Zi /DNDEBUG /D_AMD64_ /link ntdll.lib /OPT:REF

