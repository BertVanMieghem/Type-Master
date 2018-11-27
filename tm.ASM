;=============================================================================
; 32-bit Assembly Example
;
; Example of an initial top-level gameloop framework.
;=============================================================================
IDEAL
P386
MODEL FLAT, C
ASSUME cs:_TEXT,ds:FLAT,es:FLAT,fs:FLAT,gs:FLAT

INCLUDE	"rand.inc"

;=============================================================================
; CODE
;=============================================================================
CODESEG



;=============================================================================
; Procedure to synchronize game loop to 60Hz in mode 13h
PROC updateScreen
	USES eax, edx, ecx, esi

	mov 	dx, 03dah
@@upScreen_wait1:
	in 		al, dx
	and 	al, 8
	jnz @@upScreen_wait1
	
@@upScreen_wait2:
	in 		al, dx
	and 	al, 8
	jz @@upScreen_wait2
	
	; Screen buffer
	cld
	mov 	esi, offset screenBuffer
	mov 	edi, 0a0000h
	mov 	ecx, 64000 / 4
	rep 	movsd
	
	ret
ENDP updateScreen



;=============================================================================
;Enter video mode
PROC setupVideo
	USES eax

	mov		ax, 13h
	int		10h

	ret
ENDP setupVideo



;=============================================================================
;Exit video mode
PROC unsetupVideo
	USES eax

	mov		ax, 03h
	int		10h

	ret
ENDP unsetupVideo



;=============================================================================
; Procedure to exit the program
PROC exit
	USES eax

	call	unsetupVideo
	mov		eax, 4c00h
	int 	21h
	ret
ENDP exit



;=============================================================================
; Generate a random letter and put it in the alphArray
PROC randomLetter 
	USES eax, edx, ecx, ebx, edi, esi
	
	; Random generator
	call 	rand						; eax contains a big random number
	mov 	ecx, 26						; Divide by 26 to get a remainder of 0 to 26
	xor 	edx, edx
	div 	ecx							; Divide eax by ecx, now edx contains the remainder
	
	; Check if letter is not already on screen
	mov 	ecx, [alphaArrayIdx]
	mov 	ebx, offset alphaArray
	xor 	edi, edi
	
@@judgeLoop:							; Only allow a letter on screen if it's not already there
	cmp 	edi, 99						; This means: the more letters on the screen the higher the chance the game will skip a letterspawn
	je @@allowed
	cmp 	[ebx + 4*edi], edx				; Compare generated number to letter in the array
	je @@denied
	mov 	esi, 27
	cmp 	[ebx + 4*edi], esi
	je @@allowed
	inc 	edi
	jmp @@judgeLoop
	
@@allowed:
	; Fill alphaArray
	mov 	[ebx + 4*ecx], edx			; Put the random number (0-26) in the first free slot of an array of letters
	
	; Link coordinates to the new letter
	call 	linkCo, ecx
	
	; Add 1 to the index
	inc 	[alphaArrayIdx]
	
@@denied:
	ret
ENDP randomLetter



;=============================================================================
; Procedure that puts a random X-coordinate and Y-coordinate in the cooresponding arrays, these coordiantes belong to a letter on screen
PROC linkCo
	ARG @@index :dword
	USES ebx, ecx, esi, edx, eax
	
	mov 	ecx, [@@index]				; Use the same index as we used in the alphaArray
	
	; Add x-coordinate
	mov 	ebx, offset xArray
	call 	rand
	mov 	esi, 312
	xor 	edx, edx
	div 	esi							; Divide eax (random number) by 312, the remainder is in edx
	mov 	[ebx + 4*ecx], edx
	
	; Add y-coordinate
	mov 	ebx, offset yArray
	xor 	edx, edx					; Initially, a letter's y-coordinate is 0 (top of screen)
	mov 	[ebx + 4*ecx], edx
	
	ret
ENDP linkCo



;=============================================================================
; Procedure that iterates over the array of letters and moves them correctly
PROC moveLetter
	USES eax, edx, ebx, ecx, esi, edi
	
	xor ebx, ebx

