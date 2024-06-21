; ====================================================
;	PKUNZIP utility for Sprinter version 0.8
;   Created by Aleksey Gavrilenko 09.02.2002
;   Procedure deflate by Michail Kondratyev
; ----------------------------------------------------
;   Version 0.8 by Romychs, for DSS v1.70, 
;   + support for current dir
; ====================================================

; Set to 1 to turn debug ON with DeZog VSCode plugin
; Set to 0 to compile .EXE
DEBUG				EQU	0
EXE_VERSION			EQU 1

	SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION
	
	DEVICE NOSLOT64K

	IF  DEBUG == 1
		include "bios.asm"
		include "test_data.asm"

		DS 0x80, 0
	ENDIF

; DSS RST Entry
DSS					EQU 0x10

; DSS Functions
DSS_CREATE_FILE		EQU 0x0B
DSS_OPEN_FILE		EQU 0x11
DSS_CLOSE_FILE		EQU 0x12
DSS_READ_FILE		EQU 0x13
DSS_WRITE			EQU 0x14
DSS_MOVE_FP_CP		EQU 0x0115
DSS_FIND_FIRST		EQU 0x0119
DSS_FIND_NEXT		EQU 0x011A
DSS_MKDIR			EQU 0x1B
DSS_CHDIR			EQU 0x1D
DSS_CURDIR			EQU 0x1E
DSS_EXIT			EQU 0x41
DSS_PCHARS			EQU 0x5C

; DSS Error codes
E_FILE_EXISTS		EQU 7
E_FILE_NOT_FOUND	EQU 3

; Memory pages
PAGE0_ADDR			EQU 0x0000
PAGE1_ADDR			EQU 0x4000
PAGE2_ADDR			EQU 0x8000
PAGE3_ADDR			EQU 0xC000

; Sprinter ports
; to switch mem pages
PAGE0				EQU 0x82
PAGE1				EQU 0xA2
PAGE2				EQU 0xC2
PAGE3				EQU 0xE2

BRD_SND				EQU 0xFE	; WR_BRD?

; Other
; Max number of Code Length codes
NR_CL				EQU 19
MAX_CL				EQU	16
NR_LIT				EQU	288
NR_DIST				EQU	32

	ORG 0x8080

EXE_HEADER
	DB	"EXE"
	DB	EXE_VERSION										; EXE Version
	DW	0x0080											; Code offset
	DW	0
	DW	0												; Primary loader size
	DW	0												; Reserved
	DW	0
	DW	0
	DW	START											; Loading Address
	DW	START											; Entry Point
	DW	STACK_TOP										; Stack address
	DS	106, 0											; Reserved

	ORG 0x8100
STACK_TOP

; ====================================================
; MAIN Entry point
; ====================================================
START
	IF DEBUG == 1
	LD IX,CMD_LINE1
	ENDIF
	PUSH	IX											; IX ptr to cmd line
	POP		HL
	INC		HL											; Skip size of Command line
	LD		DE,PATH_INPUT
	CALL	GET_CMD_PARAM
	JR		C,INVALID_CMDLINE
	LD		DE,PATH_OUTPUT
	CALL	GET_CMD_PARAM
	JR		NC,IS_SEC_PAR
	; Set output dir to current dir
	LD		C, DSS_CURDIR
	LD		HL,PATH_OUTPUT
	RST		DSS
	JP		NC, START_L1
	JP		ERR_FILE_OP

IS_SEC_PAR
	; split path and file name
	LD		HL,PATH_OUTPUT
	CALL	SPLIT_PATH_FILE
	JR		START_L1

	; Out start message and usage message, then exit to DSS
INVALID_CMDLINE
	LD		HL,MSG_START							
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,MSG_USAGE
	LD		C,DSS_PCHARS
	RST		DSS
	LD		BC,DSS_EXIT
	RST		DSS

START_L1
	LD		A,(PATH_INPUT)								; ToDo: No parameters, It is already checked before?
	AND		A
	JR		Z,INVALID_CMDLINE
	LD		HL,MSG_START							; "PKUNZIP utility for Sprinter 
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,PATH_INPUT
	CALL	SPLIT_PATH_FILE								; get zip file path and name from first cmd line parameter
	JP		C,ERR_FILE_OP
	; if input path is empty, get current dir
	LD		A,(PATH_INPUT)
	AND		A
	JP	    NZ,INP_P_NE

	LD		C, DSS_CURDIR
	LD		HL,PATH_INPUT
	RST		DSS


INP_P_NE
	LD		HL,MSG_INP_PATH								; "Input path:"
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,PATH_INPUT
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,MSG_EOL									; '\r'
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,MSG_OUT_PATH								; "Out path:"
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,PATH_OUTPUT
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,MSG_EOL									; '\r'
	LD		C,DSS_PCHARS
	RST		DSS
	IN		A,(PAGE0)
	LD		(SAVE_P0),A
	; Change dir to input file directory
	LD		HL,PATH_INPUT
	LD		C,DSS_CHDIR
	RST		DSS
	JP		C,ERR_FILE_OP
	; Find first file by specified name or mask (*.zip for example)
	LD		HL,FILE_SPEC
	LD		DE,FF_WORK_BUF								; Work buffer
	LD		BC,DSS_FIND_FIRST							; FIND_FIRST
	LD		A,0x2f										; Attrs
	RST		DSS
	JP		C,ERR_FILE_OP								; File not found
	JR		OPEN_ZIP_FILE

; ----------------------------------------------------
DO_NEXT_FILE
	LD		DE,FF_WORK_BUF
	LD		BC,DSS_FIND_NEXT							; FIND_NEXT
	RST		DSS
	JR		NC,OPEN_ZIP_FILE
	CP		E_FILE_NOT_FOUND
	JP		NZ,ERR_FILE_OP
	LD		HL,MSG_DEPAC_COMPLT							; "\r\nDepaking complited\r\n\n"
	LD		C,DSS_PCHARS
	RST		DSS
	LD		BC,DSS_EXIT
	RST		DSS

OPEN_ZIP_FILE
	LD		HL,FF_FILE_NAME
	XOR		A
	LD		C,DSS_OPEN_FILE
	RST		DSS
	JP		C,ERR_FILE_OP
	LD		(FH_INP),A
	LD		HL,MSG_DEPAC_FILE							; "Depaking file: "
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,FF_FILE_NAME
	LD		C,DSS_PCHARS
	RST		DSS

RD_LOCAL_HDR
	CALL	READ_HEADERS
	JR		C,ERR_IN_ZIP
	AND		A											; it is LFH? 
	JP		Z,DO_OUT_FNAME
	; it is not local file header, but central directory
	; close input file and go to next file
CLOSE_AND_NXT
	LD		A,(FH_INP)
	LD		C,DSS_CLOSE_FILE
	RST		DSS
	JP		C,ERR_FILE_OP
	XOR		A
	LD		(FH_INP),A
	JR		DO_NEXT_FILE

ERR_IN_ZIP
	LD		HL,MSG_ERR_IN_ZIP							; "\r\nError in ZIP!\r\n"
	LD		C,DSS_PCHARS
	RST		DSS
	JR		CLOSE_AND_NXT

	; Build full file name from output path and  zip local header
DO_OUT_FNAME
	LD		HL,PATH_OUTPUT
	LD		DE,TEMP_BUFFR
	LD		BC,256
	LDIR
	LD		HL,MSG_EOL									; '\r'
	LD		C,DSS_PCHARS
	RST		DSS
	LD		HL,TEMP_BUFFR
	XOR		A
	; find end of path
FND_PATH_CPY_END
	CP		(HL)										; HL => TEMP_BUFFR
	JR		Z,END_PATH_CPY
	INC		HL
	JR		FND_PATH_CPY_END
	; check last symbol is '\'' and add if not
END_PATH_CPY
	DEC		HL
	LD		A,(HL)										
	CP		"\\"
	JR		Z,IS_DIR_SEP
	INC		HL
	LD		(HL),"\\"									
IS_DIR_SEP
	INC		HL
	LD		(HL),0x0									; mark end of string
	LD		DE,ENTRY_FILE_NAME

ADD_FNAME_TO_PATH
	LD		A,(DE)										; =>ENTRY_FILE_NAME
	LD		(HL),A										; =>TEMP_BUFFR + 1
	INC		HL
	INC		DE
	; check end of file name
	AND		A
	JR		NZ,ADD_FNAME_TO_PATH

	; replace UNIX slash to DOS back slash
	LD		HL,TEMP_BUFFR
CHK_SLASH	
	LD		A,(HL)										; HL => TEMP_BUFFR
	CP		'/'
	JR		NZ,SYM_NO_BSLASH
	LD		(HL),"\\"
SYM_NO_BSLASH
	INC		HL
	AND		A
	JR		NZ,CHK_SLASH

	; Output compression method to screen
	LD		HL,(LH_PARAMS)
	LD		A,H
	OR		A
	JR		NZ,COMP_PARAMS_EMP
	LD		A,L
	CP		9
	JR		NC,COMP_PARAMS_EMP
	LD		HL,MSG_STORED								; "Stored:	"
	AND		A
	JR		Z,OUT_COMP_MSG
	LD		HL,MSG_UNSHRINK								; "Unshrinkin: "
	DEC		A
	JR		Z,OUT_COMP_MSG
	LD		HL,MSG_REDUCED								; "Reduced:	"
	DEC		A
	JR		Z,OUT_COMP_MSG
	DEC		A
	JR		Z,OUT_COMP_MSG
	DEC		A
	JR		Z,OUT_COMP_MSG
	DEC		A
	JR		Z,OUT_COMP_MSG
	LD		HL,MSG_IMPLODING							; "Imploding:  "
	DEC		A
	JR		Z,OUT_COMP_MSG
	LD		HL,MSG_TOKENIZING							; "Tokenizing: "
	DEC		A
	JR		Z,OUT_COMP_MSG								; Method 8 - Deflate|Inflate
	LD		HL,MSG_INFLATING							; "Inflanting: "

