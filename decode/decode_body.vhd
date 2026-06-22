-- ******************************************************************
-- ******************************************************************
-- ******************************************************************
-- This file is generated. Changing this file directly is probably
-- not what you want to do. Any changes will be overwritten next time
-- the generator is run.
-- ******************************************************************
-- ******************************************************************
-- ******************************************************************
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.decode_pack.all;
use work.cpu2j0_components_pack.all;
use work.mult_pkg.all;
package body decode_pack is
    function predecode_rom_addr (code : std_logic_vector(15 downto 0)) return std_logic_vector is
        variable addr : std_logic_vector(8 downto 0);
    begin
        case code(15 downto 12) is
            when x"0" =>
                -- 0000 0000 0000 1000 => 000000000  CLRT
                -- 0000 0000 0010 1000 => 000000001  CLRMAC
                -- 0000 0000 0001 1001 => 000000010  DIV0U
                -- 0000 0000 0000 1001 => 000000011  NOP
                -- 0000 0000 0010 1011 => 000000100  RTE
                -- 0000 0000 0000 1011 => 000000111  RTS
                -- 0000 0000 0001 1000 => 000001001  SETT
                -- 0000 0000 0001 1011 => 000001010  SLEEP
                -- 0000 0000 0011 1011 => 000001110  BGND
                -- 0000 ---- 0010 1001 => 000010010  MOVT Rn
                -- 0000 ---- 0000 0010 => 000100001  STC SR, Rn
                -- 0000 ---- 0001 0010 => 000100010  STC GBR, Rn
                -- 0000 ---- 0010 0010 => 000100011  STC VBR, Rn
                -- 0000 ---- 0000 1010 => 000100100  STS MACH, Rn
                -- 0000 ---- 0001 1010 => 000100101  STS MACL, Rn
                -- 0000 ---- 0010 1010 => 000100110  STS PR, Rn
                -- 0000 ---- 0101 1010 => 000110110  STS CPI_COM, Rn
                -- 0000 ---- 0010 0011 => 001010011  BRAF Rm
                -- 0000 ---- 0000 0011 => 001010101  BSRF Rm
                -- 0000 ---- ---- 0111 => 001101110  MUL.L Rm, Rn
                -- 0000 ---- ---- 1111 => 010000101  MAC.L @Rm+, @Rn+
                -- 0000 ---- ---- 0100 => 010010011  MOV.B Rm, @(R0, Rn)
                -- 0000 ---- ---- 0101 => 010010100  MOV.W Rm, @(R0, Rn)
                -- 0000 ---- ---- 0110 => 010010101  MOV.L Rm, @(R0, Rn)
                -- 0000 ---- ---- 1100 => 010010110  MOV.B @(R0, Rm), Rn
                -- 0000 ---- ---- 1101 => 010010111  MOV.W @(R0, Rm), Rn
                -- 0000 ---- ---- 1110 => 010011000  MOV.L @(R0, Rm), Rn
                -- 0000 ---- 1--- 0010 => 011010001  STC Rm_BANK, Rn
                -- 0000 ---- 0011 0010 => 011010010  STC SSR, Rn
                -- 0000 ---- 0100 0010 => 011010011  STC SPC, Rn
                -- 0000 ---- 0101 0010 => 011010110  STC EXPEVT, Rn
                -- 0000 ---- 0110 0010 => 011010111  STC INTEVT, Rn
                -- 0000 ---- 0111 0010 => 011011000  STC TRA, Rn
                -- 0000 ---- 0101 0011 => 011011010  STC PTEH, Rn
                -- 0000 ---- 0110 0011 => 011011100  STC PTEL, Rn
                -- 0000 ---- 0111 0011 => 011011110  STC ASIDR, Rn
                -- 0000 0000 0011 1000 => 011011111  LDTLB
                addr(0) := (not code(0) and not code(1) and not code(2) and code(3) and code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and not code(1) and not code(2) and code(3) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(3) and code(7)) or (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(2) and not code(3)) or (code(0) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(2) and code(3)) or (code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7));
                addr(1) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and not code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and not code(3) and code(4) and code(5) and code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(3) and code(7)) or (not code(0) and code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2)) or (code(0) and not code(1) and code(2) and not code(3)) or (code(0) and code(1) and not code(2) and not code(3) and not code(4) and code(5) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(1) and not code(2) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(1) and code(2) and code(3)));
                addr(2) := (not code(0) and not code(1) and not code(2) and code(3) and code(4) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(7)) or (not code(0) and code(1) and not code(2) and code(4) and not code(5) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and code(5) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(1) and not code(2) and code(3) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(2)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(2) and not code(3) and not code(4) and code(5) and code(6) and not code(7)) or (code(1) and code(2) and not code(3));
                addr(3) := (not code(0) and not code(1) and not code(2) and code(3) and code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and code(2) and code(3)) or (code(0) and code(1) and not code(2) and not code(3) and code(4) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and code(5) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(1) and code(2) and not code(3)) or (code(1) and not code(2) and not code(3) and code(4) and code(5) and code(6) and not code(7));
                addr(4) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(1) and code(2)) or (not code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)));
                addr(5) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and not code(3));
                addr(6) := (not code(0) and not code(1) and not code(2) and code(3) and code(4) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and not code(3) and code(4) and code(5) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(3) and code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(3) and code(7)) or (code(0) and code(1) and not code(2) and not code(3) and not code(4) and code(5) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and not code(3)) or (code(1) and not code(2) and not code(3) and code(4) and code(6) and not code(7));
                addr(7) := (not code(0) and not code(1) and not code(2) and code(3) and code(4) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and not code(3) and code(4) and code(5) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(3) and code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(3) and code(7)) or (not code(0) and code(2)) or (not code(1) and code(2)) or (code(1) and not code(2) and not code(3) and code(4) and code(6) and not code(7)) or (code(1) and not code(2) and not code(3) and code(5) and code(6) and not code(7)) or (code(2) and code(3));
                addr(8) := '0';

            when x"1" =>
                -- 0001 ---- ---- ---- => 010011101  MOV.L Rm, @(disp, Rn)
                addr := "010011101";

            when x"2" =>
                -- 0010 ---- ---- 1001 => 001011010  AND Rm, Rn
                -- 0010 ---- ---- 1100 => 001100000  CMP /STR Rm, Rn
                -- 0010 ---- ---- 0011 => 001100001  CAS.L Rm, Rn, @R0
                -- 0010 ---- ---- 0111 => 001100110  DIV0S Rm, Rn
                -- 0010 ---- ---- 1111 => 001101111  MULS.W Rm, Rn
                -- 0010 ---- ---- 1110 => 001110000  MULU.W Rm, Rn
                -- 0010 ---- ---- 1011 => 001110100  OR Rm, Rn
                -- 0010 ---- ---- 1000 => 001111010  TST Rm, Rn
                -- 0010 ---- ---- 1010 => 001111011  XOR Rm, Rn
                -- 0010 ---- ---- 1101 => 001111100  XTRACT Rm, Rn
                -- 0010 ---- ---- 0000 => 001111111  MOV.B Rm, @Rn
                -- 0010 ---- ---- 0001 => 010000000  MOV.W Rm, @Rn
                -- 0010 ---- ---- 0010 => 010000001  MOV.L Rm, @Rn
                -- 0010 ---- ---- 0100 => 010010000  MOV.B Rm,@-Rn
                -- 0010 ---- ---- 0101 => 010010001  MOV.W Rm,@-Rn
                -- 0010 ---- ---- 0110 => 010010010  MOV.L Rm,@-Rn
                addr(0) := (not code(0) and code(1) and not code(2)) or (not code(0) and not code(2) and not code(3)) or (code(0) and not code(1) and code(2) and not code(3)) or (code(0) and code(1) and code(2) and code(3)) or (code(1) and not code(2) and not code(3));
                addr(1) := (not code(0) and not code(1) and not code(2)) or (not code(0) and not code(2) and code(3)) or (code(0) and code(1) and code(2)) or (not code(1) and not code(2) and code(3)) or (code(1) and code(2) and not code(3));
                addr(2) := (not code(0) and not code(1) and not code(2) and not code(3)) or (code(0) and code(1) and code(2)) or (code(0) and code(1) and code(3)) or (code(0) and code(2) and code(3));
                addr(3) := (not code(0) and not code(1) and not code(2)) or (not code(0) and not code(2) and code(3)) or (code(0) and not code(1) and code(3)) or (code(0) and code(2) and code(3));
                addr(4) := (not code(0) and not code(1) and not code(3)) or (not code(0) and code(1) and code(2)) or (code(0) and not code(1) and code(2)) or (not code(2) and code(3));
                addr(5) := not ((not code(0) and code(1) and not code(3)) or (code(0) and not code(1) and not code(2)) or (not code(1) and code(2) and not code(3)));
                addr(6) := (not code(0) and not code(1) and not code(2)) or (code(0) and code(1)) or (code(3));
                addr(7) := (not code(0) and code(1) and not code(3)) or (not code(0) and code(2) and not code(3)) or (code(0) and not code(1) and not code(3));
                addr(8) := '0';

            when x"3" =>
                -- 0011 ---- ---- 1100 => 001010111  ADD Rm, Rn
                -- 0011 ---- ---- 1110 => 001011000  ADDC Rm, Rn
                -- 0011 ---- ---- 1111 => 001011001  ADDV Rm, Rn
                -- 0011 ---- ---- 0000 => 001011011  CMP /EQ Rm, Rn
                -- 0011 ---- ---- 0010 => 001011100  CMP /HS Rm, Rn
                -- 0011 ---- ---- 0011 => 001011101  CMP /GE Rm, Rn
                -- 0011 ---- ---- 0110 => 001011110  CMP /HI Rm, Rn
                -- 0011 ---- ---- 0111 => 001011111  CMP /GT Rm, Rn
                -- 0011 ---- ---- 0100 => 001100101  DIV1 Rm, Rn
                -- 0011 ---- ---- 1101 => 001100111  DMULS.L Rm, Rn
                -- 0011 ---- ---- 0101 => 001101000  DMULU.L Rm, Rn
                -- 0011 ---- ---- 1000 => 001110101  SUB Rm, Rn
                -- 0011 ---- ---- 1010 => 001110110  SUBC Rm, Rn
                -- 0011 ---- ---- 1011 => 001110111  SUBV Rm, Rn
                addr(0) := not ((not code(0) and code(1)) or (code(0) and not code(1) and code(2) and not code(3)));
                addr(1) := (not code(0) and not code(1) and not code(2) and not code(3)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(2) and code(3)) or (code(1) and code(2) and not code(3));
                addr(2) := not ((not code(0) and not code(1) and not code(2) and not code(3)) or (code(0) and not code(1) and code(2) and not code(3)) or (code(1) and code(2) and code(3)));
                addr(3) := (not code(0) and not code(2) and not code(3)) or (code(0) and code(2) and not code(3)) or (code(1) and code(2)) or (code(1) and not code(3));
                addr(4) := not ((code(0) and not code(1) and code(2)) or (not code(1) and code(2) and not code(3)));
                addr(5) := (not code(0) and not code(2) and code(3)) or (code(0) and not code(1) and code(2)) or (not code(1) and code(2) and not code(3)) or (code(1) and not code(2) and code(3));
                addr(6) := '1';
                addr(7) := '0';
                addr(8) := '0';

            when x"4" =>
                -- 0100 ---- 0001 0101 => 000001111  CMP/PL Rn
                -- 0100 ---- 0001 0001 => 000010000  CMP/PZ Rn
                -- 0100 ---- 0001 0000 => 000010001  DT Rn
                -- 0100 ---- 0000 0100 => 000010011  ROTL Rn
                -- 0100 ---- 0000 0101 => 000010100  ROTR Rn
                -- 0100 ---- 0010 0100 => 000010101  ROTCL Rn
                -- 0100 ---- 0010 0101 => 000010110  ROTCR Rn
                -- 0100 ---- 0010 0000 => 000010111  SHAL Rn
                -- 0100 ---- 0010 0001 => 000011000  SHAR Rn
                -- 0100 ---- 0000 0000 => 000011001  SHLL Rn
                -- 0100 ---- 0000 0001 => 000011010  SHLR Rn
                -- 0100 ---- 0000 1000 => 000011011  SHLL2 Rn
                -- 0100 ---- 0000 1001 => 000011100  SHLR2 Rn
                -- 0100 ---- 0001 1000 => 000011101  SHLL8 Rn
                -- 0100 ---- 0001 1001 => 000011110  SHLR8 Rn
                -- 0100 ---- 0010 1000 => 000011111  SHLL16 Rn
                -- 0100 ---- 0010 1001 => 000100000  SHLR16 Rn
                -- 0100 ---- 0001 1011 => 000100111  TAS.B @Rn
                -- 0100 ---- 0000 0011 => 000101011  STC.L SR, @-Rn
                -- 0100 ---- 0001 0011 => 000101101  STC.L GBR, @-Rn
                -- 0100 ---- 0010 0011 => 000101111  STC.L VBR, @-Rn
                -- 0100 ---- 0000 0010 => 000110001  STS.L MACH, @-Rn
                -- 0100 ---- 0001 0010 => 000110010  STS.L MACL, @-Rn
                -- 0100 ---- 0010 0010 => 000110011  STS.L PR, @-Rn
                -- 0100 ---- 1100 1000 => 000110100  STS CP0_COM, Rn
                -- 0100 ---- 1100 1001 => 000110101  CSTS CP0_COM, CP0_Rn
                -- 0100 ---- 0000 1110 => 000111000  LDC Rm, SR
                -- 0100 ---- 0001 1110 => 000111001  LDC, Rm, GBR
                -- 0100 ---- 0010 1110 => 000111010  LDC Rm, VBR
                -- 0100 ---- 0000 1010 => 000111011  LDS Rm, MACH
                -- 0100 ---- 0001 1010 => 000111100  LDS Rm, MACL
                -- 0100 ---- 0010 1010 => 000111101  LDS Rm, PR
                -- 0100 ---- 0010 1011 => 000111110  JMP @Rm
                -- 0100 ---- 0000 1011 => 001000000  JSR @Rm
                -- 0100 ---- 0000 0111 => 001000010  LDC.L @Rm+, SR
                -- 0100 ---- 0001 0111 => 001000101  LDC.L @Rm+, GBR
                -- 0100 ---- 0010 0111 => 001001000  LDC.L @Rm+, VBR
                -- 0100 ---- 0000 0110 => 001001011  LDS.L @Rm+, MACH
                -- 0100 ---- 0001 0110 => 001001100  LDS.L @Rm+, MACL
                -- 0100 ---- 0010 0110 => 001001101  LDS.L @Rm+, PR
                -- 0100 ---- 1000 1000 => 001001111  LDS Rm, CP0_COM
                -- 0100 ---- 1000 1001 => 001010000  CLDS CP0_Rm, CP0_COM
                -- 0100 ---- 0101 1010 => 001010001  LDS Rm, CPI_COM
                -- 0100 ---- ---- 1100 => 001111101  SHAD Rm, Rn
                -- 0100 ---- ---- 1101 => 001111110  SHLD Rm, Rn
                -- 0100 ---- ---- 1111 => 010001000  MAC.W @Rm+, @Rn+
                -- 0100 ---- 1--- 1110 => 011010000  LDC Rm, Rn_BANK
                -- 0100 ---- 0011 1110 => 011010100  LDC Rm, SSR
                -- 0100 ---- 0100 1110 => 011010101  LDC Rm, SPC
                -- 0100 ---- 0101 1110 => 011011001  LDC Rm, PTEH
                -- 0100 ---- 0110 1110 => 011011011  LDC Rm, PTEL
                -- 0100 ---- 0111 1110 => 011011101  LDC Rm, ASIDR
                addr(0) := (not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6)) or (not code(0) and not code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (not code(0) and not code(1) and code(2) and code(3)) or (not code(0) and code(1) and code(2) and code(3) and code(4) and not code(5) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(6) and not code(7)) or (not code(0) and code(1) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (not code(0) and not code(2) and not code(4) and not code(6) and not code(7)) or (not code(0) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(6) and code(7)) or (code(0) and code(1) and not code(2) and code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7));
                addr(1) := (not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6)) or (not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and not code(4) and code(5) and not code(7)) or (not code(0) and not code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(0) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(2) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and code(2) and code(3)) or (code(0) and code(1) and not code(2) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(2) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7));
                addr(2) := not ((not code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and not code(4) and code(5) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(7)) or (not code(0) and code(1) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (not code(0) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(0) and not code(2) and not code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and code(7)) or (code(0) and not code(1) and not code(2) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and code(3)) or (not code(1) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (code(1) and not code(2) and not code(4) and not code(5) and not code(6) and not code(7)));
                addr(3) := not ((not code(0) and code(1) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and not code(4) and not code(5) and code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(4) and code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(7)) or (not code(0) and not code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(6) and code(7)) or (not code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)));
                addr(4) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and code(3)) or (code(0) and code(1) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7)));
                addr(5) := (not code(0) and code(1) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and code(3) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(6) and code(7)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(1) and not code(2) and code(4) and not code(5) and not code(6) and not code(7));
                addr(6) := (not code(0) and code(1) and code(2) and code(3) and code(4) and code(5) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(7)) or (not code(0) and code(1) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and code(7)) or (not code(1) and code(2) and code(3)) or (code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7));
                addr(7) := (not code(0) and code(1) and code(2) and code(3) and code(4) and code(5) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(7)) or (code(0) and code(1) and code(2) and code(3));
                addr(8) := '0';

            when x"5" =>
                -- 0101 ---- ---- ---- => 010011110  MOV.L @(disp, Rm), Rn
                addr := "010011110";

            when x"6" =>
                -- 0110 ---- ---- 1110 => 001101001  EXTS.B Rm, Rn
                -- 0110 ---- ---- 1111 => 001101010  EXTS.W Rm, Rn
                -- 0110 ---- ---- 1100 => 001101011  EXTU.B Rm, Rn
                -- 0110 ---- ---- 1101 => 001101100  EXTU.W Rm, Rn
                -- 0110 ---- ---- 0011 => 001101101  MOV Rm, Rn
                -- 0110 ---- ---- 1011 => 001110001  NEG Rm, Rn
                -- 0110 ---- ---- 1010 => 001110010  NEGC Rm, Rn
                -- 0110 ---- ---- 0111 => 001110011  NOT Rm, Rn
                -- 0110 ---- ---- 1000 => 001111000  SWAP.B Rm, Rn
                -- 0110 ---- ---- 1001 => 001111001  SWAP.W Rm, Rn
                -- 0110 ---- ---- 0000 => 010000010  MOV.B @Rm, Rn
                -- 0110 ---- ---- 0001 => 010000011  MOV.W @Rm, Rn
                -- 0110 ---- ---- 0010 => 010000100  MOV.L @Rm, Rn
                -- 0110 ---- ---- 0100 => 010001010  MOV.B @Rm+, Rn
                -- 0110 ---- ---- 0101 => 010001100  MOV.W @Rm+, Rn
                -- 0110 ---- ---- 0110 => 010001110  MOV.L @Rm+, Rn
                addr(0) := (not code(0) and code(2) and code(3)) or (code(0) and code(1) and not code(3)) or (code(0) and not code(2));
                addr(1) := (not code(0) and not code(1) and code(2)) or (not code(0) and code(1) and not code(2) and code(3)) or (not code(0) and code(2) and not code(3)) or (code(0) and code(1) and code(2)) or (not code(1) and not code(2) and not code(3));
                addr(2) := (not code(0) and code(1) and not code(3)) or (code(0) and not code(1) and code(2)) or (code(1) and not code(2) and not code(3));
                addr(3) := not ((not code(0) and code(1) and not code(2)) or (code(0) and code(1) and code(2) and not code(3)) or (not code(1) and not code(2) and not code(3)) or (code(1) and not code(2) and code(3)));
                addr(4) := (code(0) and code(1) and code(2) and not code(3)) or (not code(2) and code(3));
                addr(5) := (code(0) and code(1)) or (code(3));
                addr(6) := (code(0) and code(1)) or (code(3));
                addr(7) := (not code(0) and not code(3)) or (not code(1) and not code(3));
                addr(8) := '0';

            when x"7" =>
                -- 0111 ---- ---- ---- => 011001110  ADD #imm, Rn
                addr := "011001110";

            when x"8" =>
                -- 1000 0100 ---- ---- => 010011001  MOV.B @(disp, Rm), R0
                -- 1000 0101 ---- ---- => 010011010  MOV.W @(disp, Rm), R0
                -- 1000 0000 ---- ---- => 010011011  MOV.B R0, @(disp, Rn)
                -- 1000 0001 ---- ---- => 010011100  MOV.W R0, @(disp, Rn)
                -- 1000 1011 ---- ---- => 010100110  BF label
                -- 1000 1111 ---- ---- => 010101001  BF /S label
                -- 1000 1001 ---- ---- => 010101011  BT label
                -- 1000 1101 ---- ---- => 010101110  BT /S label
                -- 1000 1000 ---- ---- => 011000011  CMP /EQ #imm, R0
                addr(0) := (not code(8) and not code(9) and not code(11)) or (code(8) and code(9) and code(10) and code(11)) or (not code(9) and not code(10) and code(11));
                addr(1) := (not code(8) and not code(9) and not code(10)) or (code(8) and not code(10) and code(11)) or (code(8) and not code(9) and code(10));
                addr(2) := (code(8) and not code(9) and not code(10) and not code(11)) or (code(8) and not code(9) and code(10) and code(11)) or (code(8) and code(9) and not code(10) and code(11));
                addr(3) := not ((not code(8) and not code(9) and not code(10) and code(11)) or (code(8) and code(9) and not code(10) and code(11)));
                addr(4) := (not code(9) and not code(11));
                addr(5) := (code(8) and code(11));
                addr(6) := (not code(8) and not code(9) and not code(10) and code(11));
                addr(7) := '1';
                addr(8) := '0';

            when x"9" =>
                -- 1001 ---- ---- ---- => 010110100  MOV.W @(disp, PC), Rn
                addr := "010110100";

            when x"A" =>
                -- 1010 ---- ---- ---- => 010110000  BRA label
                addr := "010110000";

            when x"B" =>
                -- 1011 ---- ---- ---- => 010110010  BSR label
                addr := "010110010";

            when x"C" =>
                -- 1100 0000 ---- ---- => 010011111  MOV.B R0, @(disp, GBR)
                -- 1100 0001 ---- ---- => 010100000  MOV.W R0, @(disp, GBR)
                -- 1100 0010 ---- ---- => 010100001  MOV.L R0, @(disp, GBR)
                -- 1100 0100 ---- ---- => 010100010  MOV.B @(disp, GBR), R0
                -- 1100 0101 ---- ---- => 010100011  MOV.W @(disp, GBR), R0
                -- 1100 0110 ---- ---- => 010100100  MOV.L @(disp, GBR), R0
                -- 1100 0111 ---- ---- => 010100101  MOVA @(disp, PC), R0
                -- 1100 1101 ---- ---- => 010110110  AND.B #imm, @(R0, GBR)
                -- 1100 1111 ---- ---- => 010111001  OR.B #imm, @(R0, GBR)
                -- 1100 1100 ---- ---- => 010111100  TST.B #imm, @(R0, GBR)
                -- 1100 1110 ---- ---- => 010111111  XOR.B #imm, @(R0, GBR)
                -- 1100 1001 ---- ---- => 011000010  AND #imm, R0
                -- 1100 1011 ---- ---- => 011000100  OR #imm, R0
                -- 1100 1000 ---- ---- => 011000101  TST #imm, R0
                -- 1100 1010 ---- ---- => 011000110  XOR #imm, R0
                -- 1100 0011 ---- ---- => 011000111  TRAPA #imm
                addr(0) := (not code(8) and not code(9) and not code(10)) or (code(8) and code(10) and not code(11)) or (code(9) and not code(10) and not code(11)) or (code(9) and code(10) and code(11));
                addr(1) := (not code(8) and not code(9) and not code(11)) or (not code(8) and code(9) and code(11)) or (code(8) and not code(9) and code(10)) or (code(8) and not code(9) and code(11)) or (code(8) and code(9) and not code(10) and not code(11));
                addr(2) := not ((not code(8) and code(9) and not code(10) and not code(11)) or (code(8) and not code(9) and not code(10)) or (code(8) and code(9) and code(10) and code(11)) or (not code(9) and code(10) and not code(11)));
                addr(3) := (not code(8) and code(10) and code(11)) or (not code(8) and not code(9) and not code(10) and not code(11)) or (code(9) and code(10) and code(11));
                addr(4) := (code(10) and code(11)) or (not code(8) and not code(9) and not code(10) and not code(11));
                addr(5) := (code(10)) or (not code(8) and code(9) and not code(11)) or (code(8) and not code(9) and not code(11));
                addr(6) := (not code(10) and code(11)) or (code(8) and code(9) and not code(10));
                addr(7) := '1';
                addr(8) := '0';

            when x"D" =>
                -- 1101 ---- ---- ---- => 010110101  MOV.L @(disp, PC), Rn
                addr := "010110101";

            when x"E" =>
                -- 1110 ---- ---- ---- => 011001111  MOV #imm, Rn
                addr := "011001111";

            when x"F" =>
                -- 1111 ---- 0000 1101 => 000110111  CSTS CPI_COM, CPI_Rn
                -- 1111 ---- 0001 1101 => 001010010  CLDS CPI_Rm, CPI_COM
                addr(0) := (code(0) and not code(1) and code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7));
                addr(1) := '1';
                addr(2) := (code(0) and not code(1) and code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7));
                addr(3) := '0';
                addr(4) := '1';
                addr(5) := (code(0) and not code(1) and code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7));
                addr(6) := (code(0) and not code(1) and code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7));
                addr(7) := '0';
                addr(8) := '0';

            when others =>
                addr := "111111111";

        end case;
        return addr;
    end;
    function check_illegal_delay_slot (code : std_logic_vector(15 downto 0)) return std_logic is
    begin
        if ((code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(12) and not code(13) and code(14) and not code(15)) or (code(13) and not code(14) and code(15)) or (code(8) and code(9) and not code(10) and not code(11) and not code(12) and not code(13) and code(14) and code(15))) = '1' then
            return '1';
        else
            return '0';
        end if;
    end;
    function check_illegal_instruction (code : std_logic_vector(15 downto 0)) return std_logic is
    begin
        -- TODO: Improve detection of illegal instructions
        if code(15 downto 8) = x"ff" then
            return '1';
        else
            return '0';
        end if;
    end;
    function privileged (code : std_logic_vector(15 downto 0)) return std_logic is
    begin
        if ((not code(0) and not code(1) and not code(2) and code(3) and code(4) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11) and not code(12) and not code(13) and not code(14) and not code(15)) or (not code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(7) and not code(12) and not code(13) and not code(14) and not code(15)) or (not code(0) and code(1) and not code(2) and not code(3) and code(5) and not code(7) and not code(12) and not code(13) and not code(14) and not code(15)) or (not code(0) and code(1) and not code(2) and not code(3) and code(7) and not code(12) and not code(13) and not code(14) and not code(15)) or (not code(0) and code(1) and code(2) and code(3) and not code(4) and not code(7) and not code(12) and not code(13) and code(14) and not code(15)) or (not code(0) and code(1) and code(2) and code(3) and code(5) and not code(7) and not code(12) and not code(13) and code(14) and not code(15)) or (not code(0) and code(1) and code(2) and code(3) and code(6) and not code(7) and not code(12) and not code(13) and code(14) and not code(15)) or (not code(0) and code(1) and code(2) and code(3) and code(7) and not code(12) and not code(13) and code(14) and not code(15)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(0) and code(1) and not code(3) and not code(4) and not code(6) and not code(7) and not code(12) and not code(13) and code(14) and not code(15)) or (code(1) and not code(2) and not code(3) and code(4) and code(6) and not code(7) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(1) and not code(2) and not code(3) and code(5) and code(6) and not code(7) and not code(12) and not code(13) and not code(14) and not code(15))) = '1' then
            return '1';
        else
            return '0';
        end if;
    end;
end;