@@loop:
	cmp 	ebx, 99
	je 	@@done
	mov 	edx, offset alphaArray
	mov 	ecx, [edx + 4*ebx]			; ecx should now contain a number 0-26 which represents a letter on screen
	cmp 	ecx, 27						; Initially the array is filled with 27, if this number is reached no more letters need to be moved
	je 	@@done
	
	mov 	esi, [xArray + 4*ebx]		; X coordinate of ebx'th letter on screen
	mov 	edi, [yArray + 4*ebx]		; Y "
	
	; Remove the letter from the screen in its previous position
	call 	drawSprite, offset _Space, offset screenBuffer, esi, edi
	cmp 	edi, 161
	jg @@removeLetter
	
	; Draw letter in its new position
	inc 	edi							; Increment the letter's Y-co so it appears lower on the screen
	lea 	edx, [yArray + 4*ebx]
	mov 	[edx], edi					; Put the new Y-co in the array
	mov 	eax, [fontTable + 4*ecx]	; Convert the number (0 - 26) into a letter
	call 	drawSprite, eax, offset screenBuffer, esi, edi
	inc 	ebx
	jmp @@loop
	
@@removeLetter:
	call removeLetter, ebx
	call updateScore, "-"
	
@@done:
	ret
ENDP moveLetter



;=============================================================================
; Procedure that removes a letter from the screen when typed correctly or if it hit the bottom
; It's important to always make sure a letter in the alphArray has its coordinates in the xArray and yArray on the same index
PROC removeLetter
	ARG @@index :dword
	USES esi, edi, edx, ebx, ecx, eax

	; Remove letter from screen
	mov 	ecx, [@@index]
	mov 	esi, [xArray + 4*ecx]
	mov 	edi, [yArray + 4*ecx]
	call 	drawSprite, offset _Space, offset screenBuffer, esi, edi
	
	
	; Remove the letter from the alphaArray and fill the gap with the last non-sentinal element of the array to avoid 'holes'
	mov 	edx, offset alphaArray
@@letterLoop:
	mov 	ebx, [edx]
	cmp 	ebx, 27						; Last element of array has been reached
	je @@letterSwitch
	add 	edx, 4
	jmp @@letterLoop
	
	; Swap two elements in the alpaArray
@@letterSwitch:
	lea 	esi, [edx - 4]
	mov 	ebx, [esi]
	mov 	[offset alphaArray + 4*ecx], ebx
	mov 	eax, 27
	mov 	[esi], eax
	dec 	[alphaArrayIdx]
	
	
	; Remove the letter's Y-coordinate from the yArray and fill the gap again
	mov 	edx, offset yArray
@@yLoop:
	mov 	ebx, [edx]
	cmp 	ebx, 200
	je @@ySwitch
	add 	edx, 4
	jmp @@yLoop

	; Swap two elements in the yArray
@@ySwitch:
	lea 	esi, [edx - 4]
	mov 	ebx, [esi]
	mov 	[offset yArray + 4*ecx], ebx
	mov 	eax, 200
	mov 	[esi], eax
	
	
	; Remove the letter's X-coordinate from the xArray and fill the gap again 
	mov 	edx, offset xArray
@@xLoop:
	mov 	ebx, [edx]
	cmp 	ebx, 320
	je @@xSwitch
	add 	edx, 4
	jmp @@xLoop
	
	; Swap two elements in the xArray
@@xSwitch:
	lea 	esi, [edx - 4]
	mov 	ebx, [esi]
	mov 	[offset xArray + 4*ecx], ebx
	mov 	eax, 320
	mov 	[esi], eax
	
	
@@done:
	ret
ENDP removeLetter



;=============================================================================
; Procedure that determines if the key pressed corresponds with a letter on screen and adjusts score accordingly
PROC alphaSeek
	USES eax, edx, ecx, ebx
	
	cmp 	al, 97
	jl @@done							; Determine if key pressed is an actual letter from the alphabet (lowercase)
	cmp 	al, 122
	jg @@done
	sub 	al, 97						; al contains the position of the letter in the alphabet
	xor 	ah, ah
	mov 	edx, offset alphaArray 		; edx contains memory location of alphaArray
	xor 	ecx, ecx
@@alphaLoop:
	cmp 	ecx, 99
	je @@miss
	mov 	ebx, [edx + 4*ecx]			; ebx contains letter in alphaArray
	cmp 	eax, ebx					; Compare the key pressed with a letter on screen
	je @@hit
	cmp 	ebx, 27						; If we reach the end of the array the user has pressed the wrong key
	je @@miss
	inc 	ecx							; if the letter didn't match and we're not at the end -> go to the next letter in the array
	jmp @@alphaLoop
	
