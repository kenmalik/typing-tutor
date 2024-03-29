; TypingTutor.asm

INCLUDE Irvine32.inc
INCLUDE Macros.inc

.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

.data
MenuTable BYTE '1'
	DWORD PLAY_GAME
EntrySize = ($ - MenuTable)
	BYTE '2'
	DWORD LEADERBOARD
NumberOfEntries = ($ - MenuTable) / EntrySize

.code
main proc
	MAIN_MENU_X = 35
	MAIN_MENU_Y = 10
	LINE_SPACING = 2

MainMenu:
	; Clear screen to prevent weird screen color
	mov eax, white+(black*16)
	call SetTextColor
	call Clrscr

	; Display title
	mov eax, black + (yellow * 16)
	call SetTextColor

	mGotoxy MAIN_MENU_X, MAIN_MENU_Y
	mWrite "        TYPING TUTOR        "

	; Display menu options
	mov eax, yellow+(black*16)
	call SetTextColor

	mGotoxy MAIN_MENU_X, MAIN_MENU_Y + LINE_SPACING
	mWrite "1. Play Game"

	mGotoxy MAIN_MENU_X, MAIN_MENU_Y + LINE_SPACING * 2
	mWrite "2. View Leaderboard"

	mGotoxy MAIN_MENU_X, MAIN_MENU_Y + LINE_SPACING * 3
	mWrite "Press number to select menu."

	mGotoxy MAIN_MENU_X, MAIN_MENU_Y + LINE_SPACING * 4

	call ReadChar
	mov ebx, OFFSET MenuTable
	mov ecx, NumberOfEntries

L1:
	cmp al, [ebx]				; Inputted char = lookup value?
	jne L2

	call Clrscr					; Run menu procedure
	call NEAR PTR [ebx + 1]
	call Crlf
	jmp MainMenu

L2:
	add ebx, EntrySize			; Go to next entry
	loop L1

	exit						; If no matching entries found, exit


	invoke ExitProcess,0
main endp


;-------------------------------------------------------------------------------
;                                 MAIN GAME
;-------------------------------------------------------------------------------


; Play area bounds
PLAY_AREA_Y = 2
PLAY_AREA_X = 10
LINE_LENGTH = 64
STARTING_DISTANCE = 24
INFO_COLUMN_X = PLAY_AREA_X + LINE_LENGTH + 6
SCOREBOARD_Y = PLAY_AREA_Y + 4
SCORE_LABEL_LENGTH = 20

; File reading utilities
PROMPT_BUFFER_SIZE = 5000
FILE_UNREAD = -1

; Game logic timing
TICK = 50	; in milliseconds
SECOND_IN_TICKS = 20
STARTING_PROGRESSION_SPEED = SECOND_IN_TICKS * 2


.data
	; Graphics elements
	divider BYTE LINE_LENGTH DUP("-"), 0
	endingMsg BYTE "--- Level Complete ---", 0

	; For file handling
	typingPrompt BYTE PROMPT_BUFFER_SIZE DUP(?)
	typingPromptSize DWORD 0
	filename BYTE "Text.txt", 0
	fileHandle HANDLE ?

	; Typing prompt data
	typingPromptLeftBound DWORD 0
	charIdx DWORD 0
	textColors WORD LENGTHOF typingPrompt - 1 DUP(black+(white*16)), 0
	lineStatus DWORD 0, 0

	; Cursor position data
	cursorX BYTE 0
	cursorY BYTE 0
	distanceFromTop BYTE STARTING_DISTANCE

	; Game timing
	linePrintTicksElapsed BYTE 0
	typingPromptRightBound DWORD 0
	lineProgressSpeed BYTE STARTING_PROGRESSION_SPEED
	timerTicks DWORD 0

	; Score counters
	charsTyped DWORD 0
	backspacesPressed DWORD 0
	secondsPlayed DWORD 0
	linesCleared DWORD 0
	wrongCharCount DWORD 0


.code
PLAY_GAME proc
	call ResetGame	; Reset game data every new game

	; Read file to memory
	mov ebx, PROMPT_BUFFER_SIZE
	mov ecx, OFFSET typingPrompt
	mov edx, OFFSET filename
	call ReadFileToString
	cmp eax, FILE_UNREAD
	je Quit
	mov typingPromptSize, eax
	
	; Graphical elements
	call DisplayPlayArea
	call GameStart

	; Set to standard color
	mov eax, black + (white * 16)
	call SetTextColor

	; Initial cursor positioning
	mov dh, PLAY_AREA_Y
	add dh, distanceFromTop
	mov dl, PLAY_AREA_X
	call UpdateCursorPos


MainGameLoop:
    mov  eax, TICK    
    call Delay           ; Delay to ensure proper key read

	inc timerTicks
	cmp timerTicks, SECOND_IN_TICKS
	jne TimerNotSet
	inc secondsPlayed
	mov timerTicks, 0

TimerNotSet:
	call UpdateScoreboard

	; If time to print another line of text prompt, do so
	inc linePrintTicksElapsed
	mov al, lineProgressSpeed
	cmp linePrintTicksElapsed, al
	jne KeyRead						; Else, read key

	; If reached top of play area, game over
	dec distanceFromTop
	cmp distanceFromTop, -1			
	jne AddLine
	call GameOver
	jmp GameStats

