/* tlbwalk.c -- M6 software page-table walker (filled in Task 2). */
unsigned long __jcore_tlb_walk(unsigned long *pgd,
                               unsigned long addr,
                               unsigned long *tsb_slot)
{
	(void)pgd; (void)addr; (void)tsb_slot;
	return 0;
}
