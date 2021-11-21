cursorcode:
	.org mpLcdCursorImg
#include "opcodegen.asm"
	
draw_sprites_done:
draw_sprites_save_sp = $+1
	ld sp,0
	ret
	
; Input: A = current scanline
draw_sprites:
LCDC_1_smc = $
myspriteLY = $+1
	ld c,0			;ret when sprites disabled
	sub c
	ret z
LCDC_2_smc_4 = $+1
	add a,7			;add a,15 when 8x16 sprites
	ld (draw_sprite_height_smc_1),a
	ld a,c
LCDC_2_smc_5 = $+1
	add a,9			;add a,1 when 8x16 sprites
	ld (draw_sprite_top_smc),a
	ld (draw_sprites_save_sp),sp
	ld ix,$FEA4
draw_next_sprite:
	lea ix,ix-3
draw_next_sprite_2:
	dec ixl
	jr z,draw_sprites_done
	ld.s bc,(ix-4)
	dec b
	ld a,b
	cp 167
	jr nc,draw_next_sprite
	ld a,c
draw_sprite_top_smc = $+1
	sub 1
	ld e,a
draw_sprite_height_smc_1 = $+1
	sub 144 + 7
	jr nc,draw_next_sprite
	
	pea.s ix-3
scanlineLUT_sprite_ptr = $+1
	 ld hl,0
LCDC_2_smc_2 = $+1
	 ld c,7			;ld c,15 when 8x16 sprites
	 ld d,c
	 adc a,c
	 jr nc,_
	 xor c
	 ld c,a
_
	 ld a,e
	 sub d
	 jr nc,_
	 add a,c
	 ld c,a
	 ld a,e
	 xor d
	 add a,a
	 add a,a
	 add a,a
	 jr ++_
_
	 ld e,a
	 ld d,3
	 mlt de
	 add hl,de
	 xor a
_
	 ld sp,hl
	 
	 ld hl,vram_pixels_start
	 ld l,a
	 ld.s de,(ix-2)
	 inc c
	 ld ixl,c
	 ld c,e
	 ld a,b
	 ld b,64
LCDC_2_smc_3 = $+1
	 res 0,b		;res 0,c when 8x16 sprites
	 mlt bc
	 add hl,bc
	 
	 ld b,a
	 sub 7
	 jr nc,_
	 ld iyl,0
	 inc b
	 cpl
	 adc a,l
	 jr draw_sprite_clip_done
_	 
	 ld b,8
	 ld iyl,a
	 add a,256-152
	 jr nc,_
	 cpl
	 adc a,b
	 ld b,a
_
	 ld a,l
draw_sprite_clip_done:

	 ld iyh,b
	 
	 bit 4,d
scaling_mode_smc_1 = $+1
	 ld c,$03	;$33 in double scaling mode
	 jr z,_
	 sla c
_
	
	 bit 6,d
	 ld ixh,8
	 jr z,_
	 ld ixh,-8
LCDC_2_smc_1 = $+1
	 xor $38
_
	 
	 sla d
	 bit 6,d
	 jr c,draw_sprite_priority
	 jr nz,draw_sprite_flip
	
draw_sprite_normal_row:
	 pop de
	 ld l,a
	 ld a,iyl
	 add a,e
	 jr nc,_
	 ld e,$FF
	 inc de
_
	 ld e,a
draw_sprite_normal_pixels:
	 ld a,(hl)
	 add a,c
	 jr c,_
	 ld (de),a
_
	 inc de
	 inc l
	 djnz draw_sprite_normal_pixels
	 ld b,iyh
	 ld a,l
	 sub b
	 add a,ixh
	 dec ixl
	 jr nz,draw_sprite_normal_row
	pop.s ix
	jp draw_next_sprite_2
	
draw_sprite_flip:
	 xor 7
draw_sprite_flip_row:
	 pop de
	 ld l,a
	 ld a,iyl
	 add a,e
	 jr nc,_
	 ld e,$FF
	 inc de
