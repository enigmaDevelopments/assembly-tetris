NAME=game

all: game

clean:
	rm -rf assembly-tetris game.o

game: game.asm
	nasm -f elf game.asm
	gcc -no-pie -g -m32 -o game game.o driver.c asm_io.o