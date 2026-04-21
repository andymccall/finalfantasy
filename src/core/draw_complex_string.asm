DrawComplexString_Exit:
    LDA #$00       ; reset scroll to 0
    STA $2005
    STA $2005
    LDA ret_bank   ; swap back to original bank
    JMP SwapPRG_L  ;   then return


DrawComplexString:
    LDA cur_bank
    JSR SwapPRG_L
    JSR CoordToNTAddr

  @StallAndDraw:
    LDA menustall     ; check to see if we need to stall
    BEQ @Draw_NoStall ; if not, skip over stall call
    JSR MenuCondStall ;   this isn't really necessary, since MenuCondStall checks menustall already

  @Draw_NoStall:
    LDY #0            ; zero Y -- we don't want to use it as an index.  Rather, the pointer is updated
    LDA (text_ptr), Y ;   after each fetch
    BEQ DrawComplexString_Exit   ; if the character is 0  (null terminator), exit the routine

    INC text_ptr      ; otherwise, inc source pointer
    BNE :+
      INC text_ptr+1  ;   inc high byte if low byte wrapped

:   CMP #$1A          ; values below $1A are control codes.  See if this is a control code
    BCC @ControlCode  ;   if it is, jump ahead

    LDX $2002         ; reset PPU toggle
    LDX ppu_dest+1    ;  load and set desired PPU address
    STX $2006         ;  do this with X, as to not disturb A, which is still our character
    LDX ppu_dest
    STX $2006

    CMP #$7A          ; see if this is a DTE character
    BCS @noDTE        ;  if < #$7A, it is DTE  (even though it probably should be #$6A)

      SEC             ;  characters 1A-69 are valid DTE characters.  6A-79 are treated as DTE, but will draw crap
      SBC #$1A        ; subtract #$1A to get a zero-based index
      TAX             ; put the index in X
      LDA lut_DTE1, X ;  load and draw the first character in DTE
      STA $2007
      LDA lut_DTE2, X ;  load the second DTE character to be drawn in a bit
      INC ppu_dest    ;  increment the destination PPU address

  @noDTE:
    STA $2007         ; draw the character as-is
    INC ppu_dest      ; increment dest PPU address
    JMP @Draw_NoStall ; and repeat the process until terminated


   ; Jumps here for control codes.  Start comparing to see which control code this actually is
@ControlCode:
    CMP #$01           ; is it $01?
    BNE @Code_02to19   ; if not, jump ahead

    ;;; Control code $01 -- double line break
    LDX #$40

  @LineBreak:      ; Line break -- X=40 for a double line break (control code $01),
    STX tmp        ;  X=20 for a single line break (control code $05)
    LDA ppu_dest   ; store X in tmp for future use.
    AND #$E0       ; Load dest PPU Addr, mask off the low bits (move to start of the row)
    ORA dest_x     ;  OR with the destination X coord (moving back to original start column)
    CLC
    ADC tmp        ; add the line break value (number of rows to inc by) to PPU Addr
    STA ppu_dest
    LDA ppu_dest+1
    ADC #0         ; catch any carry for the high byte
    STA ppu_dest+1
    JMP @StallAndDraw   ; continue processing text


@Code_02to19:
    CMP #$02        ; is control code $02?
    BNE :+
      JMP @Code_02  ; if it is, jump to its handler

:   CMP #$03        ; otherwise... is it $03?
    BNE :+
      JMP @Code_03  ; if it is, jump to 03's handler

:   CMP #$04        ; otherwise... 04?
    BNE @Code05to19

    ;;; Control code $04 -- draws current gold
    JSR @Save               ; this is a substring we'll need to draw, so save 
    LDA #BANK_MENUS
    JSR SwapPRG_L           ;  swap to menu bank (for "PrintGold" routine)
    JSR PrintGold           ;  PrintGold to temp buffer
    JSR @StallAndDraw       ;  recursively call this routine to draw temp buffer
    JMP @Restore            ; then restore original string state and continue


@Code05to19:
    CMP #$14         ; is control code < $14?
    BCC @Code05to13

                     ; codes $14 and up default to single line break
@SingleLineBreak:    ; reached by control codes $05-0F and $14-19
    LDX #$20         ; these control codes all just do a single line break
    JMP @LineBreak   ;  afaik, $05 is the only single line break used by the game.. the other
                     ;  control codes are probably invalid and just line break by default

