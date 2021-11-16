z80code:
	.assume adl=0
	.org 0
active_ints:
	.db 0
waitloop_sentinel:
	.db 0
	
	.block $08-$
r_mem:
	pop ix
	ex af,af'
	ld iyl,a
	jp decode_mem
	
	.block $10-$
r_bits:
	ld ixl,NO_CYCLE_INFO
	jp do_bits

	.block $18-$
r_event:
	exx
	push.l hl
	pop hl
	dec hl
	jp do_event

	.block $20-$
r_pop:
	ex af,af'
	exx
	inc b
do_pop_jump_smc_1 = $+1
	djnz do_pop_hmem
	jr do_pop_check_overflow
	
	.block $28-$
r_call:
	ex af,af'
	ld ix,(-call_stack_lower_bound) & $FFFF
	add ix,sp
	jr c,do_call
	call.il callstack_overflow_helper
	jr do_call
	
	;.block $30-$
	; Currently taken by previous entry
	
	.block $38-$
r_cycle_check:
rst38h:
	inc iyh
	ret nz
	ld iyl,a
	pop ix
	exx
	jr nc,cycle_overflow_for_jump
	ld c,(ix-3)
	ld de,(ix-7)
	inc ix
	push ix
#ifdef VALIDATE_SCHEDULE
	call.il schedule_subblock_event_helper
#else
	jp.lil schedule_subblock_event_helper
#endif
	
do_pop_check_overflow:
	ld c,a
	ld a,h
do_pop_bound_smc_1 = $+1
	cp 0
_
	jp p,do_pop_overflow
	ld a,c
do_pop_jump_smc_2 = $+1
	jr do_pop_hmem
do_pop_z80:
	bit 6,b
	jr nz,-_
	inc b
	ld ix,(hl)
	inc hl
	inc hl
	ex (sp),ix
	exx
	ex af,af'
	jp (ix)
	
do_pop_adl:
	ld.l ix,(hl)
_
	inc b
	inc.l hl
	inc.l hl
	ex (sp),ix
	exx
	ex af,af'
	jp (ix)
	
do_pop_rtc:
	ld ix,(sp_base_address)
	ld ix,(ix)
	ld ixh,ixl
	jr -_
	
do_pop_hmem:
	ld iyl,a
	; Advance the return address to the end of the instruction,
	; and execute the skipped pop opcode here in case it's overwritten
	pop de
	ld a,(de)
	ld (do_pop_hmem_smc),a
	inc de
	push de
	call pop_hmem
	push de
	 exx
do_pop_hmem_smc = $
	pop bc
	ret
	
cycle_overflow_for_jump:
	ld a,-3
	sub (ix-3)
	ld c,a
	ld de,(ix+4)
	ld ix,(ix+2)
	push ix
#ifdef VALIDATE_SCHEDULE
	call.il schedule_jump_event_helper_adjusted
#else
	jp.lil schedule_jump_event_helper_adjusted
#endif
	
do_call:
	pop ix
	exx
	ld de,(ix+3)
	add a,e ; Count cycles for taken CALL
	ld c,d  ; Cycles for taken RET
	ld de,(ix+5)  ; Game Boy return address
	pea ix+7  ; Cache JIT return address
	jr c,do_call_maybe_overflow
do_call_no_overflow:
	call do_push_for_call
	; BCDEHL' are swapped, D=cached stack offset, E=cached RET cycles
callstack_ret:
	ex af,af'
	ld c,a  ; Save cycle counter
	ld a,d  ; Compare the cached stack offset to the current one
	cp b
	jr nz,callstack_ret_stack_mismatch
callstack_ret_check_overflow_smc = $+1
	and $FF ; Check if the stack may be overflowing its bounds
	jr z,callstack_ret_bound
callstack_ret_nobound:
	ld a,e  ; Save the RET cycle count
	; Pop the return address into DE
callstack_ret_pop_prefix_smc_1 = $
	ld.l e,(hl)
	inc.l hl
callstack_ret_pop_prefix_smc_2 = $
	ld.l d,(hl)
	inc.l hl
	inc b   ; Increment the stack bound counter
callstack_ret_do_compare:
	; Save the GB stack pointer and get the cached return address.
	; The high byte of this address is non-zero if and only if
	; the mapped bank is different than when the call occurred.
	ex.l (sp),hl
	; Both compare the return addresses and ensure the bank has not changed.
	sbc.l hl,de
	jr nz,callstack_ret_target_mismatch
	add a,c  ; Count cycles
	jr c,callstack_ret_maybe_overflow
callstack_ret_no_overflow:
	pop.l hl  ; Restore GB stack pointer
	exx
	ex af,af'
	ret
	
do_call_maybe_overflow:
	inc iyh
	jr nz,do_call_no_overflow
	call cycle_overflow_for_call
	jr callstack_ret
	
callstack_ret_stack_mismatch:
	; Get the previous top of the stack
	ld ix,-4
	add ix,sp
	ld a,e  ; Get the requested cycles taken
	jp m,callstack_ret_skip
	; Restore the stack to that position, preserving the present values
	ld sp,ix
	ld iyl,c  ; Transfer the cycle count
	sub (ix)  ; Get the taken RET cycles
	add a,4
	ld c,a
	jr do_ret_full
	
do_rom_bank_call:
	ex af,af'
	exx
	ld c,a  ; Save cycle count
curr_rom_bank = $+1
	ld a,0  ; Get current bank
banked_call_common:
	ex.l de,hl
	ld hl,(-call_stack_lower_bound) & $FFFF
	add hl,sp
	jr nc,banked_call_stack_overflow
banked_call_stack_overflow_continue:
	pop hl  ; Get return address
	ld ix,(hl)  ; Get pointer to associated data
	inc hl
	inc hl
	cp (ix+4)  ; Validate the current bank
	jr nz,banked_call_mismatch
banked_call_mismatch_continue:
	ld a,c  ; Restore cycle count
	ld c,(hl)  ; Cycles for taken RET
	inc hl
	inc hl
	inc hl
	push hl  ; JIT return address
	dec hl
	dec hl
	ld hl,(hl)  ; Game Boy return address
	ex.l de,hl
	add a,(ix+3)  ; Count cycles for taken CALL
	jr nc,do_call_no_overflow
	inc iyh
	jr nz,do_call_no_overflow
	call cycle_overflow_for_call
	jr callstack_ret
	
callstack_ret_bound:
	ld a,h
do_pop_bound_smc_4 = $+1
	cp 0
callstack_ret_overflow:
	jp p,_callstack_ret_overflow
	or a
	jr callstack_ret_nobound

callstack_ret_target_mismatch:
	ld iyl,c  ; Transfer the cycle count
	; If the subtraction carried, the high byte of HL was definitely zero
	jr c,callstack_ret_bank_mismatch_continue
	; Check if the bank difference is non-zero
	add.l hl,de  ; Restore the original high byte while keeping carry clear
	ld c,h  ; Save the original middle byte in case propagation is needed
	ld h,d
	ld l,e
	sbc.l hl,de
	jr nz,callstack_ret_bank_mismatch
callstack_ret_bank_mismatch_continue:
	ld hl,-4
	sub l     ; Add 4 cycles for the RET itself
	add hl,sp ; Get the old stack pointer
	sub (hl)  ; Get the taken RET cycles
	ld c,a
	pop hl    ; Remove the cached JIT return address
	pop.l hl  ; Restore GB stack pointer
	jr do_ret_full_continue
	
callstack_ret_maybe_overflow:
	inc iyh
	jr nz,callstack_ret_no_overflow
	ld iyl,a
	; HL was 0, get the stack pointer and get the JIT target address
	add hl,sp
	ld ix,(hl)
	; Get the original cycle count (unmodified by conditional RET)
	dec hl
	dec hl
	dec hl
	dec hl
	ld a,(hl)
	sub 4  ; Subtract taken RET cycles to get the block cycle offset
	ld c,a
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_helper
#else
	jp.lil schedule_event_helper
#endif
	
ophandlerRET:
	ld sp,myz80stack-4  ; Restore the stack to above this default handler
	ld c,e  ; Save the taken cycle count (4=unconditional, 5=conditional)
	ex af,af'
	ld iyl,a  ; Save the cycle count
do_ret_full:
	inc b
do_pop_for_ret_jump_smc_1 = $+1
	djnz do_pop_for_ret_overflow
	ld a,h
do_pop_bound_smc_2 = $+1
	cp 0
	jp p,do_pop_for_ret_overflow
do_pop_for_ret_jump_smc_2 = $+1
	jr do_pop_for_ret_overflow
	
banked_call_stack_overflow:
	call.il callstack_overflow_helper
	jr banked_call_stack_overflow_continue
	
banked_call_mismatch:
	jp.lil banked_call_mismatch_helper
	
do_pop_for_ret_adl:
	inc b
	ld.l e,(hl)
	inc.l hl
	ld.l d,(hl)
	inc.l hl
do_ret_full_continue:
	push bc
	 call.il lookup_code_cached
	pop bc
	add a,c  ; Add the taken cycles for RET
	add a,iyl  ; Count cycles
	jr c,do_ret_full_maybe_overflow
do_ret_full_no_overflow:
	exx
	ex af,af'
	jp (ix)
	
callstack_ret_bank_mismatch:
	call.il callstack_ret_bank_mismatch_helper
	jr callstack_ret_bank_mismatch_continue
	
do_pop_for_ret_z80:
	bit 6,b
	jr nz,do_pop_for_ret_overflow
	inc b
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	jr do_ret_full_continue
	
do_pop_for_ret_overflow:
	call pop_overflow
	ex af,af'
	exx
	pop de
	jr do_ret_full_continue
	
do_ret_full_maybe_overflow:
	inc iyh
	jr nz,do_ret_full_no_overflow
	push.l hl
	; Get the total number of taken cycles
	ex de,hl
	ld e,iyl
	ld iyl,a
	sub e
	sub c ; Subtract out taken cycles from RET itself
	ld c,a
	ex de,hl  ; Clears top byte of DE
	push ix
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_helper
#else
	jp.lil schedule_event_helper
#endif
	
callstack_ret_skip:
	sub (ix) ; Get the conditional RET cycle offset
	inc sp  ; Skip the JIT return address
	inc sp
	pop de  ; Prepare the next return inputs
	add a,e ; Add the conditional offset
	ld e,a
	; Skip the Game Boy return address, but make sure
	; to propagate any bank mismatch
	inc.l sp
	pop.l af
	dec.l sp
	or a
	jr nz,callstack_ret_skip_propagate
	ld a,c  ; Restore the cycle counter
	ex af,af'
	ret
	
callstack_ret_skip_propagate:
	; Get the full return address
	dec.l sp
	dec.l sp
	dec.l sp
	 ex.l (sp),hl
	 call.il callstack_ret_skip_propagate_helper
	pop.l hl
	ex af,af'
	ret
	
_callstack_ret_overflow:
	push de  ; Save the requested RET taken cycles
	dec sp
	dec sp   ; Preserve the original RET taken cycles
	call pop_overflow_for_callstack_ret
	ex af,af'
	exx
	ld c,iyl ; Restore the cycle count
	pop de  ; Get popped GB address
	inc sp
	pop af  ; Pop requested taken cycles into A
	inc sp
	or a
	jp callstack_ret_do_compare
	
cycle_overflow_for_call:
	ld iyl,a
	dec b
	push bc
	inc b
	push ix
	push de
	dec de
	dec de
	ld a,(ix+3)
	sub 6
	ld c,a
	ld ix,(ix+1)
#ifdef VALIDATE_SCHEDULE
	call.il schedule_call_event_helper
#else
	jp.lil schedule_call_event_helper
#endif
	
cycle_overflow_for_bridge:
	inc iyh
	ret nz
	ld iyl,a
	pop ix
	exx
	ld c,(ix-4)
	ld de,(ix+4)
	ld ix,(ix+2)
	push ix
	push.l hl
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_helper
#else
	jp.lil schedule_event_helper
#endif
	
do_overlapped_jump:
	ex af,af'
	pop ix
	add a,(ix+4)
	jr c,++_
_
	ex af,af'
	jp (ix)
_
	inc iyh
	jr nz,--_
	exx
	ld d,(ix+4)
	jr do_slow_jump_overflow_common
	
do_rom_bank_jump:
	ex af,af'
	exx
	ld c,a
	pop ix
rom_bank_check_smc_1 = $+1
	ld a,0
	ld de,(ix+3)
	cp e
	jr nz,banked_jump_mismatch
	ld a,d
banked_jump_mismatch_continue:
	add a,c
	jr c,++_
_
	exx
	ex af,af'
	jp (ix)
_
	inc iyh
	jr nz,--_
do_slow_jump_overflow_common:
	ld iyl,a
	ld a,d
	add a,(ix+5)
	ld c,a
	sub d
	ld de,(ix+6)
	ld ix,(ix+1)
	push ix
#ifdef VALIDATE_SCHEDULE
	call.il c,schedule_slow_jump_event_helper
	push.l hl
	call.il schedule_event_helper
#else
	jp.lil c,schedule_slow_jump_event_helper
	push.l hl
	jp.lil schedule_event_helper
#endif
	
banked_jump_mismatch:
	jp.lil banked_jump_mismatch_helper
	
schedule_event_finish:
	ld (event_cycle_count),a
	ld (event_gb_address),hl
#ifdef DEBUG
	ld a,(event_address+1)
	cp (event_value >> 8) + 1
	jr nc,$
#endif
	lea hl,ix
	ld (event_address),hl
	ld a,(hl)
	ld (event_value),a
	ld (hl),RST_EVENT
	ld a,iyl
schedule_event_finish_no_schedule:
	ex af,af'
	pop.l hl
	exx
	ret
	
do_push_for_call_overflow:
	push ix
do_push_overflow:
	ld iyl,c
	ex af,af'
	push af
	 ld b,e	; B' can be used for safe storage, since set_gb_stack restores it
	 ld a,d
	 ld de,(sp_base_address_neg)
	 add hl,de
	 push hl
	  exx
	  ex (sp),hl
	  dec hl
	  ld ixl,NO_CYCLE_INFO - 1
	  call mem_write_any
	  exx
	  ld a,b
	  exx
	  dec hl
	  ld ixl,NO_CYCLE_INFO
	  call mem_write_any
	  ex (sp),hl
	  exx
	 pop hl
	 jr set_gb_stack_pushed

do_pop_overflow:
	ld iyl,c
	; Advance the return address to the end of the instruction,
	; and execute the skipped pop opcode here in case it's overwritten
	pop de
	ld a,(de)
	ld (do_pop_overflow_smc),a
	inc de
	push de
	call pop_overflow
do_pop_overflow_smc = $
	pop bc
	ret

pop_overflow_for_callstack_ret:
	ld iyl,c  ; Make the full cycle count available
	ld c,e  ; Make the requested cycles available
pop_overflow:
	push bc
	 ld de,(sp_base_address_neg)
	 add hl,de
	 push hl
	  exx
	  ex (sp),hl
	  ld ixl,(NO_CYCLE_INFO - 1) | NO_RESCHEDULE
	  call mem_read_any_before_write
	  inc hl
	  push af
	   ld ixl,NO_CYCLE_INFO | NO_RESCHEDULE
	   call mem_read_any
	  pop ix
	  ld ixl,ixh
	  ld ixh,a
	  inc hl
	  ex (sp),hl
	  exx
	 pop hl
	pop bc
	ex (sp),ix
	push ix
	ld a,iyl
	ex af,af'

