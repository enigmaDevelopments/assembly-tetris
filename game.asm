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


segment .data

			debug_buffer db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ; Enough space for a string
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
segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)

	; these variables store the current player position
	xpos	resd	1
	ypos	resd	1
	time 	resd	1
	level	resb	1
	used_blocks resb 2
	next_blocks resb 2
	rotation resb 1

	auto_drop_enabled resb 1  ; Flag to enable or disable auto-drop
	termios_current resb 32 ; Buffer for current termios settings
    termios_new resb 32     ; Buffer for modified termios settings
	 char_buffer resb 1 ; Single byte buffer for input

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

	extern	system
	extern	putchar
	;extern	getchar
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
	mov		DWORD [xpos], STARTX
	mov		DWORD [ypos], STARTY
	rdtsc
	mov [time], eax; set initial time
	mov [level], byte 1; set level to 1
	mov [used_blocks], word 077Fh;set used blocks to defult mask and count
	call random
	call random;initialize first blocks

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
			call render

			; Perform auto-drop
			call auto_drop

			; Process player input
			call process_input

			; Continue game logic
			jmp game_loop
		process_input:
			; Non-blocking input using read syscall (32-bit)
			mov eax, 3           ; syscall number for read
			mov ebx, 0           ; stdin file descriptor
			lea ecx, [char_buffer] ; Buffer to store input character
			mov edx, 1           ; Read 1 byte
			int 0x80             ; Perform syscall

			; Check if a key was pressed
			cmp eax, 1           ; Was a character read?
			jne skip_input       ; If not, skip input handling

			; Load the character from char_buffer into al
			movzx eax, byte [char_buffer]

			; Store the current position
			; Save current xpos and ypos for potential restoration
			mov esi, DWORD [xpos]
			mov edi, DWORD [ypos]

			; Compare input character and perform actions
			cmp al, UPCHAR
			je move_up
			cmp al, DOWNCHAR
			je move_down
			cmp al, CLOCKWISECHAR
			je rotate_clockwise
			cmp al, COUNTERCLOCKWISECHAR
			je rotate_counterclockwise
			cmp al, EXITCHAR
			je game_loop_end
			cmp al, LEFTCHAR
			je move_left
			cmp al, RIGHTCHAR
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

		move_up:
			dec DWORD [ypos]
			jmp input_end

		move_left:
			sub DWORD [xpos], 2
			jmp input_end

		move_down:
			inc DWORD [ypos]
			jmp input_end

		move_right:
			add DWORD [xpos], 2

		input_end:
			; Calculate new position and test collision
			movzx ebx, byte [next_blocks]
			movzx eax, byte [rotation]
			shl ebx, 5
			shl eax, 3
			add ebx, eax
			mov eax, tetrominoes
			add eax, ebx
			inc eax
			mov ecx, 4
			dec eax

		collision_loop_userinput:
			mov ebx, [xpos]
			movsx edx, byte [eax]
			add ebx, edx
			inc eax
			push ebx
			mov ebx, [ypos]
			movzx edx, byte [eax]
			sub ebx, edx
			inc eax
			push ebx
			call collition_test
			jne invalid_move
			add esp, 8
			loop collision_loop_userinput

			add esp, 1
			jmp game_loop

		invalid_move:
			; Oops, that was an invalid move, reset
			add esp, 8
			mov DWORD [xpos], esi
			mov DWORD [ypos], edi
			jmp game_loop

		skip_input:
			ret
		game_loop_end:

	; restore old terminal functionality
	call raw_mode_off

	mov		eax, 0
	mov		esp, ebp
	pop		ebp
	ret