_
	 ld e,a
draw_sprite_flip_pixels:
	 ld a,(hl)
	 add a,c
	 jr c,_
	 ld (de),a
_
	 inc de
	 dec l
	 djnz draw_sprite_flip_pixels
	 ld b,iyh
	 ld a,l
	 add a,b
	 add a,ixh
	 dec ixl
	 jr nz,draw_sprite_flip_row
	pop.s ix
	jp draw_next_sprite_2
	
draw_sprite_priority:
	 jr z,_
	 xor 7
_
	 ld l,a
	 sbc a,a
	 add a,$2D
	 ld (draw_sprite_priority_hdir),a
	 sbc a,a
	 and $10
	 add a,$80
	 ld (draw_sprite_priority_hdir_2),a
draw_sprite_priority_row:
	 pop de
	 ld a,iyl
	 add a,e
	 jr nc,_
	 ld e,$FF
	 inc de
_
	 ld e,a
draw_sprite_priority_pixels:
	 ld a,(de)
	 inc a
	 jr nz,_
	 ld a,(hl)
	 add a,c
	 jr c,_
	 ld (de),a
_
	 inc de
draw_sprite_priority_hdir:
	 inc l
	 djnz draw_sprite_priority_pixels
	 ld b,iyh
	 ld a,l
draw_sprite_priority_hdir_2:
	 sub b
	 add a,ixh
	 ld l,a
	 dec ixl
	 jr nz,draw_sprite_priority_row
	pop.s ix
	jp draw_next_sprite_2
	
_
	   call write_vram_check_sprite_catchup
	   jr _
write_vram_and_expand_catchup:
	 push bc
	  push de
	   bit 4,d
	   jr z,-_
	   call render_catchup
_
	  pop de
	  jr _
write_vram_and_expand_push:
	push hl
write_vram_and_expand:
	 push bc
_
	  ld hl,vram_base
	  add hl,de
	  ex af,af'
	  ld c,a
	  ex af,af'
	  ld a,(hl)
	  cp c
	  jr z,write_vram_no_change
	  ld (hl),c
	  ld a,d
	  add a,256-$98
	  jr nc,write_vram_pixels
	  ld h,a
	  ld a,e
	  and $E0
	  ld l,a
	  xor e
	  add a,a
	  add hl,hl
	  add hl,hl
	  add.s hl,hl
	  ld de,vram_tiles_start
	  ld e,a
	  add hl,de
	  ld de,64
	  ld b,e
	  mlt bc
	  ld (hl),c
	  inc hl
	  ld (hl),b
	  add hl,de
	  ld (hl),b
	  dec hl
	  ld (hl),c
	  add hl,de
	  ld a,b
	  add a,a
	  cpl
	  and e
	  or b
	  ld (hl),c
	  inc hl
	  ld (hl),a
	  add hl,de
	  ld (hl),a
	  dec hl
	  ld (hl),c
write_vram_no_change:
	 pop bc
	pop hl
	jp.sis z80_restore_swap_ret
write_vram_catchup:
	 push bc
	  ; Disable the normal return to z80 mode by using a false jump condition
	  ld a,$EA ;JP PE,
	  ld (write_vram_catchup_smc),a
	  ; Carry is set, which forces the written value to have bit 0 reset
write_vram_pixels:
	  ; Check if writing to the same slice as the last write
	  set 0,l
write_vram_last_slice = $+1
	  ld de,0
	  sbc hl,de
	  ; If equivalent, clear the last write slice
	  jr z,_
	  ; Otherwise, save the currently written slice
	  add hl,de
