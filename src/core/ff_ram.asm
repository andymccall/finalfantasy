; ---------------------------------------------------------------------------
; ff_ram.asm - FF1 RAM buffers allocated for host-side re-hosting.
; ---------------------------------------------------------------------------
; Names mirror the FF1 disassembly so extracted core routines reference
; them unchanged. Layout is flat on the host (no page-1 stack split, no
; NES-style zero-page scarcity), so anything that isn't actually used in
; an indirect-indexed addressing mode can sit in regular BSS.
; ---------------------------------------------------------------------------

.export cur_pal
.export box_x, box_y, box_wd, box_ht
.export dest_x, dest_y
.export ppu_dest
.export soft2000
.export menustall
.exportzp text_ptr                      ; must be ZP for (text_ptr),Y addressing
.exportzp clear_ptr                     ; scratch pointer used by clear_ram
.exportzp tmp                           ; must be ZP for (tmp),Y in Draw2x2Sprite
.export cur_bank, ret_bank
.export tmp_hi
.export char_index
.export format_buf
.export ch_name, ch_class, ch_ailments, ch_weapons, ch_armor, ch_spells
.export ptygen
.export namecurs_x, namecurs_y
.export name_selectedtile, name_cursoradd, name_buf
.export respondrate, cursor
.export joy, joy_a, joy_b, joy_start, joy_select, joy_prevdir, joy_ignore
.export spr_x, spr_y, sprindex
.export music_track
.export oam
.export intro_ataddr, intro_atbyte, intro_color
.export framecounter
.export startintrocheck
.export unk_FE, NTsoft2000

.export mapflags, mapdraw_x, mapdraw_y, mapdraw_ntx, mapdraw_nty, mapdraw_job
.export facing, move_speed, scroll_y, scroll_x
.export ow_scroll_x, ow_scroll_y, sm_scroll_x, sm_scroll_y
.export sm_player_x, sm_player_y, vehicle, cur_map
.export draw_buf_ul, draw_buf_ur, draw_buf_dl, draw_buf_dr, draw_buf_attr
.export draw_buf_at_hi, draw_buf_at_lo, draw_buf_at_msk
.export mapdata

.segment "ZEROPAGE"

; DrawComplexString reads the source string via LDA (text_ptr),Y so the
; pointer must live in zero page. Everything else that DrawComplexString
; touches is only loaded/stored directly, so the rest stays in BSS.
text_ptr:   .res 2

; clear_ram uses (clear_ptr),Y to sweep the BSS segment at boot. Lives
; in zero page so the indirect-indexed store is available; gets zeroed
; by the ZEROPAGE clear at the tail of clear_ram itself.
clear_ptr:  .res 2

; Draw2x2Sprite reads the sprite arrangement table via LDA (tmp),Y, so
; tmp has to sit in zero page. On the NES it's at $10..$1F; flat RAM
; here so any ZP address is fine. 16 bytes to match FF1's tmp+0..tmp+15.
tmp:        .res 16

.segment "BSS"

cur_pal:    .res 32       ; FF1 "current palette" -- 32 NES colour indices

; --- Box-drawing inputs / outputs ------------------------------------------
box_x:      .res 1        ; box draw: top-left X in tiles
box_y:      .res 1        ; box draw: top-left Y in tiles
box_wd:     .res 1        ; box draw: width in tiles (incl. borders)
box_ht:     .res 1        ; box draw: height in tiles (incl. borders)
dest_x:     .res 1        ; CoordToNTAddr input / DrawBox inner-body output
dest_y:     .res 1        ; CoordToNTAddr input / DrawBox inner-body output
ppu_dest:   .res 2        ; 16-bit PPU target address (low, high)

; --- Scratch / shadow registers --------------------------------------------
; (tmp lives in ZEROPAGE above -- Draw2x2Sprite needs (tmp),Y.)
soft2000:   .res 1        ; shadow of PPUCTRL, restored after menu draws
menustall:  .res 1        ; non-zero = MenuCondStall should wait a frame