@Code05to13:
    CMP #$10              ; is control code < $10?
    BCC @SingleLineBreak  ; if yes... line break

    ;;;; Control Codes $10-13
    ;;;;   These control codes indicate to draw a stat of a specific character
    ;;;;   ($10 is character 0, $11 is character 1, etc)
    ;;;; Which stat to draw is determined by the next byte in the string

    ROR A          ; rotate low to 2 bits to the high 2 bits and mask them out
    ROR A          ;  effectively giving you character * $40
    ROR A          ;  this will be used to index character stats
    AND #$C0
    STA char_index ; store index

    LDA (text_ptr), Y   ; get the next byte in the string (the stat to draw)
    INC text_ptr        ; inc our string pointer
    BNE :+
      INC text_ptr+1    ; inc high byte if low byte wrapped

:   CMP #0
    BNE @StatCode_Over00

      ;; Stat Code $00 -- the character's name
      LDX char_index      ; load character index
      LDA ch_name, X      ; copy name to format buffer
      STA format_buf-4
      LDA ch_name+1, X
      STA format_buf-3
      LDA ch_name+2, X
      STA format_buf-2
      LDA ch_name+3, X
      STA format_buf-1

      JSR @Save              ; need to draw a substring, so save current string
      LDA #<(format_buf-4)   ; set string source pointer to temp buffer
      STA text_ptr
      LDA #>(format_buf-4)
      STA text_ptr+1
      JSR @Draw_NoStall      ; recursively draw it
      JMP @Restore           ; then restore original string and continue


@StatCode_Over00:
    CMP #$01
    BNE @StatCode_Over01

      ;; Stat Code $01 -- the character's class name
      LDX char_index   ; get character index
      LDA ch_class, X  ; get character's class
      CLC              ; add #$F0 (start of class names)
      ADC #$F0         ; draw it (yes I know, class names are not items, but they're stored with items)
      JMP @DrawItem

@StatCode_Over01:
    CMP #$02
    BNE @StatCode_Over02

      ;; Stat Code $02 -- draw ailment blurb ("HP" if character is fine, nothing if dead, "ST" if stone, or "PO" if poisoned)
      LDX char_index        ; character index
      LDA ch_ailments, X    ; out-of-battle ailment ID
      CLC                   ; add #$FC (start of ailment names)
      ADC #$FC              ; draw it (not an item, but with item names)
      JMP @DrawItem