; Get a literal 24-bit pointer to the Game Boy stack.
; Does not use a traditional call/return, must be jumped to directly.
;
; This routine is invoked whenever SP is set to a new value which may be outside
; its current bank. If the bank has changed, any relevant stack routines are modified.
;
; Inputs:  HL = 16-bit Game Boy SP
;          BCDEHL' have been swapped
; Outputs: HL' = 24-bit literal SP
;          B' = stack overflow counter
;          C' is preserved, IX is destroyed
;          BCDEHL' have been unswapped
;          SMC applied to stack operations
set_gb_stack:
	push af
set_gb_stack_pushed:
	 ; Get memory region, 0-7
	 ; This is the same as memroutines, except $FFFF is included in region 0 because
	 ; accesses would always be handled by the overflow handler
	 ld a,h
	 cp $FE
	 jr c,_
	 rrca
	 and l
	 rrca
	 cpl
	 and $40
	 jr ++_
_
	 and $E0
	 jp m,_
	 set 5,a
_
curr_gb_stack_bank = $+1
	 cp 1	; Default value forces a mismatch
	 jr nz,set_gb_stack_bank
	 or a
set_gb_stack_bank_done:
	 ; Calculate the new stack bound counter
	 ld a,h
	 rra
	 ld a,l
	 rra
	 jr nz,_
	 ; Special-case for HRAM, base the counter at $FF80
	 and $3F
_
	 inc a
	 ; Put the direct stack pointer in HL'
sp_base_address = $+2
	 ld.lil de,0
	 add.l hl,de
	 ; Put the new stack bound counter in B'
	 ld b,a
	 exx
	pop af
	ret

set_gb_stack_bank:
	ld (curr_gb_stack_bank),a
	push bc
	 call.il set_gb_stack_bounds_helper
	 call.il set_gb_stack_bank_helper
	pop bc
	jr set_gb_stack_bank_done
	
resolve_mem_cycle_offset_for_events:
	push.l hl
	 call resolve_mem_cycle_offset
	 add a,iyl
	 jr c,resolve_mem_cycle_offset_for_events_continue
	pop.l hl
	ret
	
	; Check if an event was scheduled at or before the current memory cycle
	; Inputs: IY = cycle count at end of block (only call when IYH=0)
	;         IXL = block-relative cycle offset (negative) or NO_CYCLE_INFO
	;         A = 0
	; Destroys: AF, DE, C
handle_events_for_mem_access:
	or ixl
	jp p,resolve_mem_cycle_offset_for_events
	add a,iyl
	ret nc
	push.l hl
resolve_mem_cycle_offset_for_events_continue:
	; Advance the cycle offsets to after the current cycle
	cpl
	ld c,a
	ld hl,event_cycle_count
	add a,(hl)
	ld (hl),a
	ASSERT_C
	ld a,ixl
	cpl
	ld iyl,a
	
	; Save and override the terminating event counter checker, preventing interrupt dispatch
	ld hl,event_counter_checkers_ei_delay
	ld de,(hl)
	push de
	 ld de,event_expired_for_mem_access_loop
	 ld (hl),de
	 jr do_event_pushed_noassert
	
event_expired_for_mem_access_loop:
	  ld sp,(event_save_sp)
	  ld h,b
	  ld l,c
	 pop bc
	 ; Check if there are more events before the memory access
	 inc d
	 jr nz,_
	 ld a,c
	 sub e
	 jr nc,event_expired_for_mem_access_more_events
_
	 ; Advance the next event time to after the current cycle
	 ld a,l
	 sub c
	 ld l,a
	 jr c,_
	 inc h
_
	 ld i,hl
	pop hl
	; Restore the terminating event counter checker
	ld (event_counter_checkers_ei_delay),hl
	pop.l hl
	ret
	
start_emulation:
	call set_gb_stack
	ex af,af'
	exx
	push.l hl
	jr event_not_expired
	
do_event:
event_value = $+1
	ld (hl),0
	push hl
#ifdef DEBUG
	ld hl,event_value
	ld (event_address),hl
#endif
	ex af,af'
event_cycle_count = $+2
	ld iyl,0
	sub iyl
	ASSERT_NC
	ld c,a
do_event_pushed:
#ifdef DEBUG
	inc iyh
	dec iyh
	jr nz,$
#endif
do_event_pushed_noassert:
	push bc

	 ; Check scheduled events
	 ld (event_save_sp),sp
event_expired_halt_loop:
	 ld hl,i ; This clears the carry flag
event_expired_loop:
	 ld sp,event_counter_checkers

	 ld b,h
	 ld c,l
ppu_counter = $+1
	 ld de,0
	 adc hl,de
	 ret z
	 ex de,hl
ppu_scheduled:
	 inc sp
	 inc sp
audio_counter_checker:
audio_counter = $+1
	 ld hl,0
	 or a
	 sbc hl,bc
	 jp z,audio_expired_handler
	 add hl,de
	 ret c
	 ex de,hl
	 sbc hl,de
	 ex de,hl
	 ret

event_expired_for_mem_access_more_events:
	 ld c,a
	 push bc
	 dec d
event_expired_more_events:
	 or a
	 sbc hl,de
	 or a
	 jr event_expired_loop

cpu_continue_halt:
	 ld iy,0
	 jr event_expired_halt_loop

schedule_ei_delay:
	 ; Force an event after one GB cycle
	 ld de,-1
	 ; Overwrite the function pointer with the following code,
	 ; which will run after the one GB cycle elapses
	 call event_counter_checkers_done
schedule_ei_delay_startup:
	 ; Enable interrupts
	 ld a,trigger_interrupt - (intstate_smc_2 + 1)
	 ld (intstate_smc_2),a
	 ; Restore the default counter checker end pointer
	 call event_counter_checkers_done
event_counter_checkers_done:
	 ld h,b
	 ld l,c
	 add iy,de
	 jr c,event_expired_more_events
	 sbc hl,de
	 ld i,hl
event_save_sp = $+1
	 ; Use this initial value in case an interrupt happens when loading a save state
	 ld sp,myz80stack-4-4
	pop bc
event_not_expired:
	ld hl,(IE)
	ld a,l
	and h
intstate_smc_2 = $+1
	jr nz,trigger_interrupt
cpu_halted_smc = $
	ld a,iyl
	add a,c
	jr c,event_maybe_reschedule
event_no_reschedule:
	pop.l hl
	exx
	ex af,af'
	ret
	
cpu_exit_halt_no_interrupt:
	xor a
	ld (intstate_smc_2),a
	ld hl,$7DFD ; LD A,IYL
	ld (cpu_halted_smc),hl
	jr cpu_halted_smc
	
event_maybe_reschedule:
	inc iyh
	jr nz,event_no_reschedule
	ld iyl,a
	ld de,(event_gb_address)
	pop ix
	push ix
	; This is guaranteed to carry, so the event cannot be now
	sub c
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_later
#else
	jp.lil schedule_event_later
#endif
	
trigger_int_callstack_overflow:
	pop.l hl
	call.il callstack_overflow_helper
	push.l hl
	; Just in case the dispatch is retried, save the adjusted event SP
	push bc
	 ld (event_save_sp),sp
	pop bc
	ASSERT_NC
	sbc hl,hl ;active_ints
	scf
	jr trigger_int_selected
	
trigger_interrupt_retry_dispatch:
	; Count the full dispatch cycles again, without causing another retry
	lea iy,iy-4
	; Skip the first SMC for disabling interrupts and the RET cycle
	; count adjustment, which have already been done
	ld e,a
	jr trigger_interrupt_retry_dispatch_continue
	
cpu_exit_halt_trigger_interrupt:
	ld de,$7DFD ; LD A,IYL
	ld (cpu_halted_smc),de
trigger_interrupt:
	ld e,a
	; Disable interrupts
	ld a,$08 ;EX AF,AF'
	ld (intstate_smc_1),a
	; Get the number of cycles to be taken by RET
	rrca	;ld a,4
	add a,c
	ld c,a
trigger_interrupt_retry_dispatch_continue:
	; More disabling interrupts
	xor a
	ld (intstate_smc_2),a
	; Get the lowest set bit of the active interrupts
	sub e
	and e
	; Clear the IF bit
	xor h
	ld e,a
	; Index the dispatch routines by the interrupt bit times 4
	xor h
	add a,a
	add a,a
	ld ixl,a
	ld ixh,dispatch_vblank >> 8
	; Check for callstack overflow
	ld hl,(-call_stack_lower_bound) & $FFFF
	add hl,sp
	jr nc,trigger_int_callstack_overflow
	ld l,h ;active_ints
trigger_int_selected:
	; Save the new IF value
	ld (hl),e
event_gb_address = $+1
	ld de,event_gb_address
	; Get number of cycles to be taken, minus 1
	ld a,(ix+3)
	ASSERT_C
	adc a,iyl ; Carry is set, to add additional cycle over RST cache
	jr c,dispatch_int_maybe_overflow
dispatch_int_no_overflow:
	pop.l hl
	call do_push_for_call
callstack_reti:
	jp callstack_ret
	
dispatch_int_maybe_overflow:
	inc iyh
	jr nz,dispatch_int_no_overflow
	; Check if an event was scheduled during the first 4 cycles of dispatch
	lea hl,iy+4
	ld iyl,a
	sbc a,l ; Carry is set
	jr nc,dispatch_int_handle_events
	; Push the special return value used as a sentinel
	ld hl,callstack_reti
	push hl
cycle_overflow_for_rst_or_int:
	dec b
	push bc
	inc b
	ld c,a
	push ix
	push de
	lea hl,ix+(10*4)
	srl l
	ld de,(hl)
	ld ix,(ix+1)
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_helper_for_call
#else
	jp.lil schedule_event_helper_for_call
#endif
	
dispatch_int_handle_events:
	; Set IY to the 4-cycle-added value
	ld a,l
	ld iyl,a
	; Restore the original value of IF
	ld a,ixl
	rrca
	rrca
	ASSERT_NC
	sbc hl,hl ;active_ints
	or (hl)
	ld (hl),a
	; Set the restoring interrupt trigger
	ld a,trigger_interrupt_retry_dispatch - (intstate_smc_2 + 1)
	ld (intstate_smc_2),a
	 ; The correct SP restore value is already saved, so enter the loop directly
	push bc
	 jp event_expired_halt_loop
	
ppu_mode2_line_0_lyc_match:
	; The LYC match bit was already set by the scheduled LYC event
	; Just transition from mode 1 to mode 2
	inc a
	ld (hl),a
	; Check for mode 1 or LYC blocking
	tst a,$50
	jr nz,ppu_mode2_continue
	sbc hl,hl ;ld hl,active_ints
	set 1,(hl)
	dec h
	jr ppu_mode2_continue
	
ppu_expired_mode2_line_0:
	ld hl,ppu_expired_mode2
	push hl
	inc sp
	inc sp
	; Check if LYC is 0
	ld hl,LYC
	ld a,h ;$FF
	ld (ppu_mode2_LY),a
	and (hl)
	ld l,STAT & $FF
	ld a,(hl)
	jr z,ppu_mode2_line_0_lyc_match
	; Check for mode 1 blocking
	bit 4,a
	jr nz,ppu_mode2_blocked_fast
	sbc hl,hl ;ld hl,active_ints
ppu_expired_mode2:
	; Request STAT interrupt
	set 1,(hl) ;active_ints
ppu_mode2_blocked:
	; Set mode 2
	ld hl,STAT
	ld a,(hl)
ppu_mode2_blocked_fast:
	and $F8
	or 2
	ld (hl),a
ppu_mode2_continue:
	; Allow catch-up rendering if this frame is not skipped
ppu_mode2_enable_catchup_smc = $+1
	ld r,a
	ld l,-MODE_2_CYCLES
	add hl,de
	ld (nextupdatecycle_STAT),hl
	ld hl,-CYCLES_PER_SCANLINE
	ex de,hl
	add hl,de
	ld (nextupdatecycle_LY),hl
	ld (ppu_counter),hl
ppu_mode2_LY = $+1
	ld a,0
	inc a
	ld (ppu_mode2_LY),a
	ld (LY),a
ppu_mode2_event_line = $+1
	cp 0
	jp nz,audio_counter_checker
	ld hl,STAT
	; Check whether vblank should be scheduled immediately
	cp 143
	jr z,ppu_mode2_prepare_vblank
	; Set next line event to vblank
	ld a,143
	ld (ppu_mode2_event_line),a
	; Set LYC coincidence bit
	set 2,(hl)
	; Block mode 2 interrupt after LYC coincidence, if enabled
	bit 6,(hl)
	jp z,audio_counter_checker
	call ppu_scheduled
	
ppu_expired_mode2_lyc_blocking:
	ld hl,ppu_expired_mode2
	push hl
	inc sp
	inc sp
	jr ppu_mode2_blocked
	
ppu_expired_mode0_line_0:
	xor a
	ld (ppu_mode0_LY),a
	ld hl,LYC
	or (hl)
	jr z,ppu_expired_mode0_lyc_match
	ld hl,ppu_expired_mode0
	push hl
	inc sp
	inc sp
	sbc hl,hl ;ld hl,active_ints
ppu_expired_mode0:
	; Request STAT interrupt
	set 1,(hl) ;active_ints
	; Set mode 0
	ld hl,STAT
	ld a,(hl)
	and $F8
	ld (hl),a
ppu_mode0_blocked:
	; Allow catch-up rendering if this frame is not skipped
ppu_mode0_enable_catchup_smc = $+1
	ld r,a
	ld l,-MODE_0_CYCLES
	add hl,de
	ld (nextupdatecycle_STAT),hl
	ld (nextupdatecycle_LY),hl
	ld hl,-CYCLES_PER_SCANLINE
	ex de,hl
	add hl,de
	ld (ppu_counter),hl
ppu_mode0_LY = $+1
	ld a,0
	ld (LY),a
	inc a
	ld (ppu_mode0_LY),a
ppu_mode0_event_line = $+1
	cp 0
	jp nz,audio_counter_checker
	; Check whether vblank should be scheduled immediately
	cp 144
	jr z,ppu_mode0_prepare_vblank
	call ppu_scheduled
	
ppu_expired_mode0_lyc_match:
	ld hl,ppu_expired_mode0
	push hl
	inc sp
	inc sp
	; Set next line event to vblank
	ld a,144
	ld (ppu_mode0_event_line),a
	; Set mode 0 and LYC coincidence bit
	ld hl,STAT
	ld a,(hl)
	and $F8
	or 4
	ld (hl),a
	; Block mode 0 interrupt during LYC coincidence, if enabled
	bit 6,a
	jr nz,ppu_mode0_blocked
	; Request STAT interrupt
	sbc hl,hl ;ld hl,active_ints
	set 1,(hl)
	dec h
	jr ppu_mode0_blocked
	
ppu_mode2_prepare_vblank:
	; Check if LYC matches during active video
	ld a,(LYC)
	cp 143
	jr c,_
	jr nz,ppu_expired_pre_vblank
	; If LYC is on line 143, set coincidence bit
	set 2,(hl)
_
	; Set next line event to LYC
	ld (ppu_mode2_event_line),a
	jr ppu_expired_pre_vblank
	
ppu_mode0_prepare_vblank:
	; Reset scheduled time and offset
	sbc hl,de
	ld e,-MODE_0_CYCLES
	add hl,de
	ld (ppu_counter),hl
	; Check if LYC matches during active video
	ld a,(LYC)
	cp 144
	jr nc,ppu_expired_pre_vblank
	; Set next line event to LYC
	ld (ppu_mode0_event_line),a
	jr ppu_expired_pre_vblank
	
ppu_expired_lyc_mode2:
	; Set LY to LYC
	ld hl,LYC
	ld a,(hl)
	dec hl
	ld (hl),a
	; Set STAT to mode 2 with LY=LYC bit set
	ld l,STAT & $FF
	ld a,(hl)
	or $07
	dec a
	ld (hl),a
	; Allow catch-up rendering if this frame is not skipped