OUT_COMP_MSG
	LD		C,DSS_PCHARS
	RST		DSS											; Out compression type
	LD		HL,TEMP_BUFFR								; Out output file name
	LD		C,DSS_PCHARS
	RST		DSS
	LD		A,(LH_PARAMS)
	AND		A
	JR		Z,C_SUPPORTED
	CP		8											; DEFLATE
	JR		Z,C_SUPPORTED
	LD		HL,MSG_RESERVD_METHOD						; "  Reserved metod!"
	LD		C,DSS_PCHARS
	RST		DSS
	
	; move file pointer to next local header in zip file
MV_TO_NEXT_LH
	LD		HL,(LH_COMP_SIZE_H)
	LD		IX,(LH_COMP_SIZE_L)
	LD		BC,DSS_MOVE_FP_CP							; MOVE_FP from Current Pos
	LD		A,(FH_INP)
	RST		DSS
	JP		C,ERR_FILE_OP
	JP		RD_LOCAL_HDR
	
COMP_PARAMS_EMP
	LD		HL,MSG_UNKNOWN								; "Unknown:	"
	LD		C,DSS_PCHARS
	RST		DSS
	JR		MV_TO_NEXT_LH
	
DIR_OR_EMPTY
	LD		HL,TEMP_BUFFR
	CALL	MAKE_FILE_PATH
	OUT		(BRD_SND),A
	JP		C,ERR_FILE_OP
	JP		RD_LOCAL_HDR
	
; Supported compression method. Stored or Deflate
C_SUPPORTED
	LD		HL,(LH_COMP_SIZE_L)
	LD		(BYTES_REMAINS_L),HL
	LD		DE,(LH_COMP_SIZE_H)
	LD		(BYTES_REMAINS_H),DE
	LD		HL,0xffff
	LD		(CRC32_L),HL
	LD		(CRC32_H),HL
	LD		HL,0x0
	LD		(DW_COUNTER_L),HL
	LD		(DW_COUNTER_H),HL
	LD		HL,(LH_COMP_SIZE_L)
	LD		DE,(LH_COMP_SIZE_H)
	LD		A,H
	OR		L
	OR		D
	OR		E
	JR		Z,DIR_OR_EMPTY
	LD		HL,TEMP_BUFFR
	; check end of file name for '\'
	XOR		A
	LD		BC,0x80
	CPIR												; Find end of string (zero byte)
	DEC		HL
	DEC		HL											; HL points to last string char
	LD		A,(HL)										; HL => TEMP_0
	CP		"\\"										; it is directory separator?
	JR		Z,DIR_OR_EMPTY

	; create output file and jump to ok, or try to create dir
	; and then create output file
	LD		HL,TEMP_BUFFR
	XOR		A
	LD		C,DSS_CREATE_FILE
	RST		DSS
	JR		NC,OK_CREATE_FILE
	CP		E_FILE_EXISTS								; FM = 7?
	JR		Z,ERR_FILE_EXIST
	; separate output file path and name
	LD		HL,TEMP_BUFFR
	CALL	SPLIT_PATH_FILE
	JP		C,ERR_FILE_OP
	; make output directory
	LD		HL,TEMP_BUFFR								; HL => output file path
	CALL	MAKE_FILE_PATH								
	JP		C,ERR_FILE_OP
	; change dir to output directory
	LD		HL,TEMP_BUFFR
	LD		C,DSS_CHDIR
	RST		DSS
	JP		C,ERR_FILE_OP
	; create output file
	LD		HL,FILE_SPEC
	XOR		A
	LD		C,DSS_CREATE_FILE
	RST		DSS
	JR		NC,OK_CREATE_FILE
	CP		E_FILE_EXISTS
	JP		NZ,ERR_FILE_OP
	
	; If file exists, notify user, and jump to next file
ERR_FILE_EXIST
	LD		HL,MSG_FILE_EXISTS							; "  File exists!"
	LD		C,DSS_PCHARS
	RST		DSS
	JP		MV_TO_NEXT_LH
	
OK_CREATE_FILE
	LD		(FH_OUT),A
	CALL	FL_DECOMP									; Call decompression routine
	LD		B,0x4
	LD		DE,LH_CRC32
	LD		HL,CRC32_L
	LD		B,0x4										; TODO: Remove exltra B=4
	
	; Compare CRC32 from header and calculated for output file
CRC_CMP	
	LD		A,(DE)										; DE => LH_CRC32
	XOR		(HL)										; HL => CRC32
	INC		HL
	INC		DE
	INC		A
	JR		NZ, CRC_CHK_ERR
	DJNZ	CRC_CMP
	; CRC Ok, close output file and go to next header
	LD		HL, MSG_OK_CR_LF							; ' '
	LD		C, DSS_PCHARS
	RST		DSS
	LD		A,(FH_OUT)
	LD		C, DSS_CLOSE_FILE
	RST		DSS
	JP		C,ERR_FILE_OP
	XOR		A
	LD		(FH_OUT),A									; mark File Manipulator as 0 - closed
	JP		RD_LOCAL_HDR
	
CRC_CHK_ERR
	; Notify user about possible error and go to next header
	LD		HL,MSG_ERR_CRC								; "  Error CRC!"
	LD		C,DSS_PCHARS
	RST		DSS
	LD		A,(FH_OUT)
	LD		C,DSS_CLOSE_FILE
	RST		DSS
	JP		C,ERR_FILE_OP
	JP		RD_LOCAL_HDR


; ----------------------------------------------------
; ZIP Local File Header:
; +0 sw Signature 0x04034b50
; +2 w Version to extract
; +4 w general purpose flag
; +8 w compression method
; +10 w MTIME
; +12 w MDATE
; +14 dw CRC32
; +18 dw Compressed Size
; +22 dw UncompressedSize
; +26 w FileName Len (n) 
; +28 w Extra field Len (m)
; +30 n FileName
; +30+n m Extra Field
; ----------------------------------------------------

; STRUCT LH_PARAM_STRUCT
; VERSION WORD
; 	GPP_FLAG WORD
; 	COMP_METHOD WORD
; 	MTIME WORD
; 	MDATE WORD
; 	CRC32 DWORD
; 	COMP_SIZE DWORD
; 	UCOMP_SIZE DWORD
; 	FNAME_LEN WORD
; 	EXTRA_LEN WORD
; 	FILENAME BYTE
; ENDS

; ----------------------------------------------------
; Read local file header to buffer
; Out:  CF=0 - Ok
;		A=0x00 - for LocalHileHeader
;		A=0xff - for CentralDirectory
;		CF=1 - Error
; ----------------------------------------------------
READ_HEADERS
	LD		A,(FH_INP)
	LD		HL,TEMP_BUFFR								; DST ADDR
	LD		DE,30										; BYTES COUNT
	LD		C,DSS_READ_FILE
	RST		DSS
	JP		C,ERR_FILE_OP
	; Check Local file header signature 0x04034b50
	LD		IX,TEMP_BUFFR
	LD		A,(IX+0)									; IX =>TEMP_BUFFR
	CP		50h
	JR		NZ,ERR_LH_SIGN
	LD		A,(IX+1)
	CP		4Bh
	JR		NZ,ERR_LH_SIGN
	LD		A,(IX+2)
	CP		03h
	JP		NZ,NO_LOCAL_FH								; TODO: Check it! 
	LD		A,(IX+3)
	CP		04h
	JR		NZ,ERR_LH_SIGN
	LD		HL,TEMP_BUFFR+8								; From compression method to unc
	LD		DE,LH_PARAMS								; move to LH_PARAMS
	LD		BC,18
	LDIR
	LD		E,(IX+0x1A)									; offset LH_FN_LEN_L
	LD		D,(IX+0x1B)									; offset LH_FN_LEN_H
	PUSH	DE											; File Name Len
	LD		HL,LH_FILENAME								; File Name ptr
	LD		A,(FH_INP)
	LD		C,DSS_READ_FILE
	RST		DSS
	JP		C,ERR_FILE_OP
	POP		DE
	LD		HL,LH_FILENAME
	ADD		HL,DE
	LD		(HL),0x0									; Mark end of string fileName
	LD		HL,LH_FILENAME
	INC		E
	LD		B,0x0
	LD		C,E
	LD		DE,ENTRY_FILE_NAME
	LDIR
	LD		HL,LH_EXTRA_LEN_L							; Extra field len
	LD		E,(HL)
	INC		HL
	LD		D,(HL)
	LD		A,(GPP_FLAG)								; GPP Flag
	AND		0x8											; bit 3 flag, 1 - have optional data desc
	JR		Z,NO_DATA_DSCR
	EX		DE,HL
	LD		DE,12										; Skip data descriptor (3 word)
														; crc32 dw, compressedsize dw, size dw
	ADD		HL,DE
	EX		DE,HL
	; no optrional data descriptor
NO_DATA_DSCR
	LD		HL,LH_FILENAME
	LD		A,(FH_INP)
	LD		C,DSS_READ_FILE
	RST		DSS
	JP		C,ERR_FILE_OP
	XOR		A
	RET

ERR_LH_SIGN
	SCF
	RET

	; it is non local file header
NO_LOCAL_FH
	CP		0x01										; it is CentralDirectory FH?
	JR		NZ,NO_CENTRAL_DIR
	LD		A,(IX+3)									; TMP_BUFFR+3
	CP		0x02										; valid sign 0x02014b50?
	JR		NZ,ERR_LH_SIGN
	LD		A,0xff
	AND		A
	RET

NO_CENTRAL_DIR
	CP		0x05										; is End of central directory?
	JR		NZ,ERR_LH_SIGN
	LD		A,(IX+3)									; TMP_BUFFR+3
	CP		0x06										; valid sign 0x06054b50?
	JR		NZ,ERR_LH_SIGN
	LD		A,0xff
	AND		A
	RET

; ----------------------------------------------------
; Read next command line parameter
; Inp: HL - pointer to cmd line position
;	   DE - pointer to buffer to place parameter
; Out: CF = 1 if no more parameters
; ----------------------------------------------------
GET_CMD_PARAM
	PUSH	DE

FIRST_SPACE
	LD		A,(HL)
	INC		HL
	AND		A
	JR		Z,PARAM_EOL
	; skip first space
	CP		' '
	JR		Z,FIRST_SPACE
	DEC		HL

