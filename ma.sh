as -arch arm64 $1.s -o $1.o
ld $1.o -o $1 -syslibroot 'xcrun -sdk macos --show-sdk-path' -e _start -L /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib -lSystem