AddLine:
	call NewPromptLine				; Print a new line of prompt
	cmp lineProgressSpeed, 10		; Line progress speed = 10?
	jbe IsMaxSpeed					; No: don't make faster
	sub lineProgressSpeed, 1		; Yes: make faster

IsMaxSpeed:
	mov linePrintTicksElapsed, 0	; Reset tick counter for display

KeyRead:
    call ReadKey			; look for keyboard input
    jz   MainGameLoop		; no key pressed yet

	; If at bottom of play area, don't do anything
	cmp cursorY, PLAY_AREA_Y + STARTING_DISTANCE
	je MainGameLoop

	; Check if escape pressed
	cmp dx, VK_ESCAPE
	jne CheckBackspace
	ret

CheckBackspace:
	; Check if backspace pressed
	cmp dx, VK_BACK
	jne checkCharEqual				; If not backspace, process inputted character

	; Backspace was pressed
	cmp cursorX, PLAY_AREA_X	; If on char 0, don't do anything
	je MainGameLoop

	inc backspacesPressed
	call ReplacePreviousChar
	call RevertLineStatus
	jmp MainGameLoop

checkCharEqual:
	inc charsTyped

	; Compare input with text
	mov edi, charIdx
	cmp    al, typingPrompt[edi]
	jne    CharNotEqual

	; If character is equal
	mov eax, white + (green * 16)
	call WriteToColorArr
	call CorrectInput
	jmp LineEndCheck

CharNotEqual:
	mov eax, white + (red * 16)
	call WriteToColorArr
	call WrongInput
	inc wrongCharCount

LineEndCheck:
	inc    charIdx
	cmp cursorX, LINE_LENGTH + PLAY_AREA_X
	jne finishCheck

	call CheckLineStatus
	jc ClearLine
	call ReplacePreviousChar
	call RevertLineStatus
	dec charsTyped
	jmp MainGameLoop

ClearLine:
	; Clear completed lines
	mov ebx, typingPromptLeftBound
	call ClearLineStatus
	mov dh, cursorY
	mov dl, PLAY_AREA_X
	call UpdateCursorPos					; Move cursor position for display clearing
	call ClearDisplayLine
	call NewLine
	add typingPromptLeftBound, LINE_LENGTH	; Move left bound for typing prompt forward
	inc distanceFromTop						; Inc distance from top to account for cleared line
	inc linesCleared

finishCheck:
	; If not finished yet
	cmp    typingPrompt[edi + 1], 0
	jne    MainGameLoop

	mov ebx, typingPromptLeftBound	; Is everything on the last line correct?
	call CheckLineStatus
	jc LevelComplete				; Yes: complete level
	call ReplacePreviousChar		; No: Revert last typed character
	call RevertLineStatus
	jmp MainGameLoop


LevelComplete:
	mov cursorX, PLAY_AREA_X
	mGotoxy cursorX, cursorY
	call ClearDisplayLine
	inc linesCleared
	call LevelCleared

GameStats:
	call Clrscr
	call DisplayScores

Quit:
	ret
PLAY_GAME endp


;-------------------------------------------------------------------------------
;                             MAIN GAME PROCEDURES
;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
; ReadFileToString
;
; Opens the file whose name is stored in filename. Verifies file is opened and
; that contents are within designated buffer size.
; Receives: EDX = Offset of the filename to be opened.
;			ECX = Offset of the string to read to.
;			EBX = Size of buffer
; Returns:  EAX = Bytes read (set to FILE_UNREAD if error occurs).
;-------------------------------------------------------------------------------
.data
	fHandle HANDLE ?
	bytesRead DWORD 0
	stringOffset DWORD 0
	bufsize DWORD 0
.code
ReadFileToString proc
	mov stringOffset, ecx
	mov bufSize, ebx

	call OpenInputFile
	mov fHandle, eax

	cmp eax, INVALID_HANDLE_VALUE
	jne FileOk
	mWrite <"Cannot open file", 0dh, 0ah>
	mov eax, FILE_UNREAD
	jmp Quit

FileOk:
	mov edx, stringOffset
	mov ecx, bufSize
	call ReadFromFile
	mov bytesRead, eax
	jnc CheckBufferSize
	mWrite "Error reading file. "
	call WriteWindowsMsg
	mov eax, FILE_UNREAD
	jmp CloseInFile
	
CheckBufferSize:
	cmp eax, bufSize
	jb CloseInFile
	mWrite <"Error: Buffer too small for the file", 0dh, 0ah>
	mov eax, FILE_UNREAD

CloseInFile:
	mov eax, fHandle
	call CloseFile
	mov eax, bytesRead

Quit:
	ret
ReadFileToString endp


