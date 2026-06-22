-- ******************************************************************
-- ******************************************************************
-- ******************************************************************
-- This file is generated. Changing this file directly is probably
-- not what you want to do. Any changes will be overwritten next time
-- the generator is run.
-- ******************************************************************
-- ******************************************************************
-- ******************************************************************
architecture direct_logic of decode_table is
    signal mac_busy : mac_busy_t;
    signal imms_12_1 : std_logic_vector(31 downto 0);
    signal imms_8_0 : std_logic_vector(31 downto 0);
    signal imms_8_1 : std_logic_vector(31 downto 0);
    signal cond0 : std_logic_vector(2 downto 0);
    signal cond1 : std_logic_vector(1 downto 0);
    signal cond10 : std_logic_vector(1 downto 0);
    signal cond11 : std_logic_vector(2 downto 0);
    signal cond12 : std_logic_vector(1 downto 0);
    signal cond13 : std_logic_vector(1 downto 0);
    signal cond14 : std_logic_vector(1 downto 0);
    signal cond15 : std_logic_vector(1 downto 0);
    signal cond16 : std_logic_vector(6 downto 0);
    signal cond17 : std_logic_vector(5 downto 0);
    signal cond18 : std_logic_vector(9 downto 0);
    signal cond19 : std_logic_vector(8 downto 0);
    signal cond2 : std_logic_vector(6 downto 0);
    signal cond20 : std_logic_vector(2 downto 0);
    signal cond21 : std_logic_vector(9 downto 0);
    signal cond22 : std_logic_vector(2 downto 0);
    signal cond23 : std_logic_vector(1 downto 0);
    signal cond24 : std_logic_vector(2 downto 0);
    signal cond25 : std_logic_vector(1 downto 0);
    signal cond26 : std_logic_vector(7 downto 0);
    signal cond27 : std_logic_vector(4 downto 0);
    signal cond3 : std_logic_vector(6 downto 0);
    signal cond4 : std_logic_vector(2 downto 0);
    signal cond5 : std_logic_vector(2 downto 0);
    signal cond6 : std_logic_vector(4 downto 0);
    signal cond7 : std_logic_vector(2 downto 0);
    signal cond8 : std_logic_vector(30 downto 0);
    signal cond9 : std_logic_vector(2 downto 0);
    signal imp_bit_0 : std_logic;
    signal imp_bit_1 : std_logic;
    signal imp_bit_2 : std_logic;
    signal imp_bit_3 : std_logic;
    signal imp_bit_4 : std_logic;
    signal imp_bit_5 : std_logic;
    signal imp_bit_6 : std_logic;
    signal imp_bit_7 : std_logic;
    signal imp_bit_8 : std_logic;
    signal imp_bit_9 : std_logic;
    signal imp_bit_10 : std_logic;
    signal imp_bit_11 : std_logic;
    signal imp_bit_12 : std_logic;
    signal imp_bit_13 : std_logic;
    signal imp_bit_14 : std_logic;
    signal imp_bit_15 : std_logic;
    signal imp_bit_16 : std_logic;
    signal imp_bit_17 : std_logic;
    signal imp_bit_18 : std_logic;
    signal imp_bit_19 : std_logic;
    signal imp_bit_20 : std_logic;
    signal imp_bit_21 : std_logic;
    signal imp_bit_22 : std_logic;
    signal imp_bit_23 : std_logic;
    signal imp_bit_24 : std_logic;
    signal imp_bit_25 : std_logic;
    signal imp_bit_26 : std_logic;
    signal imp_bit_27 : std_logic;
    signal imp_bit_28 : std_logic;
    signal imp_bit_29 : std_logic;
    signal imp_bit_30 : std_logic;
    signal imp_bit_31 : std_logic;
    signal imp_bit_32 : std_logic;
    signal imp_bit_33 : std_logic;
    signal imp_bit_34 : std_logic;
    signal imp_bit_35 : std_logic;
    signal imp_bit_36 : std_logic;
    signal imp_bit_37 : std_logic;
    signal imp_bit_38 : std_logic;
    signal imp_bit_39 : std_logic;
    signal imp_bit_40 : std_logic;
    signal imp_bit_41 : std_logic;
    signal imp_bit_42 : std_logic;
    signal imp_bit_43 : std_logic;
    signal imp_bit_44 : std_logic;
    signal imp_bit_45 : std_logic;
    signal imp_bit_46 : std_logic;
    signal imp_bit_47 : std_logic;
    signal imp_bit_48 : std_logic;
    signal imp_bit_49 : std_logic;
    signal imp_bit_50 : std_logic;
    signal imp_bit_51 : std_logic;
    signal imp_bit_52 : std_logic;
    signal imp_bit_53 : std_logic;
    signal imp_bit_54 : std_logic;
    signal imp_bit_55 : std_logic;
    signal imp_bit_56 : std_logic;
    signal imp_bit_57 : std_logic;
    signal imp_bit_58 : std_logic;
    signal imp_bit_59 : std_logic;
    signal imp_bit_60 : std_logic;
    signal imp_bit_61 : std_logic;
    signal imp_bit_62 : std_logic;
    signal imp_bit_63 : std_logic;
    signal imp_bit_64 : std_logic;
    signal imp_bit_65 : std_logic;
    signal imp_bit_66 : std_logic;
    signal imp_bit_67 : std_logic;
    signal imp_bit_68 : std_logic;
    signal imp_bit_69 : std_logic;
    signal imp_bit_70 : std_logic;
    signal imp_bit_71 : std_logic;
    signal imp_bit_72 : std_logic;
    signal imp_bit_73 : std_logic;
    signal imp_bit_74 : std_logic;
    signal imp_bit_75 : std_logic;
    signal imp_bit_76 : std_logic;
    signal imp_bit_77 : std_logic;
    signal imp_bit_78 : std_logic;
    signal imp_bit_79 : std_logic;
    signal imp_bit_80 : std_logic;
    signal imp_bit_81 : std_logic;
    signal imp_bit_82 : std_logic;
    signal imp_bit_83 : std_logic;
    signal imp_bit_84 : std_logic;
    signal imp_bit_85 : std_logic;
    signal imp_bit_86 : std_logic;
    signal imp_bit_87 : std_logic;
    signal imp_bit_88 : std_logic;
    signal imp_bit_89 : std_logic;
    signal imp_bit_90 : std_logic;
    signal imp_bit_91 : std_logic;
    signal imp_bit_92 : std_logic;
    signal imp_bit_93 : std_logic;
    signal imp_bit_94 : std_logic;
    signal imp_bit_95 : std_logic;
    signal imp_bit_96 : std_logic;
    signal imp_bit_97 : std_logic;
    signal imp_bit_98 : std_logic;
    signal imp_bit_99 : std_logic;
    signal imp_bit_100 : std_logic;
    signal imp_bit_101 : std_logic;
    signal imp_bit_102 : std_logic;
    signal imp_bit_103 : std_logic;
    signal imp_bit_104 : std_logic;
    signal imp_bit_105 : std_logic;
    signal imp_bit_106 : std_logic;
    signal imp_bit_107 : std_logic;
    signal imp_bit_108 : std_logic;
    signal imp_bit_109 : std_logic;
    signal imp_bit_110 : std_logic;
    signal imp_bit_111 : std_logic;
    signal imp_bit_112 : std_logic;
    signal imp_bit_113 : std_logic;
    signal imp_bit_114 : std_logic;
    signal imp_bit_115 : std_logic;
    signal imp_bit_116 : std_logic;
    signal imp_bit_117 : std_logic;
    signal imp_bit_118 : std_logic;
    signal imp_bit_119 : std_logic;
    signal imp_bit_120 : std_logic;
    signal imp_bit_121 : std_logic;
    signal imp_bit_122 : std_logic;
    signal imp_bit_123 : std_logic;
    signal imp_bit_124 : std_logic;
    signal imp_bit_125 : std_logic;
    signal imp_bit_126 : std_logic;
    signal imp_bit_127 : std_logic;
    signal imp_bit_128 : std_logic;
    signal imp_bit_129 : std_logic;
    signal imp_bit_130 : std_logic;
    signal imp_bit_131 : std_logic;
    signal imp_bit_132 : std_logic;
    signal imp_bit_133 : std_logic;
    signal imp_bit_134 : std_logic;
    signal imp_bit_135 : std_logic;
    signal imp_bit_136 : std_logic;
    signal imp_bit_137 : std_logic;
    signal imp_bit_138 : std_logic;
    signal imp_bit_139 : std_logic;
    signal imp_bit_140 : std_logic;
    signal imp_bit_141 : std_logic;
    signal imp_bit_142 : std_logic;
    signal imp_bit_143 : std_logic;
    signal imp_bit_144 : std_logic;
    signal imp_bit_145 : std_logic;
    signal imp_bit_146 : std_logic;
    signal imp_bit_147 : std_logic;
    signal imp_bit_148 : std_logic;
    signal imp_bit_149 : std_logic;
    signal imp_bit_150 : std_logic;
    signal imp_bit_151 : std_logic;
    signal imp_bit_152 : std_logic;
    signal imp_bit_153 : std_logic;
    signal imp_bit_154 : std_logic;
    signal imp_bit_155 : std_logic;
    signal imp_bit_156 : std_logic;
    signal imp_bit_157 : std_logic;
    signal imp_bit_158 : std_logic;
    signal imp_bit_159 : std_logic;
    signal imp_bit_160 : std_logic;
    signal imp_bit_161 : std_logic;
    signal imp_bit_162 : std_logic;
    signal imp_bit_163 : std_logic;
    signal imp_bit_164 : std_logic;
    signal imp_bit_165 : std_logic;
    signal imp_bit_166 : std_logic;
    signal imp_bit_167 : std_logic;
    signal imp_bit_168 : std_logic;
    signal imp_bit_169 : std_logic;
    signal imp_bit_170 : std_logic;
    signal imp_bit_171 : std_logic;
    signal imp_bit_172 : std_logic;
    signal imp_bit_173 : std_logic;
    signal imp_bit_174 : std_logic;
    signal imp_bit_175 : std_logic;
    signal imp_bit_176 : std_logic;
    signal imp_bit_177 : std_logic;
    signal imp_bit_178 : std_logic;
    signal imp_bit_179 : std_logic;
    signal imp_bit_180 : std_logic;
    signal imp_bit_181 : std_logic;
    signal imp_bit_182 : std_logic;
    signal imp_bit_183 : std_logic;
    signal imp_bit_184 : std_logic;
    signal imp_bit_185 : std_logic;
    signal imp_bit_186 : std_logic;
    signal imp_bit_187 : std_logic;
    signal imp_bit_188 : std_logic;
    signal imp_bit_189 : std_logic;
    signal imp_bit_190 : std_logic;
    signal imp_bit_191 : std_logic;
    signal imp_bit_192 : std_logic;
    signal imp_bit_193 : std_logic;
    signal imp_bit_194 : std_logic;
    signal imp_bit_195 : std_logic;
    signal imp_bit_196 : std_logic;
    signal imp_bit_197 : std_logic;
    signal imp_bit_198 : std_logic;
    signal imp_bit_199 : std_logic;
    signal imp_bit_200 : std_logic;
    signal imp_bit_201 : std_logic;
    signal imp_bit_202 : std_logic;
    signal imp_bit_203 : std_logic;
    signal imp_bit_204 : std_logic;
    signal imp_bit_205 : std_logic;
    signal imp_bit_206 : std_logic;
    signal imp_bit_207 : std_logic;
    signal imp_bit_208 : std_logic;
    signal imp_bit_209 : std_logic;
    signal imp_bit_210 : std_logic;
    signal imp_bit_211 : std_logic;
    signal imp_bit_212 : std_logic;
    signal imp_bit_213 : std_logic;
    signal imp_bit_214 : std_logic;
    signal imp_bit_215 : std_logic;
    signal imp_bit_216 : std_logic;
    signal imp_bit_217 : std_logic;
    signal imp_bit_218 : std_logic;
    signal imp_bit_219 : std_logic;
    signal imp_bit_220 : std_logic;
    signal imp_bit_221 : std_logic;
    signal imp_bit_222 : std_logic;
    signal imp_bit_223 : std_logic;
    signal imp_bit_224 : std_logic;
    signal imp_bit_225 : std_logic;
    signal imp_bit_226 : std_logic;
    signal imp_bit_227 : std_logic;
    signal imp_bit_228 : std_logic;
    signal imp_bit_229 : std_logic;
    signal imp_bit_230 : std_logic;
    signal imp_bit_231 : std_logic;
    signal imp_bit_232 : std_logic;
    signal imp_bit_233 : std_logic;
    signal imp_bit_234 : std_logic;
    signal imp_bit_235 : std_logic;
    signal imp_bit_236 : std_logic;
    signal imp_bit_237 : std_logic;
    signal imp_bit_238 : std_logic;
    signal imp_bit_239 : std_logic;
    signal imp_bit_240 : std_logic;
    signal imp_bit_241 : std_logic;
    signal imp_bit_242 : std_logic;
    signal imp_bit_243 : std_logic;
    signal imp_bit_244 : std_logic;
    signal imp_bit_245 : std_logic;
    signal imp_bit_246 : std_logic;
    signal imp_bit_247 : std_logic;
    signal imp_bit_248 : std_logic;
    signal imp_bit_249 : std_logic;
    signal imp_bit_250 : std_logic;
    signal imp_bit_251 : std_logic;
    signal imp_bit_252 : std_logic;
    signal imp_bit_253 : std_logic;
    signal imp_bit_254 : std_logic;
    signal imp_bit_255 : std_logic;
    signal imp_bit_256 : std_logic;
    signal imp_bit_257 : std_logic;
    signal imp_bit_258 : std_logic;
    signal imp_bit_259 : std_logic;
    signal imp_bit_260 : std_logic;
    signal imp_bit_261 : std_logic;
    signal imp_bit_262 : std_logic;
    signal imp_bit_263 : std_logic;
    signal imp_bit_264 : std_logic;
    signal imp_bit_265 : std_logic;
    signal imp_bit_266 : std_logic;
    signal imp_bit_267 : std_logic;
    signal imp_bit_268 : std_logic;
    signal imp_bit_269 : std_logic;
    signal imp_bit_270 : std_logic;
    signal imp_bit_271 : std_logic;
    signal imp_bit_272 : std_logic;
    signal imp_bit_273 : std_logic;
    signal imp_bit_274 : std_logic;
    signal imp_bit_275 : std_logic;
    signal imp_bit_276 : std_logic;
    signal imp_bit_277 : std_logic;
    signal imp_bit_278 : std_logic;
    signal imp_bit_279 : std_logic;
    signal imp_bit_280 : std_logic;
    signal imp_bit_281 : std_logic;
    signal imp_bit_282 : std_logic;
    signal imp_bit_283 : std_logic;
    signal imp_bit_284 : std_logic;
    signal imp_bit_285 : std_logic;
    signal imp_bit_286 : std_logic;
    signal imp_bit_287 : std_logic;
    signal imp_bit_288 : std_logic;
    signal imp_bit_289 : std_logic;
    signal imp_bit_290 : std_logic;
    signal imp_bit_291 : std_logic;
    signal imp_bit_292 : std_logic;
    signal imp_bit_293 : std_logic;
    signal imp_bit_294 : std_logic;
    signal imp_bit_295 : std_logic;
    signal imp_bit_296 : std_logic;
    signal imp_bit_297 : std_logic;
    signal imp_bit_298 : std_logic;
    signal imp_bit_299 : std_logic;
    signal imp_bit_300 : std_logic;
    signal imp_bit_301 : std_logic;
    signal imp_bit_302 : std_logic;
    signal imp_bit_303 : std_logic;
    signal imp_bit_304 : std_logic;
    signal imp_bit_305 : std_logic;
    signal imp_bit_306 : std_logic;
    signal imp_bit_307 : std_logic;
    signal imp_bit_308 : std_logic;
    signal imp_bit_309 : std_logic;
    signal imp_bit_310 : std_logic;
    signal imp_bit_311 : std_logic;
    signal imp_bit_312 : std_logic;
    signal imp_bit_313 : std_logic;
    signal imp_bit_314 : std_logic;
    signal imp_bit_315 : std_logic;
    signal imp_bit_316 : std_logic;
    signal imp_bit_317 : std_logic;
    signal imp_bit_318 : std_logic;
    signal imp_bit_319 : std_logic;
    signal imp_bit_320 : std_logic;
    signal imp_bit_321 : std_logic;
    signal imp_bit_322 : std_logic;
    signal imp_bit_323 : std_logic;
    signal imp_bit_324 : std_logic;
    signal imp_bit_325 : std_logic;
    signal imp_bit_326 : std_logic;
    signal imp_bit_327 : std_logic;
    signal imp_bit_328 : std_logic;
    signal imp_bit_329 : std_logic;
    signal imp_bit_330 : std_logic;
    signal imp_bit_331 : std_logic;
    signal imp_bit_332 : std_logic;
    signal imp_bit_333 : std_logic;
    signal imp_bit_334 : std_logic;
    signal imp_bit_335 : std_logic;
    signal imp_bit_336 : std_logic;
    signal imp_bit_337 : std_logic;
    signal imp_bit_338 : std_logic;
    signal imp_bit_339 : std_logic;
    signal imp_bit_340 : std_logic;
    signal imp_bit_341 : std_logic;
    signal imp_bit_342 : std_logic;
    signal imp_bit_343 : std_logic;
    signal imp_bit_344 : std_logic;
    signal imp_bit_345 : std_logic;
    signal imp_bit_346 : std_logic;
    signal imp_bit_347 : std_logic;
    signal imp_bit_348 : std_logic;
    signal imp_bit_349 : std_logic;
    signal imp_bit_350 : std_logic;
    signal imp_bit_351 : std_logic;
    signal imp_bit_352 : std_logic;
    signal imp_bit_353 : std_logic;
    signal imp_bit_354 : std_logic;
    signal imp_bit_355 : std_logic;
    signal imp_bit_356 : std_logic;
    signal imp_bit_357 : std_logic;
    signal imp_bit_358 : std_logic;
    signal imp_bit_359 : std_logic;
    signal imp_bit_360 : std_logic;
    signal imp_bit_361 : std_logic;
    signal imp_bit_362 : std_logic;
    signal imp_bit_363 : std_logic;
    signal imp_bit_364 : std_logic;
    signal imp_bit_365 : std_logic;
    signal imp_bit_366 : std_logic;
    signal imp_bit_367 : std_logic;
    signal imp_bit_368 : std_logic;
    signal imp_bit_369 : std_logic;
    signal imp_bit_370 : std_logic;
    signal imp_bit_371 : std_logic;
    signal imp_bit_372 : std_logic;
    signal imp_bit_373 : std_logic;
    signal imp_bit_374 : std_logic;
    signal imp_bit_375 : std_logic;
    signal imp_bit_376 : std_logic;
    signal imp_bit_377 : std_logic;
    signal imp_bit_378 : std_logic;
    signal imp_bit_379 : std_logic;
    signal p : std_logic_vector(0 downto 0);