_
	  ld (write_vram_last_slice),hl
	  ; If the last slice was cleared, defer pixel generation
	  bit 0,e
	  jr z,write_vram_defer_pixels
	  ; Write pixels from the last slice
	  ex de,hl
	  ; Get the HIGH and low bitplanes with nibbles X and Y
	  ld b,(hl)  ;B=[X][Y]
	  dec hl
	  ld a,(hl)  ;A=[x][y]
	  add hl,hl
	  add hl,hl
	  ld de,vram_pixels_start-((vram_start*4) & $FFFFFF)
	  add hl,de
	  ex de,hl
	  rlca \ rlca \ rlca \ rlca  ;A=[y][x]
	  xor b   ;A=[X^y][Y^x]
	  ld c,a  ;C=[X^y][Y^x]
	  and $0F ;A=[0][Y^x]
	  xor b   ;A=[X][x]
	  ld hl,overlapped_pixel_index_lut
	  ld b,l  ;B=0
	  ld l,a  ;L=[X][x]
	  xor c   ;A=[y][Y]
	  rrca \ rrca \ rrca \ rrca  ;A=[Y][y]
	  ; Look up sequence of pixels for nibble X
	  ld l,(hl)
	  inc h
	  ; Copy 4 pixels to cached VRAM tile data
	  ld c,4
	  ldir
	  ld l,a  ;L=[Y][y]
	  ; Look up sequence of pixels for nibble Y
	  ld h,(overlapped_pixel_index_lut >> 8) & $FF
	  ld l,(hl)
	  inc h
	  ; Copy 4 pixels to cached VRAM tile data
	  ld c,4
	  ldir
write_vram_defer_pixels:
	 pop bc
	pop hl
write_vram_catchup_smc = $+1
	jp.sis z80_restore_swap_ret ;Replaced with JP PE when catching up
	ld a,$C3 ;JP
	ld (write_vram_catchup_smc),a
	jp (hl)
	
scanline_do_subtile:
	ld a,8
	sub b
	jr nc,_
	xor a
_
	pop.s bc
	add hl,bc
	ld c,a
	ld a,ixl
	sub c
	ret c
	ld b,0
	add hl,bc
	ld c,a
	inc c
	ldir
	ret
	
	
	; Input: B=Start X+8, A=Length-1, HL=pixel base pointer, DE=pixel output pointer, IY=scanline pointer, SPS=tilemap pointer
scanline_do_render:
	ld c,a
	and 7
	ld ixl,a
	xor c
	jr z,scanline_do_subtile
	ld c,a
	rrca
	rrca
	sub c
	add a,20*6
	ld (scanline_unrolled_smc),a
	ld sp,hl
	
	ld a,8
	sub b
	jr nc,_
	xor a
	ld b,8
_
	ld c,a
	ld a,b
	pop.s hl
	add hl,sp
	ld b,0
	add hl,bc
	ld c,a
	ldir
	ld a,8
scanline_unrolled_smc = $+1
	jr $+2
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl \ add hl,sp \ ld c,a \ ldir
	pop.s hl
	add hl,sp
	ld c,ixl
	inc c
	ldir
	
render_save_spl = $+1
	ld sp,0
	ret
	
cursorcodesize = $-mpLcdCursorImg
	.org cursorcode+cursorcodesize
	
	.echo "Cursor memory code size: ", cursorcodesize
	
palettecode:
	.org mpLcdPalette + 32
	
render_scanline_off:
	push de
	pop hl
	inc de
	ld bc,159
scaling_mode_smc_3 = $+1
	ld (hl),BG_COLOR_0	;*$11 in double scaling mode
	ldir
	jp render_scanline_next
	
; Catches up the renderer before changing an LCD register.
; Must be called only if the current frame is being rendered.
;
; Inputs:  (LY) = current scanline (0-143)
;          (STAT) = current mode (0, 2, 3)
;          AF' has been swapped
;          BCDEHL' have been swapped
; Outputs: Scanlines rendered if applicable
; Destroys: AF, DE, HL, IX
render_catchup:
	; Disable catch-up until at least one more scanline passes
	ld hl,hram_base+STAT
	ld a,(hl)
	cpl
	ld r,a
	; Set A to 1 if in hblank, 0 otherwise
	rrca
	and l ;$41
	; Get value of LY, plus 1 if in hblank
	ld l,LY & $FF
	add a,(hl)
	; Input: A=LY, should always be <=144