; --- DrawComplexString state ----------------------------------------------
; cur_bank is the PRG bank DrawComplexString believes it's in; ret_bank is
; the bank to return to on exit. The host has no banking, so SwapPRG_L is a
; stub -- these slots just have to exist and be writable for the verbatim
; code to store into them.
cur_bank:   .res 1
ret_bank:   .res 1
tmp_hi:     .res 3        ; Save/Restore slots for text_ptr (2 bytes) + cur_bank
char_index: .res 1        ; character * $40 -- indexes ch_name/ch_class/etc.

; format_buf is written via format_buf-4 .. format_buf-1 when drawing a
; character name (stat code $00), so it needs four bytes of headroom
; immediately before it. The pad also doubles as scratch for other
; PrintGold/PrintCharStat/PrintPrice stubs that write into the buffer.
            .res 4        ; headroom for format_buf-4..format_buf-1 writes
format_buf: .res 16

; Character stat arrays. Each character occupies $40 bytes, so ch_name+X
; (with X = character*$40) reaches the relevant slot. DrawComplexString
; only indexes with X values produced by char_index, and the title screen
; text doesn't reference any of them -- these are sized minimally to keep
; the symbols resolvable.
ch_name:     .res $100    ; 4 chars/name * 4 chars * $40 stride
ch_class:    .res $100
ch_ailments: .res $100
ch_weapons:  .res $100
ch_armor:    .res $100
ch_spells:   .res $100

