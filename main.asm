;*****************************************************************
;* This stationery serves as the framework for a                 *
;* user application (single file, absolute assembly application) *
;* For a more comprehensive program that                         *
;* demonstrates the more advanced functionality of this          *
;* processor, please see the demonstration applications          *
;* located in the examples subdirectory of the                   *
;* Freescale CodeWarrior for the HC12 Program directory          *
;*****************************************************************

; export symbols
            XDEF Entry, _Startup
            ABSENTRY Entry

; Include derivative-specific definitions
            INCLUDE 'derivative.inc'

ROMStart    EQU  $4000

; variable/data section
            ORG   RAMStart
DENSA       DS.B 1                  ; density of road A (AN5)
DENSB       DS.B 1                  ; density of road B (AN3)
TGREEN      DS.B 1                  ; green light duration in seconds
ROAD        DS.B 1                  ; active road: 0 = A, 1 = B
PHASE       DS.B 1                  ; 0 = green, 1 = yellow, 2 = red
SECLEFT     DS.B 1                  ; remaining seconds of the phase
TICKS       DS.B 1                  ; 2 x 0.5 s = 1 s
SECFLAG     DS.B 1                  ; set by the MCCNT ISR every 1 s
EMERG       DS.B 1                  ; set by the IRQ ISR (PB1)
EMGNEXT     DS.B 1                  ; road A gets 8 s of green next
PEDREQ      DS.B 1                  ; pedestrian request (DIP1 or DIP4)
HEAVY       DS.B 1                  ; both densities >= 230
LASTRD      DS.B 1                  ; road of the last green phase
GCOUNT      DS.B 1                  ; successive green phases of LASTRD
BUF         DS.B 18                 ; LCD text: 2 lines of 8 characters

; code section
            ORG   ROMStart

Entry:
_Startup:
            LDS   #RAMEnd+1         ; initialize the stack pointer

            LDX #DENSA              ; clear all the variables
            LDAB #14
CLRVAR      CLR 1,X+
            DBNE B,CLRVAR
            MOVB #2,TICKS
            MOVB #$FF,LASTRD        ; no green phase yet

            MOVB #$3F,DDRA          ; PA0-PA5 outputs (traffic LEDs)
            CLR PORTA
            MOVB #$F0,DDRB          ; PB0-PB3 inputs (DIP switches)
            MOVB #$F0,PORTB         ; board LEDs OFF
            MOVB #$02,PUCR          ; enable the pull-ups of port B

            MOVB #$10,MODRR         ; route SPI0 to port M
            MOVB #$38,DDRM          ; PM3, PM4, PM5 outputs
            MOVB #$52,SPI0CR1       ; SPI0 on, master, MSB first
            MOVB #$10,SPI0CR2
            MOVB #$00,SPI0BR

            MOVB #$80,ATD0CTL2      ; power up the ATD
            MOVB #$08,ATD0CTL3      ; one conversion per sequence
            MOVB #$80,ATD0CTL4      ; 8-bit resolution

            MOVB #$01,PWMPRCLK      ; clock A = 2 MHz / 2 = 1 MHz
            MOVB #5,PWMSCLA         ; clock SA = 1 MHz / (2 x 5) = 100 kHz
            MOVB #$30,PWMCLK        ; channels 4 and 5 use clock SA
            MOVB #$30,PWMPOL        ; high at the start of the period
            MOVB #100,PWMPER4       ; 100 x 10 us = 1 ms -> 1 kHz
            MOVB #50,PWMDTY4        ; 50 % duty cycle
            MOVB #20,PWMPER5        ; 20 x 10 us = 0.2 ms -> 5 kHz
            MOVB #10,PWMDTY5        ; 50 % duty cycle
            CLR PWME                ; buzzer OFF

            MOVB #$C0,INTCR         ; IRQ enabled, falling edge
            MOVB #$C7,MCCTL         ; interrupt, modulus mode, prescaler 16
            MOVW #62500,MCCNT       ; 62500 x 16 x 0.5 us = 0.5 s
            CLI                     ; enable maskable interrupts

            LDY #10
            JSR WAIT                ; 50 ms LCD power-up time
            LDAA #$33               ; LCD initialization
            JSR SENDINST
            LDAA #$32
            JSR SENDINST
            LDAA #$28               ; 4-bit mode, 2 lines
            JSR SENDINST
            LDAA #$0C               ; display ON, cursor OFF
            JSR SENDINST
            LDAA #$01               ; clear display
            JSR SENDINST
            LDAA #$06               ; cursor moves to the right
            JSR SENDINST

            LDX #MSG1               ; TRAFFIC / CONTROL
            JSR PRINT
            MOVB #5,SECLEFT         ; for 5 s
            JSR SYNC
