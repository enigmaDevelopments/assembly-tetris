;%include "/usr/local/share/csc314/asm_io.inc"
%include "/mnt/c/Users/granite/Documents/AssemblyLanguage/gameBasecopy/game/asm_io.inc"
; the file that stores the initial state
%define BOARD_FILE 'board.txt'

; how to represent everything
%define WALL_CHAR '#'
%define PLAYER_CHAR 'O'

; the size of the game screen in characters
%define HEIGHT 20
%define WIDTH 40

; the player starting position.
; top left is considered (0,0)
%define STARTX 1
%define STARTY 1

; these keys do things
%define EXITCHAR 'x'
%define UPCHAR 'w'
%define LEFTCHAR 'a'
%define DOWNCHAR 's'
%define RIGHTCHAR 'd'

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
	
	tetrominoes: 
			db 0,0, 1,0, 2,0, 3,0           ; Horizontal line 
			db 0,0, 0,1, 0,2, 0,3           ; Vertical line
			db 1,0, 0,1, 1,1, 2,1           ; T-shape
			db 0,0, 0,1, 1,1, 2,1           ; L-shape
			db 0,0, 1,0, 1,1, 2,1           ; Z-shape
			db 0,0, 1,0, 1,1, 0,1           ; Square (O-shape)
			
			db 2,0, 0,1, 1,1, 2,1         ; L flipped
			db 0,1, 1,1, 1,0, 2,0           ; Z flipped
			db 1,0, 0,1, 1,1, 2,1            ; T flipped
			db 0,1, 0,2, 1,2, 2,2            ; J-shape
			
			db 1,0, 2,0, 0,1, 1,1            ; S-shape
			db 0,0, 1,0, 2,0, 2,1           ; Horizontal L (long base)
			db 0,0, 0,1, 0,2, 1,2           ; Vertical stick with extra top
			db 0,0, 1,0, 2,0, 1,1           ; Horizontal T
			
			db 0,0, 1,0, 1,1, 2,0           ; Diagonal square
			db 0,0, 1,0, 1,1, 2,1           ; Small Z-shape
			db 0,0, 1,0, 2,0, 3,0           ; Long horizontal line
			db 0,0, 1,0, 1,1, 1,2           ; Stacked L
		
	tetrominoes_end:
    ; Define the number of tetrominoesNUM_TETROMINOES equ 19   ; Total number of tetrominoes defined
     NUM_TETROMINOES equ (tetrominoes_end - tetrominoes) / 8
	


segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)

	; these variables store the current player position
	xpos	resd	2
	ypos	resd	1
	seed resd 1                ; Reserve space for the random seed
	random_index resd 1        ; Reserve space for the random index
	selected_tetromino_data resb 8 ; Reserve 8 bytes for the tetromino's block positions

segment .text

	global	asm_main
	global  raw_mode_on
	global  raw_mode_off
	global  init_board
	global  render
	global random_tetromino

	extern	system
	extern	putchar
	extern	getchar
	extern	printf
	extern	fopen
	extern	fread
	extern	fgetc
	extern	fclose
	extern rand                ; Declare rand from the C standard library
	extern srand               ; Declare srand for seeding
	extern time                ; Declare time for seeding srand