PARAM_MOV
	; move parameter to buffer pointed by DE byte by byte
	; until space or 0 reached
	LD		A,(HL)
	AND		A
	JR		Z,PARAM_EOL
	CP		' '
	JR		Z,PARAM_EOL
	LD		(DE),A
	INC		HL
	INC		DE
	JR		PARAM_MOV

PARAM_EOL
	; set end of string marker 0 at parameter end
	XOR		A
	LD		(DE),A
	POP		DE
	; if parameter is empty, return CF=1
	LD		A,(DE)
	AND		A
	RET		NZ
	SCF
	RET

; ----------------------------------------------------
; Split filepath for path and file specification 
; (file name, or mask *.zip)
; Inp: HL - Ptr to filepath, zero ended
; Out: CF=1 - Error
;	   CF=0 - FILE_SPEC and trunc filepath to path
; ----------------------------------------------------
SPLIT_PATH_FILE
	PUSH	HL
	; check next 128 bytes to find 0 - end of string
	LD		BC,0x0080
	LD		A,B
	CPIR
	LD		A,C
	AND		A
	JR		NZ,EOS_FOUND
	POP		HL
	; return error flag
	LD		A,0x10
	SCF
	RET
EOS_FOUND
	; find back for last back slash \
	LD		C,0x80
	LD		A,"\\"
	CPDR
	LD		A,C
	AND		A
	JR		NZ,BKSL_FOUND
	POP		HL
	PUSH 	HL
	; copy 13 symbols of filepath to FILE_SPEC. 'filename.zip',0
	LD		BC,13
	LD		DE,FILE_SPEC
	LDIR
	POP 	HL
	LD		(HL),0										; Mark path as empty
	AND		A											; CF=0
	RET
BKSL_FOUND
	; path + filename
	; copy filename to FILE_SPEC
	INC		HL											; HL =>  '\'
	LD		DE,FILE_SPEC
	LD		C,13
	INC		HL											; HL => first symbol of filename
	PUSH	HL
	LDIR
	POP		HL
	; mark path endto last symbol of path
	LD		(HL),0x0
	POP		HL
	AND		A											; CF=0
	RET

; ----------------------------------------------------
MAKE_FILE_PATH
	PUSH	DE
	PUSH	BC
	LD		D,H
	LD		E,L

FIND_SPEC
	LD		A,(DE)
	CP		"\\"
	JR		Z,L_PATH_SPEC
	CP		':'
	JR		Z,L_DRV_SPEC
	AND		A
	JR		Z,L_PATH_SPEC
	CP		' '
	JR		Z,L_PATH_SPEC
	INC		DE
	JR		FIND_SPEC

L_DRV_SPEC
	INC		DE
	INC		DE
	LD		A,(DE)
	CP		' '
	JR		Z,L_SPC_END
	AND		A
	JR		Z,L_SPC_END
	JR		FIND_SPEC

L_PATH_SPEC
	LD		A,(DE)
	PUSH	AF
	PUSH	DE
	XOR		A
	LD		(DE),A
	DEC		DE
	LD		A,(DE)
	CP		"\\"
	SCF
	CCF
	JR		Z,L_PATH_DS
	PUSH	HL
	LD		C,DSS_MKDIR
	RST		DSS
	POP		HL

L_PATH_DS
	POP		DE
	JR		NC,L_DIR_NOT_EXST
	CP		0xf											; Directory exist?
	JR		Z,L_DIR_NOT_EXST
	LD		L,A
	POP		AF
	LD		(DE),A
	POP		BC
	POP		DE
	LD		A,L
	SCF
	RET

L_DIR_NOT_EXST
	POP		AF
	LD		(DE),A
	INC		DE
	AND		A
	JR		Z,L_SPC_END
	CP		' '
	JR		NZ,FIND_SPEC

L_SPC_END
	POP		BC
	POP		DE
	XOR		A
	RET

; ----------------------------------------------------
; Main code Variables and Constants
; ----------------------------------------------------

; Local header parameters from zip file storage
LH_PARAMS:
LH_METHOD:
	DW	0
LH_MTIME:					
	DW	0
LH_DATE:				
	DW	0
LH_CRC32:
	DW  0,0
LH_COMP_SIZE_L:
	DW	0
LH_COMP_SIZE_H:
	DW	0
LH_UCOMP_SIZE_L:		
	DW	0
LH_UCOMP_SIZE_H:		
	DW	0

MSG_START
	DB  "UNZIP utility for Sprinter v0.8.beta1\r\n"
	DB  "Created by Aleksey Gavrilenko 09.02.2002\r\n"
	DB  "Procedure deflate by Michail Kondratyev\r\n"
	DB  "Patched by Romych at 20.06.2024 for DSS v1.70+ support.\r\n\r\n", 0

MSG_USAGE
	DB  "Usage:\r\n unzip.exe <filepath.zip> [<out_dir>]\r\n\r\n",0

MSG_INP_PATH:
	DB	"Input path:", 0

MSG_OUT_PATH:
	DB	"Out path:", 0

MSG_EOL
	DB "\r\n", 0

MSG_DEPAC_COMPLT:
	DB	"\r\nUnpacking complited\r\n\n",0

MSG_DEPAC_FILE:
	DB	"Unpacking file: ", 0

MSG_ERR_CRC:
	DB	"  Error CRC!", 0

MSG_OK_CR_LF
	DB "  OK", 0

MSG_FILE_EXISTS:
	DB	"  File exists!", 0

MSG_RESERVD_METHOD:
	DB	"  Reserved metod!", 0

MSG_INFLATING
	DB  "Inflanting: ", 0

MSG_TOKENIZING
	DB	"Tokenizing: ", 0

MSG_IMPLODING
	DB	"Imploding:  ", 0

MSG_REDUCED
	DB	"Reduced:    ", 0

MSG_UNSHRINK
	DB	"Unshrinkin: ", 0

MSG_STORED
	DB	"Stored:     ", 0

MSG_UNKNOWN
	DB	"Unknown:    ", 0					

MSG_WRONG_DEV
	DB	"Wrong device!\r\n", 0

MSG_FILE_NOT_FND
	DB	"File not found!\r\n", 0

MSG_WRONG_PATH
	DB	"Wrong path!\r\n", 0

MSG_FWRONG_FM
	DB	"Wrong file manipulator!\r\n", 0

MSG_NO_SPACE_FM
	DB	"No space for file manipulator!\r\n", 0

MSG_FILE_EXISTS2
	DB	"File exist!\r\n", 0

MSG_RDONLY
	DB	"File read only!\r\n", 0

MSG_ERR_ROOT
	DB	"Root overflow!\r\n", 0

MSG_NO_SPACE
	DB	"Not free space!\r\n", 0

MSG_PATH_EXISTS
	DB	"Path exists!\r\n", 0

MSG_WRONG_NAME
	DB	"Invalid filename!\r\n", 0

MSG_FATAL_ERR
	DB	"Fatal error!\r\n", 0

MSG_ERR_IN_ZIP
	DB	"\r\nError in ZIP!\r\n", 0

MSG_BAD_TABLE
	DB	"  File has bad table!", 0

; RAM page for decompression needsFindFi
WORK_P0
	DB	0Ah
; To save memory PAGE0 state
SAVE_P0
	DB	0
; File handler for input file
FH_INP
	DB	0
; File handler for output file
FH_OUT
	DB	0
; First parameter: Path to file
PATH_INPUT
	DS 256, 0											

; Second parameter: Path to .zip file
PATH_OUTPUT
	DS 256, 0											

; Work buffer for FindFist/FindNext op (256bytes)
FF_WORK_BUF
	DS 33,0

FF_FILE_NAME
	DS 223, 0

; Output file name from zip local header
ENTRY_FILE_NAME
	DS 256, 0

FILE_SPEC
	DS 13, 0

CRC32_L
	DW	0

CRC32_H
	DW	0

DW_COUNTER_L
	DW	0

DW_COUNTER_H
	DW	0


; ----------------------------------------------------
; End Main code Variables and Constants
; ----------------------------------------------------

; ----------------------------------------------------
; Load BC Bytes to (HL) from input file
; ----------------------------------------------------
LOAD_DATA_BLK
	PUSH	BC
	POP		DE
	PUSH	HL
BYTES_REMAINS_H+*	LD	IX,0x0
BYTES_REMAINS_L+*	LD	HL,0x0
	LD		A,IXH
	OR		IXL
	JR		NZ,L_IX_N0
	PUSH	HL
	SBC		HL,DE
	POP		HL
	JR		NC,L_IX_N0
	LD		E,L
	LD		D,H
L_IX_N0
	OR		A
	SBC		HL,DE
	JR		NC,LD_NXT_BLK
	DEC		IX
LD_NXT_BLK
	LD		(BYTES_REMAINS_H),IX
	LD		(BYTES_REMAINS_L),HL
	LD		A,D
	OR		E
	POP		HL
	RET		Z
	LD		A,(SAVE_P0)									; Restore Page0 before DSS call
	OUT		(PAGE0),A
	LD		C,DSS_READ_FILE
	LD		A,(FH_INP)
	RST		DSS
	JP		C,ERR_FILE_OP
	DI
	LD		A,(WORK_P0)									; Restore our work Page0 
	OUT		(PAGE0),A
	RET

; ----------------------------------------------------
FL_DECOMP
	LD		A,(LH_PARAMS)
	AND		A
	JP		NZ,DECOMPRESS
	; file stored without compression
DC_NEXT_BLK
	LD		HL,PAGE1_ADDR
	LD		BC,16384									; BC - bytes to read
	CALL	UC_READ
	LD		A,D											; DE - bytes readed
	OR		E
	RET		Z
	LD		HL,PAGE1_ADDR
	LD		B,D
	LD		C,E
	PUSH	DE
	CALL	UPD_CRC
	POP		DE
	LD		HL,PAGE1_ADDR
	; A - File handle; HL - buffer; DE - count
	LD		C,DSS_WRITE
	LD		A,(FH_OUT)
	RST		DSS
	JP		C,ERR_FILE_OP
	JR		DC_NEXT_BLK

