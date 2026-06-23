/* tlbwalk.c -- M6 software page-table walker (linux-spec §4.2 transliteration).
 *
 * Single-level-effective for the test: a one-entry PGD (index 0) points at a
 * 4 KB PTE table; the PTE word is the hardware PTEL image so the asm hot path
 * can LDC it straight into PTEL. On success, also writes the 16-byte TSB slot
 * (tag_hi=VPN, tag_lo=ASID_TAG, Data=PTEL) so the next touch of this VPN hits
 * the §4.1 fast path, and bumps the walker_calls counter. */

typedef unsigned long u32;

#define WALKER_CALLS  (*(volatile u32 *)0x80002D00)

#define _PAGE_VALID   0x1UL        /* PTEL bit0 (V) and PGD present bit */
#define PTE_TAB_MASK  (~0xFUL)     /* PGD entry low nibble = flags      */

unsigned long __jcore_tlb_walk(u32 *pgd, u32 addr, u32 *tsb_slot)
{
	u32 pde = pgd[0];                       /* pgd_index(addr) == 0 here */
	u32 *pte_tab;
	u32 idx, pte;

	if (!(pde & _PAGE_VALID))               /* pgd_none / not present */
		return 0;

	pte_tab = (u32 *)(pde & PTE_TAB_MASK);
	idx = (addr >> 12) & 0x3FF;             /* VA[21:12] */
	pte = pte_tab[idx];

	if (!(pte & _PAGE_VALID))               /* PTE not valid -> real fault */
		return 0;

	WALKER_CALLS++;

	tsb_slot[0] = addr;                     /* +0  tag_hi  = expected VPN  */
	tsb_slot[1] = 0;                        /* +4  tag_lo  = expected ASID */
	tsb_slot[2] = pte;                      /* +8  Data lo = PTEL image    */
	tsb_slot[3] = 0;                        /* +12 Data hi = unused (J32)  */

	return pte;
}