ppu_lyc_enable_catchup_smc = $+1
	ld r,a
	; Set interrupt bit, if LYC interrupt is enabled
	bit 6,a
	jr z,_
	sbc hl,hl ;ld hl,active_ints
	set 1,(hl)
	dec h
_
	; Set LY/STAT caches
	ld l,-MODE_2_CYCLES
	add hl,de
	ld (nextupdatecycle_STAT),hl
	ld hl,-CYCLES_PER_SCANLINE
	add hl,de
	ld (nextupdatecycle_LY),hl
	; Set next scheduled time to vblank
	ld hl,(vblank_counter)
	add hl,de
	ex de,hl
	or a
	sbc hl,de
	ld (ppu_counter),hl
	add hl,bc
	ex de,hl
ppu_expired_pre_vblank:
	call ppu_scheduled
	
ppu_expired_vblank:
	; Always trigger vblank interrupt
	set 0,(hl) ;active_ints
	; Set LY to 144
	ld hl,LY
	ld a,144
	ld (hl),a
	; Check for either a LYC match or an LYC block
	inc hl
	sub (hl)
	sub 2
	inc a
	ld l,STAT & $FF
	ld a,(hl)
	jr c,ppu_vblank_lyc_close_match
	; Set mode 1
	and $F8
	inc a
	ld (hl),a
	; Check for mode 1 or mode 2 interrupt enable
	tst a,$30
	jr nz,ppu_vblank_mode1_int
ppu_vblank_stat_int_continue:
	; Set next LY/STAT update to scanline 145
	ld l,-CYCLES_PER_SCANLINE
	add hl,de
	ld (nextupdatecycle_LY),hl
	ld (nextupdatecycle_STAT),hl
ppu_expired_lcd_off:
	; Set the next vblank start time
	ld hl,CYCLES_PER_FRAME
	add hl,bc
	ld (vblank_counter),hl
	; Save a persistent time by which the next vblank must occur,
	; in case the LCD is toggled on and off
	ld (persistent_vblank_counter),hl
	; Set the next event time and handler
ppu_post_vblank_event_offset = $+1
	ld hl,-CYCLES_PER_FRAME
	ex de,hl
	add hl,de
	ld (ppu_counter),hl
ppu_post_vblank_event_handler = $+1
	ld hl,ppu_expired_vblank
	push hl
	jp.lil vblank_helper
	
ppu_vblank_lyc_close_match:
	jr nz,ppu_vblank_lyc_match
	; LYC=143 case
	; Set mode 1
	and $F8
	inc a
	ld (hl),a
	; Check for mode 1 or mode 2 interrupt enable
	tst a,$30
	jr z,ppu_vblank_stat_int_continue
	; Check for STAT block
	bit 6,a
	jr nz,ppu_vblank_stat_int_continue
ppu_vblank_mode1_int:
	; Check for mode 0 block
	bit 3,a
	jr nz,ppu_vblank_stat_int_continue
	; Trigger STAT interrupt
	sbc hl,hl ;ld hl,active_ints
	set 1,(hl)
	dec h
	jr ppu_vblank_stat_int_continue
	
ppu_vblank_lyc_match:
	; LYC=144 case
	; Set mode 1 with LY=LYC bit
	and $F8
	or 5
	ld (hl),a
	; Check for mode 0 block
	bit 3,a
	jr nz,ppu_vblank_stat_int_continue
	; Check for either mode 1, mode 2, or LY=LYC interrupt enable
	and $70
	jr z,ppu_vblank_stat_int_continue
	; Trigger STAT interrupt
	sbc hl,hl ;ld hl,active_ints
	set 1,(hl)
	dec h
	jr ppu_vblank_stat_int_continue
	
ppu_expired_lyc_mode1:
	; Set LY to LYC
	ld hl,LYC
	ld a,(hl)
	dec hl
	ld (hl),a
	; Set STAT to mode 1 with LY=LYC bit set
	ld l,STAT & $FF
	ld a,(hl)
	and $F8
	or $05
	ld (hl),a
	; Set LY/STAT caches
ppu_lyc_scanline_length_smc = $+1
	ld l,-CYCLES_PER_SCANLINE
	add hl,de
	ld (nextupdatecycle_LY),hl
	ld (nextupdatecycle_STAT),hl
	; Prepare next event
ppu_post_mode1_lyc_event_handler = $+1
	ld hl,0
	push hl
	inc sp
	inc sp
ppu_post_mode1_lyc_event_offset = $+1
	ld hl,0
	ex de,hl
	add hl,de
	ld (ppu_counter),hl
	; Check if LY=LYC interrupt is enabled and not blocked by mode 1 interrupt
	xor $40
	and $50
	jp nz,audio_counter_checker
	; If so, trigger LYC interrupt
	sbc hl,hl ;ld hl,active_ints
	set 1,(hl)
	jp audio_counter_checker
	
timer_counter_checker:
timer_counter = $+1
	ld hl,0
	or a
	sbc hl,bc
	jr z,timer_expired_handler
	add hl,de
	ret c
	ex de,hl
	sbc hl,de
	ex de,hl
	ret
	
timer_expired_handler:
	set 2,(hl) ;active_ints
timer_period = $+1
	ld hl,0
	; If scheduled for 65536 cycles in the future, no need to reschedule
	; Returning here prevents the delay from being interpreted as 0
	add hl,hl
	ret c
	add hl,bc
	ld (timer_counter),hl
	or a
	sbc hl,bc
	add hl,de
	ret c
	ex de,hl
	sbc hl,de
	ex de,hl
	ret
	
audio_expired_handler:
	ld.lil a,(mpLcdMis)
	or a
	jr nz,do_frame_interrupt
frame_interrupt_return:
	ld a,(NR52)
	tst a,$0F
	jr z,audio_expired_disabled
	push.l bc
	 ld h,audio_port_value_base >> 8
	 ld b,$3F
	 ld c,a
	 rra
	 jr nc,++_
	 ld l,NR14-ioregs
	 bit 6,(hl)
	 jr z,++_
	 ld l,NR11-ioregs
	 ld a,(hl)
	 inc a
	 tst a,b
	 jr nz,_
	 dec c
	 sub $40
_
	 ld (hl),a
_
	 bit 1,c
	 jr z,++_
	 ld l,NR24-ioregs
	 bit 6,(hl)
	 jr z,++_
	 ld l,NR21-ioregs
	 ld a,(hl)
	 inc a
	 tst a,b
	 jr nz,_
	 res 1,c
	 sub $40
_
	 ld (hl),a
_
	 bit 2,c
	 jr z,_
	 ld l,NR34-ioregs
	 bit 6,(hl)
	 jr z,_
	 ld l,NR31-ioregs
	 inc (hl)
	 jr nz,_
	 res 2,c
_
	 bit 3,c
	 jr z,_
	 ld l,NR44-ioregs
	 bit 6,(hl)
	 jr z,_
	 ld l,NR41-ioregs
	 ld a,(hl)
	 inc a
	 and b
	 ld (hl),a
	 jr nz,_
	 res 3,c
_
	 ld a,c
	 ld (NR52),a
	pop.l bc
audio_expired_disabled:
	ld a,b
	add a,4096 >> 8	; Double this in double-speed mode
	ld (audio_counter+1),a
	sub b
	add a,d
	ret c
	ld de,-4096	; Double this in double-speed mode
	ret

do_frame_interrupt:
	jp.lil frame_interrupt

serial_counter_checker:
serial_counter = $+1
	ld hl,0
	or a
	sbc hl,bc
	jr z,serial_expired_handler
	add hl,de
	ret c
	ex de,hl
	sbc hl,de
	ex de,hl
	ret
	
serial_expired_handler:
	set 3,(hl) ;active_ints
	dec h
	inc hl ;SB
	ld (hl),h ;$FF
	inc hl ;SC
	res 7,(hl)
	call disabled_counter_checker
disabled_counter_checker:
	ret
	
decode_mem:
	ld a,(memroutine_next)
	sub ixl
	ld a,(memroutine_next+1)
	sbc a,ixh
	jr nc,_
	pop af
	ex af,af'
	ld a,(ix)
	pop ix
	lea ix,ix-2
	ld (ix),a
_
	push hl
	 push de
	  call.il decode_mem_helper
	  ld (ix+1),de
	  ld (ix),$CD
	  ; Load the previous byte into IYL just in case this was LD (HL),n
	  ld e,(ix-1)
	  ld a,iyl
	  ld iyl,e
	 pop de
	pop hl
	ex af,af'
	jp (ix)
	
decode_block_bridge:
	ex af,af'
	scf
	.db $D2 ;JP NC,
decode_jump:
	ex af,af'
	or a
	exx
	push.l hl
	pop hl
	ld c,a
	push bc
	 inc hl
	 inc hl
	 inc hl
	 ld ix,(hl)
	 ld (hl),$C3 ;JP
	 inc hl
	 push hl
	  inc hl
	  ld a,(hl)
	  inc hl
	  ld de,(hl)
	  jp.lil decode_jump_helper
decode_jump_return:
	 pop hl
	 ld (hl),ix
	 ld de,-5
	 add hl,de
	 sbc a,b ; Carry is set
	 cpl
	 ld (hl),a
	 dec hl
	 ld (hl),$D6	;SUB -cycles
decode_block_bridge_finish:
	 dec hl
	 ld (hl),$08	;EX AF,AF'
decode_jump_waitloop_return:
	pop bc
	ld a,c
	push hl
	pop.l hl
	exx
	ex af,af'
	ret
	
decode_block_bridge_return:
	 pop hl
	 ld (hl),ix
	 ld de,-5
	 add hl,de
	 ld (hl),$DC	;CALL C,cycle_overflow_for_bridge
	 dec hl
	 ld (hl),a
	 dec hl
	 ld (hl),$C6	;ADD A,cycles
	 jr decode_block_bridge_finish
	
decode_bank_switch_return:
	 pop hl
	 inc hl
	 ld (hl),b	;negative jump cycles
	 dec hl
	 ld (hl),a  ;taken cycle count
	 dec hl
	 ld (hl),c	;bank id
	 dec hl
	 dec hl
	 ld (hl),ix
	 dec hl
	 ld (hl),$C3	;JP target
	 dec hl
	 dec hl
	 ld (hl),de
	 dec hl
	 ld (hl),$CD	;CALL do_xxxx_jump
	 jr decode_jump_waitloop_return
	
decode_call:
	ex (sp),hl
	push af
	 push bc
	  push de
	   inc hl
	   push hl
	    inc hl
	    inc hl
	    ld de,(hl)
	    dec de
	    call.il decode_call_helper
	   pop hl
	  pop de
	  ld (hl),a  ;taken cycles
	  dec hl
	  jr c,++_
	  dec hl
	  ld (hl),ix
	  dec hl
	  ld (hl),$C3  ;JP jit_target
	  dec hl
	  ld (hl),RST_CALL
_
	 pop bc
	pop af
	ex (sp),hl
	ret
	
_
	  ld (hl),ix
	  dec hl
	  dec hl
	  ld (hl),bc
	  dec hl
	  ld (hl),$CD  ;CALL do_rom_bank_call
	  jr --_
	
decode_call_cond:
	ex (sp),hl
	push af
	 push bc
	  push de
	   push hl
	    inc hl
	    inc hl
	    ld de,(hl)
	    dec de
	    call.il decode_call_helper
	   pop hl
	  pop de
	  ld (hl),a
	  dec hl
	  jr c,++_
	  dec hl
	  ld (hl),ix
	  dec hl
	  ld (hl),$C3
	  dec hl
	  dec hl
_
	  dec hl
	  ld (hl),$CD
	 pop bc
	pop af
	ex (sp),hl
	ret
	
_
	  ld (hl),ix
	  dec hl
	  dec hl
	  ld (hl),bc
	  dec hl
	  dec hl
	  ; Modify the conditional entry point to use the banked call
	  ld bc,(hl)
	  dec bc
	  dec bc
	  ld (hl),bc
	  jr --_
	
do_rst_00:
	ld ix,dispatch_rst_00
	jr decode_rst
do_rst_08:
	ld ix,dispatch_rst_08
	jr decode_rst
do_rst_10:
	ld ix,dispatch_rst_10
	jr decode_rst
do_rst_18:
	ld ix,dispatch_rst_18
	jr decode_rst
do_rst_20:
	ld ix,dispatch_rst_20
	jr decode_rst
do_rst_28:
	ld ix,dispatch_rst_28
	jr decode_rst
do_rst_30:
	ld ix,dispatch_rst_30
	jr decode_rst
do_rst_38:
	ld ix,dispatch_rst_38
	jr decode_rst
	
decode_rst:
	jp.lil decode_rst_helper
	
do_rst:
	ex af,af'
	exx
do_rst_decoded:
	ex.l de,hl
	ld hl,(-call_stack_lower_bound) & $FFFF
	add hl,sp
	jr nc,++_
_
	pop hl
	ld c,(hl)  ; Cycles for taken RET
	inc hl
	inc hl
	inc hl
	push hl  ; JIT return address
	dec hl
	dec hl
	ld hl,(hl)  ; Game Boy return address
	ex.l de,hl
	add a,(ix+3)  ; Count cycles
	jp nc,do_call_no_overflow
	inc iyh
	jp nz,do_call_no_overflow
	push.l hl
	ld iyl,a
	ld a,(ix+3)
	sub 4
	call cycle_overflow_for_rst_or_int
	jp callstack_ret
	
_
	call.il callstack_overflow_helper
	jr --_
	
do_banked_call_cond:
	pop ix
	pea ix+2
	ld ix,(ix)
	jp (ix)
	
	jr nz,do_banked_call_cond
do_call_nz:
	jr z,skip_cond_call
	jp r_call
	
	jr z,do_banked_call_cond
do_call_z:
	jr nz,skip_cond_call
	jp r_call
	
	jr nc,do_banked_call_cond
do_call_nc:
	jr c,skip_cond_call
	jp r_call
	
	jr c,do_banked_call_cond
do_call_c:
	jp c,r_call
skip_cond_call:
	pop ix
	lea ix,ix+7
	ex af,af'
	add a,(ix-3)
	jr c,++_
_
	dec a
	ex af,af'
	jp (ix)
_
	jr z,--_
	inc iyh
	jr nz,--_
	dec a
	ld iyl,a
	exx
	ld a,(ix-3)
	sub 4
	ld c,a
	ld de,(ix-2)
	push ix
	push.l hl
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_helper
#else
	jp.lil schedule_event_helper
#endif
	
do_swap_c:
	ld iyl,a
	ld a,c
	rrca
	rrca
	rrca
	rrca
	or a
	ld c,a
	ld a,iyl
	ret
	
do_swap_b:
	ld iyl,a
	ld a,b
	rrca
	rrca
	rrca
	rrca
	or a
	ld b,a
	ld a,iyl
	ret
	
do_swap_e:
	ld iyl,a
	ld a,e
	rrca
	rrca
	rrca
	rrca
	or a
	ld e,a
	ld a,iyl
	ret
	
do_swap_d:
	ld iyl,a
	ld a,d
	rrca
	rrca
	rrca
	rrca
	or a
	ld d,a
	ld a,iyl
	ret
	
do_swap_l:
	ld iyl,a
	ld a,l
	rrca
	rrca
	rrca
	rrca
	or a
	ld l,a
	ld a,iyl
	ret
	
do_swap_h:
	ld iyl,a
	ld a,h
	rrca
	rrca
	rrca
	rrca
	or a
	ld h,a
	ld a,iyl
	ret
	
do_swap_a:
	rrca
	rrca
	rrca
	rrca
	or a
	ret
	.block 6
	