asm_main:
	push	ebp
	mov		ebp, esp

	; put the terminal in raw mode so the game works nicely
	call	raw_mode_on

	; read the game board file into the global variable
	call	init_board

	call random_tetromino	

	; set the player at the proper start position
	mov		DWORD [xpos], STARTX
	mov		DWORD [ypos], STARTY

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

		; draw the game board
		call	render

		; get an action from the user
		call	getchar

		; store the current position
		; we will test if the new position is legal
		; if not, we will restore these
		mov		esi, DWORD [xpos]
		mov		edi, DWORD [ypos]

		; choose what to do
		cmp		eax, EXITCHAR
		je		game_loop_end
		cmp		eax, UPCHAR
		je 		move_up
		cmp		eax, LEFTCHAR
		je		move_left
		cmp		eax, DOWNCHAR
		je		move_down
		cmp		eax, RIGHTCHAR
		je		move_right
		jmp		input_end			; or just do nothing

		; move the player according to the input character
	; Move the tetrimino up, ensuring it stays within bounds
	move_up:
		; Check if the topmost block will go out of bounds
		mov     ecx, 0                 ; Block counter for tetrimino
	check_up_bound:
		cmp     ecx, 4                 ; Number of blocks in tetrimino
		je      move_up_done           ; All blocks are within bounds

		movsx   eax, BYTE [selected_tetromino_data + ecx * 2 + 1] ; y offset of block
		add     eax, DWORD [ypos]
		cmp     eax, 1                 ; Inner boundary starts at y=1
		jl      restore_position       ; Out of bounds, restore position

		inc     ecx
		jmp     check_up_bound

	move_up_done:
		dec     DWORD [ypos]           ; Move player up
		jmp     input_end

	; Move the tetrimino down, ensuring it stays within bounds
	move_down:
    ; Check if the bottommost block will go out of bounds
    mov     ecx, 0                 ; Block counter for tetrimino
	check_down_bound:
		cmp     ecx, 4                 ; Number of blocks in tetrimino
		je      move_down_done         ; All blocks are within bounds

		; Calculate the position of the current block
		movsx   eax, BYTE [selected_tetromino_data + ecx * 2 + 1] ; y offset of block
		add     eax, DWORD [ypos]
		cmp     eax, HEIGHT - 3        ; Inner boundary ends at y=HEIGHT-2
		jg      restore_position       ; Out of bounds, restore position

		inc     ecx
		jmp     check_down_bound

	move_down_done:
		inc     DWORD [ypos]           ; Move player down
		jmp     input_end


	; Move the tetrimino left, ensuring it stays within bounds
	move_left:
    ; Check if the leftmost block will go out of bounds
    mov     ecx, 0                 ; Block counter for tetrimino
	check_left_bound:
		cmp     ecx, 4                 ; Number of blocks in tetrimino
		je      move_left_done         ; All blocks are within bounds

		movsx   eax, BYTE [selected_tetromino_data + ecx * 2] ; x offset of block
		add     eax, DWORD [xpos]
		cmp     eax, 2                 ; Inner boundary starts at x=2
		jl      restore_position       ; Out of bounds, restore position

		inc     ecx
		jmp     check_left_bound

	move_left_done:
		dec     DWORD [xpos]           ; Move player left
		jmp     input_end


	; Move the tetrimino right, ensuring it stays within bounds
	move_right:
		; Check if the rightmost block will go out of bounds
		mov     ecx, 0                 ; Block counter for tetrimino
	check_right_bound:
		cmp     ecx, 4                 ; Number of blocks in tetrimino
		je      move_right_done        ; All blocks are within bounds

		movsx   eax, BYTE [selected_tetromino_data + ecx * 2] ; x offset of block
		add     eax, DWORD [xpos]
		cmp     eax, WIDTH - 3         ; Inner boundary ends at x=WIDTH-3
		jg      restore_position       ; Out of bounds, restore position

		inc     ecx
		jmp     check_right_bound

	move_right_done:
		inc     DWORD [xpos]           ; Move player right
		jmp     input_end


	; Restore position if the move was invalid
	restore_position:
		mov     DWORD [xpos], esi      ; Restore previous x position
		mov     DWORD [ypos], edi      ; Restore previous y position
		jmp     input_end



	
		input_end:

		; (W * y) + x = pos

		; compare the current position to the wall character
		mov		eax, WIDTH
		mul		DWORD [ypos]
		add		eax, DWORD [xpos]
		lea		eax, [board + eax]
		cmp		BYTE [eax], WALL_CHAR
		jne		valid_move
			; opps, that was an invalid move, reset
			mov		DWORD [xpos], esi
			mov		DWORD [ypos], edi
		valid_move:

	jmp		game_loop
	game_loop_end:

	; restore old terminal functionality
	call raw_mode_off

	mov		eax, 0
	mov		esp, ebp
	pop		ebp
	ret

raw_mode_on:

	push	ebp
	mov		ebp, esp

	push	raw_mode_on_cmd
	call	system
	add		esp, 4

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
    push ebp
    mov ebp, esp

    ; Two loop counters for height and width
    sub esp, 8

    ; Clear the screen
    push clear_screen_code
    call printf
    add esp, 4

    ; Print help information
    push help_str
    call printf
    add esp, 4

    ; Loop over game board rows (height)
    mov DWORD [ebp - 4], 0  ; Outer loop counter (y)