@StatCode_Over02:
    CMP #$0C
    BCC @DrawCharStat      ; if stat code is between $02-0B, relay this stat code to PrintCharStat

    CMP #$2C
    BCC @StatCode_0Cto2B   ; see if stat code is below #$2C.  If it isn't, we relay to PrintCharStat

  @DrawCharStat:           ; this paticular stat code is going to be handled in a routine in another bank
    TAX                    ;  temporarily put the code in X
    JSR @Save              ;  save string data (we'll be drawing a substring)
    LDA #BANK_MENUS
    JSR SwapPRG_L          ;  swap to menu bank (has the PrintCharStat routine)
    TXA                    ;  put the stat code back in A
    JSR PrintCharStat      ;  print it to temp string buffer
    JSR @StallAndDraw      ; draw it to the screen
    JMP @Restore           ; restore original string data and continue


@StatCode_0Cto2B:
    CMP #$14
    BCS @StatCode_14to2B   ; see if code >= #$14

    CMP #$10
    BCS @StatCode_10to13   ; see if >= #$10

      ;;; Stat Codes $0C-0F -- weapons (BUGGED)
      AND #$03        ; isolate the weapons slot (each character has 4 weapons)
      CLC
      ADC char_index  ; add character index
      TAX
      LDA ch_weapons, X  ; get the weapon ID
      STA tmp            ; put unedited weapon ID in $10 (temporary)
      AND #$7F           ; mask out high bit (high bit indicates whether or not weapon is equipped)
      BEQ @WeaponArmor   ; if weapon ID == 0 (slot is empty), skip ahead and draw string 0 (blank string)

        CLC           ; if weapon ID is nonzero (slot has an actual weapon), add #$1B to ID
        ADC #$1B      ; $1C is the start of the weapon names in the item list (-1 because 0 is nothing)
        BNE @WeaponArmor ; jump ahead to draw it (always branches)


  @StatCode_10to13:   ;; Stat Codes $10-13 -- armor (BUGGED)
    AND #$03          ; isolate the armor slot (each character has 4 armor)
    CLC
    ADC char_index    ; add character index
    TAX
    LDA ch_armor, X   ; get armor ID
    STA tmp           ; store as-is in $10 (temp)
    AND #$7F          ; mask off the equip bit
    BEQ @WeaponArmor      ; if zero (empty slot), skip ahead and draw string 0 (blank string)

        CLC           ; if nonzero, add #$43 to armor ID
        ADC #$43      ; $44 is the start of armor names in the item list (-1 because 0 is nothing)

  @WeaponArmor:          ; above weapon and armor codes reach here with A containing
      STA tmp+1          ;  the string index to draw.  Write that index to tmp+1
      JMP @DrawEquipment_BUGGED ;  and jump to equipment drawing (BUGGED)

@StatCode_14to2B:     ;; Stat Codes $14-2B -- magic
    SEC
    SBC #$14          ; subtract #$14 to get it zero based
    TAX               ; use that as an index
    LDA @lutMagic, X  ;  in the magic conversion LUT.  This gets the index to the spell in RAM
    CLC
    ADC char_index    ; add character index
    TAX               ; and put it in X for indexing

    ASL A             ; then double A
    AND #$38          ;  and mask out bits 4-6.  This gives us the spell level * 8

    CLC               ; Add #$AF to the spell level*8 ($B0 is the start of the magic item text.  -1 because 0 is nothing)
    ADC #$AF          ;  we add the spell level here because spells are only 01-08 in RAM.  IE:  CURE and LAMP are both stored
                      ;  as $01 in the character's spell list.  The game tells them apart because LAMP is stored in the level 2 section
                      ;  and CURE is stored in the level 1 section.
    STA tmp           ; store this calculated index in tmp ram

    LDA ch_spells, X  ; use X as index to get the spell
    BEQ :+            ; if 0, skip ahead and draw nothing (no spell)

      CLC             ; add our level+text index to the current spell
      ADC tmp         ;  previously stored in tmp
      JMP @DrawItem   ; and jump to @DrawItem

:   JMP @StallAndDraw ; jumps here when spell=0.  Simply do nothing and continue with string processing

    ;; Magic conversion LUT [$DF90 :: 0x3DFA0]
    ;;  each character has 24 spells (8 levels * 3 spells per level).  However these 24 spells
    ;;  span a 32 byte range in RAM because each level starts on its own 4-byte boundary
    ;; therefore the 3rd byte in every set of 4 goes unused (padding).  This table converts
    ;; a 24-index to the desired 32-index by simply skipping the 3rd byte in every set of 4

@lutMagic:
    .BYTE $00,$01,$02,    $04,$05,$06,    $08,$09,$0A,    $0C,$0D,$0E
    .BYTE $10,$11,$12,    $14,$15,$16,    $18,$19,$1A,    $1C,$1D,$1E


    ; This is called to draw weapon/armor, along with the "E-" before it if the item is equipped
    ;  supposedly, anyway.  This routine is totally bugged.  Extra spaces are drawn where they shouldn't be
    ;  which would result in screwed up output.  Plus it draws the wrong item string!
    ;
    ;  Due to the bugs, I don't believe this routine is ever used.  Weapon/Armor subscreens and shops don't appear to use
    ;  these control codes -- and I don't think in-battle ever even calls DrawComplexString
    ;
    ;   tmp   = raw weap/armor ID.  High bit set if piece is equipped (draw the "E-") or clear if unequipped (draw spaces instead)
    ;   tmp+1 = ID of item text string to draw (name of weapon/armor) -- supposedly... but it isn't used!

@DrawEquipment_BUGGED:
    LDA tmp              ; get weapon/armor ID
    BNE :+               ; if it's zero...
      JMP @Draw_NoStall  ; draw nothing -- continue with normal text processing

:   BMI @isEquipped    ; if high bit set, we need to draw the "E-"
      LDX #$FF         ; otherwise... (not equipped), just draw spaces
      LDY #$FF         ;  set X and Y to $FF (blank space tile)
      BNE :+           ;  and jump ahead (always branches)

    @isEquipped:       ; code jumps here if item is equipped
      LDX #$C7         ; set X to the "E" tile
      LDY #$C2         ; and Y to the "-" tile

:   LDA $2002       ; both equipped and nonequipped code meet up here
    LDA ppu_dest+1  ; reset PPU toggle
    STA $2006       ; and set desired PPU address
    LDA ppu_dest
    STA $2006

    LDA #$FF
    STA $2007       ; draw a space (why??? -- screws up result!)
    STX $2007       ; then the "E" (if equipped) or another space (if not)

    INC ppu_dest    ; inc dest address

    LDA $2002       ; reset toggle again
    LDA ppu_dest+1  ; and set desired PPU address
    STA $2006
    LDA ppu_dest
    STA $2006

    LDA #$FF        ; draw a space.  Again.. why?  This only makes sense if you're in inc-by-32 mode
    STA $2007       ;  otherwise this space will overwrite the "E" we just drew.  But if you're in inc-by-32 mode...
    STY $2007       ;  the "E-" will draw 1 line below the item name (makes no sense).
                    ; but anyway yeah.. after that space, draw the "-" or another space

    INC ppu_dest    ; inc dest PPU address
    LDA tmp         ;  get weapon/armor ID   (but this is wrong -- should be tmp+1)
    AND #$7F        ;  mask off the equip bit  (but this is wrong)
    JMP @DrawItem   ;  and draw the string.  But that's wrong!  It probably meant to draw tmp+1 (the item string index)

    ;;; Control Code $02 -- draws an item name
  @Code_02:
    LDA (text_ptr), Y     ; get another byte from the string (this byte is the ID of the item string to draw)
    INC text_ptr          ; inc source pointer
    BNE @DrawItem
      INC text_ptr+1      ;   and inc high byte if low byte wrapped

  @DrawItem:
    JSR @Save             ; drawing an item requires a substring.  Save current string
    TAX                   ; put item ID in X temporarily

    LDA #BANK_ITEMS
    STA cur_bank 
    JSR SwapPRG_L         ; swap to BANK_ITEMS (contains item strings)

    TXA                   ; get item ID
    ASL A                 ; double it (for pointer table lookup)
    TAX                   ; put low byte in X for indexing

    BCS @itemHigh                 ; if doubling A caused a carry (item ID >= $80)... jump ahead
      LDA lut_ItemNamePtrTbl, X   ;  if item ID was < $80... read pointer from first half of pointer table
      STA text_ptr                ;  low byte of pointer
      LDA lut_ItemNamePtrTbl+1, X ;  high byte of pointer (will be written after jump)
      JMP @itemGo

  @itemHigh:                         ; item high -- if item ID was >= $80
      LDA lut_ItemNamePtrTbl+$100, X ;  load pointer from second half of pointer table
      STA text_ptr                   ;  write low byte of pointer
      LDA lut_ItemNamePtrTbl+$101, X ;  high byte (written next inst)

  @itemGo:
    STA text_ptr+1        ; finally write high byte of pointer
    JSR @Draw_NoStall     ; recursively draw the substring
    JMP @Restore          ; then restore original string and continue

    ;;;; Control Code $03 -- prints an item price
  @Code_03:
    LDA (text_ptr), Y    ; get another byte of string (the ID of item whose price we want)
    INC text_ptr         ; inc string pointer
    BNE :+
      INC text_ptr+1     ; inc high byte if low byte wrapped

:   JSR @Save            ; Save string info (item price is a substring)
    TAX                  ; put item ID in X temporarily
    LDA #BANK_MENUS
    JSR SwapPRG_L        ; swap to bank (for PrintPrice routine)
    TXA                  ; get back the item ID
    JSR PrintPrice       ; print the price to temp string buffer
    JSR @StallAndDraw    ; recursivly draw it
    JMP @Restore         ; then restore original string state and continue

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Complex String save/restore [$E03E :: 0x3E04E]
;;
;;    Some format characters require a complex string to swap banks
;;  and start drawing a seperate string mid-job.  It calls this 'Save' routine
;;  before doing that, and then calls the 'restore' routine after it's done
;;
;;    Note that Restore does not RTS, but rather JMPs back to the text
;;  loop explicitly -- therefore you should JMP to it.. not JSR to it.
;;
;;    Note I'm still using local labels here ... this is still part of DrawComplexString  x_x
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

@Save:
    LDY text_ptr    ; back up the text pointer
    STY tmp_hi      ;  and the data bank
    LDY text_ptr+1  ;  to temporary RAM space
    STY tmp_hi+1
    LDY cur_bank    ; use Y, so as not to dirty A
    STY tmp_hi+2
    RTS

@Restore:
    LDA tmp_hi     ; restore text pointer and data bank
    STA text_ptr
    LDA tmp_hi+1
    STA text_ptr+1
    LDA tmp_hi+2
    STA cur_bank
    JSR SwapPRG_L      ; swap the data bank back in
    JMP @Draw_NoStall  ;  and continue with text processing