;-------------------------------------------------------------------------------
; NewPromptLine
;
; Writes a new line in the typing prompt.
;-------------------------------------------------------------------------------
NewPromptLine proc USES eax ebx ecx edx
	; Push cursor position to stack
	movzx ax, cursorX
	push ax
	movzx ax, cursorY
	push ax

	; Set cursor position to rewrite block of text
	mov dh, distanceFromTop
	add dh, PLAY_AREA_Y
	mov dl, PLAY_AREA_X
	call UpdateCursorPos

	; Write text block
	add typingPromptRightBound, LINE_LENGTH
	mov edx, OFFSET typingPrompt
	mov ecx, typingPromptRightBound
	mov ebx, typingPromptLeftBound
	call ReprintPrompt
	
	call NewLine	; Move cursor to line below written prompt

	; If cursor is not at bottom of play area, clear the display line below prompt
	cmp cursorY, PLAY_AREA_Y + STARTING_DISTANCE
	je ReturnToOriginalPos
	call ClearDisplayLine
	
ReturnToOriginalPos:
	; Pop original cursor position to return to former position
	pop ax
	dec al			; Cursor y has to decrement to account for prompt having moved
	mov dh, al
	pop ax
	mov dl, al
	call UpdateCursorPos
	ret
NewPromptLine endp


;-------------------------------------------------------------------------------
; ReprintPrompt
;
; Reprints typing prompt using colors from text colors from colors array
; Receives: EDX = OFFSET of typing prompt
;			EBX = The index of typing prompt to start printing from
;			ECX = The index of typing prompt to stop printing at
;-------------------------------------------------------------------------------
ReprintPrompt proc USES edi
 	mov edi, 0				; Counter for if line length was reached
	mov al, [edx + ebx]

printLoop:
	; If reached line length, start new line
	cmp edi, LINE_LENGTH
	jne writeChars
	call NewLine
	mov edi, 0

writeChars:
	call WriteFromColorArr

	; Break if end of string
	inc ebx
	inc edi
	mov al, [edx + ebx]
	cmp al, 0
	jne continuePrintLoop

	call ClearDisplayLine	; Clear the rest of the display line
	jmp Quit

continuePrintLoop:
	cmp ebx, ecx
	jne printLoop
	
Quit:
	ret
ReprintPrompt endp


;-------------------------------------------------------------------------------
; WriteFromColorArr
;
; Writes a colored character to display using colors from text colors array.
; Receives: EBX = Index of character in array to write
;-------------------------------------------------------------------------------
WriteFromColorArr proc USES ecx
	inc cursorX
	mov ecx, OFFSET textColors	; Get a reference to text colors array

	mov eax, [ecx + (ebx * TYPE textColors)]	; Select color from array
	call SetTextColor

	mov al, [edx + ebx]			; Write character in selected color
	call WriteChar
	
	ret
WriteFromColorArr endp


;-------------------------------------------------------------------------------
; WriteToColorArr
;
; Writes a charater in a given color and saves that color to textColors array.
; Receives: EAX = the color to write in and save to textColors array
;			EDI = the index of color array to write to.
;-------------------------------------------------------------------------------
WriteToColorArr proc
	call SetTextColor
	mov textColors[edi * TYPE textColors], ax	; Save color
	movzx eax, typingPrompt[edi]
	call WriteChar
	inc cursorX
	ret
WriteToColorArr endp


;-------------------------------------------------------------------------------
; UpdateCursorPos
;
; Moves cursor to an (x,y) coordinate on screen and updates cursor location
; varaibles accordingly.
; Receives: DL = the x position to set cursor to
;			DH = the y position to set cursor to
;-------------------------------------------------------------------------------
UpdateCursorPos proc
	mov cursorX, dl
	mov cursorY, dh
	mGotoxy cursorX, cursorY
	ret
UpdateCursorPos endp


;-------------------------------------------------------------------------------
; NewLine
;
; Moves cursor to the next line in play area.
;-------------------------------------------------------------------------------
NewLine proc USES edx
	inc cursorY
	mov dh, cursorY
	mov dl, PLAY_AREA_X
	call UpdateCursorPos
	ret
NewLine endp


;-------------------------------------------------------------------------------
; ClearDisplayLine
;
; Clears a line of the play area starting from cursor's x coordinate.
;-------------------------------------------------------------------------------
ClearDisplayLine proc USES eax
	mov eax, white+(black*16)
	call SetTextColor

spaceWrite:
	mWriteSpace
	inc cursorX
	cmp cursorX, PLAY_AREA_X + LINE_LENGTH
	jne spaceWrite
	
	ret
ClearDisplayLine endp


;-------------------------------------------------------------------------------
; ReplacePreviousChar
;
; Reverts color of previous character in play area and updates text color array
; accordingly.
;-------------------------------------------------------------------------------
ReplacePreviousChar proc
	dec cursorX
	mov dh, cursorY
	mov dl, cursorX
	call UpdateCursorPos           ; Move cursor to previous char

	mov eax, black + (white * 16)  ; Reverting color of char (this moves cursor forward)
	dec charIdx         
	mov edi, charIdx
	call WriteToColorArr

	call UpdateCursorPos           ; Move cursor back to previous char's space

	ret
ReplacePreviousChar endp