SPLASH      TST SECFLAG
            BEQ SPLASH
            CLR SECFLAG
            DEC SECLEFT
            BNE SPLASH
            CLR EMERG

;------------------- new light sequence --------------------------
NEWCYCLE    JSR READADC             ; read DENSITYA and DENSITYB
            TST EMGNEXT
            BNE EMGCYCLE

            CLR ROAD                ; road A by default
            LDAA DENSA
            CMPA DENSB
            BHS CHKMAX              ; DENSA >= DENSB: road A first
            INC ROAD                ; DENSA < DENSB: road B first
CHKMAX      LDAA ROAD
            CMPA LASTRD
            BNE NEWRD
            LDAB GCOUNT
            CMPB #2
            BLO SAMERD
            EORA #1                 ; 2 greens in a row: give the other road
            STAA ROAD
NEWRD       STAA LASTRD
            MOVB #1,GCOUNT
            BRA CALCT
SAMERD      INC GCOUNT

CALCT       LDAB ROAD
            LDX #DENSA
            LDAA B,X                ; density of the active road
            LDAB #10
            MUL                     ; D = DENSITY x 10
            LDX #255
            IDIV                    ; X = DENSITY x 10 / 255
            TFR X,B
            ADDB #5                 ; TGREEN = 5 + DENSITY x 10 / 255
            STAB TGREEN
            STAB SECLEFT
            CLR PHASE
            BRA RUNPHASE

EMGCYCLE    CLR EMGNEXT             ; emergency: road A green for 8 s
            CLR ROAD
            CLR PHASE
            MOVB #8,SECLEFT

RUNPHASE    JSR SETLEDS
            JSR SYNC
            JSR SHOW

PLOOP       BRSET PORTB,#%00000001,NOPEDA
            MOVB #1,PEDREQ          ; DIP1 ON: pedestrian on road A
NOPEDA      BRSET PORTB,#%00001000,NOPEDB
            MOVB #1,PEDREQ          ; DIP4 ON: pedestrian on road B
NOPEDB      TST EMERG
            BEQ NOEMG
            CLR EMERG
            JSR EMGHAND
NOEMG       TST SECFLAG
            BEQ PLOOP               ; wait for the next second
            CLR SECFLAG
            JSR READADC
            JSR HEAVYCHK
            DEC SECLEFT
            BEQ NEXTPH
            JSR SHOW                ; decreasing counter on the LCD
            BRA PLOOP

NEXTPH      INC PHASE
            LDAA PHASE
            CMPA #3
            BEQ ENDCYC              ; green, yellow and red are done
            LDAB #3                 ; yellow: 3 s
            CMPA #1
            BEQ SETT
            LDAB #2                 ; red on both roads: 2 s
SETT        STAB SECLEFT
            BRA RUNPHASE

ENDCYC      TST EMGNEXT
            BNE GONEW               ; emergency is served first
            TST PEDREQ
            BEQ GONEW
            JSR PEDCROSS            ; pedestrian crossing after the red
GONEW       JMP NEWCYCLE            ; recheck the potentiometers

;------------------- subroutines ---------------------------------
READADC     MOVB #%10000101,ATD0CTL5 ; right justified, single, AN5
            BRCLR ATD0STAT0,#$80,*
            MOVB ATD0DR0L,DENSA
            MOVB #%10000011,ATD0CTL5 ; right justified, single, AN3
            BRCLR ATD0STAT0,#$80,*
            MOVB ATD0DR0L,DENSB
            RTS

SETLEDS     LDAA ROAD
            LDAB #3
            MUL                     ; B = ROAD x 3
            ADDB PHASE
            LDX #LEDTAB
            LDAA B,X
            STAA PORTA
            RTS

SYNC        SEI
            MOVB #2,TICKS
            CLR SECFLAG
            BSET MCCTL,#$08         ; FLMC = 1: restart the 0.5 s count
            CLI
            RTS

EMGHAND     TST PHASE
            BNE EMGLATE             ; yellow or red: finish the phase
            TST ROAD
            BNE EMGB
            LDAA SECLEFT            ; road A green: add 8 s
            ADDA #8
            STAA SECLEFT
            BRA SHOW
EMGB        MOVB #1,PHASE           ; road B green: stop it safely
            MOVB #3,SECLEFT         ; road B yellow for 3 s
            JSR SETLEDS
            JSR SYNC
            JSR SHOW
EMGLATE     MOVB #1,EMGNEXT         ; road A green 8 s after the red
            RTS

PEDCROSS    CLR PEDREQ
            MOVB #$24,PORTA         ; red on both roads
            BCLR PWME,#$20          ; 5 kHz tone OFF
            LDX #TEMPL              ; A:R / B:R
            JSR PRINT
            BSET PWME,#$10          ; 1 kHz tone ON
            LDY #1600
            JSR WAIT                ; 1600 x 5 ms = 8 s
            BCLR PWME,#$10          ; 1 kHz tone OFF
            RTS

