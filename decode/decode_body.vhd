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
                -- 0000 0000 0000 1011 => 000001000  RTS
                -- 0000 0000 0001 1000 => 000001010  SETT
                -- 0000 0000 0001 1011 => 000001011  SLEEP
                -- 0000 0000 0011 1011 => 000001111  BGND
                -- 0000 ---- 0010 1001 => 000010011  MOVT Rn
                -- 0000 ---- 0000 0010 => 000100010  STC SR, Rn
                -- 0000 ---- 0001 0010 => 000100011  STC GBR, Rn
                -- 0000 ---- 0010 0010 => 000100100  STC VBR, Rn
                -- 0000 ---- 0000 1010 => 000100101  STS MACH, Rn
                -- 0000 ---- 0001 1010 => 000100110  STS MACL, Rn
                -- 0000 ---- 0010 1010 => 000100111  STS PR, Rn
                -- 0000 ---- 0101 1010 => 000110111  STS CPI_COM, Rn
                -- 0000 ---- 0010 0011 => 001010100  BRAF Rm
                -- 0000 ---- 0000 0011 => 001010110  BSRF Rm
                -- 0000 ---- ---- 0111 => 001101111  MUL.L Rm, Rn
                -- 0000 ---- ---- 1111 => 010000110  MAC.L @Rm+, @Rn+
                -- 0000 ---- ---- 0100 => 010010100  MOV.B Rm, @(R0, Rn)
                -- 0000 ---- ---- 0101 => 010010101  MOV.W Rm, @(R0, Rn)
                -- 0000 ---- ---- 0110 => 010010110  MOV.L Rm, @(R0, Rn)
                -- 0000 ---- ---- 1100 => 010010111  MOV.B @(R0, Rm), Rn
                -- 0000 ---- ---- 1101 => 010011000  MOV.W @(R0, Rm), Rn
                -- 0000 ---- ---- 1110 => 010011001  MOV.L @(R0, Rm), Rn
                addr(0) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(2) and not code(3)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(2) and code(3)) or (not code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)));
                addr(1) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3)) or (code(0) and not code(1) and code(2)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(1) and code(2) and not code(3)) or (code(1) and not code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)));
                addr(2) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and code(2) and code(3)) or (code(0) and not code(2) and code(3) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)));
                addr(3) := (not code(0) and not code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and code(2) and code(3)) or (code(0) and not code(1) and code(2) and code(3)) or (code(0) and code(1) and not code(2) and code(3) and code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(1) and code(2) and not code(3));
                addr(4) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (not code(0) and code(2)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (not code(1) and code(2));
                addr(5) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and not code(3));
                addr(6) := (code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and not code(3));
                addr(7) := (not code(0) and code(2)) or (not code(1) and code(2)) or (code(2) and code(3));
                addr(8) := '0';

            when x"1" =>
                -- 0001 ---- ---- ---- => 010011110  MOV.L Rm, @(disp, Rn)
                addr := "010011110";

            when x"2" =>
                -- 0010 ---- ---- 1001 => 001011011  AND Rm, Rn
                -- 0010 ---- ---- 1100 => 001100001  CMP /STR Rm, Rn
                -- 0010 ---- ---- 0011 => 001100010  CAS.L Rm, Rn, @R0
                -- 0010 ---- ---- 0111 => 001100111  DIV0S Rm, Rn
                -- 0010 ---- ---- 1111 => 001110000  MULS.W Rm, Rn
                -- 0010 ---- ---- 1110 => 001110001  MULU.W Rm, Rn
                -- 0010 ---- ---- 1011 => 001110101  OR Rm, Rn
                -- 0010 ---- ---- 1000 => 001111011  TST Rm, Rn
                -- 0010 ---- ---- 1010 => 001111100  XOR Rm, Rn
                -- 0010 ---- ---- 1101 => 001111101  XTRACT Rm, Rn
                -- 0010 ---- ---- 0000 => 010000000  MOV.B Rm, @Rn
                -- 0010 ---- ---- 0001 => 010000001  MOV.W Rm, @Rn
                -- 0010 ---- ---- 0010 => 010000010  MOV.L Rm, @Rn
                -- 0010 ---- ---- 0100 => 010010001  MOV.B Rm,@-Rn
                -- 0010 ---- ---- 0101 => 010010010  MOV.W Rm,@-Rn
                -- 0010 ---- ---- 0110 => 010010011  MOV.L Rm,@-Rn
                addr(0) := (not code(0) and code(2)) or (code(0) and not code(1) and not code(2)) or (code(0) and not code(2) and code(3)) or (not code(1) and code(3)) or (code(1) and code(2) and not code(3));
                addr(1) := (code(0) and code(2) and not code(3)) or (not code(1) and not code(2) and code(3)) or (code(1) and not code(3));
                addr(2) := (code(0) and not code(1) and code(2) and code(3)) or (code(0) and code(1) and code(2) and not code(3)) or (code(1) and not code(2) and code(3));
                addr(3) := (not code(0) and not code(2) and code(3)) or (code(0) and not code(1) and code(3));
                addr(4) := not ((not code(0) and not code(1) and code(2) and code(3)) or (code(0) and code(1) and not code(3)) or (not code(2) and not code(3)));
                addr(5) := (not code(0) and code(3)) or (code(0) and code(1)) or (code(2) and code(3));
                addr(6) := (code(0) and code(1)) or (code(3));
                addr(7) := (not code(0) and not code(3)) or (not code(1) and not code(3));
                addr(8) := '0';

            when x"3" =>
                -- 0011 ---- ---- 1100 => 001011000  ADD Rm, Rn
                -- 0011 ---- ---- 1110 => 001011001  ADDC Rm, Rn
                -- 0011 ---- ---- 1111 => 001011010  ADDV Rm, Rn
                -- 0011 ---- ---- 0000 => 001011100  CMP /EQ Rm, Rn
                -- 0011 ---- ---- 0010 => 001011101  CMP /HS Rm, Rn
                -- 0011 ---- ---- 0011 => 001011110  CMP /GE Rm, Rn
                -- 0011 ---- ---- 0110 => 001011111  CMP /HI Rm, Rn
                -- 0011 ---- ---- 0111 => 001100000  CMP /GT Rm, Rn
                -- 0011 ---- ---- 0100 => 001100110  DIV1 Rm, Rn
                -- 0011 ---- ---- 1101 => 001101000  DMULS.L Rm, Rn
                -- 0011 ---- ---- 0101 => 001101001  DMULU.L Rm, Rn
                -- 0011 ---- ---- 1000 => 001110110  SUB Rm, Rn
                -- 0011 ---- ---- 1010 => 001110111  SUBC Rm, Rn
                -- 0011 ---- ---- 1011 => 001111000  SUBV Rm, Rn
                addr(0) := (not code(0) and code(1)) or (code(0) and not code(1) and code(2) and not code(3));
                addr(1) := (not code(0) and not code(2) and code(3)) or (not code(0) and code(2) and not code(3)) or (code(0) and code(1) and not code(2) and not code(3)) or (code(0) and code(1) and code(2) and code(3));
                addr(2) := (not code(0) and not code(2)) or (not code(0) and not code(3)) or (code(1) and not code(2) and not code(3));
                addr(3) := not ((not code(0) and not code(1) and code(2) and not code(3)) or (not code(0) and not code(2) and code(3)) or (code(0) and code(1) and code(2) and not code(3)));
                addr(4) := not ((code(0) and not code(1) and code(2)) or (code(0) and code(2) and not code(3)) or (not code(1) and code(2) and not code(3)));
                addr(5) := (not code(0) and not code(2) and code(3)) or (code(0) and not code(1) and code(2)) or (code(0) and code(2) and not code(3)) or (not code(1) and code(2) and not code(3)) or (code(1) and not code(2) and code(3));
                addr(6) := '1';
                addr(7) := '0';
                addr(8) := '0';

            when x"4" =>
                -- 0100 ---- 0001 0101 => 000010000  CMP/PL Rn
                -- 0100 ---- 0001 0001 => 000010001  CMP/PZ Rn
                -- 0100 ---- 0001 0000 => 000010010  DT Rn
                -- 0100 ---- 0000 0100 => 000010100  ROTL Rn
                -- 0100 ---- 0000 0101 => 000010101  ROTR Rn
                -- 0100 ---- 0010 0100 => 000010110  ROTCL Rn
                -- 0100 ---- 0010 0101 => 000010111  ROTCR Rn
                -- 0100 ---- 0010 0000 => 000011000  SHAL Rn
                -- 0100 ---- 0010 0001 => 000011001  SHAR Rn
                -- 0100 ---- 0000 0000 => 000011010  SHLL Rn
                -- 0100 ---- 0000 0001 => 000011011  SHLR Rn
                -- 0100 ---- 0000 1000 => 000011100  SHLL2 Rn
                -- 0100 ---- 0000 1001 => 000011101  SHLR2 Rn
                -- 0100 ---- 0001 1000 => 000011110  SHLL8 Rn
                -- 0100 ---- 0001 1001 => 000011111  SHLR8 Rn
                -- 0100 ---- 0010 1000 => 000100000  SHLL16 Rn
                -- 0100 ---- 0010 1001 => 000100001  SHLR16 Rn
                -- 0100 ---- 0001 1011 => 000101000  TAS.B @Rn
                -- 0100 ---- 0000 0011 => 000101100  STC.L SR, @-Rn
                -- 0100 ---- 0001 0011 => 000101110  STC.L GBR, @-Rn
                -- 0100 ---- 0010 0011 => 000110000  STC.L VBR, @-Rn
                -- 0100 ---- 0000 0010 => 000110010  STS.L MACH, @-Rn
                -- 0100 ---- 0001 0010 => 000110011  STS.L MACL, @-Rn
                -- 0100 ---- 0010 0010 => 000110100  STS.L PR, @-Rn
                -- 0100 ---- 1100 1000 => 000110101  STS CP0_COM, Rn
                -- 0100 ---- 1100 1001 => 000110110  CSTS CP0_COM, CP0_Rn
                -- 0100 ---- 0000 1110 => 000111001  LDC Rm, SR
                -- 0100 ---- 0001 1110 => 000111010  LDC, Rm, GBR
                -- 0100 ---- 0010 1110 => 000111011  LDC Rm, VBR
                -- 0100 ---- 0000 1010 => 000111100  LDS Rm, MACH
                -- 0100 ---- 0001 1010 => 000111101  LDS Rm, MACL
                -- 0100 ---- 0010 1010 => 000111110  LDS Rm, PR
                -- 0100 ---- 0010 1011 => 000111111  JMP @Rm
                -- 0100 ---- 0000 1011 => 001000001  JSR @Rm
                -- 0100 ---- 0000 0111 => 001000011  LDC.L @Rm+, SR
                -- 0100 ---- 0001 0111 => 001000110  LDC.L @Rm+, GBR
                -- 0100 ---- 0010 0111 => 001001001  LDC.L @Rm+, VBR
                -- 0100 ---- 0000 0110 => 001001100  LDS.L @Rm+, MACH
                -- 0100 ---- 0001 0110 => 001001101  LDS.L @Rm+, MACL
                -- 0100 ---- 0010 0110 => 001001110  LDS.L @Rm+, PR
                -- 0100 ---- 1000 1000 => 001010000  LDS Rm, CP0_COM
                -- 0100 ---- 1000 1001 => 001010001  CLDS CP0_Rm, CP0_COM
                -- 0100 ---- 0101 1010 => 001010010  LDS Rm, CPI_COM
                -- 0100 ---- ---- 1100 => 001111110  SHAD Rm, Rn
                -- 0100 ---- ---- 1101 => 001111111  SHLD Rm, Rn
                -- 0100 ---- ---- 1111 => 010001001  MAC.W @Rm+, @Rn+
                addr(0) := (not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(6) and code(7)) or (not code(0) and code(1) and not code(2) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6)) or (code(0) and not code(1) and not code(2) and not code(4) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(2) and code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(2) and code(3));
                addr(1) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(0) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(6) and code(7)) or (code(0) and code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7));
                addr(2) := (not code(0) and code(1) and not code(2) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(0) and not code(2) and code(3) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(6) and code(7)) or (not code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7)) or (not code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7));
                addr(3) := not ((not code(0) and code(1) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(1) and not code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)));
                addr(4) := not ((code(0) and code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and code(3)) or (not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7)));
                addr(5) := (not code(0) and code(1) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and code(3) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(6) and code(7)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(1) and not code(2) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7));
                addr(6) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and code(7)) or (not code(1) and code(2) and code(3)) or (code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7));
                addr(7) := (code(0) and code(1) and code(2) and code(3));
                addr(8) := '0';

            when x"5" =>
                -- 0101 ---- ---- ---- => 010011111  MOV.L @(disp, Rm), Rn
                addr := "010011111";

            when x"6" =>
                -- 0110 ---- ---- 1110 => 001101010  EXTS.B Rm, Rn
                -- 0110 ---- ---- 1111 => 001101011  EXTS.W Rm, Rn
                -- 0110 ---- ---- 1100 => 001101100  EXTU.B Rm, Rn
                -- 0110 ---- ---- 1101 => 001101101  EXTU.W Rm, Rn
                -- 0110 ---- ---- 0011 => 001101110  MOV Rm, Rn
                -- 0110 ---- ---- 1011 => 001110010  NEG Rm, Rn
                -- 0110 ---- ---- 1010 => 001110011  NEGC Rm, Rn
                -- 0110 ---- ---- 0111 => 001110100  NOT Rm, Rn
                -- 0110 ---- ---- 1000 => 001111001  SWAP.B Rm, Rn
                -- 0110 ---- ---- 1001 => 001111010  SWAP.W Rm, Rn
                -- 0110 ---- ---- 0000 => 010000011  MOV.B @Rm, Rn
                -- 0110 ---- ---- 0001 => 010000100  MOV.W @Rm, Rn
                -- 0110 ---- ---- 0010 => 010000101  MOV.L @Rm, Rn
                -- 0110 ---- ---- 0100 => 010001011  MOV.B @Rm+, Rn
                -- 0110 ---- ---- 0101 => 010001101  MOV.W @Rm+, Rn
                -- 0110 ---- ---- 0110 => 010001111  MOV.L @Rm+, Rn
                addr(0) := not ((not code(0) and code(2) and code(3)) or (code(0) and code(1) and not code(3)) or (code(0) and not code(2)));
                addr(1) := (not code(0) and not code(1) and not code(3)) or (not code(0) and code(1) and code(2)) or (code(0) and code(1) and not code(2)) or (code(0) and not code(2) and code(3)) or (code(1) and code(3));
                addr(2) := (code(0) and not code(3)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(3));
                addr(3) := not ((not code(0) and code(1) and not code(2)) or (code(0) and code(1) and code(2) and not code(3)) or (not code(1) and not code(2) and not code(3)) or (code(1) and not code(2) and code(3)));
                addr(4) := (code(0) and code(1) and code(2) and not code(3)) or (not code(2) and code(3));
                addr(5) := (code(0) and code(1)) or (code(3));
                addr(6) := (code(0) and code(1)) or (code(3));
                addr(7) := (not code(0) and not code(3)) or (not code(1) and not code(3));
                addr(8) := '0';

            when x"7" =>
                -- 0111 ---- ---- ---- => 011001111  ADD #imm, Rn
                addr := "011001111";

            when x"8" =>
                -- 1000 0100 ---- ---- => 010011010  MOV.B @(disp, Rm), R0
                -- 1000 0101 ---- ---- => 010011011  MOV.W @(disp, Rm), R0
                -- 1000 0000 ---- ---- => 010011100  MOV.B R0, @(disp, Rn)
                -- 1000 0001 ---- ---- => 010011101  MOV.W R0, @(disp, Rn)
                -- 1000 1011 ---- ---- => 010100111  BF label
                -- 1000 1111 ---- ---- => 010101010  BF /S label
                -- 1000 1001 ---- ---- => 010101100  BT label
                -- 1000 1101 ---- ---- => 010101111  BT /S label
                -- 1000 1000 ---- ---- => 011000100  CMP /EQ #imm, R0
                addr(0) := (code(8) and not code(9) and code(10)) or (code(8) and not code(9) and not code(11)) or (code(8) and code(9) and not code(10) and code(11));
                addr(1) := not ((not code(9) and not code(10)));
                addr(2) := not ((code(8) and code(9) and code(10) and code(11)) or (not code(9) and code(10) and not code(11)));
                addr(3) := not ((not code(8) and not code(9) and not code(10) and code(11)) or (code(8) and code(9) and not code(10) and code(11)));
                addr(4) := (not code(9) and not code(11));
                addr(5) := (code(8) and code(11));
                addr(6) := (not code(8) and not code(9) and not code(10) and code(11));
                addr(7) := '1';
                addr(8) := '0';

            when x"9" =>
                -- 1001 ---- ---- ---- => 010110101  MOV.W @(disp, PC), Rn
                addr := "010110101";

            when x"A" =>
                -- 1010 ---- ---- ---- => 010110001  BRA label
                addr := "010110001";

            when x"B" =>
                -- 1011 ---- ---- ---- => 010110011  BSR label
                addr := "010110011";

            when x"C" =>
                -- 1100 0000 ---- ---- => 010100000  MOV.B R0, @(disp, GBR)
                -- 1100 0001 ---- ---- => 010100001  MOV.W R0, @(disp, GBR)
                -- 1100 0010 ---- ---- => 010100010  MOV.L R0, @(disp, GBR)
                -- 1100 0100 ---- ---- => 010100011  MOV.B @(disp, GBR), R0
                -- 1100 0101 ---- ---- => 010100100  MOV.W @(disp, GBR), R0
                -- 1100 0110 ---- ---- => 010100101  MOV.L @(disp, GBR), R0
                -- 1100 0111 ---- ---- => 010100110  MOVA @(disp, PC), R0
                -- 1100 1101 ---- ---- => 010110111  AND.B #imm, @(R0, GBR)
                -- 1100 1111 ---- ---- => 010111010  OR.B #imm, @(R0, GBR)
                -- 1100 1100 ---- ---- => 010111101  TST.B #imm, @(R0, GBR)
                -- 1100 1110 ---- ---- => 011000000  XOR.B #imm, @(R0, GBR)
                -- 1100 1001 ---- ---- => 011000011  AND #imm, R0
                -- 1100 1011 ---- ---- => 011000101  OR #imm, R0
                -- 1100 1000 ---- ---- => 011000110  TST #imm, R0
                -- 1100 1010 ---- ---- => 011000111  XOR #imm, R0
                -- 1100 0011 ---- ---- => 011001000  TRAPA #imm
                addr(0) := (not code(8) and code(10) and not code(11)) or (code(8) and not code(9) and not code(10)) or (not code(9) and code(10) and code(11)) or (code(9) and not code(10) and code(11));
                addr(1) := (not code(8) and not code(10) and code(11)) or (not code(8) and not code(9) and code(10) and not code(11)) or (not code(8) and code(9) and not code(10)) or (code(8) and not code(9) and code(11)) or (code(8) and code(9) and code(10));
                addr(2) := (not code(8) and not code(9) and code(11)) or (code(8) and not code(9) and code(10)) or (code(9) and not code(10) and code(11)) or (code(9) and code(10) and not code(11));
                addr(3) := (not code(8) and not code(9) and code(10) and code(11)) or (code(8) and code(9) and not code(10) and not code(11)) or (code(8) and code(9) and code(10) and code(11));
                addr(4) := (code(8) and code(10) and code(11)) or (not code(9) and code(10) and code(11));
                addr(5) := not ((not code(10) and code(11)) or (not code(8) and code(9) and code(11)) or (code(8) and code(9) and not code(10)));
                addr(6) := (not code(10) and code(11)) or (not code(8) and code(9) and code(11)) or (code(8) and code(9) and not code(10));
                addr(7) := '1';
                addr(8) := '0';

            when x"D" =>
                -- 1101 ---- ---- ---- => 010110110  MOV.L @(disp, PC), Rn
                addr := "010110110";

            when x"E" =>
                -- 1110 ---- ---- ---- => 011010000  MOV #imm, Rn
                addr := "011010000";

            when x"F" =>
                -- 1111 ---- 0000 1101 => 000111000  CSTS CPI_COM, CPI_Rn
                -- 1111 ---- 0001 1101 => 001010011  CLDS CPI_Rm, CPI_COM
                addr(0) := (code(0) and not code(1) and code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7));
                addr(1) := (code(0) and not code(1) and code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7));
                addr(2) := '0';
                addr(3) := (code(0) and not code(1) and code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7));
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
        if ((code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(12) and not code(13) and code(14) and not code(15)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(13) and not code(14) and code(15)) or (code(8) and code(9) and not code(10) and not code(11) and not code(12) and not code(13) and code(14) and code(15))) = '1' then
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
        if ((not code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7) and not code(12) and not code(13) and not code(14) and not code(15)) or (not code(0) and code(1) and code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(12) and not code(13) and code(14) and not code(15)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11) and not code(12) and not code(13) and not code(14) and not code(15)) or (code(0) and code(1) and not code(3) and not code(4) and not code(6) and not code(7) and not code(12) and not code(13) and code(14) and not code(15))) = '1' then
            return '1';
        else
            return '0';
        end if;
    end;
end;