;-------------------------------------------------------------------------------
; UpdateScoreboard
;
; Writes score information to info column.
;-------------------------------------------------------------------------------
UpdateScoreboard proc USES eax edx
	; Push cursor position to stack
	movzx ax, cursorX
	push ax
	movzx ax, cursorY
	push ax

	mov eax, yellow+(black*16)
	call SetTextColor

	mGotoxy INFO_COLUMN_X + SCORE_LABEL_LENGTH, SCOREBOARD_Y
	mov eax, secondsPlayed
	call TimeFormat

	mGotoxy INFO_COLUMN_X + SCORE_LABEL_LENGTH, SCOREBOARD_Y + LINE_SPACING
	mov eax, linesCleared
	call WriteDec

	mGotoxy INFO_COLUMN_X + SCORE_LABEL_LENGTH, SCOREBOARD_Y + LINE_SPACING * 2
	mov eax, charsTyped
	call WriteDec

	mGotoxy INFO_COLUMN_X + SCORE_LABEL_LENGTH, SCOREBOARD_Y + LINE_SPACING * 3
	mov eax, backspacesPressed
	call WriteDec

	mGotoxy INFO_COLUMN_X + SCORE_LABEL_LENGTH, SCOREBOARD_Y + LINE_SPACING * 4
	mov ecx, charsTyped
	mov eax, secondsPlayed
	call GetWPM
	call WriteDec

	mGotoxy INFO_COLUMN_X + SCORE_LABEL_LENGTH, SCOREBOARD_Y + LINE_SPACING * 5
	mov eax, charsTyped
	mov ecx, wrongCharCount
	call GetErrorsPerHundred
	call WriteDec

	; Pop original cursor position to return to former position
	pop ax
	mov dh, al
	pop ax
	mov dl, al
	call UpdateCursorPos

	ret
UpdateScoreboard endp


;-------------------------------------------------------------------------------
; GetWPM
;
; Calculate words per minute.
; Receives: ECX = Characters
;			EAX = Seconds
; Returns:	EAX = Words per minute
;-------------------------------------------------------------------------------
GetWPM proc
	mov edx, 0	; Clear upper register
	mov ebx, 60	; Divisor = 60 seconds
	div ebx		; EDX = seconds, EAX = minutes

	cmp eax, 0			; Minutes is 0?
	jne MinutesNotZero
	mov eax, 1			; Yes: Round up to 1

MinutesNotZero:
	push eax	; Save minutes

	; Calculating words (assuming average word is 5 chars)
	mov edx, 0		; Clear upper register
	mov eax, ecx	; Dividend = Characters
	mov ecx, 5		; Divisor = 5 (avg word length)
	div ecx			; EAX = Words

	mov edx, 0	; Clear upper register
	pop ebx		; Divisor = minutes
	div ebx		; Words / Seconds, EAX = WPM
	
	ret
GetWPM endp


;-------------------------------------------------------------------------------
; GetErrorsPerHundred
;
; Calculate errors per hundred characters.
; Receives: ECX = Error characters
;			EAX = Characters typed
; Returns:	EAX = Errors per hundred characters
;-------------------------------------------------------------------------------
GetErrorsPerHundred proc
	mov edx, 0		; Clear upper register
	mov ebx, 100	; Divisor = 100 words
	div ebx			; EAX = 100s of chars typed

	cmp eax, 0			; 100s of chars typed is 0?
	jne MinutesNotZero
	mov eax, 1			; Yes: Round up to 1

MinutesNotZero:
	; Calculating errors per 100 chars
	mov edx, 0		; Clear upper register
	mov ebx, eax	; Divisor = 100s of chars typed
	mov eax, ecx	; Dividend = Errors typed
	div ebx			; Errors / 100s of chars typed = Errors per 100, EAX = ErrorsPer100

	ret
GetErrorsPerHundred endp


;-------------------------------------------------------------------------------
; ResetGame
;
; Resets game data for repeat sessions.
;-------------------------------------------------------------------------------
ResetGame proc
	; Reset scores
	mov charsTyped, 0
	mov backspacesPressed, 0
	mov linesCleared, 0
	mov wrongCharCount, 0

	; Reset starting distance
	mov distanceFromTop, STARTING_DISTANCE

	; Reset typing prompt data
	mov typingPromptLeftBound, 0
	mov charIdx, 0

	; Reset timing
	mov linePrintTicksElapsed, 0
	mov typingPromptRightBound, 0
	mov lineProgressSpeed, STARTING_PROGRESSION_SPEED
	mov secondsPlayed, 0

	mov ecx, LENGTHOF textColors - 1
ResetColors:
	mov textColors[ecx * TYPE textColors], black+(white*16)
	loop ResetColors
	mov textColors[ecx * TYPE textColors], black+(white*16)

	mov ecx, LENGTHOF lineStatus - 1
ResetLineStatus:
	mov lineStatus[ecx * TYPE lineStatus], 0
	loop ResetColors
	mov lineStatus[ecx * TYPE lineStatus], 0

	ret
ResetGame endp


;-------------------------------------------------------------------------------
; CorrectInput
;
; Updates line status bit string to reflect correct input.
;-------------------------------------------------------------------------------
CorrectInput proc USES eax
	mov eax, lineStatus[0]
	shrd lineStatus[TYPE lineStatus], eax, 1
	mov eax, 1
	shrd lineStatus[0], eax, 1
	ret
CorrectInput endp