raw_mode_on:
    ; Step 1: Get current terminal settings
    mov eax, 54              ; ioctl syscall number
    mov ebx, 0               ; stdin file descriptor
    mov ecx, 0x5401          ; TCGETS (get termios)
    lea edx, [termios_current] ; Pointer to current termios
    int 0x80                 ; Perform syscall

    ; Step 2: Copy current settings to new settings
    lea esi, [termios_current]
    lea edi, [termios_new]
    mov ecx, 32              ; Size of termios struct
    rep movsb                ; Copy current termios to new termios

    ; Step 3: Modify termios to disable canonical mode and echo
    lea eax, [termios_new]   ; Load address of termios_new into eax
    add eax, 12              ; Offset to the c_lflag field
    mov ebx, [eax]           ; Read the 32-bit c_lflag value
    and ebx, 0xFFFFFFFE      ; Clear ICANON (bit 0)
    and ebx, 0xFFFFFFF7      ; Clear ECHO (bit 3)
    mov [eax], ebx           ; Write back the modified value

    ; Step 4: Apply the new settings
    mov eax, 54              ; ioctl syscall
    mov ebx, 0               ; stdin file descriptor
    mov ecx, 0x5402          ; TCSETS (set termios)
    lea edx, [termios_new]   ; Pointer to modified termios
    int 0x80                 ; Perform syscall

    ; Step 5: Set stdin to non-blocking mode
    mov eax, 5               ; fcntl syscall
    mov ebx, 0               ; stdin file descriptor
    mov ecx, 3               ; F_GETFL (get file status flags)
    int 0x80                 ; Perform syscall
    or eax, 0x800            ; Add O_NONBLOCK
    mov ecx, 4               ; F_SETFL (set file status flags)
    int 0x80                 ; Perform syscall

    ret
	
	;previous raw_mode_on
	;push	ebp
	;mov		ebp, esp

	;push	raw_mode_on_cmd
	;call	system
	;add		esp, 4

	;mov		esp, ebp
	;pop		ebp
	;ret

raw_mode_off:

	mov eax, 54          ; ioctl syscall
    mov edi, 0           ; stdin file descriptor
    mov esi, 0x5402      ; TCSETS (set termios)
    lea edx, [termios_current]
    syscall
    ret
	;previous raw_mode_on
	;push	ebp
	;mov		ebp, esp

	;push	raw_mode_off_cmd
	;add		esp, 4

	;mov		esp, ebp
	;pop		ebp
	;ret

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
			mov		eax, DWORD [xpos]
			movsx	ebx, BYTE [ebp + ecx]
			add		eax, ebx
			cmp		eax, DWORD [ebp - 8]
			jne		player_check_loop
			mov		eax, DWORD [ypos]
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

    ; Enough time has passed: update timer and indicate drop
    rdtsc                    ; Get current clock cycles
    mov [time], eax          ; Save the current cycles
    mov eax, 1               ; Set flag indicating it's time to drop
    popa
    ret

