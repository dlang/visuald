; StringReplace
; Replaces all ocurrences of a given needle within a haystack with another string
 
!macro StringReplace un
Function ${un}StringReplace
  Exch $R0	; R0 = REPLACE
  Exch 1
  Exch $R1	; R1 = SEARCH
  Exch 1
  Exch 2
  Exch $R2	; R2 = TEXT
  Exch 2

  Push $R3 	
  Push $R4
  Push $R7
  Push $R8
  Push $R9
  StrLen $R7 "$R0"  # R10 = strlen(REPLACE)
  StrLen $R8 "$R1"  # R11 = strlen(SEARCH)
  StrLen $R9 "$R2"  # R12 = strlen(TEXT)
  IntOp $R3 0 + 0   # R4 = pos

loop:  
  IntCmp $R3 $R9 eos continue eos
  continue:
    StrCpy $R4 "$R2" $R8 $R3 	; R4 = substr(TEXT,pos,SEARCH.len)
    StrCmp "$R4" "$R1" found
    not_found:
      IntOp $R3 $R3 + 1		; pos++
      Goto loop
    found:
      StrCpy $R4 "$R2" $R3	; R4 = substr(TEXT,0,pos)
      IntOp $R3 $R3 + $R8	; pos += SEARCH.len
      StrCpy $R2 "$R2" "" $R3	; R2 = substr(TEXT,pos+SEARCH.len)
      StrCpy $R2 "$R4$R0$R2"
      IntOp $R3 $R3 - $R8
      IntOp $R3 $R3 + $R7	; pos += REPLACE.len - SEARCH.len
      Goto loop

eos:
  Pop $R9
  Pop $R8
  Pop $R7
  Pop $R4
  Pop $R3 	

  POP $R0
  POP $R1
  Exch $R2 ; return new TEXT on the stack
FunctionEnd
 !macroend
 
!insertmacro StringReplace ""
!insertmacro StringReplace "un."

;----------------------------------------------------------------------

!macro ReplaceInFile SOURCE_FILE SEARCH_TEXT REPLACEMENT BACKUP
  Push "${BACKUP}"
  Push "${SOURCE_FILE}"
  Push "${SEARCH_TEXT}"
  Push "${REPLACEMENT}"
  Call RIF
!macroend

Function RIF
 
  ClearErrors  ; want to be a newborn
 
  Exch $0      ; REPLACEMENT
  Exch
  Exch $1      ; SEARCH_TEXT
  Exch 2
  Exch $2      ; SOURCE_FILE
  Exch 3
  Exch $3      ; BACKUP
  Exch 3
 
  Push $R0     ; SOURCE_FILE file handle
  Push $R1     ; temporary file handle
  Push $R2     ; unique temporary file name
  Push $R3     ; a line to sar/save
 
  IfFileExists $2 +1 RIF_error      ; knock-knock
  FileOpen $R0 $2 "r"               ; open the door
 
  GetFullPathName $R1 $2\..         ; same folder as source file
  GetTempFileName $R2 $R1           ; Put temporary file in same folder to preserve access rights
  FileOpen $R1 $R2 "w"              ; the escape, please!
 
  RIF_loop:                         ; round'n'round we go
    FileRead $R0 $R3                ; read one line
    IfErrors RIF_leaveloop          ; enough is enough
      Push "$R3"                    ; (hair)stack
      Push "$1"                     ; needle
      Push "$0"                     ; blood
      Call StringReplace            ; do the bartwalk
      Pop $R3                       ; gimme s.th. back in return!
    FileWrite $R1 "$R3"             ; save the newbie
  Goto RIF_loop                     ; gimme more
 
  RIF_leaveloop:                    ; over'n'out, Sir!
    FileClose $R1                   ; S'rry, Ma'am - clos'n now
    FileClose $R0                   ; me 2
 
  StrCmp $3 "NoBackup" nobackup backup
  backup:
    Delete "$2.bak"                 ; go away, Sire
    Rename "$2" "$2.bak"            ; step aside, Ma'am
    Goto rename
  nobackup:
    Delete "$2"                     ; go away, Sire
  rename:
    Rename "$R2" "$2"               ; hi, baby!
 
    ClearErrors                     ; now i AM a newborn
    Goto RIF_out                    ; out'n'away
 
  RIF_error:                        ; ups - s.th. went wrong...
    SetErrors                       ; ...so cry, boy!
 
  RIF_out:                          ; your wardrobe?
  Pop $R3
  Pop $R2
  Pop $R1
  Pop $R0
  Pop $2
  Pop $0
  Pop $1
  Pop $3
 
FunctionEnd

;----------------------------------------------------------------------

!macro InsertToFile SOURCE_FILE SEARCH_TEXT INSERTFILE BACKUP
  Push "${BACKUP}"
  Push "${SOURCE_FILE}"
  Push "${SEARCH_TEXT}"
  Push "${INSERTFILE}"
  Call ITF
!macroend