; ----------------------------------------------------
; Read block of uncompressed data
; HL - buffer to out
; BC - count of bytes to read
; ----------------------------------------------------
UC_READ
	PUSH	BC
	POP		DE											; DE = BC
	PUSH	HL
	LD		IX,(BYTES_REMAINS_H)
	LD		HL,(BYTES_REMAINS_L)
	LD		A,IXH
	OR		IXL
	JR	NZ,RD_UNTL_END
	PUSH	HL
	SBC		HL,DE
	POP		HL
	JR		NC,RD_UNTL_END
	LD		E,L
	LD		D,H
RD_UNTL_END
	OR		A
	SBC		HL,DE
	JR		NC,RD_DE_BYTES
	DEC		IX
RD_DE_BYTES
	LD		(BYTES_REMAINS_H),IX
	LD		(BYTES_REMAINS_L),HL
	LD		A,D											; if DE != 0 -> read else ret
	OR		E
	POP		HL
	RET		Z
	; HL - адрес в памяти
	; DE - количество читаемых байт
	LD		C,DSS_READ_FILE
	LD		A,(FH_INP)
	RST		DSS
	JP		C,ERR_FILE_OP
	RET

; ----------------------------------------------------
; Handle errors with file operations
; ----------------------------------------------------
ERR_FILE_OP
	SUB		0x2
	LD		HL,MSG_WRONG_DEV							; "Wrong device!\r\n"
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_FILE_NOT_FND							; "File not found!\r\n"
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_WRONG_PATH							; "Wrong path!\r\n"
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_FWRONG_FM							; "Wrong file manipulator!\r\n"
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_NO_SPACE_FM							; "Not space for file manipulato
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_FILE_EXISTS2							; "File exist!\r\n"
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_RDONLY								; "Read only!\r\n"
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_ERR_ROOT								; "Error ROOT!\r\n"
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_NO_SPACE								; "No space!\r\n"
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_PATH_EXISTS							; "Path exists!\r\n"
	SUB		0x5
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_WRONG_NAME							; "Wrong name!\r\n"
	DEC		A
	JR		Z,ERR_MSG_AND_EXIT
	LD		HL,MSG_FATAL_ERR							; "Fatal error!\r\n"

	; Output error message to screen and exit
ERR_MSG_AND_EXIT
	LD		C,DSS_PCHARS
	RST		DSS
	LD		A,(FH_INP)
	AND		A
	JR		Z,IF_ALRDY_CL
	LD		C,DSS_CLOSE_FILE
	RST		DSS
	
	; Input file already closed
IF_ALRDY_CL
	LD		A,(FH_OUT)
	AND		A
	JR		Z,OF_ALRDY_CL
	LD		C,DSS_CLOSE_FILE
	RST		DSS
	
	; Output file already closed
OF_ALRDY_CL
	LD		BC,DSS_EXIT
	RST		DSS
	; - Terminate program
	

; ----------------------------------------------------
; Switch pages and do inflate
; ----------------------------------------------------
DECOMPRESS
	DI
	LD		(SAVE_SP),SP
	LD		A,(WORK_P0)									; = 0Ah
	OUT		(PAGE0),A
	CALL	INFLATE
	LD		A,(SAVE_P0)
	OUT		(PAGE0),A
	EI
	RET

; ----------------------------------------------------
; ZIP file has invalid data format
; ----------------------------------------------------
F_HAS_BAD_TAB
SAVE_SP+*	LD	SP,0x0
	LD		HL,(NXT_WRD_PTR)
	CALL	WRITE_BUFF
	LD		A,(SAVE_P0)
	OUT		(PAGE0),A
	EI
	LD		HL,MSG_BAD_TABLE							; "  File has bad table!"
	LD		C,DSS_PCHARS
	RST		DSS
	RET

; ----------------------------------------------------
; Inp: 	BC - count
;		HL - addr
; Out: 	DE - Next word ptr
; ----------------------------------------------------
SUB_UNCOMP_7
	LD		A,C
	OR		B
	RET		Z
NXT_WRD_PTR+*	LD	DE,0x0000

HAZ_BYTEZ
	LD		A,(HL)
	LD		(DE),A
	INC		DE
	PUSH	DE
	PUSH	HL
	LD		(NXT_WRD_PTR),DE
	LD		HL,0x8000
	OR		A
	SBC		HL,DE
	JR		Z,NO_BYTEZ
	POP		HL
	POP		DE
CONT_BYTEZ 
	CPI													; CP A,(HL) DEC BC
	JP		PE,HAZ_BYTEZ
	LD		(NXT_WRD_PTR),DE
	RET
NO_BYTEZ
	CALL	BUFF_IS_FULL
	POP		HL
	POP		DE
	LD		DE,(NXT_WRD_PTR)
	JR		CONT_BYTEZ

; ----------------------------------------------------
PUT_A_TO_BUFF
	PUSH	HL
	LD		HL,(NXT_WRD_PTR)
	LD		(HL),A
	INC		HL
	LD		(NXT_WRD_PTR),HL
	LD		A,H
	CP		80h											; < 0x8000 ?
	POP		HL
	RET		C
	
; ----------------------------------------------------
BUFF_IS_FULL
	PUSH	HL
	PUSH	DE
	PUSH	BC
	PUSH	AF
	LD		HL,(NXT_WRD_PTR)
	LD		(NXT_WRD),HL
	CALL	FLUSH_BUFF
	LD		(NXT_WRD_PTR),HL
	POP		AF
	POP		BC
	POP		DE
	POP		HL
	RET
INC_DW_COUNTER
	PUSH	HL
	PUSH	DE
	PUSH	AF
	; inc (0x8b05) if wrapped, inc hi byte
	LD		HL,(DW_COUNTER_L)
	LD		DE,0x1
	ADD		HL,DE
	LD		(DW_COUNTER_L),HL
	JR		NC,SUNK_NO_WRAP
	LD		HL,(DW_COUNTER_H)
	INC		HL
	LD		(DW_COUNTER_H),HL
SUNK_NO_WRAP
	POP		AF
	POP		DE
	POP		HL
	RET
; ----------------------------------------------------
; Load next block of compressed data to TEMP_BUFFR
; ----------------------------------------------------
LOAD_NXT_BLOCK
	PUSH	HL
	PUSH	DE
	PUSH	BC
	PUSH	IX
	LD		HL,TEMP_BUFFR
	LD		(TMP_BUFFER_ADDR),HL
	LD		BC,4095
	CALL	LOAD_DATA_BLK
	POP		IX
	POP		BC
	POP		DE
	POP		HL
	RET

; ----------------------------------------------------
; Update CRC32
; HL - ptr to byte buffer
; BC - bytes in buffer
; ----------------------------------------------------
UPD_CRC
	LD		A,B
	OR		C
	RET		Z
	PUSH	HL
	LD		HL,(CRC32_H)
	LD		DE,(CRC32_L)
CRC_NXT_BYTE
	EX		(SP),HL
	LD		A,(HL)
	INC		HL
	EX		(SP),HL
	XOR		E	
	LD		IXL,A
	LD		IXH,0x3F
	ADD		IX,IX
	ADD		IX,IX
	LD		A,D
	XOR		(IX+0x0)									; CRC32 Table ref 3F00*4=0xFC00
	LD		E,A
	LD		A,L
	XOR		(IX+0x1)
	LD		D,A
	LD		A,H
	XOR		(IX+0x2)
	LD		L,A
	LD		H,(IX+0x3)
	DEC		BC
	LD		A,C
	OR		B
	JR		NZ,CRC_NXT_BYTE
	LD		(CRC32_H),HL
	LD		(CRC32_L),DE
	POP		HL
	RET

; ----------------------------------------------------
WRITE_BUFF
	LD		A,H
	OR		L
	RET		Z											; ret if HL=0
	LD		A,H
	CP		0x40
	JR		NC,WR_4000									; bytes > 0x4000?
	EX		DE,HL
	PUSH	DE
	; Store P3, switch to out P3 and original P0
	IN		A,(PAGE3)
	PUSH	AF
	LD		A,(WORK_P0)									; =0Ah
	OUT		(PAGE3),A
	LD		A,(SAVE_P0)
	OUT		(PAGE0),A
	; Write DC bytes from (HL) to A file handler
	LD		HL,PAGE3_ADDR
	LD		C,DSS_WRITE
	LD		A,(FH_OUT)
	RST		DSS
	JP		C,ERR_FILE_OP
	; Restore P3 and our P0
	POP		AF
	OUT		(PAGE3),A
	DI
	LD		A,(WORK_P0)									; = 0Ah
	OUT		(PAGE0),A
	; Update CRC for buffer
	POP		BC
	LD		HL,0x0
	CALL	UPD_CRC
	LD		HL,0x0
	RET
WR_4000
	PUSH	HL
	; Store P3, switch to out P3 and original P0
	IN		A,(PAGE3)
	PUSH	AF
	LD		A,(WORK_P0)									; = 0Ah
	OUT		(PAGE3),A
	LD		A,(SAVE_P0)
	OUT		(PAGE0),A
	; Write DC bytes from (HL) to A file handler
	LD		DE,0x4000									; bytes to write
	LD		HL,PAGE3_ADDR
	LD		C,DSS_WRITE
	LD		A,(FH_OUT)
	RST		DSS
	JP		C,ERR_FILE_OP
	; Restore P3 and our P0
	POP		AF
	OUT		(PAGE3),A
	DI
	LD		A,(WORK_P0)									; = 0Ah
	OUT		(PAGE0),A
	POP		HL
	PUSH	HL
	; DE=HL-0x4000
	LD		DE,0x4000
	AND		A
	SBC		HL,DE
	JR		Z,NO_B_TO_WR
	EX		DE,HL
	LD		A,(SAVE_P0)
	OUT		(PAGE0),A
	; Write remains DC bytes from (HL)=0x4000
	LD		HL,0x4000
	LD		C,DSS_WRITE
	LD		A,(FH_OUT)
	RST		DSS
	JP		C,ERR_FILE_OP
	DI
	LD		A,(WORK_P0)
	OUT		(PAGE0),A
NO_B_TO_WR
	POP		BC
	LD		HL,0x0
	; Update CRC for buffer
	CALL	UPD_CRC
	LD		HL,0x0
	RET

