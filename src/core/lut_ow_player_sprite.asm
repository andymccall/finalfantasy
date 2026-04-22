;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Vehicle sprite Y coord LUT  [$E36A :: 0x3E37A]
;;
;;     Many of these bytes are unused/padding.

lut_VehicleSprY:
  .BYTE     $6C
  .BYTE $6C               ; on foot
  .BYTE $6F,$6F           ; canoe
  .BYTE $6F,$6F,$6F,$6F   ; ship
  .BYTE $4F               ; airship


;;  VehicleFacingSprTblOffset LUT  [$E417 :: 0x3E427]
;;
;;    The 'facing' byte is never zero -- so the first entry is bogus.  It will be
;;  1, 2, 4, or 8... but could be anywhere between 0-F if the player is pressing
;;  multiple directions at once.  In calculations for determining facing, low bits
;;  are given priority (ie:  if you're pressing up+right, you'll move right because
;;  right is bit 0).  To have the images match this priority, this table has been
;;  built appropriately

lut_VehicleFacingSprTblOffset:
  .BYTE $00,$00,$10,$00,$30,$00,$10,$00,$20,$00,$10,$00,$30,$00,$10,$00


;;  Player mapman sprite tables [$E427 :: 0x3E437]
;;
;;     Sprite tables for use with Draw2x2Sprite.  Used for drawing
;;  the player mapman.  There are eight 8-byte tables, 2 tables for
;;  each direction (1 for each frame of animation).

lut_PlayerMapmanSprTbl:
  .BYTE $09,$40, $0B,$41, $08,$40, $0A,$41   ; facing right, frame 0
  .BYTE $0D,$40, $0F,$41, $0C,$40, $0E,$41   ; facing right, frame 1
  .BYTE $08,$00, $0A,$01, $09,$00, $0B,$01   ; facing left,  frame 0
  .BYTE $0C,$00, $0E,$01, $0D,$00, $0F,$01   ; facing left,  frame 1
  .BYTE $04,$00, $06,$01, $05,$00, $07,$01   ; facing up,    frame 0
  .BYTE $04,$00, $07,$41, $05,$00, $06,$41   ; facing up,    frame 1
  .BYTE $00,$00, $02,$01, $01,$00, $03,$01   ; facing down,  frame 0
  .BYTE $00,$00, $03,$41, $01,$00, $02,$41   ; facing down,  frame 1