;-------------------------------------------------------------------------------
; WrongInput
;
; Updates line status bit string to reflect incorrect input.
;-------------------------------------------------------------------------------
WrongInput proc USES eax
	mov eax, lineStatus[0]
	shrd lineStatus[TYPE lineStatus], eax, 1
	shr lineStatus[0], 1
	ret
WrongInput endp


;-------------------------------------------------------------------------------
; RevertLineStatus
;
; Reverts last change to line status bit string.
;-------------------------------------------------------------------------------
RevertLineStatus proc USES eax
	mov eax, lineStatus[TYPE lineStatus]
	shld lineStatus[0], eax, 1
	shl lineStatus[TYPE lineStatus], 1
	ret
RevertLineStatus endp


;-------------------------------------------------------------------------------
; ClearLineStatus
;
; Sets line status bit string to zeros.
;-------------------------------------------------------------------------------
ClearLineStatus proc USES eax
	mov ecx, LENGTHOF lineStatus - 1
StatusClearing:
	mov lineStatus[ecx * TYPE lineStatus], 0
	loop StatusClearing
	mov lineStatus[ecx * TYPE lineStatus], 0

	ret
ClearLineStatus endp


;-------------------------------------------------------------------------------
; CheckLineStatus
;
; Reverts last change to line status bit string.
; Recieves: EBX = left bound of typing prompt
; Returns : CY = 0 if line not completely correct
;			CY = 1 if line is completely correct
;-------------------------------------------------------------------------------
CheckLineStatus proc USES eax ebx ecx edx
	mov ecx, typingPromptSize
	sub ecx, ebx
	mov edx, 0		; Counter for how many times rotated

	cmp ecx, LINE_LENGTH
	jbe L_LineCheck
	mov ecx, LINE_LENGTH

L_LineCheck:
	mov eax, lineStatus[0]
	shld lineStatus[TYPE lineStatus], eax, 1
	rcl lineStatus[0], 1
	inc edx
	jnc IncorrectChar
	loop L_LineCheck

	mov edi, 1
	jmp ReturnBits

IncorrectChar:
	mov edi, 0

ReturnBits:
	mov ecx, edx
L_ReturnBits:
	mov eax, lineStatus[TYPE lineStatus]
	shrd lineStatus[0], eax, 1
	rcr lineStatus[TYPE lineStatus], 1
	loop L_ReturnBits

	cmp edi, 1
	jne LineIsIncorrect
	stc
	jmp LineIsCorrect

LineIsIncorrect:
	clc
LineIsCorrect:
	ret
CheckLineStatus endp


;-------------------------------------------------------------------------------
; TimeFormat
;
; Formats seconds as minutes:seconds.
; Recieves: EAX = the amount of seconds
;-------------------------------------------------------------------------------
TimeFormat proc USES ebx
	mov edx, 0	; Clear upper register
	mov ebx, 60	; Divisor = 60 seconds
	div ebx		; EDX = seconds, EAX = minutes

	; Write minutes
	call WriteDec
	mWrite ":"

	; Write seconds (zero-padded)
	mov eax, edx
	cmp eax, 10
	jae TwoDigitSec
	mWrite "0"
TwoDigitSec:
	call WriteDec

	ret
TimeFormat endp


;-------------------------------------------------------------------------------
; GameStart
;
; Displays game start message.
;-------------------------------------------------------------------------------
GameStart proc
	mov ecx, 3		; Countdown start number

	; Set color to black on yellow
	mov eax, black + (yellow * 16)
	call SetTextColor

Countdown:
	mov eax, 50 * SECOND_IN_TICKS	; Wait one second
	call Delay

	; Write number
	mGotoxy PLAY_AREA_X + LINE_LENGTH / 2 - 7, PLAY_AREA_Y + STARTING_DISTANCE / 2
	mWrite "      "
	mov eax, ecx
	call WriteDec
	mWrite "      "

	; Move cursor out of center
	mGotoxy PLAY_AREA_X, PLAY_AREA_Y + STARTING_DISTANCE

	loop Countdown

	; Display START
	mov eax, 50 * SECOND_IN_TICKS
	call Delay
	mGotoxy PLAY_AREA_X + LINE_LENGTH / 2 - 7, PLAY_AREA_Y + STARTING_DISTANCE / 2
	mWrite "    START    "

	; Move cursor out of center
	mGotoxy PLAY_AREA_X, PLAY_AREA_Y + STARTING_DISTANCE

	; Clear displayed messages
	mov eax, black + (black * 16)		; Set color for display removal
	call SetTextColor
	mov eax, TICK * SECOND_IN_TICKS
	call Delay
	mGotoxy PLAY_AREA_X + LINE_LENGTH / 2 - 7, PLAY_AREA_Y + STARTING_DISTANCE / 2
	mWrite "             "

	ret
GameStart endp


;-------------------------------------------------------------------------------
; GameOver
;
; Displays game over message.
;-------------------------------------------------------------------------------
GameOver proc
	mov ecx, LENGTHOF textColors - 1

	; Reset color array to contain all read