do_swap_hl:
	ld ixl,NO_CYCLE_INFO
	ex af,af'
	ld iyl,a
	ex af,af'
	ld ixh,a
	push ix
	 call mem_read_any_before_write
	pop ix
	rrca
	rrca
	rrca
	rrca
	or a
	push ix
	 call mem_write_any
	pop ix
	ld a,ixh
	ret
	
do_bits:
	ex af,af'
	ld iyl,a
	ld a,ixh
	add a,a
	jr nc,do_bits_readonly
	jp m,do_bits_preserve_flags
	ld (do_bits_smc),a
	push ix
	 call mem_read_any_before_write
	pop ix
	exx
	ld d,a
	ex af,af'
do_bits_smc = $+1
	rlc d
	push af
	 ld a,d
	 exx
	 call mem_write_any
	pop af
	ret
	
do_bits_preserve_flags:
	inc a
	ld (do_bits_preserve_flags_smc),a
	push ix
	 call mem_read_any_before_write
	pop ix
do_bits_preserve_flags_smc = $+1
	res 0,a
	ex af,af'
	push af
	 call mem_write_any_swapped
	pop af
	ret
	
do_bits_readonly:
	ld (do_bits_readonly_smc),a
	call mem_read_any
	exx
	ld d,a
	ld a,iyl
	ex af,af'
do_bits_readonly_smc = $+1
	bit 0,d
	exx
	ret
	
ophandler08:
	ld ixl,NO_CYCLE_INFO
	push af
	 push de
	  ex.l de,hl
	  ld hl,(sp_base_address_neg)
	  add hl,de
	  ex.l de,hl
	  ld a,e
	  ld ixh,d
	  exx
	  ex (sp),hl
	  push ix
	   dec ixl
	   ex af,af'
	   ld iyl,a
	   call mem_write_any_swapped
	  pop ix
	  inc hl
	  call mem_write_any_ixh
	 pop hl
	pop af
	ret
	
ophandler27:
	; Save input A value
	ld iyl,a
	; Split execution path on input carry, to extract both H and N
	jr nc,ophandler27_no_carry
	; Map a value based on input H and N flags:
	;   N=0, H=0 -> $A6
	;   N=0, H=1 -> $AA
	;   N=1, H=0 -> $06
	;   N=1, H=1 -> $00
	ld a,$66
	daa
	; Invert N flag into C, and if N=0, put the H flag in H, else put it in Z
	add a,a
	; Restore input A value
	ld a,iyl
	jr c,ophandler27_add
	; Case for N=1, C=1
	jr nz,_
	; Subtract the adjustment for H=1
	sub 6
_
	; Subtract the adjustment for C=1, set N flag, reset H flag, update Z flag
	sub $60
	ret c
	jr z,_
	; If Z flag need not be set, set C/N flags, reset H/Z flags
	cp $A0
	ret
_
	; If Z flag must be set, set C/N/Z flags, reset H flag
	sub $A0
	daa
	ret
	
ophandler27_no_carry:
	; Map a value based on input H and N flags:
	;   N=0, H=0 -> $46
	;   N=0, H=1 -> $4A
	;   N=1, H=0 -> $86
	;   N=1, H=1 -> $80
	ld a,$E6
	daa
	; Put the N flag in C, and if N=0, put the H flag in H, else put it in Z
	add a,a
	; Restore input A value
	ld a,iyl
	jr c,ophandler27_sub_no_carry
ophandler27_add:
	; N=0, C and H were restored
	daa
	; Reset H and N, preserve C and Z
	rla
	rra
	ret
	
ophandler27_sub_no_carry:
	; Case for N=1, C=0
	jr nz,_
	; Subtract the adjustment for H=1
	sub 6
_
	; Set N, reset H and C, update Z
	sub 0
	ret
	
ophandler31:
	pop ix
	pea ix+2
	exx
	ld hl,(ix)
	jp set_gb_stack
	
ophandler33:
	ex af,af'
	exx
	inc.l hl
	bit 0,l
ophandler33_jr_smc = $
	jr nz,++_
	inc b
	djnz _
	ld c,a
	ld a,h
ophandler33_bound_smc = $+1
	cp 0
	ld a,c
	jp m,_
ophandler33_3B_overflow:
	ld de,(sp_base_address_neg)
	add hl,de
	ex af,af'
	jp set_gb_stack
_
	inc b
_
	exx
	ex af,af'
	ret
	
ophandler3B:
	ex af,af'
	exx
	bit 0,l
	dec.l hl
ophandler3B_jr_smc = $
	jr nz,-_
	djnz -_
	ld c,a
	ld a,h
ophandler3B_bound_smc = $+1
	cp 0
	ld a,c
	jp m,ophandler33_3B_overflow
	exx
	ex af,af'
	ret
	
ophandler34:
	ld ixl,NO_CYCLE_INFO
	push ix
	 call mem_read_any_before_write_swap
	pop ix
	ld ixh,a
	ex af,af'
	inc ixh
	push af
	 call mem_write_any_ixh
	pop af
	ret
	
ophandler35:
	ld ixl,NO_CYCLE_INFO
	push ix
	 call mem_read_any_before_write_swap
	pop ix
	ld ixh,a
	ex af,af'
	dec ixh
	push af
	 call mem_write_any_ixh
	pop af
	ret
	
ophandler39:
	push de
	 exx
	 push hl
	  exx
	  ex (sp),hl
sp_base_address_neg = $+1
	  ld de,0
	  add hl,de
	  ex de,hl
	 pop hl
	 add hl,de
	pop de
	ret
	
handle_waitloop_stat:
	pop ix
	ex af,af'
	exx
	ld de,(nextupdatecycle_STAT)
	; Add the next jump cycles, and don't skip anything if expired
	ld c,(ix+5)
	add a,c
	jr nc,handle_waitloop_common
_
	inc iyh
	jr nz,handle_waitloop_common
	jr handle_waitloop_overflow
	
handle_waitloop_ly:
	pop ix
	ex af,af'
	exx
	ld de,(nextupdatecycle_LY)
	; Add the next jump cycles, and don't skip anything if expired
	ld c,(ix+5)
	add a,c
	jr c,-_
handle_waitloop_common:
	push.l hl
	; Check if the waitloop sentinel is set
	ld hl,(event_address)
	inc h
	dec h
	jr nz,handle_waitloop_set_sentinel
	; Get the current number of cycles until the next register update
	ld hl,i
	add hl,de
	ld d,iyh
	ld e,a
	add hl,de
	; Offset to the read time to allow extra skips as needed
	ld a,l
	add a,(ix+3)
	ld l,a
	; If the update has already passed or is not cached, don't skip
	sbc a,a
	cp h
	ld a,e
	jr nz,handle_waitloop_finish
	ld h,(ix+4)
	; Choose the smaller absolute value of the cycle counter
	; and the remaining cycles until register change
	inc d
	jr nz,_
	cp l
	jr nc,handle_waitloop_skip_to_expiration
_
	; Skip as many full loops as possible until the update time is reached
	ld a,l
_
	add a,h
	jr nc,-_
	sub l
	; Add in the cycles, which may overflow if the update time and
	; cycle expiration time are in the same block
	add a,e
	jr nc,handle_waitloop_finish
	inc iyh
	jr z,handle_waitloop_overflow_pop
handle_waitloop_finish:
	pop.l hl
	exx
	ex af,af'
	jp (ix)
	
handle_waitloop_set_sentinel_push:
	push.l hl
handle_waitloop_set_sentinel:
	ld hl,waitloop_sentinel
	ld (event_address),hl
	jr handle_waitloop_finish
	
	; Skip as many full loops as possible until the cycle count expires
handle_waitloop_skip_to_expiration:
	add a,h
	jr nc,handle_waitloop_skip_to_expiration
	inc iyh
handle_waitloop_overflow_pop:
	pop.l hl
handle_waitloop_overflow:
	ld iyl,a
handle_waitloop_variable_finish:
	ld de,(ix+6)
	ld ix,(ix+1)
	push ix
#ifdef VALIDATE_SCHEDULE
	call.il schedule_jump_event_helper
#else
	jp.lil schedule_jump_event_helper
#endif

handle_waitloop_variable:
	pop ix
	ex af,af'
	exx
	; Add the next jump cycles, and don't skip anything if expired
	ld c,(ix+5)
	add a,c
	jr nc,_
	inc iyh
	jr z,handle_waitloop_overflow
_
	; Check if the waitloop sentinel is set
	ld de,(event_address)
	inc d
	dec d
	jr nz,handle_waitloop_set_sentinel_push
	; Skip straight to the counter expiration
	ld iyl,c
	ld iyh,d
	jr handle_waitloop_variable_finish

ophandlerEI_delay_expired:
	; An event is scheduled for the current cycle, so we have to delay the
	; actual enabling of the IME flag.
	ld hl,schedule_ei_delay
	ld (event_counter_checkers_ei_delay),hl
ophandlerEI_no_interrupt:
	pop.l hl
	exx
ophandlerEI_no_change:
	; IME did not change, which also means no need to check for interrupts
	ld a,iyl
	ex af,af'
	ret
	
ophandlerEI:
	ld ixl,NO_CYCLE_INFO
intstate_smc_1 = $
	ret	; SMC overrides with EX AF,AF' when IME=0
	ld iyl,a
	
	; Always disable just the EI handler.
	; This prevents consecutive EIs from causing multiple enable delays,
	; while still preventing interrupts from happening if an event happens
	; during the delay.
	ld a,$C9
	ld (intstate_smc_1),a

	; Check if an event is scheduled at the current cycle
	exx
	push.l hl
	pop hl
	push hl
	ld a,(hl)
	cp RST_EVENT
	jr z,ophandlerEI_delay_expired
	
	; No event is scheduled for the current cycle, so fully set IME=1 now
	; and schedule an event at the following instruction, only if an
	; interrupt is currently requested
	ld a,trigger_interrupt - (intstate_smc_2 + 1)
	ld (intstate_smc_2),a
	ld hl,(IE)
	ld a,h
	and l
	jr z,ophandlerEI_no_interrupt

	call get_mem_info_full
	inc de	; Advance to cycle after EI
	inc de  ; Advance after EI delay cycle
	ld a,(ix+2)
	inc a	; Check if cycles remain in the block
	jr z,++_
	; Interrupt check will happen in this block
	push hl
	 ld hl,i
	 add hl,de
	 ld i,hl
	 ld de,(ix-2)
	pop ix
	cpl
	ld iyl,a
	inc a
	ld c,a
	xor a
	cp iyh
	ld iyh,a
	jr c,_
	ld hl,(event_address)
#ifdef DEBUG
	ld a,h
	cp (event_value >> 8) + 1
	jr c,$
#endif
	ld a,(event_value)
	ld (hl),a
#ifdef DEBUG
	ld hl,event_value
	ld (event_address),hl
#endif
	scf
_
	sbc a,a  ; Same as ld a,iyl \ sub c
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_later
#else
	jp.lil schedule_event_later
#endif
_
	; Interrupt check is delayed until the next block
	; Set cycle counter to -1 and let the next block schedule the event
	ld hl,i
	add hl,de
	ld i,hl
	pop.l hl
	exx
	dec a
	ld iyh,a
	ex af,af'
	ret
	
decode_halt:
	pop ix
	pea ix-2
	exx
	ld de,(ix+3)
	jp.lil decode_halt_helper
decode_halt_continue:
	pop hl
	ld (hl),ophandler_halt & $FF
	inc hl
	ld (hl),ophandler_halt >> 8
	inc hl
	push hl
	ld (hl),a
	inc hl
	ld (hl),ix
	ld a,ixh
	cp flush_handler >> 8
	jr nz,_
	ld a,ixl
	cp flush_handler & $FF
	jr nz,_
	; If the JIT needs to be flushed, flush at the HALT address itself
	pop hl
	ld de,(ix+flush_address-flush_handler)
	dec de
	jp.lil flush_for_halt
ophandler_halt:
	ex af,af'
	exx
	push.l hl
	ld c,a
_
	ld hl,(IE)
	ld a,h
	and l
	ld hl,intstate_smc_2
	jr z,haltspin
	; If interrupts are enabled, go straight to the event handler
	; without setting up the SMC for halt spinning
	; This can only happen as the result of an EI delay slot,
	; so the cycle counter is guaranteed to go from -1 to 0
	ld a,(hl)
	or a
	jr nz,haltnospin
	; Emulate HALT bug in this case
	pop ix
	; Advance to after the HALT
	lea ix,ix+6
	; Count cycles for the bugged instruction
	ld a,(ix-1)
	add a,c
	jr c,ophandler_halt_maybe_overflow
ophandler_halt_no_overflow:
	pop.l hl
	exx
	ex af,af'
	jp (ix)
haltspin:
	; Set halted state
	ld a,(hl)
	sub trigger_interrupt - cpu_exit_halt_trigger_interrupt
	jr nc,_
	xor (cpu_exit_halt_trigger_interrupt - trigger_interrupt) ^ (cpu_exit_halt_no_interrupt - cpu_halted_smc)
_
	ld (hl),a
	inc hl
	ld (hl),$18 ;JR cpu_continue_halt
	inc hl
	ld (hl),cpu_continue_halt - (cpu_halted_smc + 2)
haltnospin:
	pop hl
	; Set instruction cycle offset
	ld c,(hl)
	inc hl
	; Push JIT address after HALT
	ld de,(hl)
	push de
	inc hl
	inc hl
	; Set GB address to after HALT
	ld hl,(hl)
	ld (event_gb_address),hl
	; Set remaining cycles to 0
	ld iy,0
	jp do_event_pushed
	
ophandler_halt_maybe_overflow:
	inc iyh
	jr nz,ophandler_halt_no_overflow
	ld iyl,a
	; Carry is set, subtract out the cycle for the HALT itself
	sbc a,c
	ld c,a
	ld de,(ix-3)
	dec de
	push ix
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_helper
#else
	jp.lil schedule_event_helper
#endif
	
; Writes to the GB timer count (TIMA).
; Does not use a traditional call/return, must be jumped to directly.
;
; Updates the GB timer based on the new value, if enabled.
;
; Inputs:  DE = current cycle offset
;          A' = value to write
;          (SPS) = Z80 return address
;          (SPL) = saved HL'
;          BCDEHL' are swapped
; Outputs: TIMA and GB timer updated
;          Event triggered
tima_write_helper:
	 ld hl,TAC
	 bit 2,(hl)
	 ld l,TIMA & $FF
	 ex af,af'
	 ld (hl),a
	 ex af,af'
#ifdef DEBUG
	 jp z,trigger_event_already_triggered
#else
	 jr z,trigger_event_already_triggered
#endif
	 ld a,(hl)
tima_reschedule_helper:
	 ld hl,i
	 add hl,de
	 cpl
	 ld e,a
	 ld a,(timer_cycles_reset_factor_smc)
	 ld d,a
	 add a,a
	 dec a
	 or l
	 ld l,a
	 mlt de
	 inc de
	 add hl,de
	 add hl,de
	 ld (timer_counter),hl
reschedule_event_timer:
reschedule_event_serial:
	 ; Get the relative time of the event from the currently scheduled event
	 ex de,hl
	 ld hl,i ; Resets carry
	 sbc hl,de
	 jr _
	 
reschedule_event_PPU:
	 ; Get the relative time of the event from the currently scheduled event
	 ex de,hl
	 ld hl,i
	 add hl,de