FILL_3
	DB 0	
	ALIGN 0x2000, 0
	DB 0
	ALIGN 0x1000, 0

	;DS TEMP_BUFFR-FILL_3, 0
	ORG 0xB000
; 4096 bytes buffer AFFF-BFFF
TEMP_BUFFR  
	DS 6, 0
GPP_FLAG
	DB 0, 0
	DS 18, 0
LH_FN_LEN_L
	DB	0
LH_FN_LEN_H
	DB	0
LH_EXTRA_LEN_L
	DB	0
LH_EXTRA_LEN_H
	DB	0
LH_FILENAME
	DS  1024, 0

;PAGE3_ADDR	
	ALIGN 0x4000, 0
	ORG   0xC000

	DS  4096, 0
	DS  91,0
; ----
BUFF_2
	DS 167,0

MODE_STORED
	LD		A,B
	; ALIGN to 8 bit
	CP		0x8
	CALL	NZ,GET_RIGHT_A_BITS
	EX		DE,HL
	CALL	GET_NEXT_8B								; Get LEN_L
	LD		E,D
	CALL	GET_NEXT_8B								; Get LEN_H
	LD		A,D
	XOR		H
	LD		D,A
	LD		A,E
	XOR		L
	AND		D
	INC		A
	JP		NZ,F_HAS_BAD_TAB
	CALL	GET_NEXT_8B								; Get NLEN?
	EX		DE,HL
	; Move next DE bytes from input buffer to output
TMP_BUFFER_ADDR+* LD	HL,0x0000
	DEC		HL
DO_NXT_CHR
	LD		A,(HL)										; HL => TEMP_BUFFR
	INC		HL											; HL =>TEMP_BUFFR + 1		
	CALL	PUT_A_TO_BUFF
	PUSH	HL						
	LD		BC,0x4001
	ADD		HL,BC
	POP		HL
	JR		NC,NO_WRAP
	CALL	LOAD_NXT_BLOCK
	LD		HL,TEMP_BUFFR
NO_WRAP
	DEC		DE
	LD		A,D
	OR		E
	JR		NZ,DO_NXT_CHR
	LD		(TMP_BUFFER_ADDR),HL
	POP		DE
	JR		DO_NEXT_BLOCK

; ----------------------------------------------------
INFLATE
	XOR		A
	LD		(ZIP_EOF),A
	CALL	LOAD_NXT_BLOCK
	LD		HL,0x0
	LD		(NXT_WRD_PTR),HL

DO_NEXT_BLOCK
	LD		HL,(TMP_BUFFER_ADDR)
	LD		E,(HL)
	INC		HL
	LD		(TMP_BUFFER_ADDR),HL
	CALL	GET_NEXT_8B									; DE = next 16 bit from inp; b=8
DO_NEXT_BLK
ZIP_EOF+*	LD	A,0x0									; 0Ah - work mem blk in page0
	OR		A
	JR		NZ,ZIP_END									; non zero last blk
	CALL	DE_DIV_2_Bm1								; DE>>1; B-- E0 -> CY
	LD		HL,ZIP_EOF
	RR		(HL)										; CY -> 7bit
	CALL	READ_HUFF_BLOCK
SU_L2
	CALL	NEXT_SYM
	LD		A,H
	OR		A
	JR		NZ,SU_L3
	LD		A,L
	CALL	PUT_A_TO_BUFF
	JR		SU_L2
SU_L3
	DEC		A
	OR		L
	JR		Z,DO_NEXT_BLK
	DEC		H
	INC		HL
	INC		HL
	PUSH	HL											; HL => BUFF_2
	CALL	SUB_UNCOMP_6
	INC		HL
	POP		AF
	PUSH	BC
	PUSH	DE
	PUSH	AF
	POP		BC
	EX		DE,HL
	LD		HL,(NXT_WRD_PTR)
	OR		A
	SBC		HL,DE
	JR		NC,SU_L6
	EX		DE,HL
	LD		HL,0x0
	OR		A
	SBC		HL,DE
	PUSH	HL											; HL => BUFF_2 + 1
NXT_WRD+*	LD	HL,0x0
	ADD		HL,DE
	POP		DE
	EX		DE,HL
	PUSH	HL											; HL => BUFF_2 + 1
	CP		A
	SBC		HL,BC
	POP		HL
	EX		DE,HL
	JR		NC,SU_L6
	EX		DE,HL
	PUSH	BC											; BC => BUFF_2
	EX		(SP),HL
	POP		BC
	AND		A
	SBC		HL,BC
	PUSH	HL
	EX		DE,HL
	CALL	SUB_UNCOMP_7
	LD		HL,0x0000
	POP		BC
SU_L6
	CALL	SUB_UNCOMP_7
	LD		A,(NXT_WRD_PTR+1) ;+1!
	CP		0x80
	CALL	NC,BUFF_IS_FULL
	POP		DE
	POP		BC
	JR		SU_L2
ZIP_END
	LD		HL,(NXT_WRD_PTR)

; ----------------------------------------------------
FLUSH_BUFF
	LD		DE,0x0000
	JP		WRITE_BUFF

; ----------------------------------------------------
; Data definitions  block for LZ77
; ----------------------------------------------------
FILL_1
	DS 33, 0

; Code Lengths Order
CL_ORDER
	DB	16, 17, 18, 0, 8, 7, 9, 6
	DB	10, 5, 11, 4, 12, 3, 13, 2
	DB	14,	1, 15

	ORG 0xD201

EXTRA_BITS
	DB	1, 3, 7, 15, 31, 63, 127, 255					; 2^n-1

BL_CNT
	DS 34,0
BL_CNT_17
	DW 0	
BL_CNT_18
	DS 34,0
; ----------------------------------------------------
; Return A number of bits in HL from block
; ----------------------------------------------------
HL_GET_A_BITS
	CP		0x9
	JR		C,HL_LESS_8B
	SUB		0x8
	LD		H,A
	LD		A,0x8
	CALL	READ_A_BITS
	LD		L,A
	LD		A,H
	CALL	READ_A_BITS
	LD		H,A
	RET
HL_LESS_8B
	CALL	READ_A_BITS
	LD		H,0x0
	LD		L,A
	RET
	
; ----------------------------------------------------
; Return A number of bits
; ----------------------------------------------------
READ_A_BITS
	LD		(XTRA_BITS_OFFS),A
	EX		AF,AF'
XTRA_BITS_OFFS+*	LD	A,(EXTRA_BITS)					; = 3
	AND		E
	PUSH	AF
	EX		AF,AF'
	CALL	GET_RIGHT_A_BITS
	POP		AF
	RET

; ----------------------------------------------------
; DE/2, B--
; ----------------------------------------------------
DE_DIV_2_Bm1
	SRL		D
	RR		E											; E[0] -> CY
	DEC		B
	RET		NZ

; ----------------------------------------------------
; Get next 8 bits from buffer 
; Out: D - next 8 bit from block
; 	   B = 8
; ----------------------------------------------------
GET_NEXT_8B
	PUSH	AF
	PUSH	HL
	PUSH	BC
	LD		HL,(TMP_BUFFER_ADDR)
	LD		BC,0x4001
	ADD		HL,BC
	POP		BC
	CALL	C,LOAD_NXT_BLOCK
	LD		HL,(TMP_BUFFER_ADDR)
	LD		D,(HL)
	INC		HL
	LD		(TMP_BUFFER_ADDR),HL
	LD		B,0x8
	POP		HL
	POP		AF
	RET

; ----------------------------------------------------
; Get number of bits (rigth shift)
; Inp: A - bits to get, B - bits remains
; Out: DE
; ----------------------------------------------------
GET_RIGHT_A_BITS
	CP		B
	JR		C,SHF_RT_DE2
SHF_RT_DE1
	SRL		D
	RR		E
	DEC		A
	DJNZ	SHF_RT_DE1
	CALL	GET_NEXT_8B
SHF_RT_DE2
	OR		A
	RET		Z
	SRL		D
	RR		E
	DEC		A
	DJNZ	SHF_RT_DE2									; TODO: No RET?

MODE_ST_HUFF
	PUSH	BC
	PUSH	DE
	; Init literal/length table
	LD		HL,LEN_LD					
	LD		BC,0x9008									;144 8 bit, from 00110000 to 101
INI_LEN1										
	LD	(HL),C
	INC	HL
	DJNZ	INI_LEN1
	LD		BC,0x7009									;122 9 bit, from 110010000 to 11
INI_LEN2										
	LD		(HL),C
	INC		HL
	DJNZ	INI_LEN2
	LD		BC,0x1807									;24 7 bit, from 0000000 to 0010111
INI_LEN3										
	LD		(HL),C
	INC		HL
	DJNZ	INI_LEN3
	LD		BC,0x808									;8 8 bit, from 11000000 to 11000
INI_LEN4										
	LD		(HL),C
	INC		HL
	DJNZ	INI_LEN4
	LD		HL,DISTANCES
	LD		BC,0x2005									; 32
	LD		A,B
INI_DISTANCES								
	LD		(HL),C
	INC		HL
	DJNZ	INI_DISTANCES
	LD		(HDIST),A
	LD		(HLIT),A
	JP		LOAD_LIT_DIST
;

READ_HUFF_BLOCK
	LD		A,0x2
	CALL	READ_A_BITS									; Get block compression mode
	DEC		A
	JP		M,MODE_STORED
	JR		Z,MODE_ST_HUFF
	DEC		A
	JP		NZ,F_HAS_BAD_TAB							; MODE 11 - reserved
	LD		A,0x5										; Get HLIT
	CALL	READ_A_BITS
	INC		A											; +1
	LD		(HLIT),A								    ; +0x0100
	LD		A,0x5										; Get HDIST
	CALL	READ_A_BITS
	INC		A
	LD		(HDIST),A
	LD		HL,LIT_TR
	LD		A,NR_CL
CLR_LIT_TR
	LD		(HL),0x0									; HL => LIT_TR
	INC		HL
	DEC		A
	JR		NZ,CLR_LIT_TR
	; Read HCLEN (4bit)
	LD		A,0x4
	CALL	READ_A_BITS
	ADD		A,0x4										; number of Code Length codes  (4 - 19)
	LD		C,A
	LD		HL,CL_ORDER