; --- Party-generation scratch --------------------------------------------
; 64 bytes, 16 per character. Field layout (from FF1's variables.inc) is
; defined as constants in pty_gen_shim where they're consumed.
ptygen:          .res 64

; --- Name-input scratch --------------------------------------------------
; namecurs_x/y track the letter-grid selection cursor (0..9 x 0..6).
; name_selectedtile / name_cursoradd / name_buf replace FF1's $10 / $63 /
; $5C hard-coded NES zero-page locals, which on our hosts would collide
; with KERNAL / firmware memory. Kept as plain BSS so the verbatim extract
; resolves via = aliases defined in pty_gen_shim.
namecurs_x:        .res 1
namecurs_y:        .res 1
name_selectedtile: .res 1
name_cursoradd:    .res 1
name_buf:          .res 5      ; 4 name tiles + null terminator

; --- Title-screen state ----------------------------------------------------
respondrate: .res 1        ; sound-effect speed setting, 0..7
cursor:      .res 1        ; title selection: 0 = Continue, 1 = New Game

; --- Joypad shadow ---------------------------------------------------------
; UpdateJoy samples the controller and populates these. On the host they
; stay zero until we ship a real joypad HAL; the title-screen loop just
; keeps spinning in that case, which matches our current behaviour.
joy:         .res 1        ; current-frame button bits
joy_a:       .res 1        ; A-button edge catcher (incremented on press)
joy_b:       .res 1        ; B-button edge catcher
joy_start:   .res 1        ; Start-button edge catcher
joy_select:  .res 1        ; Select-button edge catcher
joy_prevdir: .res 1        ; previous-frame direction bits
joy_ignore:  .res 1        ; per-button state used by ProcessJoyButtons to
                           ; distinguish press-from-released vs. held
                           ; (see the long comment in bank_0F.asm:5770+)

; --- Sprite build scratch --------------------------------------------------
; sprindex is the running byte-offset into oam. Draw2x2Sprite reads it,
; writes four sprite slots (16 bytes) starting at oam[sprindex], and
; adds 16. ClearOAM resets it to 0 at the top of each frame. Zero-page
; on the NES ($26); flat RAM here is fine, only loads/stores access it.
spr_x:       .res 1        ; sprite X
spr_y:       .res 1        ; sprite Y
sprindex:    .res 1        ; current byte offset into oam (0, 16, 32, ...)

; --- Music driver shadow ---------------------------------------------------
music_track: .res 1        ; desired track; written by IntroTitlePrepare,
                           ; consumed by the (stubbed) music driver

; --- OAM buffer ------------------------------------------------------------
; On the NES this is page-aligned RAM (typically $0200) so that
; STA $4014 with A=$02 DMAs the whole page to PPU OAM. Our $4014 hook is
; a no-op, so alignment doesn't matter -- we just need 256 bytes so the
; per-frame ClearOAM / DrawCursor writes land somewhere.
oam:         .res 256

; --- Intro-story animation state -------------------------------------------
; intro_ataddr walks 8-byte attribute-table blocks from $23C0 to $23F8.
; intro_atbyte is the byte written into all 8 positions of that block.
; intro_color cycles the "main" fade colour for IntroStory_AnimateRow.
; On the NES these live at $62/$63/$64 zero-page; flat RAM here.
intro_ataddr:    .res 1
intro_atbyte:    .res 1
intro_color:     .res 1

; Two-byte frame counter. IntroStory_AnimateRow INCs it each sub-frame,
; and the main overworld loop increments it too. Lives at $F0/$F1 on NES.
framecounter:    .res 2

; "Was this a cold boot?" marker. On the NES, RAM boots to garbage --
; GameStart compares this byte to $4D and, if unequal, treats the reset
; as cold, runs the intro, then writes $4D so warm resets skip it.
; clear_ram zeroes this on every run so we always take the cold path,
; which matches the user-visible expectation of a fresh boot.
startintrocheck: .res 1

; unk_FE is written by GameStart_L and never read. NTsoft2000 shadows
; soft2000 for coarse scrolling on the overworld. Neither is consulted
; by the title path we currently exercise, but the verbatim code stores
; into them so the slots must exist.
unk_FE:          .res 1
NTsoft2000:      .res 1

; --- Map-draw state --------------------------------------------------------
; mapflags layout (from FF1 bank_0F.asm map routines):
;   bit 0: 0 = overworld, 1 = standard map
;   bit 1: 0 = draw row, 1 = draw column
mapflags:    .res 1
mapdraw_x:   .res 1        ; map-space column of next tile to prep
mapdraw_y:   .res 1        ; map-space row of next tile to prep
mapdraw_ntx: .res 1        ; NT column target
mapdraw_nty: .res 1        ; NT row target
mapdraw_job: .res 1        ; 0 = idle, 1 = attrs pending, 2 = tiles pending
facing:      .res 1        ; player facing bits (1=R, 2=L, 4=D, 8=U)
move_speed:  .res 1        ; pixels per frame (0 = not moving)
scroll_y:    .res 1        ; NT row of top of viewport (0..14)
scroll_x:    .res 1        ; NT column of left of viewport (0..31)
ow_scroll_x: .res 1        ; OW map-space camera X (0..255)
ow_scroll_y: .res 1        ; OW map-space camera Y (0..255)
sm_scroll_x: .res 1        ; SM camera X (0..63)
sm_scroll_y: .res 1        ; SM camera Y (0..63)
sm_player_x: .res 1
sm_player_y: .res 1
vehicle:     .res 1        ; 0/1=foot, 2=canoe, 4=ship, 8=airship
cur_map:     .res 1        ; SM id; unused until SM path comes up

; --- Tile/attr drawing buffers --------------------------------------------
; PrepRowCol fills 16 bytes of ul/ur/dl/dr/attr; DrawMapRowCol draws 16 tiles
; across a row or 15 down a column. PrepAttributePos fills 16 ats for rows /
; 15 for columns. Kept to 16 each to match FF1's $0780..$07BF area.
draw_buf_ul:     .res 16
draw_buf_ur:     .res 16
draw_buf_dl:     .res 16
draw_buf_dr:     .res 16
draw_buf_attr:   .res 16
draw_buf_at_hi:  .res 16
draw_buf_at_lo:  .res 16
draw_buf_at_msk: .res 16

; --- mapdata buffer (MAPDATA segment, 4 KB aligned) -----------------------
; LoadOWMapRow writes decompressed rows into mapdata + (mapdraw_y & $0F)*256.
; Only 16 rows are cached at a time. PrepRowCol uses (mapdraw_y & $0F) |
; >mapdata for the source pointer high byte, so >mapdata must have its low
; nibble zero; the linker pins the region at $7000 (x16) / $E000 (neo).
.segment "MAPDATA"

mapdata:     .res $1000