@@hit:
	call 	updateScore, "+"
	call 	removeLetter, ecx
	jmp @@done
	
@@miss:
	call 	updateScore, "-"
	
@@done:
	ret
ENDP alphaSeek



;=============================================================================
; Procedure to update the user's score and difficulty on screen
PROC updateScore
	ARG @@dinc :dword
	USES eax, ecx, edx, ebx
	
	; Increment or decrement score?
	cmp 	[@@dinc], "+"
	jne @@dec
	inc 	[score]
	jmp @@drawScore
	
@@dec:
	mov 	eax, [score]
	cmp 	eax, 0						; If your score was 0 and you missed, go back to previous difficulty
	je @@prevDiff
	dec 	[score]
	jmp @@drawScore
	
@@nextDiff:
	call 	drawString, offset emptyMsg, 1, 188
	mov 	[score], 0
	inc 	[diffCounter]
	sub 	[spawnTimer], 8
	cmp		[diffCounter], 4
	jne @@drawScore
	mov		[moveTimer], 1
	jmp @@drawScore
	
@@prevDiff:
	cmp 	[diffCounter], 1
	je @@gameOver
	dec 	[diffCounter]
	add 	[spawnTimer], 8
	mov 	[score], 15
	jmp @@drawScore

@@gameOver:
	call 	endGame
	jmp @@nvm
	
@@drawScore:
	mov 	eax, [score]
	cmp 	eax, 0
	jl @@nvm
	imul	 eax, 8
	cmp 	eax, 158
	jg @@nextDiff						; If score = 20, go to next difficulty
	call 	drawString, offset starMsg, 1, 188
	call 	drawString, offset emptyMsg, eax, 188
	
@@drawDiff:
	mov 	edx, [diffCounter]
	cmp 	edx, 1
	jg @@n2
	call 	drawString, offset emptyMsg, 1, 178
	call 	drawString, offset difficulty1, 1, 178
	jmp @@nvm
@@n2:
	cmp		edx, 2
	jg @@n3
	call 	drawString, offset emptyMsg, 1, 178
	call 	drawString, offset difficulty2, 1, 178
	jmp @@nvm
@@n3:
	cmp 	edx, 3
	jg @@n4
	call 	drawString, offset emptyMsg, 1, 178
	call 	drawString, offset difficulty3, 1, 178
	jmp @@nvm
@@n4:
	cmp 	edx, 4
	jg @@n5
	call 	drawString, offset emptyMsg, 1, 178
	call 	drawString, offset difficulty4, 1, 178
	jmp @@nvm
@@n5:
	cmp 	edx, 5
	jg @@n6
	call 	drawString, offset emptyMsg, 1, 178
	call 	drawString, offset difficulty5, 1, 178
	jmp @@nvm
@@n6:
	cmp 	edx, 6
	jg @@n7
	call 	drawString, offset emptyMsg, 1, 178
	call 	drawString, offset difficulty6, 1, 178
	jmp @@nvm
@@n7:
	cmp 	edx, 7
	jg @@n8
	call 	drawString, offset emptyMsg, 1, 178
	call 	drawString, offset difficulty7, 1, 178
	jmp @@nvm
@@n8:
	call 	drawString, offset emptyMsg, 1, 178
	call 	drawString, offset difficulty8, 1, 178
@@nvm:
	ret
ENDP updateScore



;=============================================================================
; Procedure used to draw a string on the screen, making use of drawSprite
PROC drawString
	ARG @@string :dword, \
		@@x :dword, \
		@@y :dword
	USES eax, esi, edx
		
	xor 	eax, eax
	mov 	esi, [@@string]
	
@@stringLoop:
	lodsb								; Load first letter of string
	cmp 	al, 0						; 0 = end of string
	jz @@exitdrawstring
	
	cmp 	al, 32						; Ascii 32 = spacebar was pressed
	je @@printSpace
	cmp 	al, 45						; Ascii 45 = '-' was pressed
	je @@printDash
	cmp 	al, 42						; Ascii 42 = '*' was pressed
	je @@printStar
	cmp 	al, 58						; al < 58, this means we have to deal with printing a number
	jge @@drawLetter					; If al > 58 we draw a letter
	sub 	al, 48						; "ascii value" - 48, get actual number
	mov 	edx, [numberTable + 4*eax]
		
@@printSpace:
	mov 	edx, offset _Space			; Exception for spacebar
	jmp @@drawSprite
	
