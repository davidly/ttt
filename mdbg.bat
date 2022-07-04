@echo off
del ba.exe
del ba.pdb
@echo on

cl /nologo ba.cxx /Ot /Ox /O2 /Ob2 /MT /EHac /Zi /Gy /DDEBUG /D_AMD64_ /link ntdll.lib /OPT:REF