render_scanlines:
#ifdef DEBUG
	cp 145
	jr nc,$
#endif
myLY = $+1
	ld l,0
	sub l
	ret z
	ASSERT_NC
	push bc
	 ld b,a
	 ld c,l
	 push bc
render_scanlines_wait_smc = $+1
	  call sync_frame_flip
	 pop bc
	 ; Handle any deferred VRAM writes
	 ld a,(write_vram_last_slice)
	 rra
	 call c,write_vram_catchup
	 push iy
scanlineLUT_ptr = $+2
	  ld iy,0
	  ld.sis (render_save_sps),sp
	  ld a,vram_tiles_start >> 16
	  ld mb,a
	  or a
	  ld hl,-6
	  add hl,sp
	  ld (render_save_spl),hl
render_scanline_loop:
	  push bc
	   ; Get current scanline pointer from LUT
	   ld de,(iy)
	   lea iy,iy+3
	   
	   ; Zero flag is reset
LCDC_7_smc:
	   jr z,render_scanline_off
SCY_smc = $+1
	   ld l,0
	   add hl,bc
	   ld h,32
	   mlt hl
	   ld a,l
SCX_smc_1 = $+1
	   ld l,0
	
LCDC_4_smc = $+2
LCDC_3_smc = $+3
	   ld.sis sp,(vram_tiles_start & $FFFF) + $80
LCDC_0_smc = $+1
	   add.sis hl,sp
	   ld.sis sp,hl
	 
	   ld hl,vram_pixels_start
	   rrca
	   rrca
	   ld l,a
	   
SCX_smc_2 = $+1
	   ld b,8
	 
LCDC_5_smc:
	   ; Carry flag is reset
	   jr nc,scanline_no_window
	 
WY_smc = $+1
	   ld a,0
window_trigger_smc_1 = $
	   xor c ; Replaced with XOR A
WX_smc_1 = $
	   jr nz,scanline_no_window
	   
window_trigger_smc_2 = $
	   jr do_window_trigger ; Replaced with SUB B \ ADD A,n
WX_smc_2 = $
	   .db 0
	   call c,scanline_do_render
	 
window_tile_ptr = $+2
	   ld.sis sp,(vram_tiles_start & $FFFF) + $80	;(+$2000) (-$80)
	 
window_tile_offset = $+1
	   ld hl,vram_pixels_start
	   ld a,l
	   add a,8
	   cp 64
	   jr c,_
	   ld a,(window_tile_ptr+1)
	   inc a
	   ld (window_tile_ptr+1),a
	   xor a
_
	   ld (window_tile_offset),a
	 
WX_smc_3 = $+1
	   ld b,0
	 
scanline_no_window:
	   ld a,167
	   sub b
	   call scanline_do_render
	 
render_scanline_next:
	   ; Advance to next scanline
	  pop bc
	  inc c
	  djnz render_scanline_loop
	  ld (scanlineLUT_ptr),iy
	  ld a,c
	  ld (myLY),a
	  ; Restore important Z80 things
	  ld a,z80codebase >> 16
	  ld mb,a
	  ld.sis sp,(render_save_sps)
	 pop iy
	 call sync_frame_flip
	pop bc
	ret
	
do_window_trigger:
	   ld a,$AF ; XOR A
	   ld (window_trigger_smc_1),a
	   ld a,$90 ; SUB B
	   ld (window_trigger_smc_2),a
	   ld a,$C6 ; ADD A,n
	   ld (window_trigger_smc_2+1),a
	   jr window_trigger_smc_1
	
palettecodesize = $-mpLcdPalette
	.org palettecode+palettecodesize
	
	.echo "Palette memory code size: ", palettecodesize