@@printDash:
	mov 	edx, offset _Dash			; Exception for dash
	jmp @@drawSprite
	
@@printStar:
	mov 	edx, offset _Star			; Exception for star
	jmp @@drawSprite

@@drawSprite:
	call 	drawSprite, edx, offset screenBuffer, [@@x], [@@y]
	add 	[@@x], 8					; Add a letter's width to the X-co to draw the next char perfectly next to the previous one
	jmp @@stringLoop
	
@@drawLetter:
	sub 	al, 97						;"ascii value" - 97, get the position of the letter in the alphabet
	mov 	edx, [fontTable + 4*eax]
	jmp @@drawSprite

	
@@exitdrawstring:
	ret
ENDP drawString



;=============================================================================
;Procedure that, given an offset, a screenbuffer and coordinates draws the sprite on the screen
PROC drawSprite
	ARG @@spritePtr :dword, \			; sprite (vb _plus)
		@@dstPtr :dword, \				; scherm: 0a0000h
		@@x:dword, \					; x co
		@@y:dword						; y co 
	LOCAL @@w:dword, @@h:dword
	USES eax, ebx, ecx, edx, esi, edi
	
	mov 	esi, [@@spritePtr]
	xor 	eax, eax
	lodsw 								; Read width in AX
	mov 	[@@w], eax
	lodsw 								; Read height in AX
	mov 	[@@h], eax
	
	mov 	edi, [@@dstPtr ]
	mov 	eax, [@@y]
	mov 	ebx, [screenWidth]
	mul 	ebx
	add 	edi, eax
	add 	edi, [@@x] 					; edi points to first pixel
	mov 	ecx, [@@h]
	
@@drawLine :
	push 	ecx
	
	mov 	ecx, [@@w] 					; Need to copy a line of the sprite
	rep 	movsb 						; Copy from esi to edi
	
	add 	edi, [screenWidth]
	sub 	edi, [@@w] 					; edi now points to the next line
	
	pop 	ecx
	dec 	ecx
	jnz @@drawLine
	ret
ENDP drawSprite	



;=============================================================================
; Procedure to initialize a new game
PROC initGameState

	mov 	[gameState], 0
	
	ret
ENDP initGameState



;=============================================================================
; Procedure to draw the welcome message
PROC titleScreen

	call 	drawString, offset titleMsg, 76, 80
	call 	drawString, offset titleMsg2, 116, 92

	ret
ENDP titleScreen



;=============================================================================
; Procedure to draw the GUI and modify the gameState
PROC startGame

	; Draw level
	call 	drawString, offset difficulty1, 1, 178
	call 	drawString, offset emptyMsg, 76, 80
	call 	drawString, offset emptyMsg, 116, 92

	; Draw deathline
	call 	drawString, offset lineMsg, 0, 170

	mov 	[gameState], 1
	
@@done:
	ret
ENDP startGame



;=============================================================================
; Procedure that displays the "game over" message when necessary
PROC endGame

	cmp		[diffCounter], 4
	jl		@@gameOver
	call	drawString, offset winner, 132, 181
	jmp		@@done
	
@@gameOver:
	call 	drawString, offset gameOver, 124, 181
	mov 	[gameState], 2
	
@@done:
	ret
ENDP endGame
;=============================================================================
; Procedure to handle user input
PROC handleUserInput
	USES eax, edx, ecx, ebx, esi
	
	xor 	eax, eax

	mov 	ah, 01h 					; Function 01h (test key pressed)
	int 	16h							; Call keyboard BIOS
	jz @@done	
	mov 	ah, 00h
	int 	16h

	; Process key code here (scancode in AH, ascii code in AL)
	cmp 	al, 27						; Ascii code for ESCAPE key
	jne	@@enter
	call	exit
	jmp @@done
	
@@enter:
	cmp 	al, 13						; Ascii code for ENTER key
	jne	@@alphaProc
	call 	startGame
	jmp @@done		

@@alphaProc:
	call	alphaSeek, eax

@@done:
	ret
ENDP handleUserInput