_
	 call get_mem_cycle_offset
	 ; If the current event is scheduled before or at the current cycle, do nothing
	 xor a
	 cp d
	 jr z,trigger_event_already_triggered
	 ; If the new event is after or at the currently scheduled event, do nothing
	 ex de,hl
	 dec hl
	 add hl,de
	 jr c,trigger_event_already_triggered
	 ; If the counter already overflowed, trigger an event now to reschedule
	 cp iyh
	 jr z,trigger_event_pushed
	 ; Update the schedule time
	 ld hl,i ; Resets carry
	 sbc hl,de
	 ld i,hl
	 ; Update the cycle counter
	 add iy,de
	 ; If the cycle counter didn't overflow, just continue execution
	 jr nc,trigger_event_already_triggered
	 ; Trigger an event without attempting to remove an event trigger
	 call get_mem_info_full
	 jr trigger_event_no_remove
	
trigger_event_swapped:
	push.l hl
trigger_event_pushed:
	 ; Get the cycle offset, GB address, and JIT address after the current opcode
	 call get_mem_info_full
	 ; If the end of this instruction is already past the target, no reschedule
	 xor a
	 cp d
	 jr z,trigger_event_already_triggered
	 ; If the counter already overflowed, remove any already-scheduled event
	 cp iyh
	 ld iyh,a
	 jr nz,trigger_event_no_remove
#ifdef DEBUG
	 ld a,(event_address+1)
	 cp (event_value >> 8) + 1
	 jr c,$
#endif
	 ld a,(event_value)
event_address = $+1
	 ld (event_value),a
#ifdef DEBUG
	 jr _
#endif
trigger_event_no_remove:
#ifdef DEBUG
	 ld a,(event_address+1)
	 cp (event_value >> 8) + 1
	 jr nc,$
_
#endif
	 ; Make sure the CALL/RST/interrupt dispatch case is handled
	 ld a,(hl)
	 cp $C3
	 jr z,trigger_event_call_fixup
trigger_event_call_fixup_continue:
	 ld (event_value),a
	 ld (event_address),hl
	 ld (hl),RST_EVENT
	 ; Cycle count at event is relative to the memory access
	 ld a,iyl
	 sub e
	 ld iyl,a
	 scf
	 adc a,(ix+2)
	 ASSERT_C
	 ld (event_cycle_count),a
	 ld hl,(ix-2)
	 ld (event_gb_address),hl
	 ld hl,i
	 add hl,de	; Reset div counter to the time of memory access
	 ld i,hl
trigger_event_already_triggered:
	pop.l hl
z80_restore_swap_ret:
	ld a,iyl
z80_double_swap_ret:
	ex af,af'
z80_swap_ret:
	exx
z80_ret:
	ret
	
trigger_event_call_fixup:
	inc hl
	ld hl,(hl)
	ld a,(hl)
	ld ix,mem_info_scratch
	jr trigger_event_call_fixup_continue
	
_writeTMA:
	call updateTIMA
	 ld hl,TMA
	 ex af,af'
	 ld (hl),a
	 ex af,af'
	 ; Subtract TMA from 256, without destroying Z
	 ld a,(hl)
	 cpl
	 ld l,a
	 inc hl
	 ; Check if the result was 256, without destroying Z
	 ld a,h
	 rlca
	 ; Multiply by the timer factor
timer_cycles_reset_factor_smc = $+1
	 ld h,0
	 jr nc,_
	 mlt hl
_
	 ld (timer_period),hl
	 jr nz,trigger_event_already_triggered
	 ; Make sure writes on the reload cycle go through
	 ld hl,i
	 add hl,de
	 ld (timer_counter),hl
	 jr trigger_event_already_triggered
	
ophandlerE2:
	ld ixl,NO_CYCLE_INFO
	ex af,af'
	ld ixh,b
	inc c
	jr z,_
	dec c
	jp p,++_
	ex af,af'
	ld b,$FF
	ld (bc),a
	ld b,ixh
	ret
_
	dec c
_
	ld iyl,a
	ld b,mem_write_port_lut >> 8
	ld a,(bc)
	ld (_+1),a
	ld b,ixh
	ld ixh,c
_
	jp mem_write_port_routines
	
ophandlerE8:
	exx
	ld c,a
	pop de
	ld a,(de)
	inc de
	push de
	ld de,(sp_base_address_neg)
	add hl,de
	ld e,a
	rla
	sbc a,a
	ld d,a
	ld a,l
	add hl,de
	add a,e
	; Reset Z flag but preserve H/C flags and keep N flag reset.
	ld a,$04
	daa  ; Resets H but increases low nibble to $A if H was set.
	daa  ; Iff low nibble is $A, sets H. Z is reset always.
	ld a,c
	jp set_gb_stack
	
ophandlerE9:
	push hl
	 exx
	pop de
	ld c,a
	push bc
	 call.il lookup_code_cached
	pop bc
	scf
	adc a,c
	jr c,++_
_
	exx
	ex af,af'
	jp (ix)
_
	inc iyh
	jr nz,--_
	ld iyl,a
	sbc a,c
	ld c,a
	inc de
	dec de
	push ix
	push.l hl
#ifdef VALIDATE_SCHEDULE
	call.il schedule_event_helper
#else
	jp.lil schedule_event_helper
#endif
	
ophandlerF1:
	exx
	ld d,flags_lut >> 8
	inc b
ophandlerF1_jump_smc_1 = $+1
	djnz ophandlerF1_pop_z80
	ld a,h
do_pop_bound_smc_3 = $+1
	cp 0
ophandlerF1_jump_smc_2 = $+1
	jp m,ophandlerF1_pop_z80
ophandlerF1_overflow:
	ex af,af'
	ld iyl,a
	call pop_overflow
	exx
	pop de
ophandlerF1_continue:
	ld c,d
ophandlerF1_rtc_continue:
	ld d,flags_lut >> 8
	res 3,e
	ld a,(de)
	ld e,a
	ld d,c
	push de
	 exx
	pop af
	ret
	
ophandlerF1_pop_hmem:
	ex af,af'
	ld iyl,a
	call pop_hmem
	jr ophandlerF1_continue
	
ophandlerF1_pop_rtc:
	inc b
	ld ix,(sp_base_address)
	ld e,(ix)
	ld c,e
	inc.l hl
	inc.l hl
	jr ophandlerF1_rtc_continue
	
ophandlerF1_pop_adl:
	inc b
	ld.l e,(hl)
	inc.l hl
	res 3,e
	ld a,(de)
	ld e,a
	ld.l d,(hl)
	inc.l hl
	push de
	 exx
	pop af
	ret
	
ophandlerF1_pop_z80:
	bit 6,b
	jr nz,ophandlerF1_overflow
	inc b
	ld e,(hl)
	inc hl
	res 3,e
	ld a,(de)
	ld e,a
	ld d,(hl)
	inc hl
	push de
	 exx
	pop af
	ret
	
ophandlerF2:
	ld ixl,NO_CYCLE_INFO | NO_RESCHEDULE
	ex af,af'
	bit 7,c
	jr z,_
	ex af,af'
	ld iyl,b
	ld b,$FF
	ld a,(bc)
	ld b,iyl
	ret
_
	ld iyl,a
	push hl
	 ld h,$FF
	 ld l,c
	 call mem_update_ports_swapped
	 ld a,(hl)
	pop hl
	ret
	
ophandlerF3:
	push hl
	 ld hl,intstate_smc_1
	 ld (hl),$08 ;EX AF,AF'
	 ld hl,intstate_smc_2
	 ld (hl),0
	 ; Disable any delayed EI
	 ld hl,event_counter_checkers_done
	 ld (event_counter_checkers_ei_delay),hl
	pop hl
	ret
	
ophandlerF5:
	exx
	ld c,a
	push af
	pop de
	ld d,flags_lut >> 8
	; Bit 3 of F was set by the previous pop af
	ld a,(de)
	ld d,c
	ld e,a
	ld a,c
do_push_jump_smc_1 = $+1
	djnz do_push_hmem
	jr do_push_check_overflow
	
ophandlerE5:
	push hl
	 exx
	pop de
do_push_jump_smc_2 = $+1
	djnz do_push_hmem
do_push_check_overflow:
	ex af,af'
	ld c,a
	ld a,h
do_push_bound_smc_1 = $+1
	cp 0
	jp m,do_push_overflow
	ld a,c
	ex af,af'
do_push_jump_smc_3 = $+1
	jr do_push_hmem
	
ophandlerD5:
	push de
	 exx
	pop de
do_push_jump_smc_4 = $+1
	djnz do_push_hmem
	jr do_push_check_overflow
	
ophandlerC5:
	push bc
	 exx
	pop de
do_push_jump_smc_5 = $+1
	djnz do_push_hmem
	jr do_push_check_overflow
	
do_push_adl:
	dec.l hl
	ld.l (hl),d
	dec.l hl
	ld.l (hl),e
	exx
	ret
	
do_push_z80:
	dec hl
	dec hl
	ld (hl),de
	exx
	ret

schedule_event_finish_for_call_now:
	ex de,hl
schedule_event_finish_for_call:
	ld (event_cycle_count),a
	ld (event_gb_address),hl
;#ifdef DEBUG
;	ld a,(event_address+1)
;	cp (event_value >> 8) + 1
;	jr nc,$
;#endif
	lea hl,ix
	ld (event_address),hl
	ld a,(hl)
	ld (event_value),a
	ld (hl),RST_EVENT
schedule_event_finish_for_call_no_schedule:
	pop.l hl
	ld a,iyl
	ex af,af'
	pop de
	push.l de  ; Cache Game Boy return address
do_push_and_return_jump_smc = $+1
	djnz do_push_adl
	pop ix
	jr do_push_for_call_check_overflow

do_push_for_call_rtc:
	push bc
	push ix
do_push_rtc:
	ld ix,(sp_base_address)
	ld (ix+5),e
	dec.l hl
	dec.l hl
	exx
	ret
	
do_push_for_call_cart:
	push bc
	push ix
do_push_cart:
	ld ix,mem_write_cart_always
	jr do_push_generic
	
do_push_for_call_vram:
	push bc
	push ix
do_push_vram:
	ld ix,mem_write_vram_always
	jr do_push_generic
	
do_push_for_call_hmem:
	push bc
	push ix
do_push_hmem:
	push af
	 ex af,af'
	 ld iyl,a
	 ld a,d
	 ex af,af'
	 ld a,e
	 dec hl
	 push hl
	  dec hl
	  exx
	  ex (sp),hl
	  push af
	   ld ixl,NO_CYCLE_INFO - 1
	   call mem_write_hmem_swapped
	  pop af
	  ex af,af'
	  dec hl
	  ld ixl,NO_CYCLE_INFO
	  call mem_write_hmem_swapped
	 pop hl
	pop af
	ret
	
do_push_for_call:
	ex af,af'
	push.l de  ; Cache Game Boy return address
do_push_for_call_jump_smc_1 = $+1
	djnz do_push_for_call_adl
	push bc  ; Push decremented stack offset and RET cycle count
do_push_for_call_check_overflow:
	ex af,af'
	ld c,a
	ld a,h
do_push_bound_smc_2 = $+1
	cp 0
	jp m,do_push_for_call_overflow
	ld a,c
	ex af,af'
do_push_for_call_jump_smc_2 = $+1
	jr do_push_for_call_rtc
	
do_push_for_call_z80:
	push bc
	dec hl
	dec hl
	ld (hl),de
	exx
	jp (ix)
	
do_push_for_call_adl:
	push bc
	dec.l hl
	ld.l (hl),d
	dec.l hl
	ld.l (hl),e
	exx
	jp (ix)
	
	; Pushes using the memory write routine passed in IX
	; Unswaps BCDEHL'
do_push_generic:
	push af
	 ex af,af'
	 ld iyl,a
	 ld a,d
	 ex af,af'
	 ld a,e
	 dec.l hl
	 ex.l de,hl
	 ld hl,(sp_base_address_neg)
	 add hl,de
	 push hl
	  ex.l de,hl
	  dec.l hl
	  exx
	  ex (sp),hl
	  call _
	 pop hl
	pop af
	ret
_
	push ix
	 push af
	  call _
	 pop af
	 ex af,af'
	 dec hl
	 ld ixl,NO_CYCLE_INFO
	ret
_
	push ix
	 ld ixl,NO_CYCLE_INFO - 1
	ret
	
ophandlerF8:
	ld ixl,a
	pop hl
	ld a,(hl)
	inc hl
	push hl
	exx
	push hl
	 exx
	pop hl
	push de
	 ld de,(sp_base_address_neg)
	 add hl,de
	 ld e,a
	 rla
	 sbc a,a
	 ld d,a
	 ld a,l
	 add hl,de
	 add a,e
	 ; Reset Z flag but preserve H/C flags and keep N flag reset.
	 ld a,$04
	 daa  ; Resets H but increases low nibble to $A if H was set.
	 daa  ; Iff low nibble is $A, sets H. Z is reset always.
	pop de
	ld a,ixl
	ret
	
reset_z_flag:
	; IYH is guaranteed to be 0 or at least 118 (for double speed frame)
	ld iyl,iyh
	dec iyl
	ret
	
ophandlerF9:
	push hl
	 exx
	pop hl
	jp set_gb_stack
	
ophandlerRETcond:
	; Increment the taken cycle count by 1 before returning
	exx
	pop de
	inc de ; Make sure not to destroy flags
	ret
	
ophandlerRETI:
	exx
	ld c,a
	; Enable interrupts
	ld a,$C9 ;RET
	ld (intstate_smc_1),a
	ld a,trigger_interrupt - (intstate_smc_2 + 1)
	ld (intstate_smc_2),a
	; Check if an interrupt is pending, if not then return normally
	ld de,(IE)
	ld a,d
	and e
	jr nz,_
	ld a,c
	ex af,af'
	pop de
	ret
_
	ld iyl,c
	ld a,b
	; Schedule an event after the return
	lea bc,iy+4
	inc b
	djnz _
	; If an event will already be scheduled on return, just return
	ld b,a
	ld a,iyl
	ex af,af'
	pop de
	ret
_
	; Update the cycle counter
	ex.l de,hl
	ld hl,i
	add hl,bc
	ld i,hl
	ex.l de,hl
	ld b,a
	ld iyh,-1
	ld a,-4
	ex af,af'
	pop de
	ret
	
pop_hmem:
	inc b
	push hl
	 exx
	 ex (sp),hl
	 ld ixl,(NO_CYCLE_INFO - 1) | NO_RESCHEDULE
	 call mem_update_hmem_swapped
	 inc hl
	 ex af,af'
	 ld ixl,NO_CYCLE_INFO | NO_RESCHEDULE
	 call mem_update_hmem_swapped
	pop hl
	exx
	ld de,(hl)
	inc hl
	inc hl
	ret
	
write_vram_handler:
	pop ix
	pea ix+2
	ex af,af'
	ld iyl,a
	exx
	ld de,(ix)
	; For now it's not possible to get cycle info for absolute writes,
	; so we can't call updateSTAT. It may be possible for catch-up to fail.
	; TODO: Fix this
	jp.lil write_vram_and_expand_push
	
mem_write_vram_always:
mem_write_any_vram:
	push hl
	 call updateSTAT_swap
	pop de
	ld a,r
	jp.lil p,write_vram_and_expand
	jp.lil write_vram_and_expand_catchup
	
write_cart_handler:
	ex af,af'
	ld iyl,a
	ex (sp),hl
	inc hl
	ld a,(hl)
	inc hl
	ex (sp),hl
	jp mem_write_cart_always_a
	
write_cram_bank_handler:
	pop ix
	pea ix+2
	exx
	ld de,(ix)
	ld.lil ix,(cram_bank_base)
	ex af,af'
write_cram_bank_handler_smc_1 = $+1
	add.l ix,de
	ex af,af'
write_cram_bank_handler_smc_2 = $+3
	ld.l (ix),a
	exx
	ret
	
