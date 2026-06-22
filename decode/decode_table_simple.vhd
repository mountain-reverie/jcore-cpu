-- ******************************************************************
-- ******************************************************************
-- ******************************************************************
-- This file is generated. Changing this file directly is probably
-- not what you want to do. Any changes will be overwritten next time
-- the generator is run.
-- ******************************************************************
-- ******************************************************************
-- ******************************************************************
architecture simple_logic of decode_table is
    signal imm_enum : immval_t;
    signal mac_busy : mac_busy_t;
    signal imms_12_1 : std_logic_vector(31 downto 0);
    signal imms_8_0 : std_logic_vector(31 downto 0);
    signal imms_8_1 : std_logic_vector(31 downto 0);
begin
    -- Immediate value mux
    with imm_enum select
        ex.imm_val <=
            x"fffffff0" when IMM_N16,
            x"fffffff8" when IMM_N8,
            x"fffffffe" when IMM_N2,
            x"ffffffff" when IMM_N1,
            x"00000000" when IMM_ZERO,
            x"00000001" when IMM_P1,
            x"00000002" when IMM_P2,
            x"00000004" when IMM_P4,
            x"00000008" when IMM_P8,
            x"00000010" when IMM_P16,
            imms_8_0 when IMM_S_8_0,
            imms_8_1 when IMM_S_8_1,
            imms_12_1 when IMM_S_12_1,
            x"0000000" & op.code(3 downto 0) when IMM_U_4_0,
            "000000000000000000000000000" & op.code(3 downto 0) & "0" when IMM_U_4_1,
            "00000000000000000000000000" & op.code(3 downto 0) & "00" when IMM_U_4_2,
            x"000000" & op.code(7 downto 0) when IMM_U_8_0,
            "00000000000000000000000" & op.code(7 downto 0) & "0" when IMM_U_8_1,
            "0000000000000000000000" & op.code(7 downto 0) & "00" when IMM_U_8_2;
    -- Sign extend parts of opcode
    process(op)
    begin
        -- Sign extend 8 right-most bits
        for i in 8 to 31 loop
            imms_8_0(i) <= op.code(7);
        end loop;
        imms_8_0(7 downto 0) <= op.code(7 downto 0);
        -- Sign extend 8 right-most bits shifted by 1
        for i in 9 to 31 loop
            imms_8_1(i) <= op.code(7);
        end loop;
        imms_8_1(8 downto 1) <= op.code(7 downto 0);
        imms_8_1(0) <= '0';
        -- Sign extend 12 right-most bits shifted by 1
        for i in 13 to 31 loop
            imms_12_1(i) <= op.code(11);
        end loop;
        imms_12_1(12 downto 1) <= op.code(11 downto 0);
        imms_12_1(0) <= '0';
    end process;
    -- Mac busy muxes
    with mac_busy select
        ex.mac_busy <=
            '0' when NOT_BUSY,
            not next_id_stall when EX_NOT_STALL,
            '0' when WB_NOT_STALL,
            '1' when EX_BUSY,
            '0' when WB_BUSY;
    with mac_busy select
        wb.mac_busy <=
            '0' when NOT_BUSY,
            '0' when EX_NOT_STALL,
            not next_id_stall when WB_NOT_STALL,
            '0' when EX_BUSY,
            '1' when WB_BUSY;
    process(t_bcc, op)
        variable cond : std_logic_vector(16 downto 0);
    begin
        cond := std_logic_vector(TO_UNSIGNED(instruction_plane_t'pos(op.plane), 1)) & op.code;
        -- zero outputs by default
        ilevel_cap <= '0';
        mac_stall_sense <= '0';
        dispatch <= '0';
        event_ack_0 <= '0';
        slp <= '0';
        mac_s_latch <= '0';
        ex_stall <= ('0', '0', '0', '0', SEL_ARITH, SEL_PREV, SEL_CLEAR, SEL_XBUS, SEL_ZBUS, '0', '0', '0', LOGIC, '0', NOP, SEL_XBUS, SEL_YBUS);
        debug <= '0';
        wb_stall <= ('0', '0', '0', '0', '0', SEL_XBUS, SEL_YBUS, NOP, DBUS);
        delay_jump <= '0';
        id <= ('0', '0', '0');
        maskint_next <= '0';
        ex.arith_func <= ADD;
        ex.aluinx_sel <= SEL_XBUS;
        ex.alumanip <= SWAP_BYTE;
        ex.aluiny_sel <= SEL_YBUS;
        ex.coproc_cmd <= NOP;
        ex.arith_ci_en <= '0';
        ex.xbus_sel <= SEL_IMM;
        wb.regnum_w <= "00000";
        ex.regnum_x <= "00000";
        ex.mem_size <= BYTE;
        ex.regnum_y <= "00000";
        ex.regnum_z <= "00000";
        ex.ma_wr <= '0';
        ex.logic_sr_func <= ZERO;
        ex.logic_func <= LOGIC_NOT;
        ex.ybus_sel <= SEL_IMM;
        ex.mem_lock <= '0';
        ex.arith_sr_func <= ZERO;
        imm_enum <= IMM_ZERO;
        mac_busy <= NOT_BUSY;
        -- set control signals for each opcode
        if std_match(cond, "00000--------0100") then
            -- MOV.B Rm, @(R0, Rn) [0004]
            -- Rm?(R0 +Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_R0;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00000--------0101") then
            -- MOV.W Rm, @(R0, Rn) [0005]
            -- Rm?(R0 +Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_R0;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00000--------0110") then
            -- MOV.L Rm, @(R0, Rn) [0006]
            -- Rm?(R0 +Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_R0;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00000--------0111") then
            -- MUL.L Rm, Rn [0007]
            -- Rn×Rm?MACL
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    ex_stall.macsel1 <= SEL_XBUS;
                    ex_stall.macsel2 <= SEL_YBUS;
                    ex_stall.mulcom1 <= '1';
                    ex_stall.mulcom2 <= MULL;
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_busy <= EX_NOT_STALL;
                    mac_stall_sense <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00000--------1100") then
            -- MOV.B @(R0, Rm), Rn [000C]
            -- (R0 +Rm)?sign extension ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_R0;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00000--------1101") then
            -- MOV.W @(R0, Rm), Rn [000D]
            -- (R0 +Rm)?sign extension ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_R0;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00000--------1110") then
            -- MOV.L @(R0, Rm), Rn [000E]
            -- (R0 +Rm)? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_R0;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00000--------1111") then
            -- MAC.L @Rm+, @Rn+ [000F]
            -- Signed, (Rn) × (Rm) + MAC ? MAC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    wb_stall.macsel1 <= SEL_WBUS;
                    wb_stall.mulcom1 <= '1';
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    mac_busy <= WB_BUSY;
                    mac_s_latch <= '1';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(7 downto 4);
                    wb_stall.macsel2 <= SEL_WBUS;
                    wb_stall.mulcom2 <= MACL;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00000----00000010") then
            -- STC SR, Rn [0002]
            -- SR?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_SR;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00000----00000011") then
            -- BSRF Rm [0003]
            -- Delayed branch, PC ? PR, Rm + PC ? PC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= "10010";
                    ex_stall.wrpc_z <= '1';
                    ex_stall.wrpr_pc <= '1';
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00000----00001010") then
            -- STS MACH, Rn [000A]
            -- MACH?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_stall_sense <= '1';
                    maskint_next <= '1';
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_MACH;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00000----00010010") then
            -- STC GBR, Rn [0012]
            -- GBR?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= "10000";
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00000----00011010") then
            -- STS MACL, Rn [001A]
            -- MACL?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_stall_sense <= '1';
                    maskint_next <= '1';
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_MACL;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00000----00100010") then
            -- STC VBR, Rn [0022]
            -- VBR?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= "10001";
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00000----00100011") then
            -- BRAF Rm [0023]
            -- Delayed branch, Rm + PC ? PC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex_stall.wrpc_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00000----00101001") then
            -- MOVT Rn [0029]
            -- T?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P1;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_AND;
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_IMM;
                    ex.ybus_sel <= SEL_SR;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "00000----00101010") then
            -- STS PR, Rn [002A]
            -- PR?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= "10010";
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00000----01011010") then
            -- STS CPI_COM, Rn [005A]
            -- CPI_COM?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.coproc_cmd <= STS;
                    wb_stall.cpu_data_mux <= COPROC;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    wb_stall.wrreg_w <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00000000000001000") then
            -- CLRT [0008]
            -- 0 -> T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_CLEAR;
                when others =>

            end case;
        elsif std_match(cond, "00000000000001001") then
            -- NOP [0009]
            -- no operation
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00000000000001011") then
            -- RTS [000B]
            -- Delayed branch, PR -> PC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.regnum_y <= "10010";
                    ex_stall.wrpc_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00000000000011000") then
            -- SETT [0018]
            -- 1 -> T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SET;
                when others =>

            end case;
        elsif std_match(cond, "00000000000011001") then
            -- DIV0U [0019]
            -- 0 -> M/Q/T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.sr_sel <= SEL_DIV0U;
                when others =>

            end case;
        elsif std_match(cond, "00000000000011011") then
            -- SLEEP [001B]
            -- Sleep
            case op.addr(3 downto 0) is
                when x"0" =>
                when x"1" =>
                    slp <= '1';
                when x"2" =>
                when x"3" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00000000000101000") then
            -- CLRMAC [0028]
            -- 0 -> MACH, MACL
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    ex_stall.macsel1 <= SEL_ZBUS;
                    ex_stall.macsel2 <= SEL_ZBUS;
                    ex_stall.wrmach <= '1';
                    ex_stall.wrmacl <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_XOR;
                    mac_stall_sense <= '1';
                    ex.regnum_x <= "10100";
                    ex.regnum_y <= "10100";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "00000000000101011") then
            -- RTE [002B]
            -- Delayed branch, stack -> PC/SR
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    wb_stall.wrsr_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex_stall.wrpc_z <= '1';
                    ex_stall.zbus_sel <= SEL_WBUS;
                when x"3" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00000000000111011") then
            -- BGND [003B]
            -- background
            case op.addr(3 downto 0) is
                when x"0" =>
                    debug <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00001------------") then
            -- MOV.L Rm, @(disp, Rn) [1000]
            -- Rm ? (disp × 4 + Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_4_2;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00010--------0000") then
            -- MOV.B Rm, @Rn [2000]
            -- Rm ? (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00010--------0001") then
            -- MOV.W Rm, @Rn [2001]
            -- Rm ? (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00010--------0010") then
            -- MOV.L Rm, @Rn [2002]
            -- Rm ? (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00010--------0011") then
            -- CAS.L Rm, Rn, @R0 [2003]
            -- Rn?TEMP0
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when x"1" =>
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_lock <= '1';
                    ex.mem_size <= LONG;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_x <= "00000";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                when x"2" =>
                    ex.logic_func <= LOGIC_XOR;
                    ex.logic_sr_func <= ZERO;
                    ex.mem_lock <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_LOGIC;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when x"3" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= t_bcc;
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_lock <= '1';
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "00000";
                    ex.regnum_y <= "10011";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00010--------0100") then
            -- MOV.B Rm,@-Rn [2004]
            -- Rn – 1 ? Rn, Rm ? (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P1;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00010--------0101") then
            -- MOV.W Rm,@-Rn [2005]
            -- Rn – 2 ? Rn, Rm ? (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P2;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00010--------0110") then
            -- MOV.L Rm,@-Rn [2006]
            -- Rn – 4 ? Rn, Rm ? (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00010--------0111") then
            -- DIV0S Rm, Rn [2007]
            -- MSB of Rn? Q, MSB of Rm?M,M^Q?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    ex.arith_sr_func <= DIV0S;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00010--------1000") then
            -- TST Rm, Rn [2008]
            -- Rn & Rm, when result is 0, 1 ? T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_AND;
                    ex.logic_sr_func <= ZERO;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_LOGIC;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00010--------1001") then
            -- AND Rm, Rn [2009]
            -- Rn&Rm?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_AND;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "00010--------1010") then
            -- XOR Rm, Rn [200A]
            -- Rn ^ Rm? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_XOR;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "00010--------1011") then
            -- OR Rm, Rn [200B]
            -- Rn | Rm? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_OR;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "00010--------1100") then
            -- CMP /STR Rm, Rn [200C]
            -- When a byte in Rn equals a byte in Rm, 1? T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_XOR;
                    ex.logic_sr_func <= BYTE_EQ;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_LOGIC;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00010--------1101") then
            -- XTRACT Rm, Rn [200D]
            -- Centre 32 bits of Rm and Rn ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.alumanip <= EXTRACT;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_MANIP;
                when others =>

            end case;
        elsif std_match(cond, "00010--------1110") then
            -- MULU.W Rm, Rn [200E]
            -- Unsigned, Rn × Rm ? MAC
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    ex_stall.macsel1 <= SEL_XBUS;
                    ex_stall.macsel2 <= SEL_YBUS;
                    ex_stall.mulcom1 <= '1';
                    ex_stall.mulcom2 <= MULUW;
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_busy <= EX_NOT_STALL;
                    mac_stall_sense <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00010--------1111") then
            -- MULS.W Rm, Rn [200F]
            -- Signed, Rn × Rm ? MAC
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    ex_stall.macsel1 <= SEL_XBUS;
                    ex_stall.macsel2 <= SEL_YBUS;
                    ex_stall.mulcom1 <= '1';
                    ex_stall.mulcom2 <= MULSW;
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_busy <= EX_NOT_STALL;
                    mac_stall_sense <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00011--------0000") then
            -- CMP /EQ Rm, Rn [3000]
            -- When Rn=Rm,1?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_XOR;
                    ex.logic_sr_func <= ZERO;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_LOGIC;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00011--------0010") then
            -- CMP /HS Rm, Rn [3002]
            -- When unsigned and Rn ? Rm,1?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    ex.arith_sr_func <= UGRTER_EQ;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00011--------0011") then
            -- CMP /GE Rm, Rn [3003]
            -- When signed and Rn ? Rm,1?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    ex.arith_sr_func <= SGRTER_EQ;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00011--------0100") then
            -- DIV1 Rm, Rn [3004]
            -- 1-step division (Rn ÷ Rm)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluinx_sel <= SEL_ROTCL;
                    ex.arith_func <= ADD;
                    ex.arith_sr_func <= DIV1;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00011--------0101") then
            -- DMULU.L Rm, Rn [3005]
            -- Unsigned, Rn x Rm, MACH, MACL
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    ex_stall.macsel1 <= SEL_XBUS;
                    ex_stall.macsel2 <= SEL_YBUS;
                    ex_stall.mulcom1 <= '1';
                    ex_stall.mulcom2 <= DMULUL;
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_busy <= EX_NOT_STALL;
                    mac_stall_sense <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00011--------0110") then
            -- CMP /HI Rm, Rn [3006]
            -- When unsigned and Rn > Rm,1?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    ex.arith_sr_func <= UGRTER;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00011--------0111") then
            -- CMP /GT Rm, Rn [3007]
            -- When signed and Rn > Rm,1?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    ex.arith_sr_func <= SGRTER;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00011--------1000") then
            -- SUB Rm, Rn [3008]
            -- Rn – Rm ?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00011--------1010") then
            -- SUBC Rm, Rn [300A]
            -- Rn – Rm–T ?Rn, borrow ? T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_ci_en <= '1';
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_CARRY;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00011--------1011") then
            -- SUBV Rm, Rn [300B]
            -- Rn – Rm ? Rn, underflow ?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    ex.arith_sr_func <= OVERUNDERFLOW;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00011--------1100") then
            -- ADD Rm, Rn [300C]
            -- Rn+Rm?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00011--------1101") then
            -- DMULS.L Rm, Rn [300D]
            -- Signed, Rn x Rm, MACH, MACL
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    ex_stall.macsel1 <= SEL_XBUS;
                    ex_stall.macsel2 <= SEL_YBUS;
                    ex_stall.mulcom1 <= '1';
                    ex_stall.mulcom2 <= DMULSL;
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_busy <= EX_NOT_STALL;
                    mac_stall_sense <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "00011--------1110") then
            -- ADDC Rm, Rn [300E]
            -- Rn + Rm + T ? Rn, carry ?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_ci_en <= '1';
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_CARRY;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00011--------1111") then
            -- ADDV Rm, Rn [300F]
            -- Rn + Rm ? Rn, overflow ?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    ex.arith_sr_func <= OVERUNDERFLOW;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100--------1100") then
            -- SHAD Rm, Rn [400C]
            -- 
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= ARITH;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100--------1101") then
            -- SHLD Rm, Rn [400D]
            -- 
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100--------1111") then
            -- MAC.W @Rm+, @Rn+ [400F]
            -- Signed, (Rn) × (Rm) + MAC ? MAC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P2;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= WORD;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    wb_stall.macsel1 <= SEL_WBUS;
                    wb_stall.mulcom1 <= '1';
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P2;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    mac_busy <= WB_BUSY;
                    mac_s_latch <= '1';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= WORD;
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(7 downto 4);
                    wb_stall.macsel2 <= SEL_WBUS;
                    wb_stall.mulcom2 <= MACW;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100----00000000") then
            -- SHLL Rn [4000]
            -- T?Rn?0
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SHIFT;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00000001") then
            -- SHLR Rn [4001]
            -- 0?Rn?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_N1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SHIFT;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00000010") then
            -- STS.L MACH, @-Rn [4002]
            -- Rn – 4 ? Rn, MACH ? (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    mac_stall_sense <= '1';
                    maskint_next <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_MACH;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100----00000011") then
            -- STC.L SR, @-Rn [4003]
            -- Rn–4 ?Rn,SR ?(Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_SR;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00000100") then
            -- ROTL Rn [4004]
            -- T?Rn?MSB
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= ROTATE;
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SHIFT;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00000101") then
            -- ROTR Rn [4005]
            -- LSB?Rn?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_N1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= ROTATE;
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SHIFT;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00000110") then
            -- LDS.L @Rm+, MACH [4006]
            -- (Rm)?MACH,Rm+4?Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    mac_busy <= WB_NOT_STALL;
                    mac_stall_sense <= '1';
                    maskint_next <= '1';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    wb_stall.macsel1 <= SEL_WBUS;
                    wb_stall.wrmach <= '1';
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100----00000111") then
            -- LDC.L @Rm+, SR [4007]
            -- (Rm)?SR,Rm+4?Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    wb_stall.wrsr_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00001000") then
            -- SHLL2 Rn [4008]
            -- Rn<<2 ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P2;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00001001") then
            -- SHLR2 Rn [4009]
            -- Rn>>2 ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_N2;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00001010") then
            -- LDS Rm, MACH [400A]
            -- Rm? MACH
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    ex_stall.macsel1 <= SEL_ZBUS;
                    ex_stall.wrmach <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_stall_sense <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00100----00001011") then
            -- JSR @Rm [400B]
            -- PC ? PR, Rm ? PC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= "10010";
                    ex_stall.wrpc_z <= '1';
                    ex_stall.wrpr_pc <= '1';
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00001110") then
            -- LDC Rm, SR [400E]
            -- Rm ? SR
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_ZBUS;
                    ex_stall.wrsr_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00100----00010000") then
            -- DT Rn [4010]
            -- Rn-1 ?Rn; If Rn is 0, 1 ? T, if Rn is nonzero, 0 ? T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    ex.arith_sr_func <= ZERO;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100----00010001") then
            -- CMP/PZ Rn [4011]
            -- Rn ? 0, 1?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    ex.arith_sr_func <= SGRTER_EQ;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                when others =>

            end case;
        elsif std_match(cond, "00100----00010010") then
            -- STS.L MACL, @-Rn [4012]
            -- Rn–4?Rn,MACL?(Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    mac_stall_sense <= '1';
                    maskint_next <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_MACL;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100----00010011") then
            -- STC.L GBR, @-Rn [4013]
            -- Rn–4 ?Rn,GBR ?(Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= "10000";
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00010101") then
            -- CMP/PL Rn [4015]
            -- Rn > 0, 1 -> T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    ex.arith_sr_func <= SGRTER;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                when others =>

            end case;
        elsif std_match(cond, "00100----00010110") then
            -- LDS.L @Rm+, MACL [4016]
            -- (Rm)?MACL,Rm+4?Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    mac_busy <= WB_NOT_STALL;
                    mac_stall_sense <= '1';
                    maskint_next <= '1';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    wb_stall.macsel2 <= SEL_WBUS;
                    wb_stall.wrmacl <= '1';
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100----00010111") then
            -- LDC.L @Rm+, GBR [4017]
            -- (Rm)?GBR,Rm+4?Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= "10000";
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00011000") then
            -- SHLL8 Rn [4018]
            -- Rn<<8 ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P8;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00011001") then
            -- SHLR8 Rn [4019]
            -- Rn>>8 ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_N8;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00011010") then
            -- LDS Rm, MACL [401A]
            -- Rm ? MACL
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    ex_stall.macsel2 <= SEL_ZBUS;
                    ex_stall.wrmacl <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    mac_stall_sense <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00100----00011011") then
            -- TAS.B @Rn [401B]
            -- When (Rn) is 0, 1 ? T, 1 ? MSB of (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_lock <= '1';
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= "10011";
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                when x"1" =>
                    ex.mem_lock <= '1';
                when x"2" =>
                    ex.aluinx_sel <= SEL_ZERO;
                    ex.alumanip <= SET_BIT_7;
                    ex.arith_func <= ADD;
                    ex.arith_sr_func <= ZERO;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_lock <= '1';
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_ZBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= "10011";
                    ex_stall.sr_sel <= SEL_ARITH;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_MANIP;
                when x"3" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00011110") then
            -- LDC, Rm, GBR [401E]
            -- Rm ? GBR
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= "10000";
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00100----00100000") then
            -- SHAL Rn [4020]
            -- T?Rn?0
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SHIFT;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00100001") then
            -- SHAR Rn [4021]
            -- MSB?Rn?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_N1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= ARITH;
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SHIFT;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00100010") then
            -- STS.L PR, @-Rn [4022]
            -- Rn–4?Rn,PR?(Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    maskint_next <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= "10010";
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100----00100011") then
            -- STC.L VBR, @-Rn [4023]
            -- Rn – 4 ? Rn, VBR ? (Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= "10001";
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00100100") then
            -- ROTCL Rn [4024]
            -- T?Rn?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= ROTC;
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SHIFT;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00100101") then
            -- ROTCR Rn [4025]
            -- T?Rn?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_N1;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= ROTC;
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_SHIFT;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00100110") then
            -- LDS.L @Rm+, PR [4026]
            -- (Rm)?PR,Rm+4?Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    maskint_next <= '1';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= "10010";
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00100----00100111") then
            -- LDC.L @Rm+, VBR [4027]
            -- (Rm)?VBR,Rm+4?Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_XBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= "10001";
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00101000") then
            -- SHLL16 Rn [4028]
            -- Rn<<16 ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P16;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00101001") then
            -- SHLR16 Rn [4029]
            -- Rn>>16 ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_N16;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.shiftfunc <= LOGIC;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_SHIFT;
                when others =>

            end case;
        elsif std_match(cond, "00100----00101010") then
            -- LDS Rm, PR [402A]
            -- Rm ? PR
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= "10010";
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00100----00101011") then
            -- JMP @Rm [402B]
            -- Rm ? PC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex_stall.wrpc_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----00101110") then
            -- LDC Rm, VBR [402E]
            -- Rm ? VBR
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= "10001";
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00100----01011010") then
            -- LDS Rm, CPI_COM [405A]
            -- Rm ? CPI_COM
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.coproc_cmd <= LDS;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00100----10001000") then
            -- LDS Rm, CP0_COM [4088]
            -- Rm ? CP0_COM
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.coproc_cmd <= LDS;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                    ex.regnum_y <= '0' & op.code(11 downto 8);
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00100----10001001") then
            -- CLDS CP0_Rm, CP0_COM [4089]
            -- CP0_Rm ? CP0_COM
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.coproc_cmd <= CLDS;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----11001000") then
            -- STS CP0_COM, Rn [40C8]
            -- CP0_COM?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.coproc_cmd <= STS;
                    wb_stall.cpu_data_mux <= COPROC;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    wb_stall.wrreg_w <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00100----11001001") then
            -- CSTS CP0_COM, CP0_Rn [40C9]
            -- CP0_COM?CP0_Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.coproc_cmd <= STS;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "00101------------") then
            -- MOV.L @(disp, Rm), Rn [5000]
            -- (disp × 4+ Rm) ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_4_2;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00110--------0000") then
            -- MOV.B @Rm, Rn [6000]
            -- (Rm) ? sign extension ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00110--------0001") then
            -- MOV.W @Rm, Rn [6001]
            -- (Rm) ? sign extension ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00110--------0010") then
            -- MOV.L @Rm, Rn [6002]
            -- (Rm)? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00110--------0011") then
            -- MOV Rm, Rn [6003]
            -- Rm?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "00110--------0100") then
            -- MOV.B @Rm+, Rn [6004]
            -- (Rm) ? sign extension ? Rn, Rm +1 ?Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P1;
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(7 downto 4);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P1;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00110--------0101") then
            -- MOV.W @Rm+, Rn [6005]
            -- (Rm) ? sign extension ? Rn, Rm +2 ?Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P2;
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(7 downto 4);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P2;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00110--------0110") then
            -- MOV.L @Rm+, Rn [6006]
            -- (Rm) ? Rn, Rm + 4 ? Rm
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(7 downto 4);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_P4;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00110--------0111") then
            -- NOT Rm, Rn [6007]
            -- ~Rm?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_NOT;
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_IMM;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "00110--------1000") then
            -- SWAP.B Rm, Rn [6008]
            -- Rm ? Swap upper and lower halves of lower 2 bytes ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.alumanip <= SWAP_BYTE;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_MANIP;
                when others =>

            end case;
        elsif std_match(cond, "00110--------1001") then
            -- SWAP.W Rm, Rn [6009]
            -- Rm ? Swap upper and lower word ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.alumanip <= SWAP_WORD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_MANIP;
                when others =>

            end case;
        elsif std_match(cond, "00110--------1010") then
            -- NEGC Rm, Rn [600A]
            -- 0–Rm–T ? Rn, borrow ?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_ci_en <= '1';
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.sr_sel <= SEL_SET_T;
                    ex_stall.t_sel <= SEL_CARRY;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_IMM;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00110--------1011") then
            -- NEG Rm, Rn [600B]
            -- 0–Rm?Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= SUB;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_ZERO;
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_IMM;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "00110--------1100") then
            -- EXTU.B Rm, Rn [600C]
            -- Zero-extends Rm from byte ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.alumanip <= EXTEND_UBYTE;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_MANIP;
                when others =>

            end case;
        elsif std_match(cond, "00110--------1101") then
            -- EXTU.W Rm, Rn [600D]
            -- Zero-extends Rm from word ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.alumanip <= EXTEND_UWORD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_MANIP;
                when others =>

            end case;
        elsif std_match(cond, "00110--------1110") then
            -- EXTS.B Rm, Rn [600E]
            -- Sign-extends Rm from byte ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.alumanip <= EXTEND_SBYTE;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_MANIP;
                when others =>

            end case;
        elsif std_match(cond, "00110--------1111") then
            -- EXTS.W Rm, Rn [600F]
            -- Sign-extends Rm from word ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.alumanip <= EXTEND_SWORD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    ex.regnum_y <= '0' & op.code(7 downto 4);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_MANIP;
                when others =>

            end case;
        elsif std_match(cond, "00111------------") then
            -- ADD #imm, Rn [7000]
            -- Rn + imm ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_S_8_0;
                    id.incpc <= '1';
                    ex.regnum_x <= '0' & op.code(11 downto 8);
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "010000000--------") then
            -- MOV.B R0, @(disp, Rn) [8000]
            -- R0 ? (disp + Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_4_0;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    ex.regnum_y <= "00000";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "010000001--------") then
            -- MOV.W R0, @(disp, Rn) [8100]
            -- R0 ? (disp × 2+ Rn)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_4_1;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    ex.regnum_y <= "00000";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "010000100--------") then
            -- MOV.B @(disp, Rm), R0 [8400]
            -- (disp + Rm) ? sign extension ? R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_4_0;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= "00000";
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "010000101--------") then
            -- MOV.W @(disp, Rm), R0 [8500]
            -- (disp ×2 +Rm)? sign extension ? R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_4_1;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    wb.regnum_w <= "00000";
                    ex.regnum_x <= '0' & op.code(7 downto 4);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "010001000--------") then
            -- CMP /EQ #imm, R0 [8800]
            -- When R0=imm,1?T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_S_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_XOR;
                    ex.logic_sr_func <= ZERO;
                    ex.regnum_x <= "00000";
                    ex_stall.sr_sel <= SEL_LOGIC;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                when others =>

            end case;
        elsif std_match(cond, "010001001--------") then
            -- BT label [8900]
            -- When T=1, disp ×2+PC? PC; When T = 0, nop
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    dispatch <= not t_bcc;
                    id.if_issue <= '1';
                    imm_enum <= IMM_S_8_1;
                    id.incpc <= '1';
                    ex_stall.wrpc_z <= t_bcc;
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when x"2" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "010001011--------") then
            -- BF label [8B00]
            -- When T=0, disp ×2+PC? PC; When T = 1, nop
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    dispatch <= t_bcc;
                    id.if_issue <= '1';
                    imm_enum <= IMM_S_8_1;
                    id.incpc <= '1';
                    ex_stall.wrpc_z <= not t_bcc;
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when x"2" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "010001101--------") then
            -- BT /S label [8D00]
            -- When T=1, disp ×2+PC? PC; When T = 0, nop
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    dispatch <= not t_bcc;
                    id.if_issue <= not t_bcc;
                    imm_enum <= IMM_S_8_1;
                    id.incpc <= '1';
                    ex_stall.wrpc_z <= t_bcc;
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "010001111--------") then
            -- BF /S label [8F00]
            -- When T=0, disp ×2+PC? PC; When T = 1, nop
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    dispatch <= t_bcc;
                    id.if_issue <= t_bcc;
                    imm_enum <= IMM_S_8_1;
                    id.incpc <= '1';
                    ex_stall.wrpc_z <= not t_bcc;
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "01001------------") then
            -- MOV.W @(disp, PC), Rn [9000]
            -- (disp × 2 + PC) ? sign extension ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_1;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "01010------------") then
            -- BRA label [A000]
            -- Delayed branch, disp × 2+ PC ? PC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_S_12_1;
                    id.incpc <= '1';
                    ex_stall.wrpc_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "01011------------") then
            -- BSR label [B000]
            -- Delayed branching, PC ? PR, disp × 2 + PC ? PC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_S_12_1;
                    id.incpc <= '1';
                    ex.regnum_z <= "10010";
                    ex_stall.wrpc_z <= '1';
                    ex_stall.wrpr_pc <= '1';
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    delay_jump <= '1';
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when others =>

            end case;
        elsif std_match(cond, "011000000--------") then
            -- MOV.B R0, @(disp, GBR) [C000]
            -- R0? (disp + GBR)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "011000001--------") then
            -- MOV.W R0, @(disp, GBR) [C100]
            -- R0? (disp ×2 + GBR)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_1;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "011000010--------") then
            -- MOV.L R0, @(disp, GBR) [C200]
            -- R0? (disp ×4 + GBR)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_2;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "011000011--------") then
            -- TRAPA #imm [C300]
            -- PC/SR ? Stack area, (imm × 4 + VBR) ? PC
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_SR;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_U_8_2;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_y <= "10001";
                    ex.xbus_sel <= SEL_IMM;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"3" =>
                when x"4" =>
                    ex_stall.wrpc_z <= '1';
                    ex_stall.zbus_sel <= SEL_WBUS;
                when x"5" =>
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when x"6" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "011000100--------") then
            -- MOV.B @(disp, GBR), R0 [C400]
            -- (disp + GBR) ? sign extension ? R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= "00000";
                    ex.regnum_x <= "10000";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "011000101--------") then
            -- MOV.W @(disp, GBR), R0 [C500]
            -- (disp x2 + GBR) ? sign extension ? R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_1;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= WORD;
                    wb.regnum_w <= "00000";
                    ex.regnum_x <= "10000";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "011000110--------") then
            -- MOV.L @(disp, GBR), R0 [C600]
            -- (disp  x4+ GBR) ? sign extension ? R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_2;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= "00000";
                    ex.regnum_x <= "10000";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "011000111--------") then
            -- MOVA @(disp, PC), R0 [C700]
            -- disp × 4 + PC ? R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluinx_sel <= SEL_FC;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_2;
                    id.incpc <= '1';
                    ex.regnum_z <= "00000";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "011001000--------") then
            -- TST #imm, R0 [C800]
            -- R0 & imm, when result is 0, 1 ? T
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_AND;
                    ex.logic_sr_func <= ZERO;
                    ex.regnum_x <= "00000";
                    ex_stall.sr_sel <= SEL_LOGIC;
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                when others =>

            end case;
        elsif std_match(cond, "011001001--------") then
            -- AND #imm, R0 [C900]
            -- R0 & imm?R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_AND;
                    ex.regnum_x <= "00000";
                    ex.regnum_z <= "00000";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "011001010--------") then
            -- XOR #imm, R0 [CA00]
            -- R0 ^ imm?R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_XOR;
                    ex.regnum_x <= "00000";
                    ex.regnum_z <= "00000";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "011001011--------") then
            -- OR #imm, R0 [CB00]
            -- R0 | imm?R0
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_OR;
                    ex.regnum_x <= "00000";
                    ex.regnum_z <= "00000";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "011001100--------") then
            -- TST.B #imm, @(R0, GBR) [CC00]
            -- (R0 + GBR) & imm, when result is 0, 1 ? T
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= "10100";
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                when x"2" =>
                    ex.aluiny_sel <= SEL_IMM;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_AND;
                    ex.logic_sr_func <= ZERO;
                    ex.regnum_x <= "10100";
                    ex_stall.sr_sel <= SEL_LOGIC;
                    ex.xbus_sel <= SEL_REG;
                when others =>

            end case;
        elsif std_match(cond, "011001101--------") then
            -- AND.B #imm, @(R0, GBR) [CD00]
            -- (R0 + GBR) & imm ? (R0 + GBR)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= "10100";
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.arith_func <= ADD;
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex.aluiny_sel <= SEL_IMM;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_AND;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_YBUS;
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_ZBUS;
                    ex.regnum_x <= "10100";
                    ex.regnum_y <= "10011";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "011001110--------") then
            -- XOR.B #imm, @(R0, GBR) [CE00]
            -- (R0 + GBR) ^ imm ? (R0 + GBR)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= "10100";
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.arith_func <= ADD;
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex.aluiny_sel <= SEL_IMM;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_XOR;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_YBUS;
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_ZBUS;
                    ex.regnum_x <= "10100";
                    ex.regnum_y <= "10011";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "011001111--------") then
            -- OR.B #imm, @(R0, GBR) [CF00]
            -- (R0 + GBR) | imm ? (R0 + GBR)
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.arith_func <= ADD;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= BYTE;
                    wb.regnum_w <= "10100";
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.arith_func <= ADD;
                    ex.regnum_x <= "10000";
                    ex.regnum_y <= "00000";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex.aluiny_sel <= SEL_IMM;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_0;
                    id.incpc <= '1';
                    ex.logic_func <= LOGIC_OR;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_YBUS;
                    ex.mem_size <= BYTE;
                    ex_stall.mem_wdata_sel <= SEL_ZBUS;
                    ex.regnum_x <= "10100";
                    ex.regnum_y <= "10011";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when others =>

            end case;
        elsif std_match(cond, "01101------------") then
            -- MOV.L @(disp, PC), Rn [D000]
            -- (disp × 4 + PC) ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluinx_sel <= SEL_FC;
                    ex.arith_func <= ADD;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_U_8_2;
                    id.incpc <= '1';
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= '0' & op.code(11 downto 8);
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when others =>

            end case;
        elsif std_match(cond, "01110------------") then
            -- MOV #imm, Rn [E000]
            -- imm ? sign extension ? Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    imm_enum <= IMM_S_8_0;
                    id.incpc <= '1';
                    ex.regnum_z <= '0' & op.code(11 downto 8);
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when others =>

            end case;
        elsif std_match(cond, "01111----00001101") then
            -- CSTS CPI_COM, CPI_Rn [F00D]
            -- CPI_COM?CPI_Rn
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.coproc_cmd <= STS;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "01111----00011101") then
            -- CLDS CPI_Rm, CPI_COM [F01D]
            -- CPI_Rm ? CPI_COM
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.coproc_cmd <= CLDS;
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                    maskint_next <= '1';
                when others =>

            end case;
        elsif std_match(cond, "1-----000--------") then
            -- Interrupt [0000]
            -- 
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    event_ack_0 <= '1';
                    ilevel_cap <= '1';
                    imm_enum <= IMM_P2;
                    ex_stall.wrpc_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluinx_sel <= SEL_FC;
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_ZERO;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "10011";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_SR;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"3" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "10011";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"4" =>
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_U_8_2;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= "10001";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"5" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.sr_sel <= SEL_INT_MASK;
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"6" =>
                    ex_stall.wrpc_z <= '1';
                    ex_stall.zbus_sel <= SEL_WBUS;
                when x"7" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                    imm_enum <= IMM_P4;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"8" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "1-----001--------") then
            -- Error [0100]
            -- 
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    event_ack_0 <= '1';
                    ilevel_cap <= '1';
                    imm_enum <= IMM_P2;
                    ex_stall.wrpc_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluinx_sel <= SEL_FC;
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_ZERO;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "10011";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_SR;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"3" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "10011";
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"4" =>
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_U_8_2;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_x <= "10001";
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"5" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"6" =>
                    ex_stall.wrpc_z <= '1';
                    ex_stall.zbus_sel <= SEL_WBUS;
                when x"7" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                    imm_enum <= IMM_P4;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"8" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "1-----010--------") then
            -- Break [0200]
            -- 
            case op.addr(3 downto 0) is
                when x"0" =>
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    debug <= '1';
                    imm_enum <= IMM_P2;
                    ex_stall.wrpc_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when x"3" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "1-----011--------") then
            -- Reset CPU [0300]
            -- 
            case op.addr(3 downto 0) is
                when x"0" =>
                when x"1" =>
                    event_ack_0 <= '1';
                when x"2" =>
                    imm_enum <= IMM_U_8_2;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_z <= "10011";
                    ex_stall.wrreg_z <= '1';
                    ex.ybus_sel <= SEL_IMM;
                    ex_stall.zbus_sel <= SEL_YBUS;
                when x"3" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    wb.regnum_w <= "01111";
                    ex.regnum_x <= "10011";
                    wb_stall.wrreg_w <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"4" =>
                    ex_stall.wrpc_z <= '1';
                    ex_stall.zbus_sel <= SEL_WBUS;
                when x"5" =>
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                    ex.logic_func <= LOGIC_XOR;
                    ex.regnum_x <= "10100";
                    ex.regnum_y <= "10100";
                    ex.regnum_z <= "10001";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_LOGIC;
                when x"6" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "1-----110--------") then
            -- Slot Illegal [0600]
            -- 
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_ZERO;
                    ex_stall.wrpc_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_SR;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"3" =>
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_U_8_2;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_y <= "10001";
                    ex.xbus_sel <= SEL_IMM;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"4" =>
                when x"5" =>
                    ex_stall.wrpc_z <= '1';
                    ex_stall.zbus_sel <= SEL_WBUS;
                when x"6" =>
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when x"7" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        elsif std_match(cond, "1-----111--------") then
            -- General Illegal [0700]
            -- 
            case op.addr(3 downto 0) is
                when x"0" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P2;
                    ex_stall.wrpc_z <= '1';
                    ex.xbus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"1" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_SR;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"2" =>
                    ex.aluiny_sel <= SEL_IMM;
                    ex.arith_func <= SUB;
                    imm_enum <= IMM_P4;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '1';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex_stall.mem_wdata_sel <= SEL_YBUS;
                    ex.regnum_x <= "01111";
                    ex.regnum_z <= "01111";
                    ex_stall.wrreg_z <= '1';
                    ex.xbus_sel <= SEL_REG;
                    ex.ybus_sel <= SEL_PC;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"3" =>
                    ex.arith_func <= ADD;
                    imm_enum <= IMM_U_8_2;
                    ex_stall.ma_issue <= '1';
                    ex.ma_wr <= '0';
                    ex_stall.mem_addr_sel <= SEL_ZBUS;
                    ex.mem_size <= LONG;
                    ex.regnum_y <= "10001";
                    ex.xbus_sel <= SEL_IMM;
                    ex.ybus_sel <= SEL_REG;
                    ex_stall.zbus_sel <= SEL_ARITH;
                when x"4" =>
                when x"5" =>
                    ex_stall.wrpc_z <= '1';
                    ex_stall.zbus_sel <= SEL_WBUS;
                when x"6" =>
                    id.if_issue <= '1';
                    id.ifadsel <= '1';
                when x"7" =>
                    dispatch <= '1';
                    id.if_issue <= '1';
                    id.incpc <= '1';
                when others =>

            end case;
        end if;
    end process;
end;