Function ITF
 
  ClearErrors  ; want to be a newborn
 
  Exch $0      ; INSERTFILE
  Exch
  Exch $1      ; SEARCH_TEXT
  Exch 2
  Exch $2      ; SOURCE_FILE
  Exch 3
  Exch $3      ; BACKUP
  Exch 3
 
  Push $R0     ; SOURCE_FILE file handle
  Push $R1     ; temporary file handle
  Push $R2     ; unique temporary file name
  Push $R3     ; a line to sar/save
  Push $R4     ; length of SEARCH_TEXT
  Push $R5     ; insert file handle

  StrLen $R4 "$1"  # R4 = strlen(SEARCH_TEXT)
  
  IfFileExists $2 +1 ITF_error
  FileOpen $R0 $2 "r"

  IfFileExists $0 +1 ITF_error
  FileOpen $R5 $0 "r"               ; open insert file
  
  GetTempFileName $R2
  FileOpen $R1 $R2 "w"
 
  ITF_loop:
    FileRead $R0 $R3                ; read one line
    IfErrors ITF_leaveloop
    FileWrite $R1 "$R3"             ; save the line
    StrCpy $R3 "$R3" $R4            ; get start of line

    StrCmp "$R3" $1 copy_file ITF_loop

    copy_file:
      FileSeek $R5 0
    copy_loop:
        FileRead $R5 $R3            ; read one line
        IfErrors copy_done          ; end of file
        FileWrite $R1 "$R3"         ; save the line
	Goto copy_loop
    copy_done:
    Goto ITF_loop
 
  ITF_leaveloop:
    FileClose $R1
    FileClose $R0
    FileClose $R5
 
  StrCmp $3 "NoBackup" nobackup backup
  backup:
    Delete "$2.bak"
    Rename "$2" "$2.bak"
    Goto rename
  nobackup:
    Delete "$2"
  rename:
    Rename "$R2" "$2"
 
    ClearErrors
    Goto ITF_out
 
  ITF_error:
    SetErrors
 
  ITF_out:
  Pop $R5
  Pop $R4
  Pop $R3
  Pop $R2
  Pop $R1
  Pop $R0
  Pop $2
  Pop $0
  Pop $1
  Pop $3
 
FunctionEnd

;----------------------------------------------------------------------

!macro RemoveFromFile SOURCE_FILE START_TEXT END_TEXT BACKUP
  Push "${BACKUP}"
  Push "${SOURCE_FILE}"
  Push "${START_TEXT}"
  Push "${END_TEXT}"
  Call RFF
!macroend

!macro un.RemoveFromFile SOURCE_FILE START_TEXT END_TEXT BACKUP
  Push "${BACKUP}"
  Push "${SOURCE_FILE}"
  Push "${START_TEXT}"
  Push "${END_TEXT}"
  Call un.RFF
!macroend

!macro RFF un
Function ${un}RFF
 
  ClearErrors  ; want to be a newborn
 
  Exch $0      ; END_TEXT
  Exch
  Exch $1      ; START_TEXT
  Exch 2
  Exch $2      ; SOURCE_FILE
  Exch 3
  Exch $3      ; BACKUP
  Exch 3
 
  Push $R0     ; SOURCE_FILE file handle
  Push $R1     ; temporary file handle
  Push $R2     ; unique temporary file name
  Push $R3     ; a line to test
  Push $R4     ; length of START_TEXT
  Push $R5     ; length of END_TEXT
  Push $R6     ; tmp

  StrLen $R4 "$1"  # R4 = strlen(START_TEXT)
  StrLen $R5 "$0"  # R5 = strlen(END_TEXT)
  
  IfFileExists $2 +1 RFF_error
  FileOpen $R0 $2 "r"

  GetTempFileName $R2
  FileOpen $R1 $R2 "w"
 
  RFF_loop:
    FileRead $R0 $R3                ; read one line
    IfErrors RFF_leaveloop
    
    StrCpy $R6 "$R3" $R4            ; get start of line
    StrCmp "$R6" $1 RFF_test_no_remove RFF_cont

  RFF_test_no_remove:
    Push $R3
    Push "DO NOT REMOVE"
    Push ""
    Call ${un}StringReplace
    Pop $R6
    StrCmp "$R6" "$R3" skip_file RFF_no_remove
    
  skip_file:
    FileRead $R0 $R3                ; read one line
    IfErrors RFF_leaveloop
 
    StrCpy $R6 "$R3" $R5            ; get start of line
    StrCmp "$R6" $0 end_found skip_file
 
  RFF_cont:
    FileWrite $R1 "$R3"             ; save the line
  end_found:
    Goto RFF_loop                   ; next line

  RFF_no_remove:    
    FileClose $R1
    FileClose $R0
    Delete "$R2"                    ; remove temp file
    Goto RFF_error                  ; signal error to skip insertion
    
  RFF_leaveloop:
    FileClose $R1
    FileClose $R0
 
  StrCmp $3 "NoBackup" nobackup backup
  backup:
    Delete "$2.bak"
    Rename "$2" "$2.bak"
    Goto rename
  nobackup:
    Delete "$2"
  rename:
    Rename "$R2" "$2"
 
    ClearErrors
    Goto RFF_out
 
  RFF_error:
    SetErrors
 
  RFF_out:
  Pop $R6
  Pop $R5
  Pop $R4
  Pop $R3
  Pop $R2
  Pop $R1
  Pop $R0

  Pop $2
  Pop $0
  Pop $1
  Pop $3
 
FunctionEnd
!macroend

!insertmacro RFF ""
!insertmacro RFF "un."