read_rom_bank_handler:
	pop ix
	pea ix+2
	exx
	ld de,(ix)
	ld.lil ix,(rom_bank_base)
	ex af,af'
	add.l ix,de
	ex af,af'
	ld.l a,(ix)
	exx
	ret
	
read_cram_bank_handler:
	pop ix
	pea ix+2
	exx
	ld de,(ix)
	ld.lil ix,(cram_bank_base)
	ex af,af'
read_cram_bank_handler_smc = $+1
	add.l ix,de
	ex af,af'
	ld.l a,(ix)
	exx
	ret
	
readDIVhandler:
	ex af,af'
	ld iyl,a
	call get_mem_cycle_offset_swap_push
	 ld hl,i
	 add hl,de
	 add hl,hl
	 add hl,hl
	 ld a,iyl
	 ex af,af'
	 ld a,h
	pop.l hl
	exx
	ret
	
readTIMAhandler:
	ex af,af'
	ld iyl,a
	call updateTIMA
	pop.l hl
	exx
	ld a,iyl
	ex af,af'
	ld a,(TIMA)
	ret
	
readIFhandler:
	ex af,af'
	ld iyl,a
	ld a,iyh
	or a
	exx
	call z,handle_events_for_mem_access
	ld a,(active_ints)
	or $E0
	ld c,a
	ld a,iyl
	ex af,af'
	ld a,c
	exx
	ret
	
readLYhandler:
	ex af,af'
	ld iyl,a
	call updateLY
	pop.l hl
	exx
	ld a,iyl
	ex af,af'
	ld a,(LY)
	ret
	
readSTAThandler:
	ex af,af'
	ld iyl,a
	call updateSTAT_swap
	pop.l hl
	exx
	ld a,iyl
	ex af,af'
	ld a,(STAT)
	ret
	
mem_update_STAT:
	call updateSTAT_swap
	pop.l hl
	exx
	ld a,iyl
	ex af,af'
	ret
	
mem_update_LY:
	call updateLY
	pop.l hl
	exx
	ld a,iyl
	ex af,af'
	ret
	
	;HL=GB address, ensures data at (HL) is valid for reading
mem_update_hmem:
	ex af,af'
	ld iyl,a
mem_update_hmem_swapped:
	ld a,h
	cp $FE
	jr c,mem_update_bail
	jr z,mem_update_oam
mem_update_ports_swapped:
	ld a,l
	cp STAT & $FF
	jr z,mem_update_STAT
	cp LY & $FF
	jr z,mem_update_LY
	sub IF & $FF
	jr z,mem_update_IF
	add a,IF-TIMA
	sbc a,h
	jr z,mem_update_DIV_TIMA
mem_update_oam:
	ld a,iyl
	ex af,af'
	ret
	
mem_update_IF:
	or iyh
	exx
	call z,handle_events_for_mem_access
	exx
	ld a,(active_ints)
	or $E0
	ld (hl),a
	ld a,iyl
	ex af,af'
	ret
	
mem_update_DIV_TIMA:
	jr nc,mem_update_DIV
	call updateTIMA
	pop.l hl
	exx
	ld a,iyl
	ex af,af'
	ret
	
mem_update_bail:
	pop ix
	ld a,RST_MEM
	cp (ix-5)
	jr z,_
	dec ix
	cp (ix-5)
	jr z,_
	lea ix,ix-2
_
	ld a,iyl
	ex af,af'
	push af
	pea ix-5
	ret
	
mem_read_any_before_write_swap:
	ex af,af'
	ld iyl,a
mem_read_any_before_write:
	dec ixl
	;HL=GB address, reads into A, AF'=GB AF
mem_read_any:
	ld a,h
	cp $FE
	jr nc,mem_read_any_hmem
	ex de,hl
	add a,a
	jr c,++_
	add a,a
	jr c,_
rom_start_smc_2 = $+3
	ld.lil ix,0
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
_
	ld.lil ix,(rom_bank_base)
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
_
	add a,a
	jr nc,_
	ld.lil ix,wram_base
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret p
	ex de,hl
	ld.lil ix,wram_base-$2000
	jr mem_read_any_finish
	
mem_update_DIV:
	call get_mem_cycle_offset_swap_push
	 ld hl,i
	 add hl,de
	 add hl,hl
	 add hl,hl
	 ld a,h
	pop.l hl
	exx
	ld (hl),a
	ld a,iyl
	ex af,af'
	ret
	
_
	jp m,_
	ld.lil ix,vram_base
mem_read_any_finish:
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
_
	ld.lil ix,(cram_bank_base)
mem_read_any_rtc_smc = $+1
	add.l ix,de
	ld.l a,(ix)
	ex de,hl
	ret
	
mem_read_any_hmem:
	ld a,(hl)
	ret z ;OAM
	bit 7,l
	ret nz ;HRAM
	call mem_update_ports_swapped
	ex af,af'
	ld a,(hl)
	ret
	
	;HL=GB address, IXH=data, IXL=cycle offset, destroys A,AF'
mem_write_any_ixh:
	ld a,ixh
	;HL=GB address, IXL=cycle offset, A=data, preserves AF, destroys AF'
mem_write_any:
	ex af,af'
mem_write_any_swapped:
	ld a,h
	cp $FE
	jr nc,mem_write_any_hmem
	add a,a
	jr nc,mem_write_any_cart
	add a,a
	jr nc,_
	ex de,hl
	add a,a
	jr c,mem_write_any_wram_mirror
mem_write_any_wram:
	ld.lil ix,wram_base
mem_write_any_finish:
	add.l ix,de
	ex de,hl
	ld a,iyl
	ex af,af'
	ld.l (ix),a
	ret
	
_
	jp p,mem_write_any_vram
mem_write_any_cram:
	ex de,hl
	ld.lil ix,(cram_bank_base)
mem_write_any_cram_smc_1 = $+1
	add.l ix,de
	ex de,hl
	ld a,iyl
	ex af,af'
mem_write_any_cram_smc_2 = $+3
	ld.l (ix),a
	ret
	
mem_write_any_wram_mirror:
	ld.lil ix,wram_base-$2000
	jr mem_write_any_finish
	
mem_write_any_hmem:
	jr z,mem_write_oam_swapped
	ld a,l
	cp $7F
	jp po,mem_write_ports_swapped_a
	ld a,iyl
	ex af,af'
	ld (hl),a
	ret
	
	; Inputs: IX = GB address
	;         IY = cycle counter,
	;         A = data to wrote
	; Outputs: A' = low cycle counter
	; Destroys: IX, F', C', DE'
mem_write_hmem:
	ex af,af'
	ld iyl,a
mem_write_hmem_swapped:
	inc h
	jr nz,mem_write_not_ports_swapped

; Inputs: HL = GB address
;         A = low byte of GB address
;         IY = cycle counter
;         IXL = cycle offset
;         A' = data to write
; Outputs: AF = input AF'
;          A' = low cycle counter
; Destroys: IX, F', C', DE'
mem_write_ports_swapped:
	ld a,l
mem_write_ports_swapped_a:
	ld ixh,a
	ld h,mem_write_port_lut >> 8
	ld l,(hl)
	dec h
	push hl
	 ld h,$FF
	 ld l,a
	 ret
	
mem_write_not_ports_swapped:
	ld a,h
	dec h
	inc a
	jr nz,mem_write_bail
mem_write_oam_swapped:
	ld a,iyl
	ex af,af'
	ld (hl),a
	ret

mem_write_any_cart:
	jr mem_write_cart_always
	
	
	;HL=GB address, A=data, preserves AF, destroys F'
mem_write_vram:
	ex af,af'
	ld iyl,a
	ld a,h
	sub $20
	jp pe,mem_write_vram_always
mem_write_bail:
	pop ix
	lea ix,ix-8
mem_write_bail_any:
	ld a,RST_MEM
	cp (ix)
	jr z,mem_write_bail_a
	dec ix
	cp (ix)
	jr z,mem_write_bail_de
	dec ix
	cp (ix)
	jr z,mem_write_bail_r
	dec ix
	; We subtracted either $02 (for LD (BC),A) or $7E (for LD (HL),n)
	; The latter would have overflowed
	jp pe,mem_write_bail_r
mem_write_bail_bc:
	pop hl
	ex de,hl
mem_write_bail_de:
	ex de,hl
mem_write_bail_a:
	ld a,iyl
	ex af,af'
	push af
	jp (ix)
mem_write_bail_r:
	ld a,iyl
	ex af,af'
	jp (ix)
	
mem_write_bail_no_cycle_info:
	pop ix
	lea ix,ix-5
	jr mem_write_bail_any
	
	;HL=GB address, A=data, preserves AF, destroys F'
mem_write_cart:
	ex af,af'
	ld iyl,a
	ld a,h
	rla
	jr c,mem_write_bail_no_cycle_info
	;HL=GB address, A'=data, preserves AF', destroys AF
mem_write_cart_always:
	ld a,h
mem_write_cart_always_a:
mbc_impl:
	.block MBC_IMPL_SIZE
mbc_zero_page_continue:
	 ; Adjust value to physical page based on ROM size
mbc1_large_rom_smc = $ ; Or combine with upper bits of page
rom_bank_mask_smc = $+1
	 and 0
	 ld b,a
	 push hl
	  ld (rom_bank_check_smc_1),a
	  ld hl,curr_rom_bank
	  xor (hl)
	  ld (hl),b
	  jp.lil nz,mbc_change_rom_bank_helper
mbc_2000_finish:
	 pop hl
mbc_denied_restore:
	pop bc
mbc_denied:
	ld a,iyl
	ex af,af'
	ret
	
mbc_zero_page_override:
	; If the masked value is 0, increase the result (except MBC5)
	inc a
	jr mbc_zero_page_continue
	
mbc_0000:
	 and $0F
mbc5_0000:
	 cp $0A
	 ld.lil ix,mpZeroPage
	 jr nz,mbc_ram_protect
cram_actual_bank_base = $+3
	 ld.lil ix,0
mbc1_ram_smc_1 = $ ; Replaced with JR NZ in MBC1 mode 0
	 jr mbc_ram_protect
cram_base_2 = $+3
	 ld.lil ix,0
	 jr mbc_ram_protect
	
mbc_4000:
mbc_6000_smc = $+1
	jp m,mbc_denied
	push bc
	 ex af,af'
	 ld c,a
	 ex af,af'
mbc_4000_impl:
	 ; Default to largest impl, large ROM MBC1
	 call mbc_ram_and_return
	 ex af,af'
	 ld a,c
	 rrca
	 rrca
	 rrca
mbc1_rom_size_smc = $+1
	 and 0
	 ld (rom_bank_mask_smc),a
	 ld a,(curr_rom_bank)
	 jr mbc_impl + mbc1_large_rom_continue
	 
mbc_ram_and_return:
	push bc
mbc_ram:
	 ld a,c
cram_size_smc = $+1
	 and 0
	 rrca
	 rrca
	 rrca
	 ld b,a
	 ld c,0
cram_base_0 = $+3
	 ld.lil ix,0
mbc_ram_any:
	 add.l ix,bc
	 ld.lil (z80codebase+cram_actual_bank_base),ix
	 ; If RAM is currently protected, don't remap
	 ld.lil a,(cram_bank_base+2)
	 inc a
mbc1_ram_smc_2 = $ ; Replaced with JR NC in MBC1 mode 0
	 jr z,mbc_no_fix_sp
mbc_ram_protect:
	 ld.lil (cram_bank_base),ix
	 ; See if SP is pointing into the swapped bank
	 ld a,(curr_gb_stack_bank)
	 cp 5 << 5
	 jr nz,mbc_no_fix_sp
mbc_fix_sp:
	 ; If so, update it
	 exx
	 push bc
	  ld bc,(sp_base_address_neg)
	  add hl,bc
	  call.il set_gb_stack_bounds_helper
	  ex de,hl
	  add.l hl,bc
	 pop bc
	 exx
mbc_no_fix_sp:
	pop bc
mbc_finish:
	ld a,iyl
	ex af,af'
	ret
	
mbc1_6000:
	push bc
	 ex af,af'
	 ld c,a
	 ex af,af'
	 ld a,c
	 rra
	 ld a,$20
cram_base_1 = $+3
	 ld.lil ix,0
	 jr nc,_
	 ld a,$18
	 ld.lil ix,(z80codebase+cram_actual_bank_base)
_
	 ld (mbc1_ram_smc_1),a
	 add a,$10
	 ld (mbc1_ram_smc_2),a
	 ld.lil a,(cram_bank_base+2)
	 inc a
	 jr nz,mbc_ram_protect
	 jr mbc_no_fix_sp
	
mbc3rtc_6000:
	ld a,(cram_actual_bank_base+2)
	cp z80codebase>>16
	jr nz,_
	ld ix,(cram_actual_bank_base)
	ld a,(ix)
	cp (ix+5)
	jr z,_
	xor a
	ld (mbc_rtc_latch_smc),a
_
	ld.lil a,(mpRtcIntStatus)
	rra
mbc_rtc_latch_smc = $+1
	jr nc,$+2 ;mbc_finish
	push bc
	 jp.lil mbc_rtc_latch_helper
	
write_audio_enable:
	 or c
	 ld (de),a
	 ; Set the appropriate bit in NR52
	 ld a,e
	 and 3
	 add a,-2
	 adc a,3
	 add a,a
	 daa
	 rra
	 ld c,a
	 ld e,NR52-ioregs
	 ld a,(de)
	 or c
	 ld (de),a
	 exx
	pop af
	ret
	
	; This cannot be implemented as a mixed-mode call; get_mem_cycle_offset
	; relies on the ADL stack having only one pushed value
lcd_enable_disable_helper:
	call get_mem_cycle_offset
	; Get the value of DIV
	ld hl,i
	add hl,de
	ex de,hl
	; Get the persistent vblank counter, just in case
persistent_vblank_counter = $+1
	ld hl,0
	jp.lil lcd_enable_disable_continue
	
get_mem_cycle_offset_swap_push:
	exx
get_mem_cycle_offset_push:
	push.l hl

; Inputs: IY = current block cycle base
;         IXL = block-relative cycle offset (negative) or NO_CYCLE_INFO[-1]
;         (SPL) = saved HL'
;         SPL = top of callstack cache - 3
;         (bottom of short stack) = JIT return address
;         AFBCDEHL' have been swapped
; Outputs: DE = (negative) cycle offset
;          May be positive if target lies within an instruction
;          Z flag reset
;          IXL is updated if it was NO_CYCLE_INFO[-1]
; Destroys AF
get_mem_cycle_offset:
	ld a,ixl
	ld (_+2),a
_
	lea de,iy
	or a
	ret m
resolve_mem_cycle_offset:
	push ix
	 push hl
	  call get_mem_info_full
	 pop hl
	pop ix
	ld a,e
	sub iyl
	ld ixl,a
	ret


; Inputs: IY = current block cycle base
;         IXL = currently known cycle info, possibly minus 1
;         (SPL) = saved HL'
;         SPL = top of callstack cache - 3
;         (bottom of short stack) = JIT return address
;         AFBCDEHL' have been swapped
; Outputs: DE = (negative) cycle offset
;          May be positive if target lies within an instruction
;          If the memory access is a routine call or NO_CYCLE_INFO is passed,
;          the following is guaranteed:
;            (IX-2) = Game Boy address
;            (IX+2) = cycles until block end from end of instruction, minus 1
;            HL = current JIT address
;          Otherwise, HL = call dispatch jump address, and since
;          get_mem_info_full was called once before with NO_CYCLE_INFO,
;          the GB address and cycle offset are located at mem_info_scratch.
; Destroys AF
get_mem_info_full:
	ld d,ixl
#ifdef DEBUG
	ld a,d
	add a,$7F - (NO_CYCLE_INFO | NO_RESCHEDULE)
	jp pe,$
