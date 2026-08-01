#ifndef SIM_INSTR_H
#define SIM_INSTR_H

#define SIM_INSTR_MAGIC 0x3321AACC

#define CMD_BAD_INSTR 1
#define CMD_ENABLE_EVENT_TRIGGER 2
#define CMD_ENABLE_TEST_RESULT 3
#define CMD_ENABLE_DUMP_STACK 4

#define EVENT_TRIGGER_ADDRESS 0xBCDE0000
#define TEST_RESULT_ADDRESS 0xBCDE0010

/* Written by a guard's _done to claim success. Deliberately not zero: the
 * harness used to treat any zero write as PASS, which made an uninitialised
 * or stray write indistinguishable from a guard that actually completed. */
#define TEST_PASS_MAGIC 0x600DC0DE
#define DUMP_STACK_ADDRESS 0xBCDE0020

#endif