;=============================================================================
; Procedure to update the game world status (like enemies, collisions, events, ...)
PROC updateGameState
	USES eax

	inc 	[gameLoopCounter]
	inc 	[moveCounter]
	inc 	[spawnCounter]
	
	cmp 	[gameState], 1				; Check if the game has started or not, only move/spawn letters if game is in progress
	jne @@done
	
	mov 	eax, [moveTimer]
	cmp 	[moveCounter], eax
	jl @@done
	call 	moveLetter
	mov 	[moveCounter], 0
	
	mov 	eax, [spawnTimer]
	cmp 	[spawnCounter], eax
	jl @@done
	call 	randomLetter
	mov 	[spawnCounter], 0
	
@@done:
	ret
ENDP updateGameState



;=============================================================================
; Procedure to draw everything on screen
PROC drawAll
	call updateScreen
	ret
ENDP drawAll



;=============================================================================
; MAIN Start of program
;=============================================================================
start:
    sti                            	 	; Set The Interrupt Flag
    cld                            	 	; Clear The Direction Flag

    push ds 							; Put value of DS register on the stack
    pop es 								; And write this value to ES

	; Setup and initialization
	call setupVideo
	call initGameState
	call titleScreen
	call rand_init

	; Main game (endless) loop
@@gameLoop:
	call handleUserInput
	call updateGameState
	call drawAll
	jmp @@gameLoop

	; Code can never get here



