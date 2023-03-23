@echo off
ml64 /nologo %1.asm /Zd /Zf /Zi /link /OPT:REF /nologo /PDB:%1.pdb ^
     /subsystem:console /defaultlib:kernel32.lib ^
     /defaultlib:user32.lib ^
     /defaultlib:libucrt.lib ^
     /defaultlib:libcmt.lib ^
     /entry:mainCRTStartup