#endif
	; Get the address of the recompiled code: the bottom stack entry
	ld hl,(((myz80stack - 4 - 2) / 2) - (myADLstack - 3)) & $FFFF
	add.l hl,sp
	add hl,hl
	ld hl,(hl)
	; Get the byte at the JIT target address which, if it's a jump,
	; indicates that the memory access is a branch dispatch
	ld a,(hl)
	; Assuming the JIT code was a routine call, get its target address
	dec hl
	dec hl
	ld ix,(hl)
	; If the value passed in is not NO_CYCLE_INFO, then we know it was
	; definitely a routine call, so get its target address
	bit 7,d
	jr z,resolve_mem_info
	ld a,d
get_mem_info_finish_inc2:
	inc hl
	inc hl
get_mem_info_finish:
	add a,iyl
	ld e,a
	ld d,iyh
	ret c
	dec d
	ret
	
resolve_mem_info:
	; Check if the JIT target address is an absolute jump instruction,
	; which indicates that the memory access is a branch dispatch
	cp $C3
	jr z,get_mem_info_for_branch
	; We probably have a trampoline target; however, we must check whether our
	; assumption that the JIT code was a routine call is accurate. If the first
	; byte of the JIT code is a NOP or LD IXH and not a CALL, then we actually
	; have a POP or a bitwise prefix op.
	dec hl
	bit 7,(hl)
	jr z,resolve_mem_info_for_prefix
	; Check if the target starts with a DD (LD IXL or LD IX) instruction with
	; a cycle offset that is not NO_CYCLE_INFO.
	ld a,(ix)
	sub $DD
	jr nz,resolve_mem_info_for_routine
	or (ix+2)
	jp p,resolve_mem_info_for_routine_skip
	; Remove NO_RESCHEDULE from the passed value before adding it
	res 1,d
	dec a
	add a,d
	inc hl
	jr get_mem_info_finish_inc2

get_mem_info_for_branch:
	; This is a push related to an RST, CALL, or interrupt
	ld a,dispatch_rst_00 >> 8
	cp h
	jp.lil c,get_mem_info_for_call_helper
	
	; Retrieve the cycle info and actual target address,
	; and infer the Game Boy address
	ld h,a
	ld a,l
	add a,2+3
	ld e,a
	add a,(4*10)-3
	rra
	ld l,a
	ld a,(hl)
	ld l,e
	ld ix,mem_info_scratch
	ld (ix-2),a
	ld (ix-1),0
	; Both RST and interrupt caches have an additional 4 cycles included,
	; so subtract from 3 cycles to get the last instruction cycle offset
	ld a,3
get_mem_info_for_call_finish:
	sub (hl)
	dec hl
	dec hl
	ld hl,(hl) ; Get the actual target from the dispatch
	ld (ix+2),a
	; Combine the passed NO_CYCLE_INFO offset
	dec a
	res 1,d
	add a,d
	ld d,a
	; Check if the target is possibly the flush handler
	ld a,(jit_start >> 8) - 1
	cp h
	ld a,d
	jr c,get_mem_info_finish
	; The target should be the flush handler.
#ifdef DEBUG
	ld a,h
	cp flush_handler >> 8
	jr nz,$
	ld a,l
	cp flush_handler & $FF
	jr nz,$
	ld a,d
#endif
	; Set the JIT address to a harmless location in case an event is scheduled.
	ld hl,event_value
	jr get_mem_info_finish

resolve_mem_info_for_prefix:
	; Differentiate between NOP and LD IXH
	bit 5,(hl)
	jp.lil resolve_mem_info_for_prefix_helper
	
resolve_mem_info_for_routine_skip:
	; Skip the LD IXL,NO_CYCLE_INFO
	lea ix,ix+3
resolve_mem_info_for_routine:
	; If the code is not in the JIT area, the routine call was actually for a RET
	ld a,h
	cp jit_start >> 8
	jp.lil nc,resolve_mem_info_for_routine_helper
	; The second read of an unconditional RET is always two cycles after
	; the end of a JIT sub-block. A conditional RET adds an extra cycle,
	; so we must retrieve this information which is saved on the stack.
	ld a,ixl
	cp pop_overflow & $FF
	; Get the address of the cycle count stored on the stack,
	; this is just above the return address of the call to pop_overflow
	ld hl,(((myz80stack - 4 - 4) / 2) - (myADLstack - 3)) & $FFFF
	add.l hl,sp
	add hl,hl
	ld a,(hl)
	jr z,_
	; For a callstack-based return, we must subtract the original count
	; which is located underneath the return address
	inc hl
	inc hl
	inc hl
	inc hl
	sub (hl)
_
	; Check the low bit to see if it was conditional
	rra
	; IX and HL returns are never used by reads; just get the cycle count
	ld a,iyl
	; The cycle offset is guaranteed (NO_CYCLE_INFO[-1]) | NO_RESCHEDULE,
	; so decrement and add it
	dec d
	adc a,d
	ld e,a
	ld d,iyh
	ret nc
	inc d
	ret

	.dw 0	; GB address
mem_info_scratch:
	.db 0,0
	.db 0	; Cycle offset
	
updateSTAT_if_changed_scroll:
	exx
	ex af,af'
	ld c,a
	ex af,af'
	ld d,$FF
	ld e,ixh
	ld a,(de)
	cp c
	jr z,updateSTAT_no_change_scroll
	push de
	call updateSTAT
	jp.lil scroll_write_helper
	
updateSTAT_if_changed_lyc:
	ld a,(LYC)
updateSTAT_if_changed_any:
	exx
	ex af,af'
	ld c,a
	ex af,af'
	cp c
	jr nz,updateSTAT
	pop de   ; Pop return address
updateSTAT_no_change_scroll:
	exx
	ld a,iyl
	ex af,af'
	ret
	
updateSTAT_resolve_cycle_offset:
	call resolve_mem_cycle_offset
	jr updateSTAT_resolve_cycle_offset_continue
	
	; Handle transition from fake mode 0 on LCD startup
lcd_on_STAT_handler:
	call lcd_on_STAT_restore
	inc h
	inc h
	ld a,l
	jr updateSTAT_mode2
	
updateSTAT_swap:
	exx
updateSTAT:
	push.l hl
updateSTAT_resolve_cycle_offset_continue:
	; Get the value of DIV at the end of the JIT block
updateSTAT_disable_smc = $
	ld hl,i ; Replaced with RET when LCD is disabled
	; Quickly test to see if STAT is valid for this memory access,
	; or during the entire block if no cycle info is available
	ld a,ixl
	ld (_+2),a
_
	lea de,iy
	add hl,de
nextupdatecycle_STAT = $+1
	ld de,0
	ex de,hl
	add hl,de
	inc h
	ret z
	; Check if the cycle offset was invalid, and if so, resolve the real offset
	rla
	jr nc,updateSTAT_resolve_cycle_offset
	; Now check to see if we are within one scanline after the update time
	; This limitation is needed to ensure the STAT update time is still valid
	dec h
	jr nz,updateSTAT_full
	ld a,l
	cp CYCLES_PER_SCANLINE
	jr nc,updateSTAT_full
	ld a,(STAT)
	ld h,a
	and 3
	srl a
lcd_on_updateSTAT_smc = $+1
	jr z,updateSTAT_mode0_mode1
	ld a,l
	jr c,updateSTAT_mode3
updateSTAT_mode2:
	; Check if we're currently in mode 3
	inc h
	add a,-MODE_3_CYCLES
	jr nc,updateSTAT_finish
updateSTAT_mode3:
	; Check if we're currently in mode 0
	dec h
	dec h
	dec h
	add a,-MODE_0_CYCLES
	ld l,a
	; Allow rendering catch-up after leaving mode 3, unless this frame is skipped
	ld a,h
updateSTAT_enable_catchup_smc = $+1
	ld r,a
	jr nc,updateSTAT_finish_fast
updateSTAT_mode0_mode1:
	; Update LY if it hasn't already been by an external LY read
	push de
	 push hl
	  ld hl,(nextupdatecycle_LY)
	  ex de,hl
	  add hl,de
	  ld a,h
#ifdef DEBUG
	  rla
	  sbc a,a
	  xor h
	  jr nz,$
#endif
	  or h
	  call z,updateLY_from_STAT
	  ; Check LYC coincidence
	  ld hl,(LY)
	  ld a,l
	  cp h
	 pop hl
	 res 2,h
	 jr nz,_
	 set 2,h
_
	pop de
	dec a
	cp 143
	jr nc,updateSTAT_maybe_mode1
	; Check if we're currently in mode 2
	inc h
updateSTAT_mode1_exit:
	inc h
	ld a,l
	add a,-MODE_2_CYCLES
	jr c,updateSTAT_mode2
updateSTAT_finish:
	ld l,a
	ld a,h
updateSTAT_finish_fast:
	ld (STAT),a
	ld h,$FF
	sbc hl,de
	ld (nextupdatecycle_STAT),hl
	ret
	
updateSTAT_maybe_mode1:
	; Special-case line 0 to see if vblank was exited
	inc a
	jr nz,updateSTAT_mode1
	; Check if LY update kept STAT in mode 1 or changed it to mode 0
	ld a,(STAT)
	rra
	jr nc,updateSTAT_mode1_exit
updateSTAT_mode1:
	; Disable catch-up rendering in case of vblank overflow
	xor a
	ld r,a
	; Save LYC coincidence bit and ensure mode 1 is set
	inc a
	or h
	ld (STAT),a
	; Set STAT update time to LY update time
	ld hl,(nextupdatecycle_LY)
	ld (nextupdatecycle_STAT),hl
	ret
	
get_scanline_past_vblank:
	ld r,a ; Disable catchup rendering when overflowing to vblank
	ld de,((SCANLINES_PER_FRAME-1)<<8) | (CYCLES_PER_SCANLINE<<1)
	add hl,de
	jr get_scanline_from_cycle_count_finish
	
; Inputs: HL-DE = current value of DIV
; Outputs: (LY) = current value of LY
;          (STAT) = current value of STAT
;          (nextupdatecycle_LY) = negated cycle count of next LY update
;          (nextupdatecycle_STAT) = negated cycle count of next STAT update
; Destroys: AF, DE, HL, IX
updateSTAT_full:
	; Get negative DIV, the starting point for update times
	xor a
	sbc hl,hl
updateSTAT_full_for_LY:
	sbc hl,de
	push hl
	 ; Subtract from the vblank time, to get cycles until vblank
vblank_counter = $+1
	 ld de,0
	 add hl,de
	 ; Decrement by 1, for cycles until the cycle before vblank
	 dec hl
	 ; Normalize the divisor and also check if the current cycle is past vblank
	 add hl,hl
	 jr c,get_scanline_past_vblank
	
get_scanline_from_cycle_count:
	 ; Algorithm adapted from Improved division by invariant integers
	 ; To make things simpler, a pre-normalized divisor is used, and the dividend
	 ; and remainder are scaled and descaled according to the normalization factor
	 ; This should also make it trivial to support GBC double-speed mode in the
	 ; future where the normalized divisor will be the actual divisor
	 ld d,65535 / (CYCLES_PER_SCANLINE<<1) - 256
	 ld e,h
	 mlt de
	 ex de,hl
	 add hl,de
	 ld d,h
	 inc h
	 ld a,l
	 ld l,256-(CYCLES_PER_SCANLINE<<1)
	 mlt hl
	 add hl,de
	 cp l
	 ld a,l
	 jr c,++_
	 inc d
	 sub CYCLES_PER_SCANLINE<<1
	 jr c,get_scanline_from_cycle_count_finish
	 ; Unlikely condition
	 ld l,a
_
	 inc d
	 jr get_scanline_from_cycle_count_finish
_
	 add a,CYCLES_PER_SCANLINE<<1
	 jr nc,--_ ; Unlikely condition
	 ld l,a
get_scanline_from_cycle_count_finish:
	 ; Scanline number (backwards from last before vblank) is in D,
	 ; and cycle offset (backwards from last scanline cycle) is in L
	 ld a,143
	 sub d
	pop de
	push bc
	 jr c,updateSTAT_full_vblank
	 ; Scanline is during active video
	 ld b,a
	 xor a
	 ld c,a
	 ; Get the (negative) cycles until the next scanline
	 dec a
	 ; Allow rendering catch-up outside of vblank, if this frame isn't skipped
updateSTAT_full_enable_catchup_smc = $+1
	 ld r,a
	 ld h,a
	 xor l
	 rrca ;NOP this out in double-speed
	 ld l,a
	 ; Add to the negative DIV count
	 add hl,de
	 ld (nextupdatecycle_LY),hl
	 ; Determine the STAT mode and the cycles until next update
	 ; Check if during mode 0
	 ld l,a
	 add a,MODE_0_CYCLES
	 jr c,_
	 ; Check if during mode 3
	 ld l,a
	 inc c
	 inc c
	 inc c
	 add a,MODE_3_CYCLES
	 jr c,_
	 ; During mode 2
	 ld l,a
	 dec c
_
	 ld h,$FF
	 add hl,de
	 ld (nextupdatecycle_STAT),hl
updateSTAT_full_finish:
	 ; Write value of LY
	 ld a,b
	 ld hl,LY
	 ld (hl),a
	 ; Check for LYC coincidence
	 inc hl
	 cp (hl)
	 jr nz,_
	 set 2,c
_
	 ; Write low bits of STAT
	 ld l,STAT & $FF
	 ld a,(hl)
	 and $F8
	 or c
	 ld (hl),a
	pop bc
lcd_on_STAT_restore:
	ret ; Replaced with .LIL prefix
	.db $C3
	.dl lcd_on_STAT_restore_helper
	
updateSTAT_full_for_LY_restore:
	sub l
	ld l,a
updateSTAT_full_for_LY_trampoline:
	ex de,hl
	xor a
	jr updateSTAT_full_for_LY
	
updateSTAT_full_vblank:
	 ; Set mode 1 unconditionally
	 ld c,1
	 ; Get the actual scanline, and check whether it's the final line
	 inc a
	 add a,SCANLINES_PER_FRAME - 1
	 ld b,a
	 jr nc,updateSTAT_full_last_scanline
	 ; Get the (negative) cycles until the next scanline
	 sbc a,a
	 ld h,a
	 xor l
	 rrca ; NOP this out in double-speed mode
_
	 ld l,a
_
	 ; Add to the negative DIV count
	 add hl,de
	 ; This will be used for both the next LY and STAT update times
	 ; Since during vblank, STAT must still be updated for LY=LYC
	 ld (nextupdatecycle_LY),hl
	 ld (nextupdatecycle_STAT),hl
	 jr updateSTAT_full_finish
	
updateSTAT_full_last_scanline:
	 ; On the final line, set LY to 0 after the first cycle
	 ld h,$FF
	 ld a,l
	 cpl
	 rrca
	 ld l,a
	 add a,CYCLES_PER_SCANLINE - 1
	 jr nc,--_
	 ld b,0
	 jr -_
	
updateSTAT_full_for_setup:
	call updateSTAT_full
	ret.l
	
updateLY_resolve_cycle_offset:
	call resolve_mem_cycle_offset
	jr updateLY_resolve_cycle_offset_continue
	
updateLY:
	exx
	push.l hl
updateLY_resolve_cycle_offset_continue:
	; Get the value of DIV at the end of the JIT block
updateLY_disable_smc = $
	ld hl,i ; Replaced with RET when LCD is disabled
	; Quickly test to see if LY is valid for this memory access,
	; or during the entire block if no cycle info is available
	ld a,ixl
	ld (_+2),a
_
	lea de,iy
	add hl,de