; (HCLEN + 4) x 3 bits: code lengths for the code length
; alphabet given just above, in the order: 16, 17, 18 ...
GET_NXT_CL
	LD		A,0x3
	CALL	READ_A_BITS
	PUSH	DE
	LD		E,(HL)										; HL => CL_ORDER
	LD		D,0x0
	PUSH	HL
	LD		HL,LIT_TR
	ADD		HL,DE										
	LD		(HL),A										; reorder code lengths alphabet in straigth order
	POP		HL
	POP		DE
	INC		HL
	DEC		C
	JR		NZ,GET_NXT_CL
	PUSH	BC
	PUSH	DE
	LD		HL,CL_TR
	LD		DE,LIT_TR
	LD		BC,NR_CL						
	CALL	BUILD_CODE									; build huffman codes for codelength
	LD		HL,(HLIT)
	LD		DE,(HDIST)
	ADD		HL,DE
	DEC		HL
	POP		DE
	POP		BC
	LD		IX,LEN_LD
MN_CN2
	PUSH	HL
	PUSH	DE
	LD		D,0x0
	LD		HL,CL_TR
	ADD		HL,DE
	ADD		HL,DE
	LD		E,(HL)
	LD		HL,LIT_TR
	ADD		HL,DE
	LD		A,(HL)										; HL => LIT_TR
	LD		C,E
	POP		DE
	CALL	GET_RIGHT_A_BITS
	LD		A,C
	POP		HL
	CP		0x10										; 
	JR		NC,CL_16									; >= Next bytes - length
	LD		C,A											; len 1
	LD		A,0x1
	JR		CL_CMPL
CL_16
	JR		NZ,CL_17
	; 16: Copy the previous code length 3 - 6 times. (2 bits length 0 = 3, ... , 3 = 6)
	LD		A,0x2
	CALL	READ_A_BITS
	ADD		A,3
	LD		C,(IX-0x1)									; => BYTE_ram_d619
	JR		CL_CMPL
CL_17
	CP		0x11
	JR		NZ,CL_18
	; Repeat a code length of 0 for 3 - 10 times. (3 bits of length)
	LD		A,3
	CALL	READ_A_BITS
	ADD		A,3
	JR		CL_END
CL_18
	; Repeat a code length of 0 for 11 - 138 times (7 bits of length)
	LD		A,7
	CALL	READ_A_BITS
	ADD		A,11
CL_END
	LD		C,0x0
CL_CMPL
	LD		(IX+0x0),C									; => LEN_LD
	INC		IX
	DEC		A											; A = rpt cnt - 1
	DEC		HL
	JR		Z,CL_HL_0
	BIT		0x7,H
	JP		NZ,F_HAS_BAD_TAB
	JR		CL_CMPL
CL_HL_0
	BIT		0x7,H
	JR		Z,MN_CN2
	PUSH	BC
	PUSH	DE
	LD		HL,LEN_LD
	LD		DE,(HLIT)
	ADD		HL,DE
	LD		DE,DISTANCES
	LD		BC,(HDIST)
	LDIR

; ------------------------------------------------------
; Load literal/length and distance alphabets
; ------------------------------------------------------
LOAD_LIT_DIST
; Load HLIT + 257 code lengths for the literal/length alphabet 
HLIT+*	LD	BC,0x0100									; Count of literals and lengths (+257)
	LD		DE,LEN_LD
	LD		HL,CL_TR
	LD		IX,LIT_TR
	CALL	BUILD_CODE

; Load HDIST + 1 code lengths for the distance alphabet,
HDIST+*	LD	BC,0x0
	LD		DE,DISTANCES
	LD		HL,N_CODE
	LD		IX,DIST_TR
	CALL	BUILD_CODE
	POP		DE
	POP		BC
	RET

; ------------------------------------------------------
; Build huffman codes by coldee lengths
;	In: HL - Pointer to dest huffman tree
;		DE - Pointer to code lenthts table 
;		BC - Length of code lengths table
; ------------------------------------------------------
BUILD_CODE
	LD		A,B
	OR		C
	RET		Z											; ret if no literals
	LD		(NR_SYM),BC
	LD		(LEN_PTR),HL								; HL -> CL_TR
	LD		HL,BL_CNT
	PUSH	HL												
	PUSH	BC
	LD		BC,0x2000									; ToDo: may be 0x2600?

	; BL_CNT[32]=0
BL_CNT_0
	LD		(HL),C											
	INC		HL
	DJNZ	BL_CNT_0
	POP		BC
	POP		HL											; HL -> BL_CNT
	PUSH	DE	

BC_LP_1
	LD		A,(DE)										; DE -> LIT_TR
	INC		DE
	ADD		A,A
	ADD		A,low(BL_CNT)								; len*2 + offset
	LD		L,A
	INC		(HL)
	JR		NZ,BC_NO_L
	INC		HL
	INC		(HL)

BC_NO_L
	DEC		BC
	LD		A,B
	OR		C
	JR		NZ,BC_LP_1

	LD		L,low(BL_CNT_18)							; 45
	LD		(HL),C
	INC		HL
	LD		(HL),C
	PUSH	BC
	LD		BC,0x0f02			
	
INIT_BUFF4
	LD		A,C
	ADD		A,low(BL_CNT)
	LD		L,A
	LD		E,(HL)
	INC		HL
	LD		D,(HL)
	EX		(SP),HL
	ADD		HL,DE
	ADD		HL,HL
	LD		E,L
	LD		D,H
	EX		(SP),HL
	INC		C
	INC		C
	LD		A,C
	ADD		A,low(BL_CNT_17)							; 43
	LD		L,A
	LD		(HL),E
	INC		HL
	LD		(HL),D
	DJNZ	INIT_BUFF4
	POP		DE
	LD		A,D
	OR		E
	JR		Z,CHAR_L_NE0
	LD		D,B
	LD		E,B
	LD		A,15
	LD		L,low(BL_CNT)+2
	
INIT_BUFF5
	LD		C,(HL)
	INC		HL
	LD		B,(HL)
	INC		HL
	EX		DE,HL
	ADD		HL,BC
	EX		DE,HL
	DEC		A
	JR		NZ,INIT_BUFF5
	LD		HL,0xfffe									; END_OF_CODE?
	ADD		HL,DE
	JP		C,F_HAS_BAD_TAB

CHAR_L_NE0
	POP	DE
	PUSH	DE
NR_SYM+*	LD	BC,0x0
	LD		HL,NODES
INIT_BUFF6
	LD		A,(DE)										; DE => LIT_TR + offset
	INC		DE
	PUSH	DE
	ADD		A,A
	LD		E,A
	LD		D,A
	JR		Z,CHAR_L_E0
	PUSH	HL
	LD		H,high BL_CNT								; 0xD2
	ADD		A,low BL_CNT_17								; +43
	LD		L,A
	LD		E,(HL)
	INC		HL
	LD		D,(HL)
	INC		DE
	LD		(HL),D
	DEC		HL
	LD		(HL),E
	DEC		DE
	POP		HL
CHAR_L_E0
	LD		(HL),E										; => NODES
	INC		HL
	LD		(HL),D										; => NODES+1
	INC		HL
	POP		DE
	DEC		BC
	LD		A,C
	OR		B
	JR		NZ,INIT_BUFF6
	POP		DE
	PUSH	DE
	LD		HL,NODES
	LD		BC,(NR_SYM)
INIT_BUFF7
	LD		A,(DE)										; DE => LIT_TR+offset
	INC		DE
	DEC		A
	JP		M,INIT_BUFF11								; code=0 or 1
	JR		Z,INIT_BUFF11
	PUSH	DE
	LD		E,(HL)										; HL => NODES + offset
	INC		HL
	LD		D,(HL)										; DE = [NODES + offset]
    PUSH	HL
    LD		HL,0x0
INIT_BUFF8
	SRL		D											; DE >> 1
	RR		E
	ADC		HL,HL
	EX		AF,AF'
	LD		A,D
	OR		E
	JR		Z,INIT_BUFF9
	EX		AF,AF'
	DEC		A
	JR		NZ,INIT_BUFF8
	INC		A
	EX		AF,AF'
INIT_BUFF9
	EX		AF,AF'
	RR		E
INIT_BUFF10
	ADC		HL,HL
	DEC		A
	JR		NZ,INIT_BUFF10
	EX		DE,HL
	POP		HL
	LD		(HL),D										; => NODES_1
	DEC		HL
	LD		(HL),E										; => NODES
	POP		DE
INIT_BUFF11
	INC		HL
	INC		HL
	DEC		BC
	LD		A,C
	OR		B
	JR		NZ,INIT_BUFF7

LEN_PTR+*	LD	HL,0x0000								; HL => CL_TR
	LD		E,L
	LD		D,H
	INC		DE
	LD		BC,511
	LD		(HL),A
	LDIR												; Shift CL_TR or LEN_TR  right 1 byte
	POP		HL
	LD		BC,(NR_SYM)
	DEC		BC
	ADD		HL,BC
	EX		DE,HL
	//;+++
	LD		(TR_PTR),IX									; LIT_TR or DIST_TR addr
	LD		HL,NODES+1
	ADD		HL,BC
	ADD		HL,BC
INIT_BUFF12
	LD		A,(DE)
	DEC		DE
	OR		A
	JR		Z,INIT_BUFF16
	CP		0x9
	PUSH	DE
	LD		D,(HL)										; => NODES + offset
	DEC		HL
	LD		E,(HL)
	INC		HL
	PUSH	HL
	JR		NC,INIT_BUFF17
	LD		HL,0x1
	INC		A
INIT_BUFF13
	ADD		HL,HL
	DEC		A
	JR		NZ,INIT_BUFF13
	EX		DE,HL
	ADD		HL,HL
	LD		A,(LEN_PTR)
	ADD		A,L
	LD		L,A
	LD		(IB14_L2+1),A
	LD		A,(LEN_PTR+1)
	ADC		A,H
	LD		H,A
	INC		A
	INC		A
	LD		(IB14_L1+1),A
	DEC		DE
INIT_BUFF14
	LD		(HL),C
	INC		HL
	LD		(HL),B
	ADD		HL,DE
	LD		A,H
