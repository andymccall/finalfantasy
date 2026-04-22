;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Draw Full Map   [$CFF2 :: 0x3D002]
;;
;;    Redraws the entire visible portion of the map.  Used when the map is
;;   first drawn, or after a sub-screen/menu has been displayed that would've
;;   wiped out the map data.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DrawFullMap:
    LDA #0
    STA scroll_y         ; zero y scroll

    LDA mapflags         ; see if we're on the overworld or not
    LSR A                ; put SM flag in C
    BCS @SM              ;  and jump ahead if in SM
  @OW:
     LDA ow_scroll_y     ; add 15 to OW scroll Y
     CLC
     ADC #15
     STA ow_scroll_y
     JMP @StartLoop

  @SM:
     LDA sm_scroll_y     ; same, but add to sm scroll
     CLC
     ADC #15
     AND #$3F            ; and wrap around map boundary
     STA sm_scroll_y

  @StartLoop:
    LDA #$08
    STA facing           ; have the player face upwards (for purposes of following loop)

   @Loop:
      JSR StartMapMove       ; start a fake move upwards (to prep the next row for drawing)
      JSR DrawMapRowCol      ; then draw the row that just got prepped
      JSR PrepAttributePos   ; prep attributes for that row
      JSR DrawMapAttributes  ; and draw them
      JSR ScrollUpOneRow     ; then force a scroll upward one row

      LDA scroll_y           ; check scroll_y
      BNE @Loop              ; and loop until it reaches 0 again (15 iterations)

    LDA #0
    STA facing           ; clear facing
    STA mapdraw_job      ; clear the draw job (all drawing is done)
    STA move_speed       ; clear move speed (player isn't moving)

    RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Start Map Move    [$D023 :: 0x3D033]
;;
;;    This routine starts the player moving in the direction they're facing.
;;    Also used by DrawFullMap to fake-move upward so each row can be prepped.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

StartMapMove:
    LDA scroll_y         ; copy Y scroll to
    STA mapdraw_nty      ;   nt draw Y

    LDA #$FF             ; put overworld mask ($FF -- ow is 256x256 tiles )
    STA tmp+8            ; in tmp+8 for later
    LDX ow_scroll_x      ; put scrollx in X
    LDY ow_scroll_y      ; and scrolly in Y

    LDA mapflags         ; get mapflags
    LSR A                ; shift SM bit into C
    BCC :+               ; if we're in a standard map...

      LDX sm_scroll_x    ; ... replace above OW data with SM versions
      LDY sm_scroll_y
      LDA #$3F           ; and sm mask ($3F -- 64x64) in tmp+8
      STA tmp+8

:   STX mapdraw_x        ; store desired scrollx in mapdraw_x
    STY mapdraw_y        ; and Y scroll

    TXA                  ; then put X scroll in A
    AND #$1F             ; mask out low bits (32 tiles in a 2-NT wide window)
    STA mapdraw_ntx      ; and that's our nt draw X

    LDA facing           ; check which direction we're facing
    LSR A
    BCS @Right
    LSR A
    BCS @Left
    LSR A
    BCS @Down
    LSR A
    BCS @Up

    RTS

  @Right:
    LDA sm_scroll_x
    CLC
    ADC #7+1
    AND #$3F
    STA sm_player_x

    LDA mapdraw_x
    CLC
    ADC #16

  @Horizontal:
    AND tmp+8
    STA mapdraw_x

    AND #$1F
    STA mapdraw_ntx

    LDA mapflags
    ORA #$02
    STA mapflags

    JSR PrepRowCol

  @Finalize:
    LDA #$02
    STA mapdraw_job

    LDA #$01
    STA move_speed

    LDA mapflags
    LSR A
    BCS @Exit

    LDA vehicle
    CMP #$02
    BCC @Exit

    LSR A
    STA move_speed

  @Exit:
    RTS

  @Left:
    LDA sm_scroll_x
    CLC
    ADC #7-1
    AND #$3F
    STA sm_player_x

    LDA mapdraw_x
    SEC
    SBC #1

    JMP @Horizontal

  @Down:
    LDA sm_scroll_y
    CLC
    ADC #7+1
    AND #$3F
    STA sm_player_y

    LDA #15
    STA tmp

    LDA mapdraw_nty
    CLC
    ADC #$0F
    CMP #$0F
    BCC @Vertical

    SEC
    SBC #$0F
    JMP @Vertical

  @Up:
    LDA sm_scroll_y
    CLC
    ADC #7-1
    AND #$3F
    STA sm_player_y

    LDA #$FF             ; -1
    STA tmp

    LDA mapdraw_nty
    SEC
    SBC #$01
    BCS @Vertical
    CLC
    ADC #$0F

  @Vertical:
    STA mapdraw_nty

    LDA mapdraw_y
    CLC
    ADC tmp
    AND tmp+8
    STA mapdraw_y

    LDA mapflags
    AND #$FD             ; ~$02
    STA mapflags

    JSR LoadOWMapRow
    JSR PrepRowCol
    JMP @Finalize


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  ScrollUpOneRow  [$D102 :: 0x3D112]
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ScrollUpOneRow:
    LDA mapflags
    LSR A
    BCC @OW

  @SM:
    LDA sm_scroll_y
    SEC
    SBC #$01
    AND #$3F
    STA sm_scroll_y

    JMP @Finalize

  @OW:
    LDA ow_scroll_y
    SEC
    SBC #$01
    STA ow_scroll_y

  @Finalize:
    LDA scroll_y
    SEC
    SBC #$01
    BCS :+
      ADC #$0F
:   STA scroll_y
    RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Prep Row or Column   [$D2B0 :: 0x3D2C0]
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PrepRowCol:
    LDX #$00
    LDA mapflags
    LSR A
    BCC @DoOverworld

       LDA mapdraw_y
       LSR A
       ROR tmp+2
       LSR A
       ROR tmp+2
       ORA #>mapdata
       STA tmp+1
       LDA tmp+2
       AND #$C0
       STA tmp+2
       ORA mapdraw_x
       STA tmp
       JMP PrepSMRowCol

@DoOverworld:
   LDA mapdraw_y
   AND #$0F
   ORA #>mapdata
   STA tmp+1
   LDA mapdraw_x
   STA tmp
   LDA mapflags
   AND #$02
   BNE @DoColumn

  @DoRow:
     LDY #$00
     LDA (tmp), Y
     TAY

     LDA tsa_ul,      Y
     STA draw_buf_ul, X
     LDA tsa_ur,      Y
     STA draw_buf_ur, X
     LDA tsa_dl,      Y
     STA draw_buf_dl, X
     LDA tsa_dr,      Y
     STA draw_buf_dr, X
     LDA tsa_attr,    Y
     STA draw_buf_attr, X

     INC tmp
     INX
     CPX #$10
     BCC @DoRow
     RTS

  @DoColumn:
     LDY #$00
     LDA (tmp), Y
     TAY

     LDA tsa_ul,      Y
     STA draw_buf_ul, X
     LDA tsa_ur,      Y
     STA draw_buf_ur, X
     LDA tsa_dl,      Y
     STA draw_buf_dl, X
     LDA tsa_dr,      Y
     STA draw_buf_dr, X
     LDA tsa_attr,    Y
     STA draw_buf_attr, X

     LDA tmp+1
     CLC
     ADC #$01
     AND #$0F
     ORA #>mapdata
     STA tmp+1
     INX
     CPX #$10
     BCC @DoColumn
     RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Draw Map Row or Column  [$D2E9 :: 0x3D2F9]
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DrawMapRowCol:
    LDX mapdraw_nty
    LDA lut_2xNTRowStartLo, X
    STA tmp
    LDA lut_2xNTRowStartHi, X
    STA tmp+1
    LDA mapdraw_ntx
    CMP #$10
    BCS @UseNT2400

      TAX
      ASL A
      ORA tmp
      STA tmp
      JMP @DetermineRowOrCol

  @UseNT2400:
      AND #$0F
      TAX
      ASL A
      ORA tmp
      STA tmp
      LDA tmp+1
      CLC
      ADC #$04
      STA tmp+1

  @DetermineRowOrCol:
    LDA mapflags
    AND #$02
    BEQ @DoRow
    JMP @DoColumn

@DoRow:
    TXA
    EOR #$0F
    TAX
    INX
    STX tmp+2
    LDY #$00
    LDA $2002
    LDA tmp+1
    STA $2006
    LDA tmp
    STA $2006

  @RowLoop_U:
    LDA draw_buf_ul, Y
    STA $2007
    LDA draw_buf_ur, Y
    STA $2007
    INY
    DEX
    BNE :+

      LDA tmp+1
      EOR #$04
      STA $2006
      LDA tmp
      AND #$E0
      STA $2006

:   CPY #$10
    BCC @RowLoop_U

    LDA tmp
    CLC
    ADC #$20
    STA tmp
    LDA tmp+1
    STA $2006
    LDA tmp
    STA $2006
    LDY #$00
    LDX tmp+2

@RowLoop_D:
    LDA draw_buf_dl, Y
    STA $2007
    LDA draw_buf_dr, Y
    STA $2007
    INY
    DEX
    BNE :+

      LDA tmp+1
      EOR #$04
      STA $2006
      LDA tmp
      AND #$E0
      STA $2006

:   CPY #$10
    BCC @RowLoop_D
    RTS


@DoColumn:
    LDA #$0F
    SEC
    SBC mapdraw_nty
    TAX
    STX tmp+2
    LDY #$00
    LDA $2002
    LDA tmp+1
    STA $2006
    LDA tmp
    STA $2006
    LDA #$04
    STA $2000

@ColLoop_L:
    LDA draw_buf_ul, Y
    STA $2007
    LDA draw_buf_dl, Y
    STA $2007
    DEX
    BNE :+

      LDA tmp+1
      AND #$24
      STA $2006
      LDA tmp
      AND #$1F
      STA $2006

:   INY
    CPY #$0F
    BCC @ColLoop_L


    LDY #$00
    LDA tmp+1
    STA $2006
    LDA tmp
    CLC
    ADC #$01
    STA $2006
    LDX tmp+2

@ColLoop_R:
    LDA draw_buf_ur, Y
    STA $2007
    LDA draw_buf_dr, Y
    STA $2007
    DEX
    BNE :+

      LDA tmp+1
      AND #$24
      STA $2006
      LDA tmp
      CLC
      ADC #$01
      AND #$1F
      STA $2006

:   INY
    CPY #$0F
    BCC @ColLoop_R
    RTS


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Prep Row or Column Attribute Positions  [$D401 :: 0x3D411]
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PrepAttributePos:
    LDY #$00

@Loop:
    LDA mapdraw_nty
    LDX #$0F
    LSR A
    BCC :+
       LDX #$F0
:   ASL A
    ASL A
    ASL A
    STA tmp
    STX tmp+1
    LDA mapdraw_ntx
    LDX #$23
    CMP #$10
    BCC :+
       AND #$0F
       LDX #$27

:   STX tmp+2
    LDX #$33
    LSR A
    BCC :+
       LDX #$CC
:   ORA tmp
    STA tmp
    TXA
    AND tmp+1
    STA tmp+1

    LDA tmp+2
    STA draw_buf_at_hi, Y
    LDA tmp
    ORA #$C0
    STA draw_buf_at_lo, Y
    LDA tmp+1
    STA draw_buf_at_msk, Y

    LDA mapflags
    AND #$02
    BNE @IncByColumn

       LDA mapdraw_ntx
       CLC
       ADC #$01
       AND #$1F
       STA mapdraw_ntx
       INY
       CPY #$10
       BCS @Exit
       JMP @Loop

@IncByColumn:
       LDA mapdraw_nty
       CLC
       ADC #$01
       CMP #$0F
       BCC :+
         SBC #$0F
:      STA mapdraw_nty
       INY
       CPY #$0F
       BCS @Exit
       JMP @Loop

@Exit:
    RTS


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Draw Map Attributes   [$D46F :: 0x3D47F]
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DrawMapAttributes:
    LDA mapflags
    LDX #$10
    AND #$02
    BEQ :+
      LDX #$0F

:   STX tmp+1
    LDX #$00
    LDA $2002

@Loop:
    LDA draw_buf_at_hi, X
    STA $2006
    LDA draw_buf_at_lo, X
    STA $2006
    LDA $2007
    LDA $2007
    STA tmp
    EOR draw_buf_attr, X
    AND draw_buf_at_msk, X
    EOR tmp
    LDY draw_buf_at_hi, X
    STY $2006
    LDY draw_buf_at_lo, X
    STY $2006
    STA $2007
    INX
    CPX tmp+1
    BCC @Loop
    RTS


;;  lut_2xNTRowStartLo/Hi  [$DDA7 :: 0x3DDB7]
;;
;;  Look up table of NT address of the start of each "2x row".
;;  Indexed by mapdraw_nty (0..14).

lut_2xNTRowStartLo:    .BYTE  $00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0
lut_2xNTRowStartHi:    .BYTE  $20,$20,$20,$20,$21,$21,$21,$21,$22,$22,$22,$22,$23,$23,$23,$23