HEAVYCHK    LDAA DENSA
            CMPA #230
            BLO NOHEAVY
            LDAA DENSB
            CMPA #230
            BLO NOHEAVY
            MOVB #1,HEAVY
            LDAA PWME
            EORA #$20               ; 5 kHz tone ON 1 s, OFF 1 s
            STAA PWME
            RTS
NOHEAVY     CLR HEAVY
            BCLR PWME,#$20          ; buzzer OFF
            RTS

SHOW        LDX #HVMSG
            TST HEAVY
            BNE PRINT               ; HEAVY / TRAFFIC
            LDX #TEMPL              ; copy A:R / B:R into BUF
            LDY #BUF
            LDAB #18
COPY        MOVB 1,X+,1,Y+
            DBNE B,COPY
            LDX #BUF
            TST ROAD
            BEQ LINEOK
            LEAX 9,X                ; road B is on the second line
LINEOK      LDY #STATECH
            LDAB PHASE
            LDAA B,Y
            STAA 2,X                ; G, Y or R
            CLRA
            LDAB SECLEFT
            PSHX
            LDX #10
            IDIV                    ; X = tens, B = units
            TFR X,A
            PULX
            ADDB #48                ; units to ASCII
            TSTA
            BEQ ONEDIG
            ADDA #48                ; tens to ASCII
            STAA 4,X
            STAB 5,X
            MOVB #'s',6,X
            BRA SHOWBUF
ONEDIG      STAB 4,X
            MOVB #'s',5,X
SHOWBUF     LDX #BUF

PRINT       LDAA #$80               ; start of the first line
            JSR SENDINST
LINE1       LDAA 1,X+
            BEQ LINE2
            JSR SENDDATA
            BRA LINE1
LINE2       LDAA #$C0               ; start of the second line
            JSR SENDINST
NEXTCH      LDAA 1,X+
            BEQ PDONE
            JSR SENDDATA
            BRA NEXTCH
PDONE       RTS

SENDSPI     BRCLR SPI0SR,#$20,*     ; wait until SPTEF = 1
            STAA SPI0DR
            RTS

SENDINST    TAB
            RORA
            RORA
            RORA
            RORA
            ORAA #%10000000         ; EN = 1
            ANDA #%10001111         ; RS = 0 (instruction)
            JSR SENDSPI
            ANDA #%00001111         ; EN = 0
            JSR SENDSPI
            JSR DELAY
            TBA
            ORAA #%10000000
            ANDA #%10001111
            JSR SENDSPI
            ANDA #%00001111
            JSR SENDSPI
            JSR DELAY
            RTS

SENDDATA    TAB
            RORA
            RORA
            RORA
            RORA
            ORAA #%11000000         ; EN = 1, RS = 1 (data)
            ANDA #%11001111
            JSR SENDSPI
            ANDA #%01001111         ; EN = 0
            JSR SENDSPI
            JSR DELAY
            TBA
            ORAA #%11000000
            ANDA #%11001111
            JSR SENDSPI
            ANDA #%01001111
            JSR SENDSPI
            JSR DELAY
            RTS

WAIT        JSR DELAY               ; Y x 5 ms
            DEY
            BNE WAIT
            RTS

DELAY       PSHX
            LDX #526                ; 526 x 9.5 us = 5 ms
AGAIN       PSHB
            PULB
            PSHB
            PULB
            PSHB
            PULB
            DEX
            BNE AGAIN
            PULX
            RTS

;------------------- interrupt service routines ------------------
MCISR       MOVB #$80,MCFLG         ; clear the underflow flag MCZF
            DEC TICKS
            BNE MCOUT
            MOVB #2,TICKS           ; 1 s passed
            MOVB #1,SECFLAG
MCOUT       RTI

IRQISR      MOVB #1,EMERG           ; PB1 pressed: emergency on road A
            RTI

;------------------- tables --------------------------------------
LEDTAB      DC.B $21,$22,$24        ; road A green, yellow, red (B red)
            DC.B $0C,$14,$24        ; road B green, yellow, red (A red)
STATECH     DC.B 'G','Y','R'
MSG1        DC.B 'TRAFFIC ',0,'CONTROL ',0
HVMSG       DC.B 'HEAVY   ',0,'TRAFFIC ',0
TEMPL       DC.B 'A:R     ',0,'B:R     ',0

;------------------- interrupt vectors ---------------------------
            ORG   $FFCA
            DC.W  MCISR             ; MCCNT underflow vector
            ORG   $FFF2
            DC.W  IRQISR            ; IRQ vector
            ORG   $FFFE
            DC.W  Entry             ; reset vector

