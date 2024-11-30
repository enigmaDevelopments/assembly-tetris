NAME=game

all: game

clean:
	rm -rf game game.o

game: game.asm
	nasm -f elf game.asm
	# gcc -no-pie -g -m32 -o game game.o /usr/local/share/csc314/driver.c /usr/local/share/csc314/asm_io.o
	gcc -no-pie -g -m32 -o game game.o /mnt/c/Users/granite/Documents/AssemblyLanguage/gameBasecopy/game/driver.c /mnt/c/Users/granite/Documents/AssemblyLanguage/gameBasecopy/game/asm_io.o
	