IB14_L1
	CP		0x0
	JR		C,INIT_BUFF14
	JR		NZ,INIT_BUFF15
	LD		A,L
IB14_L2
	CP		0x0
	JR		C,INIT_BUFF14
INIT_BUFF15
	POP		HL
	POP		DE
INIT_BUFF16
	DEC		HL
	DEC		HL
	DEC		BC
	BIT		0x7,B
	JR		Z,INIT_BUFF12
	RET
INIT_BUFF17
	SUB		0x8
	PUSH	BC
	LD		B,A
	LD		A,D
	LD		D,0x0
	LD		HL,(LEN_PTR)
	ADD		HL,DE
	ADD		HL,DE
	LD		C,0x1
	EX		AF,AF'
INIT_BUFF18
	LD		E,(HL)
	INC		HL
	LD		D,(HL)
	DEC		HL
	LD		A,D
	OR		E
	JR		NZ,INIT_BUFF19								; (word)(HL) != 0?
TR_PTR+*	LD	DE,0x0
	LD		(HL),E
	INC		HL
	LD		(HL),D
	LD		H,D
	LD		L,E
	LD		(HL),A
	INC		HL
	LD		(HL),A
	INC		HL
	LD		(HL),A
	INC		HL
	LD		(HL),A
	INC		HL
	LD		(TR_PTR),HL
INIT_BUFF19
	EX		DE,HL
	EX		AF,AF'
	LD		E,A
	AND		C
	LD		A,E
	JR		Z,INIT_BUFF20
	INC		HL
	INC		HL
INIT_BUFF20
	EX		AF,AF'
	SLA		C
	DJNZ	INIT_BUFF18
	POP		BC
	LD		(HL),C
	INC		HL
	LD		(HL),B
	JR		INIT_BUFF15

; --- Unparsed -------------
; ----------------------------------------------------
NEXT_SYM
	PUSH	DE
	XOR		A
	LD		D,A
	LD		HL,CL_TR+1									; Code length
	ADD		HL,DE
	ADD		HL,DE										; HL = HL + 2*E
	OR		(HL)
	DEC		HL
	LD		L,(HL)
	LD		H,A											; HL = (HL)
	JP		M,LB_A_B7_1									; A<0? bit 7 = 1
	PUSH	HL
	LD		DE,LEN_LD
	ADD		HL,DE
	LD		A,(HL)										; A - next bit count
	POP		HL
	POP		DE
DO_NXT_BITS
	CALL	GET_RIGHT_A_BITS
	LD		A,H
	OR		A
	RET		Z
	LD		A,L
	CP		0x9
	RET		C
	CP		29											; 0x1D
	LD		HL,0x200
	RET		Z
	DEC		A
	LD		C,A
	SRL		C
	SRL		C
	DEC		C
	AND		0x3
	ADD		A,0x4
	LD		H,L
	LD		L,A
	LD		A,C
DO_DBL_HL_C
	ADD		HL,HL
	DEC		C
	JR		NZ,DO_DBL_HL_C
	INC		H
	CALL	READ_A_BITS
	INC		A
	ADD		A,L
	LD		L,A
	RET		NC
	INC		H
	RET
LB_A_B7_1
	POP		DE
	CALL	SUB_ram_d5cb
	JR		DO_NXT_BITS
	
; ----------------------------------------------------
SUB_UNCOMP_6
	PUSH	DE
	XOR		A
	LD		D,A
	LD		HL,N_CODE+1
	ADD		HL,DE
	ADD		HL,DE
	OR		(HL)
	DEC		HL
	LD		L,(HL)
	LD		H,A
	JP		M,L_HLM
	PUSH	HL
	LD		DE,DISTANCES
	ADD		HL,DE
	LD		A,(HL)										; HL => DISTANCES
	POP		HL
	POP		DE
LAB_ram_d5a9
	CALL	GET_RIGHT_A_BITS
	LD		A,L
	CP		0x4
	RET		C
	RRA
	DEC		A
	LD		C,A
	LD		L,H
	RL		L
	INC		L
	INC		L
HL_SL_C
	ADD		HL,HL										; HL << C
	DEC		C
	JR		NZ,HL_SL_C
	PUSH	HL
	CALL	HL_GET_A_BITS
	EX		DE,HL
	EX		(SP),HL
	ADD		HL,DE
	POP		DE
	RET
L_HLM
	POP		DE
	CALL	SUB_ram_d5cb
	JR		LAB_ram_d5a9
	
; ----------------------------------------------------
SUB_ram_d5cb
	LD		A,0x8
	CALL	GET_RIGHT_A_BITS
	LD		C,E
	XOR		A
HI_W_BIT1
	INC		A
	RR		C
	JR		NC,LD_NXT_A
	INC		HL
	INC		HL
LD_NXT_A
	LD		(LD_NXT_W),HL
LD_NXT_W+*	LD	HL,(0x0000)
	BIT		0x7,H
	JR		NZ,HI_W_BIT1
	RET

; ----------------------------------------------------

FILL_2
	DS 53, 0

BYTE_ram_d619
	DB 0

LEN_LD
	DS NR_LIT + NR_DIST, 0

DISTANCES
	DS 32,0

; 
CL_TR
	DS 512,0
	
N_CODE
	DS 512,0

; Command codes lengths
LIT_TR
	DS 4 * NR_LIT, 0

DIST_TR
	DS 4 * NR_DIST,0

NODES
	DS 2 * MAX_CL + 2
	DS 7012,0