y_loop_start:
    cmp DWORD [ebp - 4], HEIGHT
    je y_loop_end

    ; Loop over game board columns (width)
    mov DWORD [ebp - 8], 0  ; Inner loop counter (x)
x_loop_start:
    cmp DWORD [ebp - 8], WIDTH
    je x_loop_end

        ; Render the current cell based on Tetrimino data
        mov ecx, 0          ; Block counter for Tetrimino
render_tetromino:
        cmp ecx, 4          ; Tetrimino has 4 blocks
        je render_next_cell

            ; Calculate block position
            movsx eax, BYTE [selected_tetromino_data + ecx * 2]     ; x offset
            add eax, DWORD [xpos]                             ; Base x position
            movsx ebx, BYTE [selected_tetromino_data + ecx * 2 + 1] ; y offset
            add ebx, DWORD [ypos]                             ; Base y position

            ; Compare block position with the current cell
            cmp eax, DWORD [ebp - 8]  ; Compare x
            jne next_block
            cmp ebx, DWORD [ebp - 4]  ; Compare y
            jne next_block

            ; Match found, render the block
            push PLAYER_CHAR
            call putchar
            add esp, 4
            jmp render_cell_done

next_block:
        inc ecx
        jmp render_tetromino

render_next_cell:
        ; Render empty space or wall
        mov eax, DWORD [ebp - 4] ; Row index
        mov ebx, WIDTH           ; Width of the board
        mul ebx                  ; eax = (WIDTH * y)
        add eax, DWORD [ebp - 8] ; eax = (WIDTH * y) + x
        mov ebx, 0
        mov bl, BYTE [board + eax]
        push ebx
        call putchar
        add esp, 4

render_cell_done:
        inc DWORD [ebp - 8]      ; Increment column counter
        jmp x_loop_start         ; Continue inner loop

x_loop_end:
    ; Write a newline after finishing a row
    push 0x0d           ; Carriage return
    call putchar
    add esp, 4
    push 0x0a           ; Newline
    call putchar
    add esp, 4

    ; Increment outer loop counter
    inc DWORD [ebp - 4]
    jmp y_loop_start

y_loop_end:
    mov esp, ebp
    pop ebp
    ret

random_tetromino:
    push ebp
    mov ebp, esp

    ; Seed the random number generator (only the first time)
    cmp dword [seed], 0            ; Check if seed is initialized
    jne .skip_seed                 ; Skip if already seeded
    push 0                         ; Push 0 as an argument for time(NULL)
    call time                      ; Get the current time
    add esp, 4                     ; Clean up the stack
    push eax                       ; Pass the current time as a seed to srand
    call srand                     ; Seed the PRNG
    add esp, 4                     ; Clean up the stack
    mov dword [seed], 1            ; Mark the seed as initialized

.skip_seed:
    ; Generate a random number using rand()
    call rand                      ; Generate a random number
    xor edx, edx                   ; Clear edx for division
    mov ecx, NUM_TETROMINOES       ; Set divisor (number of tetrominoes)
    div ecx                        ; eax = rand() % NUM_TETROMINOES
    mov [random_index], edx        ; Store the random index (edx)

    ; Initialize selected_tetromino_data to zero (to avoid garbage data)
    lea edi, [selected_tetromino_data] ; Destination address for initialization
    mov ecx, 8                      ; 8 bytes to clear (4 pairs of x,y)
    xor eax, eax                    ; Fill value (zero)
    rep stosb                       ; Clear memory

    ; Calculate the base address of the selected tetromino
    lea esi, [tetrominoes + edx * 8] ; Each tetromino occupies 8 bytes (4 pairs of x,y)

    ; Copy the tetromino data to the selected_tetromino_data buffer
    lea edi, [selected_tetromino_data] ; Destination for the tetromino data
    mov ecx, 8                      ; 8 bytes to copy (4 pairs of x,y)
.rep_copy:
    mov al, byte [esi]              ; Load a byte from the tetromino
    mov byte [edi], al              ; Store it in the destination
    inc esi                         ; Move to the next byte in source
    inc edi                         ; Move to the next byte in destination
    loop .rep_copy                  ; Repeat until 8 bytes are copied

    ; Return (selected_tetromino_data now contains the relative positions)
    pop ebp
    ret