;=============================================================================
; DATA
;=============================================================================
DATASEG
	; Counts the gameloops. Useful for timing and planning events.
	gameLoopCounter		dd 0
	
	moveCounter			dd 0
	moveTimer			dd 2			;higher value -> slower falling letters
	
	spawnCounter		dd 0
	spawnTimer			dd 60			;higher value -> less frequent spawning
	
	gameState			dd ?			;0 = title screen
										;1 = playing
										;2 = game over
	
	screenWidth 		dd 320
	screenHeight		dd 200
	
	difficulty1			db "baby",0
	difficulty2			db "beginner",0
	difficulty3			db "normal",0
	difficulty4			db "hard",0
	difficulty5			db "crazy",0
	difficulty6			db "expert",0
	difficulty7			db "insane",0
	difficulty8			db "programmer",0
	
	diffCounter			dd 1			; 1 = baby, 2 = beginner, ...
	
	score				dd 0			; Value between 0 and 20, instead of values > 20 the player goes to the next difficulty

	titleMsg 			db "welcome to typemaster", 0
	titleMsg2 			db "press enter", 0
	gameOver			db "game over",0
	winner				db "you win",0
	emptyMsg 			db "                     ", 0
	lineMsg 			db "----------------------------------------",0
	starMsg				db "********************",0
	
	screenBuffer 		db 64000 dup(?)
	alphaArray 			dd 100 dup (27)
	alphaArrayIdx 		dd 0
	
	xArray				dd 100 dup(320)
	yArray				dd 100 dup(200)
	
	fontTable dd offset _A, offset _B, offset _C, offset _D, offset _E, offset _F
			  dd offset _G, offset _H, offset _I, offset _J, offset _K, offset _L
			  dd offset _M, offset _N, offset _O, offset _P, offset _Q, offset _R 
			  dd offset _S, offset _T, offset _U, offset _V, offset _W, offset _X 
			  dd offset _Y, offset _Z
				
	_Space dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  
	  ;4 = red
	_Dash dw 8 , 8 ; W = 8 , h = 8
	  db 4 , 4 , 4 , 4 , 4 , 4 , 4 , 4
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 4 , 4 , 4 , 4 , 4 , 4 , 4 , 4
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0
	  
	_Star dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 4 , 4 , 4 , 4 , 0 , 0
	  db 0 , 0 , 0 , 4 , 4 , 0 , 0 , 0
	  db 0 , 4 , 0 , 4 , 4 , 0 , 4 , 0
	  db 0 , 4 , 4 , 0 , 0 , 4 , 4 , 0
	  db 0 , 4 , 4 , 0 , 0 , 4 , 4 , 0
	  db 0 , 4 , 0 , 4 , 4 , 0 , 4 , 0
	  db 0 , 0 , 0 , 4 , 4 , 0 , 0 , 0
	  db 0 , 0 , 4 , 4 , 4 , 4 , 0 , 0

		;31 = white
	_A dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  
	_B dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  
	_C dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 31 , 0	
	  
	_D dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  	
	_E dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	
	_F dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  
	_G dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0

	_H dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0

	_I dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0

	_J dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 0 , 0 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 0 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 0 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 0 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 0 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 0 , 0
	  db 0 , 0 , 31 , 31 , 31 , 0 , 0 , 0

	_K dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0

	_L dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0

	_M dw 8 , 8 ; W = 8 , h = 8
	  db 31 , 31 , 31 , 0 , 0 , 31 , 31 , 31 
	  db 31 , 31 , 31 , 31 , 31 , 31 , 31 , 31
	  db 31 , 31 , 0 , 31 , 31 , 0 , 31 , 31
	  db 31 , 31 , 0 , 31 , 31 , 0 , 31 , 31
	  db 31 , 31 , 0 , 31 , 31 , 0 , 31 , 31
	  db 31 , 31 , 0 , 0 , 0 , 0 , 31 , 31
	  db 31 , 31 , 0 , 0 , 0 , 0 , 31 , 31
	  db 31 , 31 , 0 , 0 , 0 , 0 , 31 , 31

	_N dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0

	_O dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  
	 _P dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  
	 _Q dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 ,  0, 31 , 31 , 31 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 31 , 31 , 0
	  
	 _R dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  
	 _S dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 0 , 0 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 0 , 0
	   
	 _T dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  
	 _U dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  
	 _V dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  
	 _W dw 8 , 8 ; W = 8 , h = 8
	  db 31 , 31 , 0 , 0 , 0 , 0 , 31 , 31
	  db 31 , 31 , 0 , 0 , 0 , 0 , 31 , 31
	  db 31 , 31 , 0 , 0 , 0 , 0 , 31 , 31
	  db 31 , 31 , 0 , 31 , 31 , 0 , 31 , 31
	  db 31 , 31 , 0 , 31 , 31 , 0 , 31 , 31
	  db 31 , 31 , 0 , 31 , 31 , 0 , 31 , 31
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  
	 _X dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  
	  _Y dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 31 , 31 , 0 , 0 , 31 , 31 , 0
	  db 0 , 0 , 31 , 31 , 31 , 31 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  db 0 , 0 , 0 , 31 , 31 , 0 , 0 , 0
	  
	 _Z dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 0 , 0 , 0 , 31 , 31 , 31 , 0
	  db 0 , 0 , 0 , 31 , 31 , 31 , 0 , 0
	  db 0 , 0 , 31 , 31 , 31 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 0 , 0 , 0 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  db 0 , 31 , 31 , 31 , 31 , 31 , 31 , 0
	  
	  numberTable dd offset _0, offset _1, offset _2, offset _3, offset _4
				  dd offset _5, offset _6, offset _7, offset _8, offset _9
				  
	  _0 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  
	  _1 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 0 , 9 , 9 , 0 , 0 , 0
	  db 0 , 0 , 9 , 9 , 9 , 0 , 0 , 0
	  db 0 , 0 , 9 , 9 , 9 , 0 , 0 , 0
	  db 0 , 0 , 0 , 9 , 9 , 0 , 0 , 0
	  db 0 , 0 , 0 , 9 , 9 , 0 , 0 , 0
	  db 0 , 0 , 0 , 9 , 9 , 0 , 0 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  
	  _2 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 9 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 0 , 0 , 0 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 9 , 9 , 0 , 0 , 0 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 9 , 0
	  
	  _3 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 9 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 0 , 0 , 0 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 0 , 0 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 0 , 0
	  
	  _4 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 0 , 0 , 0 , 9 , 9 , 0
	  db 0 , 0 , 0 , 0 , 0 , 9 , 9 , 0
	  db 0 , 0 , 0 , 0 , 0 , 9 , 9 , 0

	  _5 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 0 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 0 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 0 , 0
	  
	  _6 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 0 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  
	  _7 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 0 , 0 , 0 , 9 , 9 , 0 , 0
	  db 0 , 0 , 0 , 0 , 9 , 9 , 0 , 0
	  db 0 , 0 , 0 , 9 , 9 , 0 , 0 , 0
	  db 0 , 0 , 0 , 9 , 9 , 0 , 0 , 0
	  db 0 , 0 , 0 , 9 , 9 , 0 , 0 , 0
	  
	  _8 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  
	  _9 dw 8 , 8 ; W = 8 , h = 8
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 9 , 9 , 0 , 0 , 9 , 9 , 0
	  db 0 , 9 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 0 , 0 , 0 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 9 , 0
	  db 0 , 0 , 9 , 9 , 9 , 9 , 0 , 0

;=============================================================================
; STACK
;=============================================================================
STACK 1000h

END start