begin
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
            not next_id_stall when EX_NOT_STALL,
            '1' when EX_BUSY,
            '0' when others;
    with mac_busy select
        wb.mac_busy <=
            not next_id_stall when WB_NOT_STALL,
            '1' when WB_BUSY,
            '0' when others;
    p <= "0" when op.plane = NORMAL_INSTR else "1";
    imp_bit_0 <= (not op.code(0) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_1 <= (not op.code(0) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_2 <= (not op.code(0) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_3 <= (not op.code(0) and not op.code(1) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_4 <= (not op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_5 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_6 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_7 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_8 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_9 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_10 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_11 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_12 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_13 <= (not op.code(0) and not op.code(1) and not op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_14 <= (not op.code(0) and not op.code(1) and op.code(2) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_15 <= (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_16 <= (not op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_17 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_18 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_19 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_20 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_21 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_22 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_23 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_24 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_25 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_26 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_27 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_28 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_29 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_30 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_31 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_32 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_33 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_34 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_35 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_36 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(4) and not op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_37 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_38 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_39 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_40 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_41 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_42 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_43 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_44 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_45 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_46 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_47 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_48 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_49 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_50 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_51 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_52 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_53 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_54 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_55 <= (not op.code(0) and op.code(1) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_56 <= (not op.code(0) and op.code(1) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_57 <= (not op.code(0) and op.code(1) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_58 <= (not op.code(0) and op.code(1) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_59 <= (not op.code(0) and op.code(1) and op.code(3) and op.code(4) and not op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_60 <= (not op.code(0) and op.code(1) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_61 <= (not op.code(0) and op.code(1) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_62 <= (not op.code(0) and op.code(1) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_63 <= (not op.code(0) and not op.code(2) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_64 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_65 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_66 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_67 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_68 <= (not op.code(0) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_69 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_70 <= (not op.code(0) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_71 <= (not op.code(0) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_72 <= (not op.code(0) and not op.code(2) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_73 <= (not op.code(0) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_74 <= (not op.code(0) and not op.code(2) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_75 <= (not op.code(0) and op.code(2) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_76 <= (not op.code(0) and op.code(2) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_77 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_78 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_79 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_80 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_81 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_82 <= (not op.code(0) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_83 <= (not op.code(0) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_84 <= (not op.code(0) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_85 <= (not op.code(0) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_86 <= (op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_87 <= (op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_88 <= (op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_89 <= (op.code(0) and not op.code(1) and op.code(2) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_90 <= (op.code(0) and not op.code(1) and op.code(2) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_91 <= (op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and op.code(12) and op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_92 <= (op.code(0) and not op.code(1) and op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and op.code(12) and op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_93 <= (op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and op.code(12) and op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_94 <= (op.code(0) and not op.code(1) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_95 <= (op.code(0) and not op.code(1) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_96 <= (op.code(0) and not op.code(1) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_97 <= (op.code(0) and op.code(1) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_98 <= (op.code(0) and op.code(1) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_99 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_100 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_101 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_102 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_103 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_104 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_105 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and op.addr(1));
    imp_bit_106 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_107 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(1));
    imp_bit_108 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_109 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_110 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_111 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_112 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_113 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_114 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_115 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_116 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_117 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_118 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_119 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_120 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_121 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_122 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_123 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_124 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_125 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_126 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_127 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_128 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_129 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_130 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_131 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_132 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_133 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_134 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_135 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_136 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_137 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_138 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_139 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0) and op.addr(1));
    imp_bit_140 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_141 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_142 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_143 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and op.addr(1));
    imp_bit_144 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_145 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_146 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_147 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_148 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_149 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_150 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_151 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_152 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_153 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_154 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_155 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_156 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_157 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_158 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_159 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_160 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_161 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_162 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_163 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_164 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_165 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_166 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_167 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_168 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_169 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_170 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_171 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_172 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_173 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_174 <= (op.code(0) and op.code(1) and op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_175 <= (op.code(0) and not op.code(2) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_176 <= (op.code(0) and op.code(2) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_177 <= (op.code(0) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_178 <= (not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_179 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_180 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_181 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_182 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and not op.addr(1));
    imp_bit_183 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_184 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_185 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_186 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(1));
    imp_bit_187 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(1) and op.addr(2));
    imp_bit_188 <= (not op.code(10) and op.code(11) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_189 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(2));
    imp_bit_190 <= (op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_191 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_192 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_193 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_194 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_195 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_196 <= (not op.code(12) and op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_197 <= (not op.code(12) and op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_198 <= (op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_199 <= (op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_200 <= (op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_201 <= (op.code(12) and not op.code(13) and op.code(14) and not p(0));
    imp_bit_202 <= (op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_203 <= (op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_204 <= (op.code(12) and not op.code(13) and not p(0));
    imp_bit_205 <= (op.code(12) and op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_206 <= (op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_207 <= (op.code(12) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_208 <= (op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_209 <= (op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_210 <= (op.code(13) and not op.code(14) and op.code(15) and not p(0) and op.addr(0));
    imp_bit_211 <= (not op.code(1) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_212 <= (not op.code(1) and not op.code(2) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_213 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_214 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_215 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_216 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_217 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_218 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_219 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_220 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_221 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_222 <= (not op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_223 <= (not op.code(1) and not op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_224 <= (not op.code(1) and op.code(2) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_225 <= (not op.code(1) and op.code(2) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_226 <= (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_227 <= (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_228 <= (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_229 <= (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_230 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_231 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_232 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_233 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_234 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(15) and not p(0));
    imp_bit_235 <= (not op.code(1) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_236 <= (not op.code(1) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_237 <= (not op.code(1) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_238 <= (op.code(1) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_239 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_240 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_241 <= (op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_242 <= (op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_243 <= (op.code(1) and not op.code(2) and op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_244 <= (op.code(1) and op.code(2) and not op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_245 <= (op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_246 <= (op.code(1) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_247 <= (op.code(1) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_248 <= (op.code(1) and op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_249 <= (not op.code(2) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_250 <= (not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_251 <= (op.code(2) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_252 <= (op.code(2) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_253 <= (op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_254 <= (op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_255 <= (op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_256 <= (op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_257 <= (op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_258 <= (op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_259 <= (not op.code(8) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_260 <= (not op.code(8) and not op.code(10) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_261 <= (not op.code(8) and op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_262 <= (not op.code(8) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_263 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0));
    imp_bit_264 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_265 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_266 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1));
    imp_bit_267 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_268 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(2));
    imp_bit_269 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_270 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(1));
    imp_bit_271 <= (not op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_272 <= (not op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_273 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_274 <= (not op.code(8) and not op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_275 <= (not op.code(8) and not op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_276 <= (not op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0));
    imp_bit_277 <= (not op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0));
    imp_bit_278 <= (not op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(0) and not op.addr(1));
    imp_bit_279 <= (not op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_280 <= (not op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(1));
    imp_bit_281 <= (not op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(1));
    imp_bit_282 <= (not op.code(8) and op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_283 <= (not op.code(8) and op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_284 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_285 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_286 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_287 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_288 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_289 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_290 <= (op.code(8) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_291 <= (op.code(8) and not op.code(10) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_292 <= (op.code(8) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1));
    imp_bit_293 <= (op.code(8) and not op.code(10) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_294 <= (op.code(8) and not op.code(10) and p(0) and not op.addr(1));
    imp_bit_295 <= (op.code(8) and not op.code(10) and p(0) and not op.addr(1) and op.addr(2));
    imp_bit_296 <= (op.code(8) and not op.code(10) and p(0) and not op.addr(2));
    imp_bit_297 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_298 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_299 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and op.addr(0));
    imp_bit_300 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_301 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_302 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_303 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_304 <= (op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_305 <= (op.code(8) and not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_306 <= (op.code(8) and not op.code(9) and not op.code(10) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_307 <= (op.code(8) and not op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_308 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_309 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_310 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_311 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_312 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_313 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_314 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_315 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(2));
    imp_bit_316 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_317 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_318 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_319 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_320 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(2));
    imp_bit_321 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_322 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1) and op.addr(2));
    imp_bit_323 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(1) and not op.addr(2));
    imp_bit_324 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(2));
    imp_bit_325 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0));
    imp_bit_326 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_327 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_328 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_329 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(2));
    imp_bit_330 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_331 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_332 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(1));
    imp_bit_333 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_334 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(2));
    imp_bit_335 <= (op.code(8) and op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_336 <= (op.code(8) and op.code(9) and op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_337 <= (op.code(8) and op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_338 <= (op.code(8) and op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_339 <= (op.code(8) and op.code(9) and not op.code(11) and p(0) and not op.addr(1));
    imp_bit_340 <= (op.code(8) and op.code(9) and not op.code(11) and p(0) and not op.addr(1) and op.addr(2));
    imp_bit_341 <= (op.code(8) and op.code(9) and not op.code(11) and p(0) and not op.addr(2));
    imp_bit_342 <= (not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_343 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_344 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1));
    imp_bit_345 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_346 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_347 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(1));
    imp_bit_348 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(1) and op.addr(2));
    imp_bit_349 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_350 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(2));
    imp_bit_351 <= (not op.code(9) and op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_352 <= (not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_353 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_354 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_355 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_356 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and not op.addr(1));
    imp_bit_357 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_358 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_359 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_360 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(1));
    imp_bit_361 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(1) and op.addr(2));
    imp_bit_362 <= (not op.code(9) and op.code(11) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_363 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(2));
    imp_bit_364 <= (op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_365 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_366 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_367 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_368 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and op.addr(0) and not op.addr(1));
    imp_bit_369 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_370 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_371 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_372 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(1));
    imp_bit_373 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(1) and op.addr(2));
    imp_bit_374 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_375 <= (op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(2));
    imp_bit_376 <= (op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_377 <= (op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_378 <= (op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_379 <= (op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    debug <= (imp_bit_145 or imp_bit_278);
    delay_jump <= (imp_bit_111 or imp_bit_125 or imp_bit_128 or imp_bit_133 or imp_bit_210 or imp_bit_299);
    cond5 <= (imp_bit_304 or imp_bit_307) & (imp_bit_335 or imp_bit_338) & (imp_bit_41 or imp_bit_79 or imp_bit_100 or imp_bit_106 or imp_bit_116 or imp_bit_120 or imp_bit_124 or imp_bit_130 or imp_bit_135 or imp_bit_140 or imp_bit_142 or imp_bit_144 or imp_bit_147 or imp_bit_159 or imp_bit_165 or imp_bit_170 or imp_bit_172 or imp_bit_179 or imp_bit_189 or imp_bit_195 or imp_bit_209 or imp_bit_227 or imp_bit_270 or imp_bit_277 or imp_bit_280 or imp_bit_287 or imp_bit_290 or imp_bit_296 or imp_bit_321 or imp_bit_324 or imp_bit_332 or imp_bit_350 or imp_bit_353 or imp_bit_363 or imp_bit_365 or imp_bit_375);
    with cond5 select
        dispatch <=
            not t_bcc when "100",
            t_bcc when "010",
            '0' when "001",
            '1' when others;
    event_ack_0 <= ((op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2)) or (not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2)));
    cond0 <= (imp_bit_15) & (imp_bit_137) & (imp_bit_200 or imp_bit_336);
    with cond0 select
        ex.aluinx_sel <=
            SEL_ROTCL when "100",
            SEL_ZERO when "010",
            SEL_FC when "001",
            SEL_XBUS when others;
    cond1 <= (imp_bit_75 or imp_bit_224) & (imp_bit_18 or imp_bit_42 or imp_bit_55 or imp_bit_78 or imp_bit_83 or imp_bit_120 or imp_bit_147 or imp_bit_158 or imp_bit_164 or imp_bit_170 or imp_bit_171 or imp_bit_180 or imp_bit_193 or imp_bit_202 or imp_bit_226 or imp_bit_235 or imp_bit_262 or imp_bit_278 or imp_bit_310 or imp_bit_331 or imp_bit_343 or imp_bit_352 or imp_bit_354 or imp_bit_366);
    with cond1 select
        ex.aluiny_sel <=
            SEL_R0 when "10",
            SEL_IMM when "01",
            SEL_YBUS when others;
    cond2 <= ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & (imp_bit_137) & ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0)));
    with cond2 select
        ex.alumanip <=
            EXTEND_SBYTE when "1000000",
            EXTEND_SWORD when "0100000",
            EXTEND_UBYTE when "0010000",
            EXTEND_UWORD when "0001000",
            EXTRACT when "0000100",
            SET_BIT_7 when "0000010",
            SWAP_WORD when "0000001",
            SWAP_BYTE when others;
    ex.arith_ci_en <= (imp_bit_24 or imp_bit_56);
    ex.arith_func <= SUB when (imp_bit_18 or (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_68 or (not op.code(0) and not op.code(2) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_80 or imp_bit_94 or imp_bit_113 or imp_bit_120 or imp_bit_180 or (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_228 or (op.code(1) and not op.code(2) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_241 or imp_bit_246 or imp_bit_278 or imp_bit_337 or imp_bit_343 or imp_bit_354) = '1' else ADD;
    cond3 <= (imp_bit_151) & (imp_bit_15) & ((op.code(0) and op.code(1) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)));
    with cond3 select
        ex.arith_sr_func <=
            DIV0S when "1000000",
            DIV1 when "0100000",
            OVERUNDERFLOW when "0010000",
            UGRTER when "0001000",
            UGRTER_EQ when "0000100",
            SGRTER when "0000010",
            SGRTER_EQ when "0000001",
            ZERO when others;
    cond4 <= ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_92) & (imp_bit_5 or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & (imp_bit_28 or imp_bit_91 or imp_bit_217);
    with cond4 select
        ex.coproc_cmd <=
            CLDS when "100",
            LDS when "010",
            STS when "001",
            NOP when others;
    cond8 <= ((op.code(0) and not op.code(1) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(8) and op.code(9) and not op.code(10) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2))) & (imp_bit_265) & ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(8) and op.code(9) and not op.code(10) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2))) & ((not op.code(9) and op.code(10) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2))) & (imp_bit_313) & ((op.code(8) and op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2))) & ((not op.code(8) and op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2))) & ((not op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2))) & ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2))) & (imp_bit_209) & ((not op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0))) & ((op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0))) & (imp_bit_202) & ((not op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2)) or (op.code(8) and op.code(9) and not op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2))) & ((not op.code(8) and not op.code(9) and op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2)) or (op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2))) & ((not op.code(8) and op.code(9) and not op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2)) or (op.code(8) and not op.code(9) and op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2))) & (imp_bit_285 or imp_bit_298) & (imp_bit_199 or (op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0))) & ((op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(1) and not op.addr(2)) or imp_bit_311 or imp_bit_371) & (imp_bit_197 or imp_bit_206 or imp_bit_271) & (imp_bit_178 or imp_bit_193 or imp_bit_269 or (not op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_87) & (imp_bit_200 or imp_bit_283 or imp_bit_319 or imp_bit_327 or (op.code(9) and op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0))) & (imp_bit_64 or imp_bit_94 or imp_bit_132 or imp_bit_152 or imp_bit_213 or imp_bit_241 or imp_bit_282 or imp_bit_310) & ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_171 or imp_bit_180 or imp_bit_278 or imp_bit_337 or imp_bit_343 or imp_bit_354);
    with cond8 select
        ex.imm_val <=
            x"ffffffff" when "1000000000000000000000000000000",
            x"fffffff0" when "0100000000000000000000000000000",
            x"fffffffe" when "0010000000000000000000000000000",
            x"fffffff8" when "0001000000000000000000000000000",
            x"00000080" when "0000100000000000000000000000000",
            x"00000600" when "0000010000000000000000000000000",
            x"00000010" when "0000001000000000000000000000000",
            x"000000a0" when "0000000100000000000000000000000",
            x"000000c0" when "0000000010000000000000000000000",
            x"00000160" when "0000000001000000000000000000000",
            x"00000180" when "0000000000100000000000000000000",
            x"000001a0" when "0000000000010000000000000000000",
            x"00000040" when "0000000000001000000000000000000",
            x"00000008" when "0000000000000100000000000000000",
            x"00000060" when "0000000000000010000000000000000",
            imms_12_1 when "0000000000000001000000000000000",
            x"0000000" & op.code(3 downto 0) when "0000000000000000100000000000000",
            "000000000000000000000000000" & op.code(3 downto 0) & "0" when "0000000000000000010000000000000",
            "00000000000000000000000000" & op.code(3 downto 0) & "00" when "0000000000000000001000000000000",
            x"00000400" when "0000000000000000000100000000000",
            x"00000420" when "0000000000000000000010000000000",
            x"00000440" when "0000000000000000000001000000000",
            imms_8_1 when "0000000000000000000000100000000",
            "00000000000000000000000" & op.code(7 downto 0) & "0" when "0000000000000000000000010000000",
            x"00000100" when "0000000000000000000000001000000",
            imms_8_0 when "0000000000000000000000000100000",
            x"000000" & op.code(7 downto 0) when "0000000000000000000000000010000",
            x"00000001" when "0000000000000000000000000001000",
            "0000000000000000000000" & op.code(7 downto 0) & "00" when "0000000000000000000000000000100",
            x"00000000" when "0000000000000000000000000000010",
            x"00000002" when "0000000000000000000000000000001",
            x"00000004" when others;
    cond9 <= (imp_bit_152) & ((op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(8) and op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0)) or (op.code(8) and op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1))) & (imp_bit_87 or (not op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (not op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0)) or (not op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1)));
    with cond9 select
        ex.logic_func <=
            LOGIC_NOT when "100",
            LOGIC_OR when "010",
            LOGIC_AND when "001",
            LOGIC_XOR when others;
    ex.logic_sr_func <= BYTE_EQ when (imp_bit_16) = '1' else ZERO;
    ex.ma_wr <= (imp_bit_18 or imp_bit_20 or imp_bit_81 or imp_bit_83 or imp_bit_105 or imp_bit_113 or imp_bit_120 or imp_bit_137 or imp_bit_198 or imp_bit_229 or imp_bit_235 or imp_bit_259 or imp_bit_301 or imp_bit_342 or imp_bit_377);
    ex.mem_lock <= (imp_bit_103 or imp_bit_107 or imp_bit_135 or imp_bit_140);
    cond13 <= ((op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_171 or imp_bit_199 or (op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_135 or imp_bit_192 or (not op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0)) or imp_bit_300 or imp_bit_376);
    with cond13 select
        ex.mem_size <=
            WORD when "10",
            BYTE when "01",
            LONG when others;
    cond14 <= ((op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)));
    with cond14 select
        ex.mmu_reg_sel <=
            SEL_ASIDR when "10",
            SEL_PTEL when "01",
            SEL_PTEH when others;
    cond17 <= (imp_bit_331) & (imp_bit_103 or imp_bit_178 or imp_bit_272) & (imp_bit_7 or imp_bit_193 or imp_bit_330) & (imp_bit_192 or imp_bit_262 or imp_bit_303 or (not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0)) or imp_bit_379) & (imp_bit_185 or imp_bit_265 or imp_bit_306 or imp_bit_311 or imp_bit_359 or imp_bit_371) & (imp_bit_78 or imp_bit_82 or imp_bit_169 or imp_bit_173 or (op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_226 or imp_bit_230 or (not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0)));
    with cond17 select
        ex.regnum_x <=
            "10011" when "100000",
            "00000" when "010000",
            "10100" when "001000",
            "10000" when "000100",
            "10001" when "000010",
            '0' & op.code(7 downto 4) when "000001",
            '0' & op.code(11 downto 8) when others;
    cond18 <= (imp_bit_23) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_118) & (imp_bit_17 or imp_bit_129) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_127) & (imp_bit_7 or imp_bit_330) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_124) & (imp_bit_105 or imp_bit_137 or imp_bit_301 or imp_bit_377) & (imp_bit_192 or imp_bit_259 or imp_bit_303 or imp_bit_342 or imp_bit_379) & (imp_bit_5 or imp_bit_52 or imp_bit_53 or imp_bit_58 or imp_bit_59 or imp_bit_101 or imp_bit_110);
    with cond18 select
        ex.regnum_y <=
            "11" & op.code(6 downto 4) when "1000000000",
            "10000" when "0100000000",
            "10101" when "0010000000",
            "10110" when "0001000000",
            "10100" when "0000100000",
            "10001" when "0000010000",
            "10010" when "0000001000",
            "10011" when "0000000100",
            "00000" when "0000000010",
            '0' & op.code(11 downto 8) when "0000000001",
            '0' & op.code(7 downto 4) when others;
    cond19 <= ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & (imp_bit_53) & ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_330) & (imp_bit_289 or imp_bit_336 or imp_bit_364) & ((not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_108 or imp_bit_122 or imp_bit_205) & (imp_bit_79 or imp_bit_169 or imp_bit_173 or imp_bit_227) & (imp_bit_101 or imp_bit_302 or imp_bit_327 or imp_bit_378) & (imp_bit_46 or imp_bit_180 or imp_bit_310 or imp_bit_343 or imp_bit_354 or imp_bit_366) & ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_183 or imp_bit_317 or imp_bit_345 or imp_bit_357 or imp_bit_369);
    with cond19 select
        ex.regnum_z <=
            "10000" when "100000000",
            "11" & op.code(6 downto 4) when "010000000",
            "10001" when "001000000",
            "00000" when "000100000",
            "10010" when "000010000",
            '0' & op.code(7 downto 4) when "000001000",
            "10011" when "000000100",
            "10101" when "000000010",
            "10110" when "000000001",
            '0' & op.code(11 downto 8) when others;
    cond25 <= (imp_bit_110 or imp_bit_180 or imp_bit_203 or imp_bit_209 or imp_bit_278 or imp_bit_285 or imp_bit_298 or imp_bit_310 or imp_bit_336 or imp_bit_343 or imp_bit_354 or imp_bit_366) & (imp_bit_2 or imp_bit_7 or imp_bit_40 or imp_bit_55 or imp_bit_67 or imp_bit_76 or imp_bit_78 or imp_bit_95 or imp_bit_103 or imp_bit_107 or imp_bit_120 or imp_bit_135 or imp_bit_147 or imp_bit_159 or imp_bit_165 or imp_bit_170 or imp_bit_171 or imp_bit_178 or imp_bit_185 or imp_bit_191 or imp_bit_202 or imp_bit_207 or imp_bit_211 or imp_bit_222 or imp_bit_223 or imp_bit_226 or imp_bit_232 or imp_bit_236 or imp_bit_238 or imp_bit_248 or imp_bit_252 or imp_bit_254 or imp_bit_262 or imp_bit_265 or imp_bit_273 or imp_bit_293 or imp_bit_303 or imp_bit_311 or imp_bit_330 or imp_bit_352 or imp_bit_359 or imp_bit_371 or imp_bit_379);
    with cond25 select
        ex.xbus_sel <=
            SEL_PC when "10",
            SEL_REG when "01",
            SEL_IMM when others;
    cond26 <= ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_87 or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0)) or imp_bit_183 or imp_bit_317 or imp_bit_345 or imp_bit_357 or imp_bit_369) & (imp_bit_2 or imp_bit_5 or imp_bit_7 or imp_bit_17 or (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_23 or imp_bit_32 or imp_bit_52 or imp_bit_53 or imp_bit_58 or imp_bit_59 or imp_bit_63 or imp_bit_97 or imp_bit_100 or imp_bit_107 or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0) and not op.addr(0)) or imp_bit_110 or imp_bit_118 or imp_bit_124 or imp_bit_130 or imp_bit_137 or imp_bit_192 or imp_bit_198 or imp_bit_212 or imp_bit_233 or imp_bit_238 or imp_bit_252 or imp_bit_254 or imp_bit_258 or imp_bit_259 or imp_bit_300 or imp_bit_303 or imp_bit_330 or imp_bit_342 or imp_bit_376 or imp_bit_379);
    with cond26 select
        ex.ybus_sel <=
            SEL_EXPEVT when "10000000",
            SEL_INTEVT when "01000000",
            SEL_TRA when "00100000",
            SEL_MACH when "00010000",
            SEL_MACL when "00001000",
            SEL_MMU when "00000100",
            SEL_SR when "00000010",
            SEL_REG when "00000001",
            SEL_IMM when others;
    cond10 <= (imp_bit_105) & (imp_bit_18 or imp_bit_41 or imp_bit_55 or imp_bit_66 or imp_bit_75 or imp_bit_80 or imp_bit_81 or imp_bit_104 or imp_bit_113 or imp_bit_120 or imp_bit_135 or imp_bit_156 or imp_bit_162 or imp_bit_170 or imp_bit_171 or imp_bit_192 or imp_bit_204 or imp_bit_215 or imp_bit_224 or imp_bit_228 or imp_bit_229 or imp_bit_262 or imp_bit_300 or imp_bit_333 or imp_bit_352 or imp_bit_376);
    with cond10 select
        ex_stall.ma_issue <=
            t_bcc when "10",
            '1' when "01",
            '0' when others;
    ex_stall.macsel1 <= SEL_ZBUS when (imp_bit_7 or imp_bit_25) = '1' else SEL_XBUS;
    ex_stall.macsel2 <= SEL_ZBUS when (imp_bit_7 or imp_bit_27) = '1' else SEL_YBUS;
    cond12 <= (imp_bit_301 or imp_bit_377) & (imp_bit_41 or imp_bit_44 or imp_bit_103 or imp_bit_135 or imp_bit_156 or imp_bit_162 or imp_bit_170 or imp_bit_171);
    with cond12 select
        ex_stall.mem_addr_sel <=
            SEL_YBUS when "10",
            SEL_XBUS when "01",
            SEL_ZBUS when others;
    ex_stall.mem_wdata_sel <= SEL_ZBUS when (imp_bit_137 or imp_bit_301 or imp_bit_377) = '1' else SEL_YBUS;
    cond15 <= ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(4) and op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)));
    with cond15 select
        ex_stall.mmu_reg_sel <=
            SEL_ASIDR when "10",
            SEL_PTEL when "01",
            SEL_PTEH when others;
    ex_stall.mmu_reg_wr <= (imp_bit_47 or imp_bit_49);
    ex_stall.mulcom1 <= (imp_bit_90 or imp_bit_150 or imp_bit_245);
    cond6 <= ((op.code(0) and not op.code(1) and op.code(2) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & (imp_bit_150) & ((op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)));
    with cond6 select
        ex_stall.mulcom2 <=
            DMULSL when "10000",
            DMULUL when "01000",
            MULL when "00100",
            MULSW when "00010",
            MULUW when "00001",
            NOP when others;
    cond20 <= ((not op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)));
    with cond20 select
        ex_stall.shiftfunc <=
            ROTATE when "100",
            ROTC when "010",
            ARITH when "001",
            LOGIC when others;
    cond21 <= ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & (imp_bit_269) & ((not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2))) & (imp_bit_319) & (imp_bit_45 or imp_bit_127) & ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_24 or imp_bit_56 or imp_bit_236) & (imp_bit_183 or imp_bit_317 or imp_bit_345 or imp_bit_357 or imp_bit_369) & (imp_bit_181 or (op.code(8) and not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2)) or imp_bit_313 or imp_bit_355 or imp_bit_367) & (imp_bit_4 or (not op.code(0) and not op.code(1) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_102 or imp_bit_272 or imp_bit_274) & ((not op.code(0) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_94 or imp_bit_98 or imp_bit_137 or (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (not op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_246);
    with cond21 select
        ex_stall.sr_sel <=
            SEL_DIV0U when "1000000000",
            SEL_INTEVT when "0100000000",
            SEL_INT_MASK when "0010000000",
            SEL_TRA when "0001000000",
            SEL_ZBUS when "0000100000",
            SEL_SET_T when "0000010000",
            SEL_EXCEPTION when "0000001000",
            SEL_EXPEVT when "0000000100",
            SEL_LOGIC when "0000000010",
            SEL_ARITH when "0000000001",
            SEL_PREV when others;
    cond22 <= ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & (imp_bit_236) & (imp_bit_24 or imp_bit_56);
    with cond22 select
        ex_stall.t_sel <=
            SEL_SET when "100",
            SEL_SHIFT when "010",
            SEL_CARRY when "001",
            SEL_CLEAR when others;
    ex_stall.tlb_wr <= (imp_bit_9);
    ex_stall.wrmach <= (imp_bit_7 or imp_bit_25);
    ex_stall.wrmacl <= (imp_bit_7 or imp_bit_27);
    cond24 <= (imp_bit_335 or imp_bit_338) & (imp_bit_304 or imp_bit_307) & (imp_bit_110 or imp_bit_124 or imp_bit_129 or imp_bit_132 or imp_bit_185 or imp_bit_209 or imp_bit_265 or imp_bit_278 or imp_bit_306 or imp_bit_311 or imp_bit_326 or imp_bit_359 or imp_bit_371);
    with cond24 select
        ex_stall.wrpc_z <=
            not t_bcc when "100",
            t_bcc when "010",
            '1' when "001",
            '0' when others;
    ex_stall.wrpr_pc <= (imp_bit_108 or imp_bit_122 or imp_bit_205);
    ex_stall.wrreg_z <= (imp_bit_13 or imp_bit_14 or imp_bit_22 or imp_bit_23 or imp_bit_32 or imp_bit_37 or imp_bit_42 or imp_bit_46 or (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_53 or imp_bit_55 or imp_bit_72 or imp_bit_77 or imp_bit_79 or imp_bit_85 or imp_bit_88 or imp_bit_89 or imp_bit_96 or imp_bit_97 or imp_bit_101 or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0) and not op.addr(0)) or imp_bit_113 or imp_bit_120 or (op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0)) or imp_bit_158 or imp_bit_164 or imp_bit_170 or imp_bit_171 or (not op.code(10) and op.code(11) and p(0) and not op.addr(1) and not op.addr(2)) or imp_bit_197 or imp_bit_205 or imp_bit_206 or imp_bit_220 or imp_bit_227 or imp_bit_233 or imp_bit_236 or imp_bit_239 or imp_bit_240 or imp_bit_242 or imp_bit_247 or imp_bit_257 or imp_bit_289 or imp_bit_302 or (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1) and not op.addr(2)) or imp_bit_327 or imp_bit_330 or imp_bit_336 or (not op.code(9) and not op.code(10) and p(0) and not op.addr(1) and not op.addr(2)) or (not op.code(9) and op.code(11) and p(0) and not op.addr(1) and not op.addr(2)) or imp_bit_364 or (op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(1) and not op.addr(2)) or imp_bit_378);
    ex_stall.wrsr_z <= (imp_bit_45);
    cond27 <= (imp_bit_326) & ((op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0)) or imp_bit_137 or imp_bit_237 or imp_bit_255) & (imp_bit_220 or imp_bit_222 or imp_bit_231 or imp_bit_236) & (imp_bit_7 or imp_bit_87 or imp_bit_152 or (op.code(0) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_289 or imp_bit_301 or imp_bit_330 or imp_bit_364 or imp_bit_377) & (imp_bit_5 or imp_bit_22 or imp_bit_23 or imp_bit_26 or imp_bit_31 or imp_bit_52 or imp_bit_53 or imp_bit_59 or imp_bit_101 or imp_bit_124 or imp_bit_130 or imp_bit_183 or imp_bit_197 or imp_bit_239 or imp_bit_240 or imp_bit_250 or imp_bit_317 or imp_bit_327 or imp_bit_345 or imp_bit_357 or imp_bit_369);
    with cond27 select
        ex_stall.zbus_sel <=
            SEL_WBUS when "10000",
            SEL_MANIP when "01000",
            SEL_SHIFT when "00100",
            SEL_LOGIC when "00010",
            SEL_YBUS when "00001",
            SEL_ARITH when others;
    cond7 <= (imp_bit_307) & (imp_bit_338) & (imp_bit_41 or imp_bit_79 or imp_bit_100 or imp_bit_106 or imp_bit_116 or imp_bit_120 or imp_bit_124 or imp_bit_130 or imp_bit_135 or imp_bit_140 or imp_bit_142 or imp_bit_144 or imp_bit_147 or imp_bit_159 or imp_bit_165 or imp_bit_170 or imp_bit_172 or imp_bit_189 or imp_bit_195 or imp_bit_209 or imp_bit_227 or imp_bit_264 or imp_bit_280 or imp_bit_296 or imp_bit_309 or imp_bit_324 or (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1)) or imp_bit_350 or imp_bit_363 or imp_bit_375);
    with cond7 select
        id.if_issue <=
            not t_bcc when "100",
            t_bcc when "010",
            '0' when "001",
            '1' when others;
    id.ifadsel <= (imp_bit_111 or imp_bit_125 or imp_bit_128 or imp_bit_133 or (not op.code(10) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and op.addr(2)) or imp_bit_210 or (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2)) or (not op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and op.addr(1)) or imp_bit_287 or imp_bit_299 or (op.code(8) and not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and op.addr(2)) or imp_bit_318 or imp_bit_330 or (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and op.addr(2)) or (op.code(9) and op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and op.addr(2)));
    id.incpc <= (imp_bit_2 or imp_bit_12 or imp_bit_22 or imp_bit_23 or imp_bit_30 or imp_bit_34 or imp_bit_42 or imp_bit_52 or imp_bit_53 or imp_bit_62 or imp_bit_63 or imp_bit_73 or imp_bit_76 or imp_bit_80 or imp_bit_88 or imp_bit_93 or imp_bit_95 or imp_bit_97 or imp_bit_105 or imp_bit_110 or imp_bit_114 or imp_bit_121 or imp_bit_127 or imp_bit_132 or imp_bit_139 or imp_bit_143 or imp_bit_145 or imp_bit_157 or imp_bit_163 or imp_bit_168 or imp_bit_173 or imp_bit_178 or imp_bit_184 or imp_bit_190 or imp_bit_193 or imp_bit_197 or imp_bit_204 or imp_bit_207 or imp_bit_209 or imp_bit_212 or imp_bit_218 or imp_bit_221 or imp_bit_223 or imp_bit_228 or imp_bit_234 or imp_bit_236 or imp_bit_238 or imp_bit_239 or imp_bit_240 or imp_bit_252 or imp_bit_254 or imp_bit_258 or imp_bit_260 or imp_bit_267 or imp_bit_273 or imp_bit_279 or imp_bit_284 or imp_bit_298 or imp_bit_305 or imp_bit_314 or imp_bit_328 or imp_bit_352 or imp_bit_358 or imp_bit_370);
    ilevel_cap <= ((not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2)));
    cond11 <= (imp_bit_44) & (imp_bit_169 or imp_bit_173) & (imp_bit_90 or imp_bit_150 or imp_bit_245);
    with cond11 select
        mac_busy <=
            WB_NOT_STALL when "100",
            WB_BUSY when "010",
            EX_NOT_STALL when "001",
            NOT_BUSY when others;
    mac_s_latch <= (imp_bit_169 or imp_bit_173);
    mac_stall_sense <= (imp_bit_7 or imp_bit_31 or imp_bit_55 or imp_bit_90 or imp_bit_150 or imp_bit_245);
    maskint_next <= (imp_bit_9 or imp_bit_22 or imp_bit_23 or imp_bit_34 or imp_bit_38 or imp_bit_40 or imp_bit_52 or imp_bit_53 or imp_bit_59 or imp_bit_62 or imp_bit_92 or imp_bit_114 or imp_bit_121 or imp_bit_157 or imp_bit_163 or (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_239 or imp_bit_240);
    slp <= ((op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1)));
    cond16 <= (imp_bit_160) & (imp_bit_41) & (imp_bit_331) & (imp_bit_136) & (imp_bit_192) & (imp_bit_154) & (imp_bit_261 or imp_bit_351);
    with cond16 select
        wb.regnum_w <=
            "10000" when "1000000",
            "10010" when "0100000",
            "01111" when "0010000",
            "10011" when "0001000",
            "10100" when "0000100",
            "10001" when "0000010",
            "00000" when "0000001",
            '0' & op.code(11 downto 8) when others;
    wb_stall.cpu_data_mux <= COPROC when (imp_bit_6 or imp_bit_28) = '1' else DBUS;
    wb_stall.macsel1 <= SEL_WBUS when (imp_bit_39 or imp_bit_167 or imp_bit_172) = '1' else SEL_XBUS;
    wb_stall.macsel2 <= SEL_WBUS when (imp_bit_43 or imp_bit_169 or imp_bit_173) = '1' else SEL_YBUS;
    wb_stall.mulcom1 <= (imp_bit_167 or imp_bit_172);
    cond23 <= (imp_bit_169) & (imp_bit_173);
    with cond23 select
        wb_stall.mulcom2 <=
            MACL when "10",
            MACW when "01",
            NOP when others;
    wb_stall.wrmach <= (imp_bit_39);
    wb_stall.wrmacl <= (imp_bit_43);
    wb_stall.wrreg_w <= (imp_bit_6 or imp_bit_28 or imp_bit_41 or imp_bit_65 or imp_bit_80 or imp_bit_82 or imp_bit_104 or imp_bit_136 or imp_bit_154 or imp_bit_160 or imp_bit_192 or imp_bit_201 or imp_bit_203 or imp_bit_214 or imp_bit_228 or imp_bit_230 or imp_bit_261 or imp_bit_331 or imp_bit_351);
    wb_stall.wrsr_w <= ((op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1)));
end;