ResetColors:
	mov textColors[ecx * TYPE textColors], white+(red*16)
	loop ResetColors
	mov textColors[ecx * TYPE textColors], white+(red*16)

	; Position cursor for rewrite
	mov dl, PLAY_AREA_X
	mov dh, PLAY_AREA_Y
	call UpdateCursorPos

	; Rewrite prompt in red
	mov edx, OFFSET typingPrompt
	mov ebx, typingPromptLeftBound
	mov ecx, typingPromptRightBound
	call ReprintPrompt

	; Return cursor to top left
	mov dl, PLAY_AREA_X
	mov dh, PLAY_AREA_Y
	call UpdateCursorPos

	mov eax, TICK * SECOND_IN_TICKS * 2
	call Delay

	; Clear remaining lines one by one
ClearLines:
	mov eax, TICK * 2
	call Delay
	call ClearDisplayLine
	call Newline
	cmp cursorY, PLAY_AREA_Y + STARTING_DISTANCE
	jne ClearLines

	; Display GAME OVER
	mov eax, black + (yellow * 16)		; Set color for highlited message
	call SetTextColor
	mGotoxy PLAY_AREA_X + LINE_LENGTH / 2 - 10, PLAY_AREA_Y + STARTING_DISTANCE / 2 - LINE_SPACING
	mWrite "    GAME OVER    "

	; Move cursor out of center
	mGotoxy PLAY_AREA_X, PLAY_AREA_Y + STARTING_DISTANCE
	mov eax, TICK * SECOND_IN_TICKS * 2
	call Delay

	; Display "Press any key to continue..."
	mGotoxy PLAY_AREA_X + LINE_LENGTH / 2 - 15, PLAY_AREA_Y + STARTING_DISTANCE / 2 
	mov eax, yellow + (black * 16)		; Set color for standard message
	call SetTextColor
	call WaitMsg

	ret
GameOver endp


;-------------------------------------------------------------------------------
; LevelCleared
;
; Displays level cleared message.
;-------------------------------------------------------------------------------
LevelCleared proc
	mov ecx, 3		; Countdown start number

	; Set color to black on yellow
	mov eax, black + (yellow * 16)
	call SetTextColor

	; Display LEVEL CLEARED
	mGotoxy PLAY_AREA_X + LINE_LENGTH / 2 - 12, PLAY_AREA_Y + STARTING_DISTANCE / 2 - LINE_SPACING
	mWrite "    LEVEL CLEARED    "

	; Move cursor out of center
	mGotoxy PLAY_AREA_X, PLAY_AREA_Y + STARTING_DISTANCE
	mov eax, TICK * SECOND_IN_TICKS * 2
	call Delay

	; Display "Press any key to continue..."
	mGotoxy PLAY_AREA_X + LINE_LENGTH / 2 - 15, PLAY_AREA_Y + STARTING_DISTANCE / 2 
	mov eax, yellow + (black * 16)		; Set color for standard message
	call SetTextColor
	call WaitMsg

	ret
LevelCleared endp


;-------------------------------------------------------------------------------
; DisplayPlayArea
;
; Displays the static graphic elements of the game.
;-------------------------------------------------------------------------------
DisplayPlayArea proc
	; Game title
	mov eax, black + (yellow * 16)
	call SetTextColor
	mGotoxy INFO_COLUMN_X, PLAY_AREA_Y + 2
	mWrite "    TYPING TUTOR    "

	; Top divider
	mov eax, yellow + (black * 16)
	call SetTextColor
	mGotoxy PLAY_AREA_X, PLAY_AREA_Y - 1
	mWriteString OFFSET divider

	; Bottom divider
	mGotoxy PLAY_AREA_X, PLAY_AREA_Y + STARTING_DISTANCE
	mWriteString OFFSET divider

	; Scoreboard labels
	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y
	mWrite "Minutes Elapsed   : "
	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING
	mWrite "Lines Cleared     : "
	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING * 2
	mWrite "Characters Typed  : "
	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING * 3
	mWrite "Backspaces Pressed: "
	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING * 4
	mWrite "Words Per Minute  : "
	mGotoxy INFO_COLUMN_X, SCOREBOARD_Y + LINE_SPACING * 5
	mWrite "Errors Per 100    : "

	; How to exit prompt
	mGotoxy INFO_COLUMN_X, PLAY_AREA_Y + STARTING_DISTANCE
	mWrite "Press ESC to Quit"

	; Move cursor out of center
	mGotoxy PLAY_AREA_X, PLAY_AREA_Y + STARTING_DISTANCE
	ret
DisplayPlayArea endp


