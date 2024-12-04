NAME=game

all: game

clean:
	rm -rf game game.o

preprocess:
	dos2unix board.txt

game: game.asm
	nasm -f elf game.asm
	# gcc -no-pie -g -m32 -o game game.o driver.c asm_io.o
	gcc -no-pie -g -m32 -o game game.o driver.c asm_io.o
	