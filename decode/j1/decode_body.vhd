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
        variable addr : std_logic_vector(7 downto 0);
    begin
        case code(15 downto 12) is
            when x"0" =>
                -- 0000 0000 0000 1000 => 00000000  CLRT
                -- 0000 0000 0010 1000 => 00000001  CLRMAC
                -- 0000 0000 0001 1001 => 00000010  DIV0U
                -- 0000 0000 0000 1001 => 00000011  NOP
                -- 0000 0000 0010 1011 => 00000100  RTE
                -- 0000 0000 0000 1011 => 00001000  RTS
                -- 0000 0000 0001 1000 => 00001010  SETT
                -- 0000 0000 0001 1011 => 00001011  SLEEP
                -- 0000 0000 0011 1011 => 00001111  BGND
                -- 0000 ---- 0010 1001 => 00010011  MOVT Rn
                -- 0000 ---- 0000 0010 => 00100010  STC SR, Rn
                -- 0000 ---- 0001 0010 => 00100011  STC GBR, Rn
                -- 0000 ---- 0010 0010 => 00100100  STC VBR, Rn
                -- 0000 ---- 0000 1010 => 00100101  STS MACH, Rn
                -- 0000 ---- 0001 1010 => 00100110  STS MACL, Rn
                -- 0000 ---- 0010 1010 => 00100111  STS PR, Rn
                -- 0000 ---- 0010 0011 => 01001100  BRAF Rm
                -- 0000 ---- 0000 0011 => 01001110  BSRF Rm
                -- 0000 ---- ---- 0111 => 01100011  MUL.L Rm, Rn
                -- 0000 ---- ---- 1111 => 01111010  MAC.L @Rm+, @Rn+
                -- 0000 ---- ---- 0100 => 10001000  MOV.B Rm, @(R0, Rn)
                -- 0000 ---- ---- 0101 => 10001001  MOV.W Rm, @(R0, Rn)
                -- 0000 ---- ---- 0110 => 10001010  MOV.L Rm, @(R0, Rn)
                -- 0000 ---- ---- 1100 => 10001011  MOV.B @(R0, Rm), Rn
                -- 0000 ---- ---- 1101 => 10001100  MOV.W @(R0, Rm), Rn
                -- 0000 ---- ---- 1110 => 10001101  MOV.L @(R0, Rm), Rn
                -- 0000 ---- 0101 1010 => 11111111  STS CPI_COM, Rn
                addr(0) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(2) and not code(3)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(2) and code(3)) or (not code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)));
                addr(1) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3)) or (code(0) and not code(1) and code(2)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(1) and code(2) and not code(3)) or (code(1) and not code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)));
                addr(2) := (not code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and code(3)) or (code(0) and not code(1) and code(2) and code(3)) or (code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(3) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11));
                addr(3) := not ((not code(0) and not code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (not code(0) and code(1) and not code(2) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7) and not code(8) and not code(9) and not code(10) and not code(11)) or (code(0) and code(1) and code(2) and not code(3)));
                addr(4) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (code(0) and not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and code(3));
                addr(5) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2));
                addr(6) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and code(2));
                addr(7) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (not code(0) and code(2)) or (not code(1) and code(2));

            when x"1" =>
                -- 0001 ---- ---- ---- => 10010010  MOV.L Rm, @(disp, Rn)
                addr := x"92";

            when x"2" =>
                -- 0010 ---- ---- 1001 => 01010011  AND Rm, Rn
                -- 0010 ---- ---- 1100 => 01011001  CMP /STR Rm, Rn
                -- 0010 ---- ---- 0111 => 01011011  DIV0S Rm, Rn
                -- 0010 ---- ---- 1111 => 01100100  MULS.W Rm, Rn
                -- 0010 ---- ---- 1110 => 01100101  MULU.W Rm, Rn
                -- 0010 ---- ---- 1011 => 01101001  OR Rm, Rn
                -- 0010 ---- ---- 1000 => 01101111  TST Rm, Rn
                -- 0010 ---- ---- 1010 => 01110000  XOR Rm, Rn
                -- 0010 ---- ---- 1101 => 01110001  XTRACT Rm, Rn
                -- 0010 ---- ---- 0000 => 01110100  MOV.B Rm, @Rn
                -- 0010 ---- ---- 0001 => 01110101  MOV.W Rm, @Rn
                -- 0010 ---- ---- 0010 => 01110110  MOV.L Rm, @Rn
                -- 0010 ---- ---- 0100 => 10000101  MOV.B Rm,@-Rn
                -- 0010 ---- ---- 0101 => 10000110  MOV.W Rm,@-Rn
                -- 0010 ---- ---- 0110 => 10000111  MOV.L Rm,@-Rn
                -- 0010 ---- ---- 0011 => 11111111  CAS.L Rm, Rn, @R0
                addr(0) := (not code(0) and code(2)) or (code(0) and code(1) and not code(3)) or (code(0) and not code(2)) or (not code(1) and code(3));
                addr(1) := (code(0) and code(2) and not code(3)) or (not code(1) and not code(2) and code(3)) or (code(1) and not code(3));
                addr(2) := not ((code(0) and not code(1) and code(3)) or (code(0) and code(1) and code(2) and not code(3)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(2) and code(3)));
                addr(3) := (not code(0) and not code(1) and code(3)) or (code(0) and code(1) and not code(2)) or (code(0) and code(1) and not code(3));
                addr(4) := not ((not code(0) and not code(1) and not code(2) and code(3)) or (not code(0) and code(1) and code(2)) or (code(0) and code(1) and code(3)) or (not code(1) and code(2) and not code(3)));
                addr(5) := not ((not code(0) and not code(1) and code(2)) or (code(0) and not code(1) and not code(2) and code(3)) or (code(2) and not code(3)));
                addr(6) := not ((not code(0) and code(2) and not code(3)) or (not code(1) and code(2) and not code(3)));
                addr(7) := (not code(0) and code(2) and not code(3)) or (code(0) and code(1) and not code(2) and not code(3)) or (not code(1) and code(2) and not code(3));

            when x"3" =>
                -- 0011 ---- ---- 1100 => 01010000  ADD Rm, Rn
                -- 0011 ---- ---- 1110 => 01010001  ADDC Rm, Rn
                -- 0011 ---- ---- 1111 => 01010010  ADDV Rm, Rn
                -- 0011 ---- ---- 0000 => 01010100  CMP /EQ Rm, Rn
                -- 0011 ---- ---- 0010 => 01010101  CMP /HS Rm, Rn
                -- 0011 ---- ---- 0011 => 01010110  CMP /GE Rm, Rn
                -- 0011 ---- ---- 0110 => 01010111  CMP /HI Rm, Rn
                -- 0011 ---- ---- 0111 => 01011000  CMP /GT Rm, Rn
                -- 0011 ---- ---- 0100 => 01011010  DIV1 Rm, Rn
                -- 0011 ---- ---- 1101 => 01011100  DMULS.L Rm, Rn
                -- 0011 ---- ---- 0101 => 01011101  DMULU.L Rm, Rn
                -- 0011 ---- ---- 1000 => 01101010  SUB Rm, Rn
                -- 0011 ---- ---- 1010 => 01101011  SUBC Rm, Rn
                -- 0011 ---- ---- 1011 => 01101100  SUBV Rm, Rn
                addr(0) := (not code(0) and code(1)) or (code(0) and not code(1) and code(2) and not code(3));
                addr(1) := (not code(0) and not code(2) and code(3)) or (not code(0) and code(2) and not code(3)) or (code(0) and code(1) and not code(2) and not code(3)) or (code(0) and code(1) and code(2) and code(3));
                addr(2) := not ((not code(0) and not code(1) and code(2)) or (not code(0) and code(3)) or (code(0) and code(1) and code(2)));
                addr(3) := (not code(0) and not code(2) and code(3)) or (code(0) and not code(1) and code(2)) or (code(0) and code(2) and not code(3)) or (not code(1) and code(2) and not code(3)) or (code(1) and not code(2) and code(3));
                addr(4) := not ((not code(0) and not code(2) and code(3)) or (code(1) and not code(2) and code(3)));
                addr(5) := (not code(0) and not code(2) and code(3)) or (code(1) and not code(2) and code(3));
                addr(6) := '1';
                addr(7) := '0';

            when x"4" =>
                -- 0100 ---- 0001 0101 => 00010000  CMP/PL Rn
                -- 0100 ---- 0001 0001 => 00010001  CMP/PZ Rn
                -- 0100 ---- 0001 0000 => 00010010  DT Rn
                -- 0100 ---- 0000 0100 => 00010100  ROTL Rn
                -- 0100 ---- 0000 0101 => 00010101  ROTR Rn
                -- 0100 ---- 0010 0100 => 00010110  ROTCL Rn
                -- 0100 ---- 0010 0101 => 00010111  ROTCR Rn
                -- 0100 ---- 0010 0000 => 00011000  SHAL Rn
                -- 0100 ---- 0010 0001 => 00011001  SHAR Rn
                -- 0100 ---- 0000 0000 => 00011010  SHLL Rn
                -- 0100 ---- 0000 0001 => 00011011  SHLR Rn
                -- 0100 ---- 0000 1000 => 00011100  SHLL2 Rn
                -- 0100 ---- 0000 1001 => 00011101  SHLR2 Rn
                -- 0100 ---- 0001 1000 => 00011110  SHLL8 Rn
                -- 0100 ---- 0001 1001 => 00011111  SHLR8 Rn
                -- 0100 ---- 0010 1000 => 00100000  SHLL16 Rn
                -- 0100 ---- 0010 1001 => 00100001  SHLR16 Rn
                -- 0100 ---- 0001 1011 => 00101000  TAS.B @Rn
                -- 0100 ---- 0000 0011 => 00101100  STC.L SR, @-Rn
                -- 0100 ---- 0001 0011 => 00101110  STC.L GBR, @-Rn
                -- 0100 ---- 0010 0011 => 00110000  STC.L VBR, @-Rn
                -- 0100 ---- 0000 0010 => 00110010  STS.L MACH, @-Rn
                -- 0100 ---- 0001 0010 => 00110011  STS.L MACL, @-Rn
                -- 0100 ---- 0010 0010 => 00110100  STS.L PR, @-Rn
                -- 0100 ---- 0000 1110 => 00110101  LDC Rm, SR
                -- 0100 ---- 0001 1110 => 00110110  LDC, Rm, GBR
                -- 0100 ---- 0010 1110 => 00110111  LDC Rm, VBR
                -- 0100 ---- 0000 1010 => 00111000  LDS Rm, MACH
                -- 0100 ---- 0001 1010 => 00111001  LDS Rm, MACL
                -- 0100 ---- 0010 1010 => 00111010  LDS Rm, PR
                -- 0100 ---- 0010 1011 => 00111011  JMP @Rm
                -- 0100 ---- 0000 1011 => 00111101  JSR @Rm
                -- 0100 ---- 0000 0111 => 00111111  LDC.L @Rm+, SR
                -- 0100 ---- 0001 0111 => 01000010  LDC.L @Rm+, GBR
                -- 0100 ---- 0010 0111 => 01000101  LDC.L @Rm+, VBR
                -- 0100 ---- 0000 0110 => 01001000  LDS.L @Rm+, MACH
                -- 0100 ---- 0001 0110 => 01001001  LDS.L @Rm+, MACL
                -- 0100 ---- 0010 0110 => 01001010  LDS.L @Rm+, PR
                -- 0100 ---- ---- 1100 => 01110010  SHAD Rm, Rn
                -- 0100 ---- ---- 1101 => 01110011  SHLD Rm, Rn
                -- 0100 ---- ---- 1111 => 01111101  MAC.W @Rm+, @Rn+
                -- 0100 ---- 1000 1001 => 11111111  CLDS CP0_Rm, CP0_COM
                -- 0100 ---- 1100 1001 => 11111111  CSTS CP0_COM, CP0_Rn
                -- 0100 ---- 1000 1000 => 11111111  LDS Rm, CP0_COM
                -- 0100 ---- 0101 1010 => 11111111  LDS Rm, CPI_COM
                -- 0100 ---- 1100 1000 => 11111111  STS CP0_COM, Rn
                addr(0) := not ((not code(0) and not code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (not code(0) and not code(1) and code(2) and code(3)) or (not code(0) and code(1) and code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(0) and not code(2) and not code(4) and not code(6) and not code(7)) or (not code(0) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)));
                addr(1) := not ((not code(0) and code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(1) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and code(3)) or (code(0) and code(1) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(1) and code(2) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (code(1) and not code(2) and code(3) and not code(5) and not code(6) and not code(7)) or (not code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)));
                addr(2) := not ((not code(0) and code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and not code(3) and not code(5) and not code(6) and not code(7)) or (code(0) and not code(2) and not code(4) and code(5) and not code(6) and not code(7)) or (code(0) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and not code(4) and code(5) and not code(6) and not code(7)) or (not code(1) and code(2) and code(3)) or (code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(6) and not code(7)));
                addr(3) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and not code(7)) or (not code(0) and code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (not code(0) and code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and code(2) and code(3)) or (code(0) and code(1) and not code(3) and not code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(7)) or (code(1) and not code(2) and code(3) and not code(4) and not code(6) and not code(7)) or (not code(2) and code(3) and not code(5) and not code(6) and not code(7));
                addr(4) := not ((not code(0) and code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (code(0) and code(1) and not code(2) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)));
                addr(5) := not ((not code(0) and code(1) and code(2) and not code(3) and not code(5) and not code(6) and not code(7)) or (code(0) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(2) and not code(5) and not code(6) and not code(7)) or (not code(1) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)));
                addr(6) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (not code(0) and code(1) and code(2) and not code(3) and not code(4) and not code(6) and not code(7)) or (code(0) and code(2) and code(3)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(7)) or (not code(1) and code(2) and code(3)) or (code(1) and code(2) and not code(3) and not code(4) and code(5) and not code(6) and not code(7)) or (code(1) and code(2) and not code(3) and code(4) and not code(5) and not code(6) and not code(7));
                addr(7) := (not code(0) and code(1) and not code(2) and code(3) and code(4) and not code(5) and code(6) and not code(7)) or (not code(1) and not code(2) and code(3) and not code(4) and not code(5) and code(7));

            when x"5" =>
                -- 0101 ---- ---- ---- => 10010011  MOV.L @(disp, Rm), Rn
                addr := x"93";

            when x"6" =>
                -- 0110 ---- ---- 1110 => 01011110  EXTS.B Rm, Rn
                -- 0110 ---- ---- 1111 => 01011111  EXTS.W Rm, Rn
                -- 0110 ---- ---- 1100 => 01100000  EXTU.B Rm, Rn
                -- 0110 ---- ---- 1101 => 01100001  EXTU.W Rm, Rn
                -- 0110 ---- ---- 0011 => 01100010  MOV Rm, Rn
                -- 0110 ---- ---- 1011 => 01100110  NEG Rm, Rn
                -- 0110 ---- ---- 1010 => 01100111  NEGC Rm, Rn
                -- 0110 ---- ---- 0111 => 01101000  NOT Rm, Rn
                -- 0110 ---- ---- 1000 => 01101101  SWAP.B Rm, Rn
                -- 0110 ---- ---- 1001 => 01101110  SWAP.W Rm, Rn
                -- 0110 ---- ---- 0000 => 01110111  MOV.B @Rm, Rn
                -- 0110 ---- ---- 0001 => 01111000  MOV.W @Rm, Rn
                -- 0110 ---- ---- 0010 => 01111001  MOV.L @Rm, Rn
                -- 0110 ---- ---- 0100 => 01111111  MOV.B @Rm+, Rn
                -- 0110 ---- ---- 0101 => 10000001  MOV.W @Rm+, Rn
                -- 0110 ---- ---- 0110 => 10000011  MOV.L @Rm+, Rn
                addr(0) := not ((not code(0) and code(2) and code(3)) or (code(0) and code(1) and not code(3)) or (code(0) and not code(2)));
                addr(1) := (not code(0) and not code(1) and not code(3)) or (not code(0) and code(1) and code(2)) or (code(0) and code(1) and not code(2)) or (code(0) and not code(2) and code(3)) or (code(1) and code(3));
                addr(2) := (not code(0) and not code(1) and not code(3)) or (code(1) and code(3)) or (not code(2) and code(3));
                addr(3) := (not code(0) and not code(1) and code(2) and not code(3)) or (not code(0) and code(1) and not code(2) and not code(3)) or (code(0) and not code(1) and not code(2)) or (code(0) and code(1) and code(2)) or (not code(1) and not code(2) and code(3)) or (code(1) and code(2) and code(3));
                addr(4) := (not code(0) and not code(1) and not code(3)) or (not code(0) and not code(2) and not code(3)) or (not code(1) and not code(2) and not code(3)) or (code(1) and code(2) and code(3));
                addr(5) := not ((not code(0) and code(1) and code(2)) or (code(0) and not code(1) and code(2) and not code(3)) or (code(1) and code(2) and code(3)));
                addr(6) := not ((not code(0) and code(1) and code(2) and not code(3)) or (code(0) and not code(1) and code(2) and not code(3)));
                addr(7) := (not code(0) and code(1) and code(2) and not code(3)) or (code(0) and not code(1) and code(2) and not code(3));

            when x"7" =>
                -- 0111 ---- ---- ---- => 11000011  ADD #imm, Rn
                addr := x"c3";

            when x"8" =>
                -- 1000 0100 ---- ---- => 10001110  MOV.B @(disp, Rm), R0
                -- 1000 0101 ---- ---- => 10001111  MOV.W @(disp, Rm), R0
                -- 1000 0000 ---- ---- => 10010000  MOV.B R0, @(disp, Rn)
                -- 1000 0001 ---- ---- => 10010001  MOV.W R0, @(disp, Rn)
                -- 1000 1011 ---- ---- => 10011011  BF label
                -- 1000 1111 ---- ---- => 10011110  BF /S label
                -- 1000 1001 ---- ---- => 10100000  BT label
                -- 1000 1101 ---- ---- => 10100011  BT /S label
                -- 1000 1000 ---- ---- => 10111000  CMP /EQ #imm, R0
                addr(0) := (code(8) and not code(9) and code(10)) or (code(8) and not code(9) and not code(11)) or (code(8) and code(9) and not code(10) and code(11));
                addr(1) := not ((not code(9) and not code(10)));
                addr(2) := (code(8) and code(9) and code(10) and code(11)) or (not code(9) and code(10) and not code(11));
                addr(3) := not ((code(8) and not code(9) and code(11)) or (not code(9) and not code(10) and not code(11)));
                addr(4) := not ((code(8) and not code(9) and code(11)) or (not code(9) and code(10) and not code(11)));
                addr(5) := (code(8) and not code(9) and code(11)) or (not code(9) and not code(10) and code(11));
                addr(6) := '0';
                addr(7) := '1';

            when x"9" =>
                -- 1001 ---- ---- ---- => 10101001  MOV.W @(disp, PC), Rn
                addr := x"a9";

            when x"A" =>
                -- 1010 ---- ---- ---- => 10100101  BRA label
                addr := x"a5";

            when x"B" =>
                -- 1011 ---- ---- ---- => 10100111  BSR label
                addr := x"a7";

            when x"C" =>
                -- 1100 0000 ---- ---- => 10010100  MOV.B R0, @(disp, GBR)
                -- 1100 0001 ---- ---- => 10010101  MOV.W R0, @(disp, GBR)
                -- 1100 0010 ---- ---- => 10010110  MOV.L R0, @(disp, GBR)
                -- 1100 0100 ---- ---- => 10010111  MOV.B @(disp, GBR), R0
                -- 1100 0101 ---- ---- => 10011000  MOV.W @(disp, GBR), R0
                -- 1100 0110 ---- ---- => 10011001  MOV.L @(disp, GBR), R0
                -- 1100 0111 ---- ---- => 10011010  MOVA @(disp, PC), R0
                -- 1100 1101 ---- ---- => 10101011  AND.B #imm, @(R0, GBR)
                -- 1100 1111 ---- ---- => 10101110  OR.B #imm, @(R0, GBR)
                -- 1100 1100 ---- ---- => 10110001  TST.B #imm, @(R0, GBR)
                -- 1100 1110 ---- ---- => 10110100  XOR.B #imm, @(R0, GBR)
                -- 1100 1001 ---- ---- => 10110111  AND #imm, R0
                -- 1100 1011 ---- ---- => 10111001  OR #imm, R0
                -- 1100 1000 ---- ---- => 10111010  TST #imm, R0
                -- 1100 1010 ---- ---- => 10111011  XOR #imm, R0
                -- 1100 0011 ---- ---- => 10111100  TRAPA #imm
                addr(0) := (not code(8) and code(10) and not code(11)) or (code(8) and not code(9) and not code(10)) or (not code(9) and code(10) and code(11)) or (code(9) and not code(10) and code(11));
                addr(1) := (not code(8) and not code(10) and code(11)) or (not code(8) and not code(9) and code(10) and not code(11)) or (not code(8) and code(9) and not code(10)) or (code(8) and not code(9) and code(11)) or (code(8) and code(9) and code(10));
                addr(2) := (not code(10) and not code(11)) or (not code(8) and not code(9) and not code(11)) or (code(8) and not code(9) and not code(10)) or (code(9) and code(10) and code(11));
                addr(3) := (not code(8) and not code(10) and code(11)) or (code(8) and code(10)) or (code(8) and code(9)) or (code(9) and code(10) and not code(11));
                addr(4) := not ((code(8) and code(10) and code(11)));
                addr(5) := (code(11)) or (code(8) and code(9) and not code(10));
                addr(6) := '0';
                addr(7) := '1';

            when x"D" =>
                -- 1101 ---- ---- ---- => 10101010  MOV.L @(disp, PC), Rn
                addr := x"aa";

            when x"E" =>
                -- 1110 ---- ---- ---- => 11000100  MOV #imm, Rn
                addr := x"c4";

            when x"F" =>
                -- 1111 ---- 0001 1101 => 11111111  CLDS CPI_Rm, CPI_COM
                -- 1111 ---- 0000 1101 => 11111111  CSTS CPI_COM, CPI_Rn
                addr(0) := '1';
                addr(1) := '1';
                addr(2) := '1';
                addr(3) := '1';
                addr(4) := '1';
                addr(5) := '1';
                addr(6) := '1';
                addr(7) := '1';

            when others =>
                addr := x"ff";

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
        if code(15 downto 8) = x"ff" or (code and x"f0ff") = x"005a" or (code and x"f00f") = x"2003" or (code and x"f0ff") = x"405a" or (code and x"f0ff") = x"4088" or (code and x"f0ff") = x"4089" or (code and x"f0ff") = x"40c8" or (code and x"f0ff") = x"40c9" or (code and x"f0ff") = x"f01d" or (code and x"f0ff") = x"f00d" then
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