CRC32_TAB
	DB 0x00, 0x00, 0x00, 0x00, 0x96, 0x30, 0x07, 0x77, 0x2C, 0x61, 0x0E, 0xEE, 0xBA, 0x51, 0x09, 0x99
	DB 0x19, 0xC4, 0x6D, 0x07, 0x8F, 0xF4, 0x6A, 0x70, 0x35, 0xA5, 0x63, 0xE9, 0xA3, 0x95, 0x64, 0x9E
	DB 0x32, 0x88, 0xDB, 0x0E, 0xA4, 0xB8, 0xDC, 0x79, 0x1E, 0xE9, 0xD5, 0xE0, 0x88, 0xD9, 0xD2, 0x97
	DB 0x2B, 0x4C, 0xB6, 0x09, 0xBD, 0x7C, 0xB1, 0x7E, 0x07, 0x2D, 0xB8, 0xE7, 0x91, 0x1D, 0xBF, 0x90
	DB 0x64, 0x10, 0xB7, 0x1D, 0xF2, 0x20, 0xB0, 0x6A, 0x48, 0x71, 0xB9, 0xF3, 0xDE, 0x41, 0xBE, 0x84
	DB 0x7D, 0xD4, 0xDA, 0x1A, 0xEB, 0xE4, 0xDD, 0x6D, 0x51, 0xB5, 0xD4, 0xF4, 0xC7, 0x85, 0xD3, 0x83
	DB 0x56, 0x98, 0x6C, 0x13, 0xC0, 0xA8, 0x6B, 0x64, 0x7A, 0xF9, 0x62, 0xFD, 0xEC, 0xC9, 0x65, 0x8A
	DB 0x4F, 0x5C, 0x01, 0x14, 0xD9, 0x6C, 0x06, 0x63, 0x63, 0x3D, 0x0F, 0xFA, 0xF5, 0x0D, 0x08, 0x8D
	DB 0xC8, 0x20, 0x6E, 0x3B, 0x5E, 0x10, 0x69, 0x4C, 0xE4, 0x41, 0x60, 0xD5, 0x72, 0x71, 0x67, 0xA2
	DB 0xD1, 0xE4, 0x03, 0x3C, 0x47, 0xD4, 0x04, 0x4B, 0xFD, 0x85, 0x0D, 0xD2, 0x6B, 0xB5, 0x0A, 0xA5
	DB 0xFA, 0xA8, 0xB5, 0x35, 0x6C, 0x98, 0xB2, 0x42, 0xD6, 0xC9, 0xBB, 0xDB, 0x40, 0xF9, 0xBC, 0xAC
	DB 0xE3, 0x6C, 0xD8, 0x32, 0x75, 0x5C, 0xDF, 0x45, 0xCF, 0x0D, 0xD6, 0xDC, 0x59, 0x3D, 0xD1, 0xAB
	DB 0xAC, 0x30, 0xD9, 0x26, 0x3A, 0x00, 0xDE, 0x51, 0x80, 0x51, 0xD7, 0xC8, 0x16, 0x61, 0xD0, 0xBF
	DB 0xB5, 0xF4, 0xB4, 0x21, 0x23, 0xC4, 0xB3, 0x56, 0x99, 0x95, 0xBA, 0xCF, 0x0F, 0xA5, 0xBD, 0xB8
	DB 0x9E, 0xB8, 0x02, 0x28, 0x08, 0x88, 0x05, 0x5F, 0xB2, 0xD9, 0x0C, 0xC6, 0x24, 0xE9, 0x0B, 0xB1
	DB 0x87, 0x7C, 0x6F, 0x2F, 0x11, 0x4C, 0x68, 0x58, 0xAB, 0x1D, 0x61, 0xC1, 0x3D, 0x2D, 0x66, 0xB6
	DB 0x90, 0x41, 0xDC, 0x76, 0x06, 0x71, 0xDB, 0x01, 0xBC, 0x20, 0xD2, 0x98, 0x2A, 0x10, 0xD5, 0xEF
	DB 0x89, 0x85, 0xB1, 0x71, 0x1F, 0xB5, 0xB6, 0x06, 0xA5, 0xE4, 0xBF, 0x9F, 0x33, 0xD4, 0xB8, 0xE8
	DB 0xA2, 0xC9, 0x07, 0x78, 0x34, 0xF9, 0x00, 0x0F, 0x8E, 0xA8, 0x09, 0x96, 0x18, 0x98, 0x0E, 0xE1
	DB 0xBB, 0x0D, 0x6A, 0x7F, 0x2D, 0x3D, 0x6D, 0x08, 0x97, 0x6C, 0x64, 0x91, 0x01, 0x5C, 0x63, 0xE6
	DB 0xF4, 0x51, 0x6B, 0x6B, 0x62, 0x61, 0x6C, 0x1C, 0xD8, 0x30, 0x65, 0x85, 0x4E, 0x00, 0x62, 0xF2
	DB 0xED, 0x95, 0x06, 0x6C, 0x7B, 0xA5, 0x01, 0x1B, 0xC1, 0xF4, 0x08, 0x82, 0x57, 0xC4, 0x0F, 0xF5
	DB 0xC6, 0xD9, 0xB0, 0x65, 0x50, 0xE9, 0xB7, 0x12, 0xEA, 0xB8, 0xBE, 0x8B, 0x7C, 0x88, 0xB9, 0xFC
	DB 0xDF, 0x1D, 0xDD, 0x62, 0x49, 0x2D, 0xDA, 0x15, 0xF3, 0x7C, 0xD3, 0x8C, 0x65, 0x4C, 0xD4, 0xFB
	DB 0x58, 0x61, 0xB2, 0x4D, 0xCE, 0x51, 0xB5, 0x3A, 0x74, 0x00, 0xBC, 0xA3, 0xE2, 0x30, 0xBB, 0xD4
	DB 0x41, 0xA5, 0xDF, 0x4A, 0xD7, 0x95, 0xD8, 0x3D, 0x6D, 0xC4, 0xD1, 0xA4, 0xFB, 0xF4, 0xD6, 0xD3
	DB 0x6A, 0xE9, 0x69, 0x43, 0xFC, 0xD9, 0x6E, 0x34, 0x46, 0x88, 0x67, 0xAD, 0xD0, 0xB8, 0x60, 0xDA
	DB 0x73, 0x2D, 0x04, 0x44, 0xE5, 0x1D, 0x03, 0x33, 0x5F, 0x4C, 0x0A, 0xAA, 0xC9, 0x7C, 0x0D, 0xDD
	DB 0x3C, 0x71, 0x05, 0x50, 0xAA, 0x41, 0x02, 0x27, 0x10, 0x10, 0x0B, 0xBE, 0x86, 0x20, 0x0C, 0xC9
	DB 0x25, 0xB5, 0x68, 0x57, 0xB3, 0x85, 0x6F, 0x20, 0x09, 0xD4, 0x66, 0xB9, 0x9F, 0xE4, 0x61, 0xCE
	DB 0x0E, 0xF9, 0xDE, 0x5E, 0x98, 0xC9, 0xD9, 0x29, 0x22, 0x98, 0xD0, 0xB0, 0xB4, 0xA8, 0xD7, 0xC7
	DB 0x17, 0x3D, 0xB3, 0x59, 0x81, 0x0D, 0xB4, 0x2E, 0x3B, 0x5C, 0xBD, 0xB7, 0xAD, 0x6C, 0xBA, 0xC0
	DB 0x20, 0x83, 0xB8, 0xED, 0xB6, 0xB3, 0xBF, 0x9A, 0x0C, 0xE2, 0xB6, 0x03, 0x9A, 0xD2, 0xB1, 0x74
	DB 0x39, 0x47, 0xD5, 0xEA, 0xAF, 0x77, 0xD2, 0x9D, 0x15, 0x26, 0xDB, 0x04, 0x83, 0x16, 0xDC, 0x73
	DB 0x12, 0x0B, 0x63, 0xE3, 0x84, 0x3B, 0x64, 0x94, 0x3E, 0x6A, 0x6D, 0x0D, 0xA8, 0x5A, 0x6A, 0x7A
	DB 0x0B, 0xCF, 0x0E, 0xE4, 0x9D, 0xFF, 0x09, 0x93, 0x27, 0xAE, 0x00, 0x0A, 0xB1, 0x9E, 0x07, 0x7D
	DB 0x44, 0x93, 0x0F, 0xF0, 0xD2, 0xA3, 0x08, 0x87, 0x68, 0xF2, 0x01, 0x1E, 0xFE, 0xC2, 0x06, 0x69
	DB 0x5D, 0x57, 0x62, 0xF7, 0xCB, 0x67, 0x65, 0x80, 0x71, 0x36, 0x6C, 0x19, 0xE7, 0x06, 0x6B, 0x6E
	DB 0x76, 0x1B, 0xD4, 0xFE, 0xE0, 0x2B, 0xD3, 0x89, 0x5A, 0x7A, 0xDA, 0x10, 0xCC, 0x4A, 0xDD, 0x67
	DB 0x6F, 0xDF, 0xB9, 0xF9, 0xF9, 0xEF, 0xBE, 0x8E, 0x43, 0xBE, 0xB7, 0x17, 0xD5, 0x8E, 0xB0, 0x60
	DB 0xE8, 0xA3, 0xD6, 0xD6, 0x7E, 0x93, 0xD1, 0xA1, 0xC4, 0xC2, 0xD8, 0x38, 0x52, 0xF2, 0xDF, 0x4F
	DB 0xF1, 0x67, 0xBB, 0xD1, 0x67, 0x57, 0xBC, 0xA6, 0xDD, 0x06, 0xB5, 0x3F, 0x4B, 0x36, 0xB2, 0x48
	DB 0xDA, 0x2B, 0x0D, 0xD8, 0x4C, 0x1B, 0x0A, 0xAF, 0xF6, 0x4A, 0x03, 0x36, 0x60, 0x7A, 0x04, 0x41
	DB 0xC3, 0xEF, 0x60, 0xDF, 0x55, 0xDF, 0x67, 0xA8, 0xEF, 0x8E, 0x6E, 0x31, 0x79, 0xBE, 0x69, 0x46
	DB 0x8C, 0xB3, 0x61, 0xCB, 0x1A, 0x83, 0x66, 0xBC, 0xA0, 0xD2, 0x6F, 0x25, 0x36, 0xE2, 0x68, 0x52
	DB 0x95, 0x77, 0x0C, 0xCC, 0x03, 0x47, 0x0B, 0xBB, 0xB9, 0x16, 0x02, 0x22, 0x2F, 0x26, 0x05, 0x55
	DB 0xBE, 0x3B, 0xBA, 0xC5, 0x28, 0x0B, 0xBD, 0xB2, 0x92, 0x5A, 0xB4, 0x2B, 0x04, 0x6A, 0xB3, 0x5C
	DB 0xA7, 0xFF, 0xD7, 0xC2, 0x31, 0xCF, 0xD0, 0xB5, 0x8B, 0x9E, 0xD9, 0x2C, 0x1D, 0xAE, 0xDE, 0x5B
	DB 0xB0, 0xC2, 0x64, 0x9B, 0x26, 0xF2, 0x63, 0xEC, 0x9C, 0xA3, 0x6A, 0x75, 0x0A, 0x93, 0x6D, 0x02
	DB 0xA9, 0x06, 0x09, 0x9C, 0x3F, 0x36, 0x0E, 0xEB, 0x85, 0x67, 0x07, 0x72, 0x13, 0x57, 0x00, 0x05
	DB 0x82, 0x4A, 0xBF, 0x95, 0x14, 0x7A, 0xB8, 0xE2, 0xAE, 0x2B, 0xB1, 0x7B, 0x38, 0x1B, 0xB6, 0x0C
	DB 0x9B, 0x8E, 0xD2, 0x92, 0x0D, 0xBE, 0xD5, 0xE5, 0xB7, 0xEF, 0xDC, 0x7C, 0x21, 0xDF, 0xDB, 0x0B
	DB 0xD4, 0xD2, 0xD3, 0x86, 0x42, 0xE2, 0xD4, 0xF1, 0xF8, 0xB3, 0xDD, 0x68, 0x6E, 0x83, 0xDA, 0x1F
	DB 0xCD, 0x16, 0xBE, 0x81, 0x5B, 0x26, 0xB9, 0xF6, 0xE1, 0x77, 0xB0, 0x6F, 0x77, 0x47, 0xB7, 0x18
	DB 0xE6, 0x5A, 0x08, 0x88, 0x70, 0x6A, 0x0F, 0xFF, 0xCA, 0x3B, 0x06, 0x66, 0x5C, 0x0B, 0x01, 0x11
	DB 0xFF, 0x9E, 0x65, 0x8F, 0x69, 0xAE, 0x62, 0xF8, 0xD3, 0xFF, 0x6B, 0x61, 0x45, 0xCF, 0x6C, 0x16
	DB 0x78, 0xE2, 0x0A, 0xA0, 0xEE, 0xD2, 0x0D, 0xD7, 0x54, 0x83, 0x04, 0x4E, 0xC2, 0xB3, 0x03, 0x39
	DB 0x61, 0x26, 0x67, 0xA7, 0xF7, 0x16, 0x60, 0xD0, 0x4D, 0x47, 0x69, 0x49, 0xDB, 0x77, 0x6E, 0x3E
	DB 0x4A, 0x6A, 0xD1, 0xAE, 0xDC, 0x5A, 0xD6, 0xD9, 0x66, 0x0B, 0xDF, 0x40, 0xF0, 0x3B, 0xD8, 0x37
	DB 0x53, 0xAE, 0xBC, 0xA9, 0xC5, 0x9E, 0xBB, 0xDE, 0x7F, 0xCF, 0xB2, 0x47, 0xE9, 0xFF, 0xB5, 0x30
	DB 0x1C, 0xF2, 0xBD, 0xBD, 0x8A, 0xC2, 0xBA, 0xCA, 0x30, 0x93, 0xB3, 0x53, 0xA6, 0xA3, 0xB4, 0x24
	DB 0x05, 0x36, 0xD0, 0xBA, 0x93, 0x06, 0xD7, 0xCD, 0x29, 0x57, 0xDE, 0x54, 0xBF, 0x67, 0xD9, 0x23
	DB 0x2E, 0x7A, 0x66, 0xB3, 0xB8, 0x4A, 0x61, 0xC4, 0x02, 0x1B, 0x68, 0x5D, 0x94, 0x2B, 0x6F, 0x2A
	DB 0x37, 0xBE, 0x0B, 0xB4, 0xA1, 0x8E, 0x0C, 0xC3, 0x1B, 0xDF, 0x05, 0x5A, 0x8D, 0xEF, 0x02, 0x2D

END_OF_CODE

;	IF  DEBUG == 1
;		SAVESNA "unzip.sna", START
;	ENDIF

	END