;-------------------------------------------------------------------------------
; DisplayScores
;
; Displays the stats that were visible in the info column.
;-------------------------------------------------------------------------------
DisplayScores proc
	STATS_SCREEN_X = 35
	STATS_SCREEN_Y = 8

	; Game title
	mov eax, black + (yellow * 16)
	call SetTextColor
	mGotoxy STATS_SCREEN_X, STATS_SCREEN_Y - LINE_SPACING
	mWrite "           STATS           "

	mov eax, yellow+(black*16)	; Set to standard message color
	call SetTextColor

	mGotoxy STATS_SCREEN_X, STATS_SCREEN_Y
	mWrite "Minutes Elapsed   : "
	mov eax, secondsPlayed
	call TimeFormat
	mov eax, TICK * 2
	call Delay

	mGotoxy STATS_SCREEN_X, STATS_SCREEN_Y + LINE_SPACING
	mWrite "Lines Cleared     : "
	mov dl, STATS_SCREEN_X + SCORE_LABEL_LENGTH
	mov dh, STATS_SCREEN_Y + LINE_SPACING
	call UpdateCursorPos
	mov eax, linesCleared
	call CountUp
	mov eax, TICK * 2
	call Delay
	
	mGotoxy STATS_SCREEN_X, STATS_SCREEN_Y + LINE_SPACING * 2
	mWrite "Characters Typed  : "
	mov dl, STATS_SCREEN_X + SCORE_LABEL_LENGTH
	mov dh, STATS_SCREEN_Y + LINE_SPACING * 2
	call UpdateCursorPos
	mov eax, charsTyped
	call CountUp
	mov eax, TICK * 2
	call Delay

	mGotoxy STATS_SCREEN_X, STATS_SCREEN_Y + LINE_SPACING * 3
	mWrite "Backspaces Pressed: "
	mov eax, backspacesPressed
	call WriteDec
	mov eax, TICK * 2
	call Delay

	mGotoxy STATS_SCREEN_X, STATS_SCREEN_Y + LINE_SPACING * 4
	mWrite "Words Per Minute  : "
	mov ecx, charsTyped
	mov eax, secondsPlayed
	call GetWPM
	call WriteDec
	mov eax, TICK * 2
	call Delay

	mGotoxy STATS_SCREEN_X, STATS_SCREEN_Y + LINE_SPACING * 5
	mWrite "Errors Per 100    : "
	mov eax, charsTyped
	mov ecx, wrongCharCount
	call GetErrorsPerHundred
	call WriteDec
	mov eax, TICK * 2
	call Delay

	mGotoxy STATS_SCREEN_X, STATS_SCREEN_Y + LINE_SPACING * 6
	mWrite "Enter name: "
	call UpdateScoreFile

	ret
DisplayScores endp


;-------------------------------------------------------------------------------
; CountUp
;
; Displays a rapid count up to a given number.
; Receives: EAX = number to count up to
;-------------------------------------------------------------------------------
CountUp proc
	cmp eax, 0
	je IsZero
	mov ecx, eax
	mov ebx, 0

UpCounter:
	mov eax, 5
	call Delay

	; Increment the counter and display the number
	mGotoxy cursorX, cursorY
	inc ebx
	mov eax, ebx
	call WriteDec

	loop UpCounter

	jmp Quit

IsZero:
	mWrite "0"

Quit:
	ret
CountUp endp


;-------------------------------------------------------------------------------
; WriteStrToFile
;
; Writes a string to a given file.
; Receives: outFileHandle (arg 0) = the handle of the file being written to
;			strToWrite (arg 1) = the offset of the string to write
;			strLen (arg 2)     = the length of the string being written
;-------------------------------------------------------------------------------
WriteStrToFile proc, outFileHandle:HANDLE, strToWrite:PTR BYTE, strLen:DWORD
	mov eax, outFileHandle
	mov edx, strToWrite
	mov ecx, strLen
	call WriteToFile
	ret
WriteStrToFile endp


;-------------------------------------------------------------------------------
; ClearString
;
; Clears the contents of a string.
; Receives: strToClear (arg 0) = the address of the string to be cleared
;			strToClearLen (arg 1) = the length of the string to be cleared
;-------------------------------------------------------------------------------
ClearString proc USES eax ecx edx, strToClear:PTR BYTE, strToClearLen:DWORD
	mov edx, strToClear		; Move address of array into register for ease of use
	mov ecx, strToClearLen	; Set the counter for the loop to the length of array
	mov al, 0				; The value to reset string to
StringClearer:
	mov [edx + ecx - 1], al
	loop StringClearer
	ret
ClearString endp


;-------------------------------------------------------------------------------
; UpdateScoreFile
;
; Requests a name and updates score file accordingly.
;-------------------------------------------------------------------------------
UpdateScoreFile proc
SCORE_IN_BUFFER_SIZE = 2000
SCORE_OUT_BUFFER_SIZE = 501

.data
	scoreFile BYTE "scores.txt", 0
	scoreFileHandle HANDLE ?

	inBuffer BYTE SCORE_IN_BUFFER_SIZE DUP(?)
	scoreBytesRead DWORD ?

	username BYTE SCORE_OUT_BUFFER_SIZE DUP(?)
	nameLength DWORD ?

	fileNewLine BYTE 0Dh, 0Ah, 0Dh, 0Ah
	scoreDivider BYTE " | "

	linesClearedLabel BYTE "Lines cleared: "
	wpmLabel BYTE "Words per minute: "
	errorsPerHundredLabel BYTE "Errors per 100 characters: "
	timePlayedLabel BYTE "Seconds played: "

.code
	invoke ClearString, ADDR username, LENGTHOF username
	mov nameLength, 0

	; Read what was on file
	mov edx, OFFSET scoreFile
	mov ecx, OFFSET inBuffer
	mov ebx, SCORE_IN_BUFFER_SIZE
	call ReadFileToString
	mov scoreBytesRead, eax

	; Open score file in write mode
	mov edx, OFFSET scoreFile
	call CreateOutputFile
	mov scoreFileHandle, eax

	; Error checking
	cmp eax, INVALID_HANDLE_VALUE
	jne out_file_ok
	mWrite "Cannot create file"
	call Crlf
	jmp quit