time_not_up:
    mov eax, 0               ; Set flag indicating not time to drop
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
    ; Function to check if the Tetrimino collides with the board or blocks
    ; Parameters:
    ;   [ebp+8] -> xpos
    ;   [ebp+12] -> ypos
    ;   [ebp+16] -> rotation

    enter 0, 0                  ; Set up stack frame
    pusha                       ; Save registers

    ; Calculate the starting position in the Tetrimino data
    movzx ebx, byte [next_blocks] ; Load Tetrimino shape index
    mov eax, DWORD [ebp+16]       ; Load rotation directly
    shl ebx, 5                    ; Shape index * 32
    shl eax, 3                    ; Rotation index * 8
    add ebx, eax                  ; Offset = shape + rotation
    mov eax, tetrominoes          ; Base address of Tetrimino data
    add eax, ebx                  ; Adjusted to current Tetrimino position
    inc eax                       ; Move to the first coordinate

    ; Prepare loop for all 4 blocks in the Tetrimino
    mov ecx, 4
    dec eax                       ; Adjust pointer for the loop
	collision_loop:
		; Calculate absolute x coordinate
		mov ebx, DWORD [ebp+8]        ; Load xpos
		movsx edx, byte [eax]         ; Load x offset of the block
		add ebx, edx                  ; Absolute x = xpos + x offset
		inc eax                       ; Move to y offset
		push ebx                      ; Save x coordinate on stack

		; Calculate absolute y coordinate
		mov ebx, DWORD [ebp+12]       ; Load ypos
		movzx edx, byte [eax]         ; Load y offset of the block
		sub ebx, edx                  ; Absolute y = ypos - y offset
		inc eax                       ; Move to the next block
		push ebx                      ; Save y coordinate on stack

		; Call collision test
		call collition_test
		test eax, eax                 ; Check the result
		jnz collision_detected        ; If a collision occurred, exit the loop

		add esp, 8                    ; Clean up the stack
		loop collision_loop           ; Check all blocks
		jmp no_collision

	collision_detected:
		mov eax, 1                    ; Collision detected
		 jmp cleanup                   ; Jump to cleanup section

	cleanup:
		add esp, 8                    ; Clean up the stack
		jmp exit_function

	no_collision:
		mov eax, 0                    ; No collision

	exit_function:
		popa                          ; Restore registers
		leave                         ; Restore stack frame
		ret       
collition_test:
	enter 0,0
	pusha
	mov		eax, WIDTH
	mul		DWORD [ebp+8]
	add		eax, DWORD [ebp+12]
	lea		eax, [board + eax]
	cmp		BYTE [eax], AIR_CHAR
	popa
	leave
	ret

auto_drop:
    pusha
	call render
    ; Use the timer to determine if it's time to drop
    call timer

    ; Check if timer indicates it's time to drop
    cmp eax, 0               ; Check the flag from timer
    je auto_drop_exit        ; If not time, exit and wait for next loop

	; Test collision for the next downward position
    mov eax, DWORD [xpos]    ; Load xpos
    mov ebx, DWORD [ypos]    ; Load ypos
    dec ebx                  ; Simulate downward movement
    push DWORD [rotation]    ; Push rotation
    push ebx                 ; Push ypos - 1
    push eax                 ; Push xpos
    call check_collision     ; Check for collision
    add esp, 12              ; Clean up the stack

    cmp eax, 1               ; Check if collision occurred
    jne no_collision_autodrop

    ;coillision occured
	call lock_tetrimino
    jmp auto_drop_exit

	no_collision_autodrop:
		; No collision: move the Tetrimino down
		dec DWORD [ypos]

		; Debug print ypos 
		push eax 
		push ebx 
		mov eax, DWORD [ypos] 
		pop ebx 
		pop eax
		; Update the game board after moving
		call render
		jmp auto_drop_exit

	lock_tetrimino:
		; Collision occurred: lock the Tetrimino and spawn a new one
		mov DWORD [xpos], esi    ; Restore xpos
    	mov DWORD [ypos], edi    ; Restore ypos
		call disable_auto_drop   ; Disable auto-drop
		;call spawn_new_tetrimino ; Prepare the next Tetrimino
		jmp auto_drop_exit

	auto_drop_exit:
		popa
		ret


	spawn_new_tetrimino:
		pusha

		; Reset Tetrimino position and state
		mov DWORD [xpos], STARTX  ; Set starting X position
		mov DWORD [ypos], STARTY  ; Set starting Y position
		mov byte [rotation], 0    ; Reset rotation

		; Generate a new random Tetrimino
		call random               ; Update `next_blocks` with a new random value

		; Re-enable auto-drop for the new Tetrimino
		call enable_auto_drop

		; Update the game board to show the new Tetrimino
		call render

		popa
		ret

	enable_auto_drop:
		mov byte [auto_drop_enabled], 1  ; Set the auto-drop flag to enabled
		ret

	disable_auto_drop:
		mov byte [auto_drop_enabled], 0  ; Set the auto-drop flag to disabled
		ret
						; Return

