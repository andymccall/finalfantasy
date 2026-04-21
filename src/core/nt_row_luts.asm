;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  [$DCF4 :: 0x3DD04]
;;
;;  These LUTs are used by routines to find the NT address of the start of each row
;;    Really, they just shortcut a multiplication by $20 ($20 tiles per row)
;;

lut_NTRowStartLo:
  .BYTE $00,$20,$40,$60,$80,$A0,$C0,$E0
  .BYTE $00,$20,$40,$60,$80,$A0,$C0,$E0
  .BYTE $00,$20,$40,$60,$80,$A0,$C0,$E0
  .BYTE $00,$20,$40,$60,$80,$A0,$C0,$E0

lut_NTRowStartHi:
  .BYTE $20,$20,$20,$20,$20,$20,$20,$20
  .BYTE $21,$21,$21,$21,$21,$21,$21,$21
  .BYTE $22,$22,$22,$22,$22,$22,$22,$22
  .BYTE $23,$23,$23,$23,$23,$23,$23,$23