nextupdatecycle_LY = $+1
	ld de,0
	add hl,de
	inc h
	ret z
	; Check if the cycle offset was invalid, and if so, resolve the real offset
	rla
	jr nc,updateLY_resolve_cycle_offset
	; Now check to see if we are within one scanline after the update time
	dec h
	jr nz,updateSTAT_full_for_LY_trampoline
updateLY_from_STAT:
	ld a,l
	ld l,-CYCLES_PER_SCANLINE
	add a,l
	jr c,updateSTAT_full_for_LY_restore
	; If so, advance to the next scanline directly
	dec h
	add hl,de
	ld e,a
	ld (nextupdatecycle_LY),hl
	ld hl,LY
	ld a,(hl)
	inc (hl)
	dec a
	cp SCANLINES_PER_FRAME-3
	ret c
	; Special cases for advancing from lines 0, 152, and 153
	; Note that the STAT mode is always 1 during vblank, and always not 1
	; outside of vblank; this allows differentiating between the two halves
	; of line 0 (vblank and active video) without tracking additional state.
	; However, the mode value is not used outside of updateLY unless the STAT
	; cache is also valid.
	jr z,updateLY_from_line_152
	inc a
	jr z,updateLY_from_line_0
	; If LY was 153, check whether to exit vblank
	ld a,e
	ld de,1
	; Always advance to line 0
	ld (hl),d
	add a,e
	jr nc,updateLY_to_line_0_vblank
	; Exit vblank (setting mode 0) and schedule forward to line 1 change
	ld l,STAT & $FF
	dec (hl)
	ld de,1-CYCLES_PER_SCANLINE
updateLY_to_line_0_vblank:
	; Line 0 node 1 duration is one cycle less than originally scheduled
updateLY_to_line_153:
	; Keep line 153 and schedule backward to line 0 change
	ld hl,(nextupdatecycle_LY)
	add hl,de
	ld (nextupdatecycle_LY),hl
	ret
	
updateLY_from_line_152:
	; If LY was 152, check whether to proceed to line 0
	ld a,e
	ld de,CYCLES_PER_SCANLINE=1
	add a,e
	jr nc,updateLY_to_line_153
	; Advance to line 0 in mode 1, keeping original schedule
	ld (hl),d
	ret

updateLY_from_line_0:
	; If the PPU is no longer in vblank, keep line 1 advancement
	ld a,(STAT)
	dec a
	ld e,a
	and 3
	ret nz
	; Return to line 0 and exit vblank (arbitrarily setting mode 0)
	ld (hl),a
	ld l,STAT & $FF
	ld (hl),e
	ret
	
; Output: BCDEHL' are swapped
;         (SPL) = saved HL'
;         DE = current cycle offset
;         Z flag set if TIMA reload occurs this cycle
;         (TIMA) updated to current value
updateTIMA:
enableTIMA_smc = $
	jp get_mem_cycle_offset_swap_push ; Replaced with CALL when enabled
	 ld hl,i ; Resets carry
	 ld a,b
	 ld bc,(timer_counter)
	 sbc hl,bc
	 ld b,a
	 ; Handle special case if cycle offset is non-negative
	 xor a
	 add hl,de
	 cp h
	 jr z,updateTIMAoverflow
updateTIMAcontinue:
	 inc hl
updateTIMA_smc = $+1
	 jr $+8
	 add hl,hl
	 add hl,hl
	 add hl,hl
	 add hl,hl
	 add hl,hl
	 add hl,hl
	 ld a,h
	 ld (TIMA),a
	 ret
	
updateTIMAoverflow:
	 ; Check if the cycle offset was non-negative, which is the only case
	 ; that a mid-instruction overflow is possible
	 cp d
	 jr nz,updateTIMAcontinue
	 ; Check if the cycle offset caused the overflow
	 ld a,e
	 cp l
	 jr c,updateTIMAcontinue
updateTIMAoverflow_loop:
	 ; If so, handle timer event(s) immediately
	 ld c,l
	 push de
	  push bc
	   ld l,h
	   ld e,d
	   ld bc,(timer_counter)
	   call timer_expired_handler
	  pop bc
	  xor a
	  ld h,a
	  ; Set Z flag if the reload happened on this cycle
	  or c
	  ld l,a
	  add hl,de
	 pop de
	 jr nc,updateTIMAcontinue
	 jr updateTIMAoverflow_loop
	
	; Cached RST and interrupt handlers are combined in this space
	; Handlers consist of a jump followed by a cycle count
	; Interrupt handlers are indexed by 1, 2, 4, 8, 16
	; Address info is stored in halves of empty handler slots
	; Handler to address info mapping: add 10 slots and divide by 2
	; Unused slot halves: 7.5, 9.5, 10.0, 12.0, 12.5
	.block (-$)&$FF
dispatch_rst_00: ;0 -> 5.0
	jp 0 \ .db 0
dispatch_vblank: ;1 -> 5.5
	jp 0 \ .db 0
dispatch_stat:   ;2 -> 6.0
	jp 0 \ .db 0
dispatch_rst_08: ;3 -> 6.5
	jp 0 \ .db 0
dispatch_timer:  ;4 -> 7.0
	jp 0 \ .db 0
	; Address info for RST 00h, VBLANK, STAT, RST 08h, TIMER
	.dw $0000, $0040, $0048, $0008, $0050, 0
dispatch_serial: ;8 -> 9.0
	jp 0 \ .db 0
	; Address info for SERIAL, RST 10h
	.dw $0058, 0, 0, $0010
dispatch_rst_10: ;11 -> 10.5
	jp 0 \ .db 0
	; Address info for JOYPAD, RST 18h - 38h
	.dw 0, 0, $0060, $0018, $0020, $0028, $0030, $0038
dispatch_joypad: ;16 -> 13.0
	jp 0 \ .db 0
dispatch_rst_18: ;17 -> 13.5
	jp 0 \ .db 0
dispatch_rst_20: ;18 -> 14.0
	jp 0 \ .db 0
dispatch_rst_28: ;19 -> 14.5
	jp 0 \ .db 0
dispatch_rst_30: ;20 -> 15.0
	jp 0 \ .db 0
dispatch_rst_38: ;21 -> 15.5
	jp 0 \ .db 0
	
wait_for_interrupt_stub:
	ei
	halt
	ret.l
	
flush_handler:
	exx
flush_address = $+1
	ld de,0
	jp.lil flush_normal
	
flush_mem_handler:
	exx
	ex af,af'
	ld iyl,a
	ld a,b
	pop bc
	jp.lil flush_mem
	
coherency_handler:
	pop ix
	pea ix+RAM_PREFIX_SIZE-3
	ld ix,(ix)
	jp.lil check_coherency_helper

coherency_return:
	pop.l hl
	exx
	ex af,af'
	ret
	
handle_overlapped_op_1_1:
	pop ix
	jp.lil handle_overlapped_op_1_1_helper
	
handle_overlapped_op_1_2:
	pop ix
	jp.lil handle_overlapped_op_1_2_helper
	
handle_overlapped_op_2_1:
	pop ix
	jp.lil handle_overlapped_op_2_1_helper
	
Z80InvalidOpcode:
	jp.lil Z80InvalidOpcode_helper
	
Z80Error:
	jp.lil runtime_error
	
	.echo (-$-59)&$FF, " wasted Z80 bytes"
	.block (-$-59)&$FF
_
	ld de,disabled_counter_checker
	ld (event_counter_checker_slot_serial),de
	exx
	ld a,iyl
	ex af,af'
	ret
	
_writeSChandler:
	exx
	ex af,af'
	ld c,a
	ex af,af'
	ld a,c
	or $7E
	ld (SC),a
	inc a
	jr nz,-_
	call get_mem_cycle_offset_push
	 ld hl,serial_counter_checker
	 ld (event_counter_checker_slot_serial),hl
	 ; Get the DIV counter for the current cycle
	 ld hl,i
	 add hl,de
	 ; To make things simpler, since bits tick every 128 cycles,
	 ; shift left once before overriding the low byte
	 add hl,hl
	 ld a,(serial_counter)
	 ; Preserve the top bit of DIV in bit 0 while shifting left
	 rla
	 ; Check whether the tick has already occurred
	 cp l
	 ld l,a
	 ; Adjust the upper byte by 8 if the tick already occurred,
	 ; otherwise by 7
	 ld a,h
	 adc a,7
	 ld h,a
	 ; Rotate the counter back and save it
	 rra
	 rr l
	 rr h
	 ld (serial_counter),hl
	 jp reschedule_event_serial
	
#if $ & 255
	.error "mem_write_port_routines must be aligned: ", $ & 255
#endif
	
mem_write_port_routines:
writeIE:
	ex af,af'
	ld (IE),a
	ex af,af'
	exx
	jr checkInt
	
writeSChandler:
	ex af,af'
	ld a,iyl
writeSC:
	jr _writeSChandler
	
writeIEhandler:
	ld (IE),a
	ex af,af'
	ld iyl,a
	exx
	jr checkInt
	
writeIFhandler:
	ex af,af'
	ld iyl,a
writeIF:
	ld a,iyh
	or a
	exx
	call z,handle_events_for_mem_access
	ex af,af'
	ld c,a
	ex af,af'
	ld a,c
	and $1F
	ld (active_ints),a
checkInt:
	; Check the pre-delay interrupt state, since if the interrupt enable
	; delay is active then an interrupt check is already scheduled
	ld a,(intstate_smc_2)
	or a
	jr z,checkIntDisabled
	ld de,(IE)
	ld a,d
	and e
	jp nz,trigger_event_swapped
checkIntDisabled:
	exx
write_port_ignore:
	ld a,iyl
	ex af,af'
	ret

writeTIMAignore:
	pop.l hl
	jr checkIntDisabled

writeTAChandler:
	ex af,af'
	ld iyl,a
writeTAC:
	call updateTIMA
	 jp.lil tac_write_helper

writeTIMAhandler:
	ex af,af'
	ld iyl,a
writeTIMA:
	call updateTIMA
	 jp nz,tima_write_helper
	; Ignore writes directly on the reload cycle
	pop.l hl
	jr checkIntDisabled

writeLCDChandler:
	ex af,af'
	ld iyl,a
writeLCDC:
	call updateSTAT_swap
	jp.lil lcdc_write_helper

writeSTAThandler:
	ex af,af'
	ld iyl,a
writeSTAT:
	call updateSTAT_swap
	jp.lil stat_write_helper
	
writeLYChandler:
	ex af,af'
	ld iyl,a
writeLYC:
	call updateSTAT_if_changed_lyc
	jp.lil lyc_write_helper
	
writeDIVhandler:
	ex af,af'
	ld iyl,a
writeDIV:
	call updateTIMA
	 jp.lil div_write_helper

;==============================================================================
; Everything below this point must not cause a reschedule on write
;==============================================================================
write_audio:
	ld a,iyl
	ex af,af'
write_audio_handler:
write_audio_disable_smc = $
	push af
	 exx
	 ld c,a
	 ld ixl,ixh
	 ld e,ixl
	 ld d,$FF
	 ld ixh,audio_port_value_base >> 8
	 ld (ix),c
	 ld a,(ix + audio_port_masks - audio_port_values)
	 ; Handle writes to the enable bit specially
	 cp $BF
	 jr nz,_
	 bit 7,c
	 jp nz,write_audio_enable
_
	 or c
	 ld (de),a
	 exx
	pop af
	ret
	
write_scroll_handler:
	ex af,af'
	ld iyl,a
write_scroll:
	jp updateSTAT_if_changed_scroll
	
writeTMAhandler:
	ex af,af'
	ld iyl,a
writeTMA:
	jp _writeTMA
	
writeDMAhandler:
	ex af,af'
	ld iyl,a
writeDMA:
	call updateSTAT_swap
	jp.lil dma_write_helper
	
writeBGPhandler:
	ex af,af'
	ld iyl,a
writeBGP:
	ld a,(BGP)
	call updateSTAT_if_changed_any
	jp.lil BGP_write_helper
	
writeNR52handler:
	ex af,af'
	ld iyl,a
writeNR52:
	jp.lil NR52_write_helper
	
writeP1:
	ld a,iyl
	ex af,af'
writeP1handler:
	push af
	 or $CF
	 bit 4,a
	 jr nz,_
keys_low = $+1
	 and $FF
_
	 bit 5,a
	 jr nz,_
keys_high = $+1
	 and $FF
_
	 ld (P1),a
	pop af
	ret
	
	; Compatible with LD ($FF00+C),A
write_port_direct:
	ld a,iyl
	ex af,af'
	exx
	ld d,$FF
	ld e,ixh
	ld (de),a
	exx
	ret
	
	; Only invoked through (r16) writes or mem_write_any
write_hram_direct:
	ld a,iyl
	ex af,af'
	ld (hl),a
	ret
	
	.echo mem_write_port_routines+256-$, " bytes remaining for port writes"
	.block mem_write_port_routines+256-$
mem_write_port_lut:
;00
	.db writeP1 - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db writeSC - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db writeDIV - mem_write_port_routines
	.db writeTIMA - mem_write_port_routines
	.db writeTMA - mem_write_port_routines
	.db writeTAC - mem_write_port_routines
;08
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db writeIF - mem_write_port_routines
;10
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
;18
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
;20
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db write_audio - mem_write_port_routines
	.db writeNR52 - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
;28
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
;30
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
;38
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
	.db write_port_direct - mem_write_port_routines
;40
	.db writeLCDC - mem_write_port_routines
	.db writeSTAT - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db write_port_ignore - mem_write_port_routines
	.db writeLYC - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db writeBGP - mem_write_port_routines
;48
	.db write_scroll - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
	.db write_scroll - mem_write_port_routines
;4C
	.fill $FF80 - (WX+1), write_port_ignore - mem_write_port_routines
;80
	.fill IE - $FF80, write_hram_direct - mem_write_port_routines
;FF
	.db writeIE - mem_write_port_routines
	
audio_port_value_base:
	.block 1
	
rtc_latched:
try_unlock_sha:
	; 5 bytes of code, will be overwritten by RTC init
	in0 a,($06)
	ret.l z
	;.db 0	;seconds
	;.db 0	;minutes
	;.db 0	;hours
	;.dw 0	;days
rtc_current:
	; 5 bytes of code, will be overwritten by RTC init
	set 2,a
	out0 ($06),a
	;.db 0	;seconds
	;.db 0	;minutes
	;.db 0	;hours
	;.dw 0	;days
rtc_last:
	; 2 bytes of code, will be overwritten by RTC init
	ret.l
	;.db 0   ;seconds
	;.db 0   ;minutes
	.db 0   ;hours
	.dw 0   ;days
	
audio_port_values:
	.block NR52 - NR10
audio_port_masks:
	;NR10 - NR14
	.db $80, $3F, $00, $FF, $BF
	;unused, NR21 - NR24
	.db $FF, $3F, $00, $FF, $BF
	;NR30 - NR34
	.db $7F, $FF, $9F, $FF, $BF
	;unused, NR41 - NR44
	.db $FF, $FF, $00, $00, $BF
	;NR50 - NR51
	.db $00, $00
	
keys:
	.dw $FFFF
	
memroutine_next:
	.dl 0
render_save_sps:
	.dw 0
	
	; One word of stack space for sprite rendering during vblank
lcd_on_ppu_event_checker:
	.dw 0
event_counter_checkers:
event_counter_checker_slot_PPU:
	.dw ppu_expired_vblank
event_counter_checker_slot_timer:
	.dw disabled_counter_checker
event_counter_checker_slot_serial:
	.dw disabled_counter_checker
event_counter_checkers_ei_delay:
	.dw event_counter_checkers_done
	
	.assume adl=1
z80codesize = $-0
	.org z80code+z80codesize
	
	.echo "Z80 mode code size: ", z80codesize
	
jit_start = z80codesize
