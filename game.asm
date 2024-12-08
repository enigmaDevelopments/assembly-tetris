;%include "/usr/local/share/csc314/asm_io.inc"
%include "asm_io.inc"
; the file that stores the initial state
%define BOARD_FILE 'board.txt'

; how to represent everything
%define AIR_CHAR ' '
%define PLAYER_CHAR '['
%define PLAYER_CHAR2 ']'

; the size of the game screen in characters
%define HEIGHT 22
%define WIDTH 24

; the player starting position.
; top left is considered (0,0)
%define STARTX 12
%define STARTY 0

; these keys do things
%define EXITCHAR 'x'
%define UPCHAR 'w'
%define LEFTCHAR 'a'
%define DOWNCHAR 's'
%define RIGHTCHAR 'd'
%define CLOCKWISECHAR 'e'
%define COUNTERCLOCKWISECHAR 'q'
%define HOLDCHAR ' '


segment .data
	; used to fopen() the board file defined above
	board_file			db BOARD_FILE,0

	; used to change the terminal mode
	mode_r				db "r",0
	raw_mode_on_cmd		db "stty raw -echo",0
	raw_mode_off_cmd	db "stty -raw echo",0

	; ANSI escape sequence to clear/refresh the screen
	clear_screen_code	db	27,"[2J",27,"[H",0

	; things the program will print
	help_str			db 13,10,"Controls: ", \
							UPCHAR,"=UP / ", \
							LEFTCHAR,"=LEFT / ", \
							DOWNCHAR,"=DOWN / ", \
							RIGHTCHAR,"=RIGHT / ", \
							EXITCHAR,"=EXIT", \
							13,10,10,0
	tetrominoes         db -2,0, 0,0, 2,0, 4,0, \
							0,0, 0,1, 0,2, 0,3, \
							-2,0, 0,0, 2,0, 4,0, \
							0,0, 0,1, 0,2, 0,3, \
							\
							0,0, 0,1, 2,0, 2,1, \
							0,0, 0,1, 2,0, 2,1, \
							0,0, 0,1, 2,0, 2,1, \
							0,0, 0,1, 2,0, 2,1, \
							\
							-2,0, 0,0, 0,1, 2,0, \
							0,0, 0,1, 0,2, 2,1, \
							-2,1, 0,0, 0,1, 2,1,\
							-2,1, 0,0, 0,1, 0,2, \
							\
							-2,0, 0,0, 0,1, 2,1, \
							-2,1, -2,2, 0,0, 0,1,\
							-2,0, 0,0, 0,1, 2,1, \
							-2,1, -2,2, 0,0, 0,1,\
							\
							-2,1, 0,0, 0,1, 2,0, \
							0,0, 0,1, 2,1, 2,2, \
							-2,1, 0,0, 0,1, 2,0, \
							0,0, 0,1, 2,1, 2,2, \
							\
							-2,0, 0,0, 2,0, 2,1, \
							0,0, 0,1, 0,2, 2,0, \
							-2,0, -2,1, 0,1, 2,1, \
							0,2, 2,0, 2,1, 2,2, \
							\
							-2,0,-2,1, 0,0, 2,0, \
							0,0, 0,1, 0,2, 2,2, \
							-2,1, 0,1, 2,0, 2,1, \
							0,0, 2,0, 2,1, 2,2 
	clear_line			db "<!                    !>"
	score_label db" Score: %d", 0
    level_label db " Level: %d", 0
    next_blocks_label db " Next Block ", 0
	held_blocks_label db " Held Block ", 0
	game_over_label db " Game Over. ", 0

segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)

	; these variables store the current player position
	xpos	resb	2
	ypos	resb	2
	time 	resd	1
	level	resb	1
	score	resd    1
	tetris_flag	resb 1
	used_blocks resb 2
	next_blocks resb 2
	held_block 	resb 2
	rotation resb 2
	print_score_keeper resb 1  

segment .text

	global	asm_main
	global  raw_mode_on
	global  raw_mode_off
	global  init_board
	global  render
	global 	timer
	global 	random
	global 	collition_test
	global auto_drop
	global check_collision
	global write_pos
	global get_pos

	extern	system
	extern	putchar
	extern	getchar
	extern	printf
	extern	fopen
	extern	fread
	extern	fgetc
	extern	fclose

