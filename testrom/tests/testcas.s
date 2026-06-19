/**************
 Initialization
 **************/
.global _testcas
_testcas:
 sts.l  pr, @-r15
 mov.l  _pfail, r13 !fail address
 bra    _testgo
 nop
_pfail: .long _fail
_testgo:

/*****************
 CAS Rm, Rn, @R0
 *****************/
_cas_r:
 mov.l  _pram0_cas, r0
 mov.l  _p11223344_cas, r1
 mov.l  _p00001122_cas, r2
 mov.l  _p55aa55aa_cas, r3
 mov.l  r1, @r0

 mov.l  _pram0_4_cas, r4
 mov.l  _paabbccdd_cas, r5
 mov.l  r5, @r4
!----
 mov    #0, r10
 mov    #1, r11
 mov    #2, r12
 mov    r1, r8
 mov    r2, r9
/* cas.l r8, r9, @r0 */
 .word 0x02983

! cas.l had a bug where a subsequent instruction was skipped when the write back happened
! Do some movs to check later
 mov #10, r10
 mov #11, r11
 mov #12, r12

!---- check CAS succeeded
 bt     .+6
 jmp    @r13
 nop
!---- check r8 unchanged
 cmp/eq r8, r1
 bt     .+6
 jmp    @r13
 nop
!---- check r9 was set to old @R0
 cmp/eq r9, r1
 bt     .+6
 jmp    @r13
 nop
!---- check that @R0 was written
 mov.l  @r0, r4
 cmp/eq r4, r2
 bt     .+6
 jmp    @r13
 nop
!---- check mov instructions after cas set r10, r11, and r12
 mov    #10, r7
 cmp/eq r7, r10
 bt     .+6
 jmp    @r13
 nop
 mov    #11, r7
 cmp/eq r7, r11
 bt     .+6
 jmp    @r13
 nop
 mov    #12, r7
 cmp/eq r7, r12
 bt     .+6
 jmp    @r13
 nop
!----

 mov    #0, r10
 mov    #1, r11
 mov    #2, r12
 mov.l  r1, @r0
 mov    r3, r8
 mov    r2, r9
/* cas.l r8, r9, @r0 */
 .word 0x02983

! cas.l had a bug where a subsequent instruction was skipped when the write back happened
! Do some movs to check later
 mov #10, r10
 mov #11, r11
 mov #12, r12

!---- check CAS failed
 bf     .+6
 jmp    @r13
 nop
!---- check r8 unchanged
 cmp/eq r8, r3
 bt     .+6
 jmp    @r13
 nop
!---- check r9 was set to old @R0
 cmp/eq r9, r1
 bt     .+6
 jmp    @r13
 nop
!---- check that @R0 unchanged
 mov.l  @r0, r4
 cmp/eq r4, r1
 bt     .+6
 jmp    @r13
 nop
!---- check mov instructions after cas set r10, r11, and r12
 mov    #10, r7
 cmp/eq r7, r10
 bt     .+6
 jmp    @r13
 nop
 mov    #11, r7
 cmp/eq r7, r11
 bt     .+6
 jmp    @r13
 nop
 mov    #12, r7
 cmp/eq r7, r12
 bt     .+6
 jmp    @r13
 nop
!----

/**************
 Constant Table - Second table because cas tests were pushing previous
	constant table past pcrel limit
 **************/
 bra    _constantend_cas
 nop
.align 4
_pram0_cas    : .long _ram0+128
_pram0_4_cas  : .long _ram0+128+4
_p55aa55aa_cas: .long 0x55aa55aa
_p11223344_cas: .long 0x11223344
_p00001122_cas: .long 0x00001122
_paabbccdd_cas: .long 0xaabbccdd
.align 2
_constantend_cas:

/**************
 Congratulations
 **************/
_pass:
 lds.l  @r15+, pr
 mov.l _ppass_value, r0
 mov.l _ppass_addr, r1
 mov.l r0, @r1
 rts
 nop
.align 4
_ppass_addr: .long 0xABCD0000
_ppass_value: .long 0x00000024

/**********
 You Failed
 **********/
_fail:
 mov.l _pfail_value, r0
 mov.l _pfail_value, r1
 bra   _fail
 nop
.align 4
_pfail_value: .long 0x88888888

.end