out_file_ok:
	; Rewrite what was previously stored in score file
	invoke WriteStrToFile, scoreFileHandle, ADDR inBuffer, scoreBytesRead

	; Get input for name
	mReadString username
	mov nameLength, eax

	; Write username to file
	invoke WriteStrToFile, scoreFileHandle, ADDR username, nameLength

	invoke WriteStrToFile, scoreFileHandle, ADDR scoreDivider, LENGTHOF scoreDivider	; Write a divider

	; Write lines cleared
	invoke WriteStrToFile, scoreFileHandle, ADDR linesClearedLabel, LENGTHOF linesClearedLabel
	mov eax, linesCleared
	call IntToString
	invoke WriteStrToFile, scoreFileHandle, edx, ecx

	invoke WriteStrToFile, scoreFileHandle, ADDR scoreDivider, LENGTHOF scoreDivider	; Write a divider

	; Write WPM
	invoke WriteStrToFile, scoreFileHandle, ADDR wpmLabel, LENGTHOF wpmLabel
	mov eax, secondsPlayed
	mov ecx, charsTyped
	call GetWPM
	call IntToString
	invoke WriteStrToFile, scoreFileHandle, edx, ecx

	invoke WriteStrToFile, scoreFileHandle, ADDR scoreDivider, LENGTHOF scoreDivider	; Write a divider

	; Write errors per 100
	invoke WriteStrToFile, scoreFileHandle, ADDR errorsPerHundredLabel, LENGTHOF errorsPerHundredLabel
	mov eax, charsTyped
	mov ecx, wrongCharCount
	call GetErrorsPerHundred
	call IntToString
	invoke WriteStrToFile, scoreFileHandle, edx, ecx

	invoke WriteStrToFile, scoreFileHandle, ADDR scoreDivider, LENGTHOF scoreDivider	; Write a divider

	; Write time played
	invoke WriteStrToFile, scoreFileHandle, ADDR timePlayedLabel, LENGTHOF timePlayedLabel
	mov eax, secondsPlayed
	call IntToString
	invoke WriteStrToFile, scoreFileHandle, edx, ecx

	; Write a double-spaced new line
	invoke WriteStrToFile, scoreFileHandle, ADDR fileNewLine, LENGTHOF fileNewLine

	mov eax, scoreFileHandle
	call CloseFile
quit:
	ret
UpdateScoreFile endp


;-------------------------------------------------------------------------------
; ReverseString
;
; Reverses the contents of a string.
; Receives: strToReverse (arg 0) = the address of the string to be cleared
;			strToReverseLen (arg 1) = the length of the string to be cleared
;-------------------------------------------------------------------------------
ReverseString proc USES eax ebx ecx edx, strToReverse:PTR BYTE, strToReverseLen:DWORD
	mov edx, strToReverse		; Move address of array into register for ease of use
	mov ecx, strToReverseLen	; Set the counter for the loop to the length of array
	mov ebx, 0					; Index for character getting

StringPusher:
	movzx ax, BYTE PTR [edx + ebx]
	push ax
	inc ebx
	loop StringPusher

	mov ecx, strToReverseLen	; Set the counter for the loop to the length of array
	mov ebx, 0					; Index for character getting
StringPopper:
	pop ax
	mov [edx + ebx], al
	inc ebx
	loop StringPopper
	ret
ReverseString endp


;-------------------------------------------------------------------------------
; IntToString
;
; Converts integer to string
; Returns:  EDX = offset of integer string
;-------------------------------------------------------------------------------
.data
	intStr BYTE 16 DUP(0)
	intCharCount BYTE 0

.code
IntToString proc
	; Resetting data
	invoke ClearString, ADDR intStr, LENGTHOF intStr

	cmp eax, 0
	jne NumIsNotZero
	mov intStr, "0"
	mov ecx, 1
	jmp Quit

NumIsNotZero:
	mov ecx, 0		; Index for int string array
IntConversionLoop:
	mov edx, 0		; Divide original int by ten
	mov ebx, 10
	div ebx

	add edx, "0"	; Add "0" to remainder to get the number as ASCII
	mov intStr[ecx], dl
	
	inc ecx				; Move to next character

	cmp edx, "0"
	jne IntConversionLoop

	; Remove leading zero
	dec ecx
	mov intStr[ecx], 0

	invoke ReverseString, ADDR intStr, ecx

Quit:
	mov edx, OFFSET intStr
	ret
IntToString endp


;-------------------------------------------------------------------------------
;                               LEADERBOARD
;-------------------------------------------------------------------------------

LEADERBOARD_X = 35
LEADERBOARD_Y = 10

.data

.code

LEADERBOARD proc
	mov edx, OFFSET scoreFile
	mov ecx, OFFSET inBuffer
	mov ebx, SCORE_IN_BUFFER_SIZE
	call ReadFileToString

	mov eax, yellow + (black * 16)
	call SetTextColor

	mWriteString OFFSET inBuffer
	call WaitMsg
	ret
LEADERBOARD endp


end main