asm_main:
	push	ebp
	mov		ebp, esp

	; put the terminal in raw mode so the game works nicely
	call	raw_mode_on

	; read the game board file into the global variable
	call	init_board

	; set the player at the proper start position
	mov		byte [xpos], STARTX
	mov		byte [ypos], STARTY
	mov		byte [xpos+1], STARTX
	mov		byte [ypos+1], STARTY

	rdtsc
	mov [time], eax; set initial time
	mov [level], byte 1; set level to 1
	mov [used_blocks], word 077Fh;set used blocks to defult mask and count
	call random
	call random;initialize first blocks

	call render

	; the game happens in this loop
	; the steps are...
	;   1. render (draw) the current board
	;   2. get a character from the user
	;	3. store current xpos,ypos in esi,edi
	;	4. update xpos,ypos based on character from user
	;	5. check what's in the buffer (board) at new xpos,ypos
	;	6. if it's a wall, reset xpos,ypos to saved esi,edi
	;	7. otherwise, just continue! (xpos,ypos are ok)
	game_loop:
		; Render the game board
			; Perform auto-drop
			call timer

			; Process player input
			call getchar
			cmp eax,-1
			je game_loop

			; Compare input character and perform actions
			cmp eax, UPCHAR
			je hard_drop
			cmp eax, DOWNCHAR
			je move_down
			cmp eax, CLOCKWISECHAR
			je rotate_clockwise
			cmp eax, COUNTERCLOCKWISECHAR
			je rotate_counterclockwise
			cmp eax, HOLDCHAR
			je hold
			cmp eax, EXITCHAR
			je game_loop_end
			cmp eax, LEFTCHAR
			je move_left
			cmp eax, RIGHTCHAR
			je move_right
			jmp input_end          ; No valid input, skip processing

			; Move the player according to the input character
		rotate_clockwise:
			inc byte [rotation]
			cmp byte [rotation], 4
			jne input_end
			mov byte [rotation], 0
			jmp input_end

		rotate_counterclockwise:
			dec byte [rotation]
			cmp byte [rotation], -1
			jne input_end
			mov byte [rotation], 3
			jmp input_end

		hold:
			cmp byte [held_block+1], 1
			je input_end
			mov bl, [next_blocks]
			cmp byte [held_block+1], 2
			je move_to_hold
			mov bh, [next_blocks + 1]
			mov [held_block], bh
			call random
			move_to_hold:
			mov bh, [held_block]
			mov [next_blocks], bh 
			mov [held_block], bl
			mov byte [held_block+1], 1

			mov		byte [xpos], STARTX
			mov		byte [ypos], STARTY
			mov		byte [xpos+1], STARTX
			mov		byte [ypos+1], STARTY
			mov		word [rotation],0
			call render
			jmp game_loop

		hard_drop:
			inc byte [ypos]
			add dword [score], 2
			call check_collision
			cmp byte [ypos], 0
			jne hard_drop
			jmp game_loop

		move_left:
			sub byte [xpos], 2
			jmp input_end

		move_down:
			inc byte [ypos]
			inc dword [score]
			jmp input_end

		move_right:
			add byte [xpos], 2

		input_end:
		call check_collision
		jmp game_loop

		game_over_end:
		mov eax, game_over_label
		call print_string
		call print_nl
		mov eax, 0dH
		call print_char
		jmp game_loop_end

		game_loop_end:
	;restore old terminal functionality
	call raw_mode_off

	mov		eax, 0
	mov		esp, ebp
	pop		ebp
	ret

raw_mode_on:
	push	ebp
	mov		ebp, esp
	pusha

	push	raw_mode_on_cmd
	call	system
	add		esp, 4
	
	mov eax, 0x37			; syscall number for fcntl
    mov ebx, 0				; file descriptor
    mov ecx, 4				; F_SETFL command
    mov edx, 0800h			; O_NONBLOCK flag
    int 0x80				; invoke syscall

	popa
	mov		esp, ebp
	pop		ebp
	ret

raw_mode_off:

	push	ebp
	mov		ebp, esp

	push	raw_mode_off_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret


init_board:

	push	ebp
	mov		ebp, esp

	; FILE* and loop counter
	; ebp-4, ebp-8
	sub		esp, 8

	; open the file
	push	mode_r
	push	board_file
	call	fopen
	add		esp, 8
	mov		DWORD [ebp - 4], eax

	; read the file data into the global buffer
	; line-by-line so we can ignore the newline characters
	mov		DWORD [ebp - 8], 0
	read_loop:
	cmp		DWORD [ebp - 8], HEIGHT
	je		read_loop_end

		; find the offset (WIDTH * counter)
		mov		eax, WIDTH
		mul		DWORD [ebp - 8]
		lea		ebx, [board + eax]

		; read the bytes into the buffer
		push	DWORD [ebp - 4]
		push	WIDTH
		push	1
		push	ebx
		call	fread
		add		esp, 16

		; slurp up the newline
		push	DWORD [ebp - 4]
		call	fgetc
		add		esp, 4

	inc		DWORD [ebp - 8]
	jmp		read_loop
	read_loop_end:

	; close the open file handle
	push	DWORD [ebp - 4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

render:

	push	ebp
	mov		ebp, esp

	; two ints, for two loop counters
	; ebp-4, ebp-8
	; plus 8 bytes, for storing player positions
	sub		esp, 16

	;save player positions
	mov eax, tetrominoes
	movzx ebx, byte [next_blocks]
	movzx ecx, byte [rotation]
	shl ebx, 5
	shl ecx, 3
	add ebx, ecx
	mov ecx, dword [eax + ebx]
	mov [ebp - 16], ecx
	mov ecx, dword [eax + ebx + 4]
	mov [ebp - 12], ecx
	; clear the screen
	push	clear_screen_code
	call	printf
	add		esp, 4

	; print the help information
	push	help_str
	call	printf
	add		esp, 4

	; outside loop by height
	; i.e. for(c=0; c<height; c++)
	mov		DWORD [ebp - 4], 0
	y_loop_start:
	cmp		DWORD [ebp - 4], HEIGHT
	je		y_loop_end

		; inside loop by width
		; i.e. for(c=0; c<width; c++)
		mov		DWORD [ebp - 8], 0
		x_loop_start:
		cmp		DWORD [ebp - 8], WIDTH
		je 		x_loop_end
			mov ecx, -18
			player_check_loop:
			add ecx, 2
			cmp ecx, -8
			je print_board

			; check if (xpos,ypos)=(x,y)
			movzx	eax, BYTE [xpos]
			movsx	ebx, BYTE [ebp + ecx]
			add		eax, ebx
			cmp		eax, DWORD [ebp - 8]
			jne		player_check_loop
			movzx	eax, BYTE [ypos]
			movsx	ebx, BYTE [ebp + ecx + 1]
			sub		eax, ebx
			cmp		eax, DWORD [ebp - 4]
			jne		player_check_loop
				; if both were equal, print the player
				push	PLAYER_CHAR
				call	putchar
				push	PLAYER_CHAR2
				call	putchar
				add		esp, 8
				inc		DWORD [ebp - 8]
				jmp		print_end
			print_board:
				; otherwise print whatever's in the buffer
				mov		eax, DWORD [ebp - 4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, DWORD [ebp - 8]
				mov		ebx, 0
				mov		bl, BYTE [board + eax]
				push	ebx
				call	putchar
				add		esp, 4
			print_end:

		inc		DWORD [ebp - 8]
		jmp		x_loop_start
		x_loop_end:

		;load global print_score_keeper state
		    mov eax, DWORD [print_score_keeper]

			; Print Score on the first row
			cmp     eax, 0        ;if print_score_keeper is 0
			jne     gotto_level  ; Only print score on the first row
			cmp     DWORD [ebp - 4], 0  ;only print on the second row 
			jne     gotto_level  ; Only print score on the first row
			push DWORD [score]
			push    score_label
			call    printf
			add     esp, 8
			
			gotto_level:
			movzx ebx, byte [level]  ; Backup level
			; Print Level on the second row
			mov eax, DWORD [print_score_keeper]
			cmp     eax, 0 ;compare to print_score_keeper and if its one print level
			jne     gotto_nextblock  ; Only print level on the second row
			cmp     DWORD [ebp - 4], 1  ;only print on the second row 
			jne     gotto_nextblock  ; Only print level on the second row
			push ebx
		    push    level_label
			call    printf
		    add     esp, 8

			gotto_nextblock:
			; Print Next Block on the third row
			cmp     eax, 0 ;compare to print_score_keeper and if its 2 print level
			jne     gotto_heldblock  ; Only print next block on the third row
			cmp     DWORD [ebp - 4], 3
			jne     gotto_heldblock  ; Only print next block on the third row
			push    next_blocks_label
			call    printf
			add     esp, 4

			;print next_blocks+1
			;cmp   DWORD [ebp -4],4
			;push DWORD [next_blocks + 1]
			;call printf
			;add esp, 4


			gotto_heldblock:
			; Print Next Block on the third row
			cmp     eax, 0 ;compare to print_score_keeper and if its 2 print level
			jne     skip_next  ; Only print next block on the third row
			cmp     DWORD [ebp - 4], 8
			jne     skip_next  ; Only print next block on the third row
			push    held_blocks_label
			call    printf
			add     esp, 4
			

		skip_next:

		; write a carriage return (necessary when in raw mode)
		push	0x0d
		call 	putchar
		add		esp, 4

		; write a newline
		push	0x0a
		call	putchar
		add		esp, 4

	inc		DWORD [ebp - 4]
	jmp		y_loop_start
	y_loop_end:

	mov		esp, ebp
	pop		ebp
	ret

timer:
    pusha

    rdtsc                    ; Get current clock cycles
    mov edx, eax             ; Save current cycles in edx
    mov ebx, [time]          ; Load previously saved cycles
    sub eax, ebx             ; Calculate elapsed cycles
    mov ecx, eax             ; Store elapsed cycles in ecx

    movzx eax, byte [level]  ; Load the current level
    mov ebx, 1A5E3544h       ; Base interval (5 seconds in clock cycles)
    mul ebx                  ; Multiply base interval by level
    mov ebx, 0CCCCCCCCh      ; Maximum interval
    sub ebx, eax             ; Calculate the drop interval

    cmp ecx, ebx             ; Compare elapsed time with interval
    jb time_not_up           ; If not enough time has passed, exit

    	; Enough time has passed: update timer and drop
    	rdtsc                    ; Get current clock cycles
    	mov [time], eax          ; Save the current cycles
    	inc byte [ypos] 		 ; Move down
    	call check_collision     ; Check for collision
	time_not_up:
    popa
    ret

random:
	pusha
	rdtsc
	mov ebx, eax
	shl ebx, 13
	xor eax, ebx
	mov ebx, eax
	shr ebx, 17
	xor eax, ebx
	mov ebx, eax
	shl ebx, 5
	xor eax, ebx;get a random number

	xor edx,edx
	movzx ecx, byte [used_blocks + 1]
	div ecx; edx = eax mod edx
	inc edx

	mov bl, [used_blocks]
	mov bh, 10000000b
	mov ecx, edx
	mov dh, -1
	bit_finder:
		inc dh
		shr bh, 1
		test bl, bh
		jz bit_finder
			loop bit_finder;find the open spot at the number provided
	
	not bh 
	and [used_blocks],bh; remove the used bit from the filter

	cmp [used_blocks + 1], byte 1
	jne dont_reset_blocks
		mov [used_blocks], word 087Fh;resets used blocks
	dont_reset_blocks:

	dec byte [used_blocks + 1]

	mov dl, [next_blocks + 1]
	mov [next_blocks], dx
	
	popa
	ret
check_collision:
    pusha                       ; Save registers

	mov edi, 0
	begin_loop:
    ; Calculate the starting position in the Tetrimino data
    movzx ebx, byte [next_blocks] ; Load Tetrimino shape index
    movzx eax, byte [rotation]    ; Load rotation directly
    shl ebx, 5                    ; Shape index * 32
    shl eax, 3                    ; Rotation index * 8
    add ebx, eax                  ; Offset = shape + rotation
    mov eax, tetrominoes          ; Base address of Tetrimino data
    add eax, ebx                  ; Adjusted to current Tetrimino position      

    ; Prepare loop for all 4 blocks in the Tetrimino
    mov ecx, 4
	collision_loop:
		; Calculate absolute x coordinate
		movzx ebx, byte [xpos]		  ; Load xpos
		movsx edx, byte [eax]         ; Load x offset of the block
		add ebx, edx                  ; Absolute x = xpos + x offset
		inc eax                       ; Move to y offset
		push ebx                      ; Save x coordinate on stack

		; Calculate absolute y coordinate
		movzx ebx, byte [ypos]        ; Load ypos
		movzx edx, byte [eax]         ; Load y offset of the block
		sub ebx, edx                  ; Absolute y = ypos - y offset
		inc eax                       ; Move to the next block
		push ebx                      ; Save y coordinate on stack

		cmp ebx, 0
		jl negtive

		; Call collision test
		call collition_test
		jnz collision_detected        ; If a collision occurred, exit the loop

		negtive:
		add esp, 8                    ; Clean up the stack
		loop collision_loop           ; Check all blocks

		;move all positions to saved backup and exit Function
		mov al, [xpos]
		mov ah, [ypos]
		mov bl, [rotation]
		mov [xpos+1],al
		mov [ypos+1],ah
		mov [rotation+1], bl
		call render
		jmp exit_function

	collision_detected:
		add esp, 8
		mov bl, [ypos+1]
		
		cmp bl, byte[ypos]
		jne lock_tetrimino
		mov bl, [rotation+1]
		cmp bl, byte [rotation]
		jne adjust_rotation
		mov bl, [xpos+1]
		mov [xpos], bl
		jmp exit_function

		adjust_rotation:
			mov bl, [eax-2]
			shr bl,7
			shl bl,2
			sub bl,2
			
			cmp edi, 2
			je rotation_fail
				inc edi
				add [xpos], bl
				jmp begin_loop
			rotation_fail:
			mov bl, [rotation+1]
			mov bh, [xpos+1]
			mov [rotation], bl
			mov [xpos], bh
			jmp exit_function

		lock_tetrimino:
			mov byte[ypos],bl
			;reset tetromino position
			sub ecx, 5
			neg ecx
			shl ecx, 1
			sub eax,ecx
			mov ecx, 4
			; save the curent termios to the board
			save_loop:
				; Calculate absolute x coordinate
				movzx ebx, byte [xpos] ; Load xpos
				movsx edx, byte [eax]  ; Load x offset of the block
				add ebx, edx		   ; Absolute x = xpos + x offset
				inc eax				   ; Move to y offset
				push ebx			   ; Save x coordinate on stack

				; Calculate absolute y coordinate
				movzx ebx, byte [ypos] ; Load ypos
				movzx edx, byte [eax]  ; Load y offset of the block
				sub ebx, edx		   ; Absolute y = ypos - y offset
				inc eax				   ; Move to the next block
				push ebx			   ; Save y coordinate on stack
				cmp ebx, 0
				jle game_over_end
				;jl neg
				call write_pos
				neg:
				add esp, 8
				loop save_loop

			;clear tetrominos that fill a row
			std
			mov ebx, WIDTH
			mov al, AIR_CHAR
			xor ah, ah
			clear_loop:
				lea edi, [board + ebx]
				mov ecx, WIDTH
				repne scasb
				jz dont_clear
				inc ah
					lea esi, [board + ebx - WIDTH]
					lea edi, [board + ebx]
					mov ecx , ebx
					rep movsb

					cld
					mov esi, clear_line
					mov edi, board
					mov ecx, WIDTH
					rep movsb
					std
				
				dont_clear:
				add ebx, WIDTH
				cmp ebx, WIDTH * HEIGHT
				jne clear_loop
			cld
			
			;calculate the score to be added
			xor edx, edx
			cmp ah, 0
			je tetris_check
				mov edx,100
				cmp ah,1
				je clear_check
					add edx, 200
					cmp ah,2
					je clear_check
						add edx, 200
						cmp ah,3
						je clear_check
							add edx, 300
							cmp byte [tetris_flag], 0
							je clear_check
								add edx, 400
				clear_check:

				mov al, PLAYER_CHAR
				mov edi, board
				mov ecx, WIDTH * HEIGHT
				repne scasb
				jz tetris_check
					add edx, 800
					cmp ah,1
					je tetris_check
						add edx, 400
						cmp ah,2
						je tetris_check
							add edx, 400
							cmp ah,3
							je tetris_check
								add edx, 200
								cmp byte [tetris_flag], 0
								je tetris_check
									add edx, 1200

			tetris_check:
			cmp ah,4
			je tetris
				mov byte [tetris_flag], 0
				jmp	point_tally
			tetris:
				mov byte [tetris_flag], 1
			point_tally:
			movzx eax, byte [level] 
			mul edx
			add dword [score], eax

			call random
			mov		byte [xpos], STARTX
			mov		byte [ypos], STARTY
			mov		byte [xpos+1], STARTX
			mov		byte [ypos+1], STARTY
			mov		word [rotation],0
			call render

			cmp byte [held_block+1] , 0
			je no_holds
				mov byte [held_block+1], 2
			no_holds:

	exit_function:
		popa                          ; Restore registers
		ret

collition_test:
	enter 0,0
	pusha
	call get_pos
	cmp		BYTE [eax], AIR_CHAR
	popa
	leave
	ret

	

write_pos:
	enter 0,0
	pusha
	call get_pos
	mov byte [eax], byte PLAYER_CHAR
	mov byte [eax + 1], byte PLAYER_CHAR2
	popa
	leave
	ret
	
get_pos:
	mov		eax, WIDTH
	mul		DWORD [ebp+8]
	add		eax, DWORD [ebp+12]
	lea		eax, [board + eax]
	ret