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
    signal cond14 : std_logic_vector(6 downto 0);
    signal cond15 : std_logic_vector(6 downto 0);
    signal cond16 : std_logic_vector(6 downto 0);
    signal cond17 : std_logic_vector(6 downto 0);
    signal cond18 : std_logic_vector(2 downto 0);
    signal cond19 : std_logic_vector(5 downto 0);
    signal cond2 : std_logic_vector(6 downto 0);
    signal cond20 : std_logic_vector(2 downto 0);
    signal cond21 : std_logic_vector(1 downto 0);
    signal cond22 : std_logic_vector(2 downto 0);
    signal cond23 : std_logic_vector(1 downto 0);
    signal cond24 : std_logic_vector(4 downto 0);
    signal cond25 : std_logic_vector(4 downto 0);
    signal cond3 : std_logic_vector(6 downto 0);
    signal cond4 : std_logic_vector(2 downto 0);
    signal cond5 : std_logic_vector(2 downto 0);
    signal cond6 : std_logic_vector(4 downto 0);
    signal cond7 : std_logic_vector(2 downto 0);
    signal cond8 : std_logic_vector(17 downto 0);
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
    signal imp_bit_380 : std_logic;
    signal imp_bit_381 : std_logic;
    signal imp_bit_382 : std_logic;
    signal imp_bit_383 : std_logic;
    signal imp_bit_384 : std_logic;
    signal imp_bit_385 : std_logic;
    signal imp_bit_386 : std_logic;
    signal imp_bit_387 : std_logic;
    signal imp_bit_388 : std_logic;
    signal imp_bit_389 : std_logic;
    signal imp_bit_390 : std_logic;
    signal imp_bit_391 : std_logic;
    signal imp_bit_392 : std_logic;
    signal imp_bit_393 : std_logic;
    signal imp_bit_394 : std_logic;
    signal imp_bit_395 : std_logic;
    signal imp_bit_396 : std_logic;
    signal imp_bit_397 : std_logic;
    signal imp_bit_398 : std_logic;
    signal imp_bit_399 : std_logic;
    signal imp_bit_400 : std_logic;
    signal imp_bit_401 : std_logic;
    signal imp_bit_402 : std_logic;
    signal imp_bit_403 : std_logic;
    signal imp_bit_404 : std_logic;
    signal imp_bit_405 : std_logic;
    signal imp_bit_406 : std_logic;
    signal imp_bit_407 : std_logic;
    signal imp_bit_408 : std_logic;
    signal imp_bit_409 : std_logic;
    signal imp_bit_410 : std_logic;
    signal imp_bit_411 : std_logic;
    signal imp_bit_412 : std_logic;
    signal imp_bit_413 : std_logic;
    signal imp_bit_414 : std_logic;
    signal imp_bit_415 : std_logic;
    signal imp_bit_416 : std_logic;
    signal imp_bit_417 : std_logic;
    signal imp_bit_418 : std_logic;
    signal imp_bit_419 : std_logic;
    signal imp_bit_420 : std_logic;
    signal imp_bit_421 : std_logic;
    signal imp_bit_422 : std_logic;
    signal imp_bit_423 : std_logic;
    signal imp_bit_424 : std_logic;
    signal imp_bit_425 : std_logic;
    signal imp_bit_426 : std_logic;
    signal imp_bit_427 : std_logic;
    signal imp_bit_428 : std_logic;
    signal imp_bit_429 : std_logic;
    signal imp_bit_430 : std_logic;
    signal imp_bit_431 : std_logic;
    signal imp_bit_432 : std_logic;
    signal imp_bit_433 : std_logic;
    signal imp_bit_434 : std_logic;
    signal imp_bit_435 : std_logic;
    signal imp_bit_436 : std_logic;
    signal imp_bit_437 : std_logic;
    signal imp_bit_438 : std_logic;
    signal imp_bit_439 : std_logic;
    signal imp_bit_440 : std_logic;
    signal imp_bit_441 : std_logic;
    signal imp_bit_442 : std_logic;
    signal imp_bit_443 : std_logic;
    signal imp_bit_444 : std_logic;
    signal imp_bit_445 : std_logic;
    signal imp_bit_446 : std_logic;
    signal imp_bit_447 : std_logic;
    signal imp_bit_448 : std_logic;
    signal imp_bit_449 : std_logic;
    signal imp_bit_450 : std_logic;
    signal imp_bit_451 : std_logic;
    signal imp_bit_452 : std_logic;
    signal imp_bit_453 : std_logic;
    signal imp_bit_454 : std_logic;
    signal imp_bit_455 : std_logic;
    signal imp_bit_456 : std_logic;
    signal imp_bit_457 : std_logic;
    signal imp_bit_458 : std_logic;
    signal imp_bit_459 : std_logic;
    signal imp_bit_460 : std_logic;
    signal imp_bit_461 : std_logic;
    signal imp_bit_462 : std_logic;
    signal imp_bit_463 : std_logic;
    signal imp_bit_464 : std_logic;
    signal imp_bit_465 : std_logic;
    signal imp_bit_466 : std_logic;
    signal imp_bit_467 : std_logic;
    signal imp_bit_468 : std_logic;
    signal imp_bit_469 : std_logic;
    signal imp_bit_470 : std_logic;
    signal imp_bit_471 : std_logic;
    signal imp_bit_472 : std_logic;
    signal imp_bit_473 : std_logic;
    signal imp_bit_474 : std_logic;
    signal imp_bit_475 : std_logic;
    signal imp_bit_476 : std_logic;
    signal imp_bit_477 : std_logic;
    signal imp_bit_478 : std_logic;
    signal imp_bit_479 : std_logic;
    signal imp_bit_480 : std_logic;
    signal imp_bit_481 : std_logic;
    signal imp_bit_482 : std_logic;
    signal imp_bit_483 : std_logic;
    signal imp_bit_484 : std_logic;
    signal imp_bit_485 : std_logic;
    signal imp_bit_486 : std_logic;
    signal imp_bit_487 : std_logic;
    signal imp_bit_488 : std_logic;
    signal imp_bit_489 : std_logic;
    signal imp_bit_490 : std_logic;
    signal imp_bit_491 : std_logic;
    signal imp_bit_492 : std_logic;
    signal imp_bit_493 : std_logic;
    signal imp_bit_494 : std_logic;
    signal imp_bit_495 : std_logic;
    signal imp_bit_496 : std_logic;
    signal imp_bit_497 : std_logic;
    signal imp_bit_498 : std_logic;
    signal imp_bit_499 : std_logic;
    signal imp_bit_500 : std_logic;
    signal imp_bit_501 : std_logic;
    signal imp_bit_502 : std_logic;
    signal imp_bit_503 : std_logic;
    signal imp_bit_504 : std_logic;
    signal imp_bit_505 : std_logic;
    signal imp_bit_506 : std_logic;
    signal imp_bit_507 : std_logic;
    signal imp_bit_508 : std_logic;
    signal imp_bit_509 : std_logic;
    signal imp_bit_510 : std_logic;
    signal imp_bit_511 : std_logic;
    signal imp_bit_512 : std_logic;
    signal imp_bit_513 : std_logic;
    signal imp_bit_514 : std_logic;
    signal imp_bit_515 : std_logic;
    signal imp_bit_516 : std_logic;
    signal imp_bit_517 : std_logic;
    signal imp_bit_518 : std_logic;
    signal imp_bit_519 : std_logic;
    signal imp_bit_520 : std_logic;
    signal imp_bit_521 : std_logic;
    signal imp_bit_522 : std_logic;
    signal imp_bit_523 : std_logic;
    signal imp_bit_524 : std_logic;
    signal imp_bit_525 : std_logic;
    signal imp_bit_526 : std_logic;
    signal imp_bit_527 : std_logic;
    signal imp_bit_528 : std_logic;
    signal imp_bit_529 : std_logic;
    signal imp_bit_530 : std_logic;
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
    imp_bit_9 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0));
    imp_bit_10 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_11 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_12 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_13 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_14 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_15 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_16 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_17 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_18 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_19 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_20 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_21 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_22 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_23 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_24 <= (not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_25 <= (not op.code(0) and not op.code(1) and not op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_26 <= (not op.code(0) and not op.code(1) and op.code(2) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_27 <= (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_28 <= (not op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_29 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_30 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_31 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0));
    imp_bit_32 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_33 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_34 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_35 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_36 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_37 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_38 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_39 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_40 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_41 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_42 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_43 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_44 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_45 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_46 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_47 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_48 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_49 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_50 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0));
    imp_bit_51 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_52 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_53 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_54 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_55 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_56 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_57 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_58 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_59 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_60 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_61 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_62 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_63 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_64 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_65 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_66 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_67 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_68 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_69 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_70 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_71 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_72 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_73 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_74 <= (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_75 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_76 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_77 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_78 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_79 <= (not op.code(0) and op.code(1) and not op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_80 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_81 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_82 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_83 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_84 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_85 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_86 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_87 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_88 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0));
    imp_bit_89 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_90 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_91 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_92 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_93 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_94 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_95 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_96 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_97 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_98 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_99 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_100 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_101 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_102 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_103 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_104 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_105 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0));
    imp_bit_106 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_107 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_108 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_109 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_110 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_111 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_112 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_113 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_114 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_115 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_116 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_117 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_118 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_119 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_120 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_121 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_122 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0));
    imp_bit_123 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_124 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_125 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_126 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_127 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_128 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_129 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_130 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_131 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_132 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_133 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_134 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_135 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_136 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_137 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_138 <= (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_139 <= (not op.code(0) and op.code(1) and op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_140 <= (not op.code(0) and op.code(1) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_141 <= (not op.code(0) and op.code(1) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_142 <= (not op.code(0) and op.code(1) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_143 <= (not op.code(0) and op.code(1) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_144 <= (not op.code(0) and op.code(1) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_145 <= (not op.code(0) and op.code(1) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_146 <= (not op.code(0) and op.code(1) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_147 <= (not op.code(0) and op.code(1) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_148 <= (not op.code(0) and not op.code(2) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_149 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_150 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_151 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_152 <= (not op.code(0) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_153 <= (not op.code(0) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_154 <= (not op.code(0) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_155 <= (not op.code(0) and not op.code(2) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_156 <= (not op.code(0) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_157 <= (not op.code(0) and op.code(2) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_158 <= (not op.code(0) and op.code(2) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_159 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_160 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_161 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_162 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_163 <= (not op.code(0) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_164 <= (not op.code(0) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_165 <= (not op.code(0) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_166 <= (not op.code(0) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_167 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0));
    imp_bit_168 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_169 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_170 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_171 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_172 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_173 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_174 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_175 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_176 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_177 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_178 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_179 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_180 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_181 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_182 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_183 <= (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_184 <= (op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_185 <= (op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_186 <= (op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_187 <= (op.code(0) and not op.code(1) and op.code(2) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_188 <= (op.code(0) and not op.code(1) and op.code(2) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_189 <= (op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and op.code(12) and op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_190 <= (op.code(0) and not op.code(1) and op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and op.code(12) and op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_191 <= (op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and op.code(12) and op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_192 <= (op.code(0) and not op.code(1) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_193 <= (op.code(0) and not op.code(1) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_194 <= (op.code(0) and not op.code(1) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_195 <= (op.code(0) and op.code(1) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_196 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_197 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_198 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_199 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_200 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_201 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_202 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and op.addr(1));
    imp_bit_203 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_204 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(1));
    imp_bit_205 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_206 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_207 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_208 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_209 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_210 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_211 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_212 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_213 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_214 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_215 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_216 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_217 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_218 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_219 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_220 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_221 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_222 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_223 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_224 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_225 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_226 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_227 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and op.addr(1));
    imp_bit_228 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_229 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(1));
    imp_bit_230 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_231 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_232 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_233 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_234 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_235 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_236 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_237 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_238 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0) and op.addr(1));
    imp_bit_239 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_240 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_241 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_242 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and op.addr(1));
    imp_bit_243 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_244 <= (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_245 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_246 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_247 <= (op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_248 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_249 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_250 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_251 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_252 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_253 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_254 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_255 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_256 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_257 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_258 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_259 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_260 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_261 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_262 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_263 <= (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_264 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_265 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_266 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_267 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_268 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(1));
    imp_bit_269 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_270 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_271 <= (op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_272 <= (op.code(0) and op.code(1) and op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_273 <= (op.code(0) and op.code(2) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_274 <= (not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_275 <= (not op.code(10) and op.code(11) and p(0));
    imp_bit_276 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(0));
    imp_bit_277 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_278 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_279 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_280 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_281 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_282 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_283 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_284 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_285 <= (not op.code(10) and op.code(11) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_286 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_287 <= (not op.code(10) and op.code(11) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_288 <= (not op.code(10) and op.code(11) and p(0) and not op.addr(2));
    imp_bit_289 <= (not op.code(10) and op.code(11) and p(0) and op.addr(2));
    imp_bit_290 <= (op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_291 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_292 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_293 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_294 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_295 <= (op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_296 <= (not op.code(12) and op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_297 <= (not op.code(12) and op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_298 <= (op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_299 <= (op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_300 <= (op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_301 <= (op.code(12) and not op.code(13) and op.code(14) and not p(0));
    imp_bit_302 <= (op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_303 <= (op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_304 <= (op.code(12) and not op.code(13) and not p(0));
    imp_bit_305 <= (op.code(12) and op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_306 <= (op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_307 <= (op.code(12) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_308 <= (op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_309 <= (op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_310 <= (op.code(13) and not op.code(14) and op.code(15) and not p(0) and op.addr(0));
    imp_bit_311 <= (not op.code(1) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_312 <= (not op.code(1) and not op.code(2) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_313 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0));
    imp_bit_314 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_315 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_316 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_317 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_318 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_319 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_320 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_321 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_322 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_323 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_324 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_325 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_326 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_327 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_328 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_329 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_330 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_331 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_332 <= (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_333 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_334 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_335 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_336 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_337 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_338 <= (not op.code(1) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_339 <= (not op.code(1) and not op.code(2) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_340 <= (not op.code(1) and not op.code(2) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_341 <= (not op.code(1) and op.code(2) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_342 <= (not op.code(1) and op.code(2) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_343 <= (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_344 <= (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0));
    imp_bit_345 <= (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0));
    imp_bit_346 <= (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_347 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_348 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_349 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0));
    imp_bit_350 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_351 <= (not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(15) and not p(0));
    imp_bit_352 <= (not op.code(1) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_353 <= (not op.code(1) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_354 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0));
    imp_bit_355 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_356 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_357 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_358 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_359 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_360 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_361 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_362 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_363 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_364 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_365 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_366 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_367 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_368 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_369 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_370 <= (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_371 <= (not op.code(1) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_372 <= (op.code(1) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_373 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0));
    imp_bit_374 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0));
    imp_bit_375 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_376 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_377 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_378 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_379 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_380 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_381 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_382 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_383 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_384 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_385 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1));
    imp_bit_386 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_387 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_388 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(2));
    imp_bit_389 <= (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and op.addr(2));
    imp_bit_390 <= (op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_391 <= (op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_392 <= (op.code(1) and not op.code(2) and op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_393 <= (op.code(1) and op.code(2) and not op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_394 <= (op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_395 <= (op.code(1) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_396 <= (op.code(1) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_397 <= (op.code(1) and op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_398 <= (not op.code(2) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_399 <= (not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_400 <= (op.code(2) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_401 <= (op.code(2) and op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_402 <= (op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_403 <= (op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0));
    imp_bit_404 <= (op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_405 <= (op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_406 <= (op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0));
    imp_bit_407 <= (op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0));
    imp_bit_408 <= (not op.code(8) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_409 <= (not op.code(8) and not op.code(10) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_410 <= (not op.code(8) and op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_411 <= (not op.code(8) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_412 <= (not op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_413 <= (not op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_414 <= (not op.code(8) and not op.code(9) and not op.code(10) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_415 <= (not op.code(8) and not op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_416 <= (not op.code(8) and not op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_417 <= (not op.code(8) and op.code(9) and not op.code(10) and p(0));
    imp_bit_418 <= (not op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(0));
    imp_bit_419 <= (not op.code(8) and op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1));
    imp_bit_420 <= (not op.code(8) and op.code(9) and not op.code(10) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_421 <= (not op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(1));
    imp_bit_422 <= (not op.code(8) and op.code(9) and not op.code(10) and p(0) and op.addr(1));
    imp_bit_423 <= (not op.code(8) and op.code(9) and op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_424 <= (not op.code(8) and op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_425 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_426 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_427 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_428 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_429 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_430 <= (op.code(8) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_431 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0));
    imp_bit_432 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_433 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and op.addr(0));
    imp_bit_434 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_435 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_436 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_437 <= (op.code(8) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_438 <= (op.code(8) and not op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_439 <= (op.code(8) and not op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_440 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_441 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_442 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_443 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_444 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_445 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_446 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(2));
    imp_bit_447 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_448 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_449 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_450 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_451 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1) and op.addr(2));
    imp_bit_452 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(1) and not op.addr(2));
    imp_bit_453 <= (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(2));
    imp_bit_454 <= (op.code(8) and op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_455 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(0));
    imp_bit_456 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_457 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_458 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_459 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_460 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_461 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(1));
    imp_bit_462 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_463 <= (op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(2));
    imp_bit_464 <= (op.code(8) and op.code(9) and op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_465 <= (op.code(8) and op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_466 <= (op.code(8) and op.code(9) and p(0) and not op.addr(0));
    imp_bit_467 <= (op.code(8) and op.code(9) and p(0) and not op.addr(0) and op.addr(2));
    imp_bit_468 <= (op.code(8) and op.code(9) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_469 <= (op.code(8) and op.code(9) and p(0) and not op.addr(1));
    imp_bit_470 <= (op.code(8) and op.code(9) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_471 <= (op.code(8) and op.code(9) and p(0) and not op.addr(2));
    imp_bit_472 <= (not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_473 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_474 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2) and not op.addr(3));
    imp_bit_475 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2) and op.addr(3));
    imp_bit_476 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and op.addr(2) and not op.addr(3));
    imp_bit_477 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2) and not op.addr(3));
    imp_bit_478 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and op.addr(2) and not op.addr(3));
    imp_bit_479 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(3));
    imp_bit_480 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2) and not op.addr(3));
    imp_bit_481 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(3));
    imp_bit_482 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and op.addr(1) and op.addr(2) and not op.addr(3));
    imp_bit_483 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and op.addr(2) and not op.addr(3));
    imp_bit_484 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(3));
    imp_bit_485 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(1) and op.addr(2) and not op.addr(3));
    imp_bit_486 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(1) and not op.addr(3));
    imp_bit_487 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(1) and not op.addr(2) and not op.addr(3));
    imp_bit_488 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(1) and not op.addr(3));
    imp_bit_489 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(2) and not op.addr(3));
    imp_bit_490 <= (not op.code(9) and not op.code(10) and p(0) and op.addr(2) and not op.addr(3));
    imp_bit_491 <= (not op.code(9) and not op.code(10) and p(0) and not op.addr(3));
    imp_bit_492 <= (not op.code(9) and op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_493 <= (not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0));
    imp_bit_494 <= (not op.code(9) and op.code(11) and p(0));
    imp_bit_495 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(0));
    imp_bit_496 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_497 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_498 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_499 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and not op.addr(2));
    imp_bit_500 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_501 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_502 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_503 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_504 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_505 <= (not op.code(9) and op.code(11) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_506 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(1));
    imp_bit_507 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(1) and not op.addr(2));
    imp_bit_508 <= (not op.code(9) and op.code(11) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_509 <= (not op.code(9) and op.code(11) and p(0) and not op.addr(2));
    imp_bit_510 <= (not op.code(9) and op.code(11) and p(0) and op.addr(2));
    imp_bit_511 <= (op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0));
    imp_bit_512 <= (op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0));
    imp_bit_513 <= (op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1));
    imp_bit_514 <= (op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1));
    imp_bit_515 <= (op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(1));
    imp_bit_516 <= (op.code(9) and op.code(10) and p(0));
    imp_bit_517 <= (op.code(9) and op.code(10) and p(0) and not op.addr(0));
    imp_bit_518 <= (op.code(9) and op.code(10) and p(0) and not op.addr(0) and not op.addr(1));
    imp_bit_519 <= (op.code(9) and op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_520 <= (op.code(9) and op.code(10) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_521 <= (op.code(9) and op.code(10) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2));
    imp_bit_522 <= (op.code(9) and op.code(10) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2));
    imp_bit_523 <= (op.code(9) and op.code(10) and p(0) and op.addr(0) and op.addr(1));
    imp_bit_524 <= (op.code(9) and op.code(10) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2));
    imp_bit_525 <= (op.code(9) and op.code(10) and p(0) and op.addr(0) and op.addr(1) and op.addr(2));
    imp_bit_526 <= (op.code(9) and op.code(10) and p(0) and op.addr(0) and not op.addr(2));
    imp_bit_527 <= (op.code(9) and op.code(10) and p(0) and not op.addr(1));
    imp_bit_528 <= (op.code(9) and op.code(10) and p(0) and op.addr(1) and not op.addr(2));
    imp_bit_529 <= (op.code(9) and op.code(10) and p(0) and not op.addr(2));
    imp_bit_530 <= (op.code(9) and op.code(10) and p(0) and op.addr(2));
    debug <= (imp_bit_244 or imp_bit_419);
    delay_jump <= (imp_bit_208 or imp_bit_222 or imp_bit_227 or imp_bit_232 or imp_bit_310 or imp_bit_433);
    cond5 <= (imp_bit_438 or imp_bit_439) & (imp_bit_454 or imp_bit_465) & (imp_bit_10 or imp_bit_20 or imp_bit_23 or imp_bit_32 or imp_bit_43 or imp_bit_46 or imp_bit_51 or imp_bit_62 or imp_bit_65 or imp_bit_82 or imp_bit_89 or imp_bit_100 or imp_bit_103 or imp_bit_106 or imp_bit_117 or imp_bit_120 or imp_bit_123 or imp_bit_134 or imp_bit_137 or imp_bit_161 or imp_bit_168 or imp_bit_179 or imp_bit_182 or imp_bit_197 or imp_bit_203 or imp_bit_213 or imp_bit_217 or imp_bit_221 or imp_bit_224 or imp_bit_228 or imp_bit_234 or imp_bit_239 or imp_bit_241 or imp_bit_243 or imp_bit_246 or imp_bit_257 or imp_bit_263 or imp_bit_268 or imp_bit_270 or imp_bit_276 or imp_bit_288 or imp_bit_295 or imp_bit_309 or imp_bit_314 or imp_bit_325 or imp_bit_328 or imp_bit_344 or imp_bit_355 or imp_bit_366 or imp_bit_369 or imp_bit_374 or imp_bit_385 or imp_bit_388 or imp_bit_418 or imp_bit_421 or imp_bit_428 or imp_bit_449 or imp_bit_453 or imp_bit_469 or imp_bit_471 or imp_bit_491 or imp_bit_495 or imp_bit_506 or imp_bit_509 or imp_bit_517 or imp_bit_527 or imp_bit_529);
    with cond5 select
        dispatch <=
            not t_bcc when "100",
            t_bcc when "010",
            '0' when "001",
            '1' when others;
    event_ack_0 <= ((op.code(8) and op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1) and not op.addr(2)) or imp_bit_474);
    cond0 <= (imp_bit_27) & (imp_bit_236) & (imp_bit_300 or imp_bit_464 or imp_bit_480);
    with cond0 select
        ex.aluinx_sel <=
            SEL_ROTCL when "100",
            SEL_ZERO when "010",
            SEL_FC when "001",
            SEL_XBUS when others;
    cond1 <= (imp_bit_157 or imp_bit_341) & (imp_bit_13 or imp_bit_21 or imp_bit_29 or imp_bit_36 or imp_bit_44 or imp_bit_55 or imp_bit_63 or imp_bit_83 or imp_bit_93 or imp_bit_101 or imp_bit_110 or imp_bit_118 or imp_bit_127 or imp_bit_135 or imp_bit_140 or imp_bit_160 or imp_bit_165 or imp_bit_172 or imp_bit_180 or imp_bit_217 or imp_bit_228 or imp_bit_246 or imp_bit_256 or imp_bit_262 or imp_bit_268 or imp_bit_269 or imp_bit_279 or imp_bit_286 or imp_bit_293 or imp_bit_302 or imp_bit_318 or imp_bit_326 or imp_bit_343 or imp_bit_352 or imp_bit_359 or imp_bit_367 or imp_bit_378 or imp_bit_386 or imp_bit_411 or imp_bit_419 or imp_bit_450 or imp_bit_460 or imp_bit_484 or imp_bit_489 or imp_bit_493 or imp_bit_499 or imp_bit_507 or (op.code(9) and op.code(10) and p(0) and not op.addr(0) and not op.addr(2)) or (op.code(9) and op.code(10) and p(0) and not op.addr(1) and not op.addr(2)));
    with cond1 select
        ex.aluiny_sel <=
            SEL_R0 when "10",
            SEL_IMM when "01",
            SEL_YBUS when others;
    cond2 <= ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & (imp_bit_236) & ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0)));
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
    ex.arith_ci_en <= (imp_bit_67 or imp_bit_141);
    ex.arith_func <= SUB when (imp_bit_13 or imp_bit_21 or imp_bit_29 or imp_bit_36 or imp_bit_44 or imp_bit_55 or imp_bit_63 or (not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_93 or imp_bit_101 or imp_bit_110 or imp_bit_118 or imp_bit_127 or imp_bit_135 or imp_bit_153 or (not op.code(0) and not op.code(2) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_162 or imp_bit_172 or imp_bit_180 or imp_bit_192 or imp_bit_210 or imp_bit_217 or imp_bit_279 or imp_bit_286 or imp_bit_318 or imp_bit_326 or (not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_345 or imp_bit_359 or imp_bit_367 or (op.code(1) and not op.code(2) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_378 or imp_bit_386 or imp_bit_390 or imp_bit_395 or imp_bit_419 or imp_bit_450 or (op.code(8) and op.code(9) and op.code(10) and p(0) and not op.addr(0) and not op.addr(2)) or (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and not op.addr(2) and not op.addr(3)) or (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and op.addr(1) and not op.addr(3)) or imp_bit_483 or imp_bit_499 or imp_bit_507 or imp_bit_520 or imp_bit_521) = '1' else ADD;
    cond3 <= (imp_bit_249) & (imp_bit_27) & ((op.code(0) and op.code(1) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)));
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
    cond4 <= ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_190) & (imp_bit_5 or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & (imp_bit_70 or imp_bit_189 or imp_bit_334);
    with cond4 select
        ex.coproc_cmd <=
            CLDS when "100",
            LDS when "010",
            STS when "001",
            NOP when others;
    cond8 <= ((op.code(0) and not op.code(1) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & (imp_bit_309) & ((not op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0))) & ((op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0))) & (imp_bit_302) & (imp_bit_426 or imp_bit_432) & (imp_bit_299 or (op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0))) & (imp_bit_297 or imp_bit_306 or imp_bit_412) & (imp_bit_274 or imp_bit_293 or (not op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_185) & (imp_bit_149 or imp_bit_192 or imp_bit_231 or imp_bit_250 or imp_bit_330 or imp_bit_390 or imp_bit_423 or imp_bit_480) & ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_11 or imp_bit_34 or imp_bit_53 or imp_bit_91 or imp_bit_108 or imp_bit_125 or imp_bit_170 or (op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_269 or imp_bit_277 or imp_bit_316 or imp_bit_357 or imp_bit_376 or imp_bit_419 or (op.code(8) and op.code(9) and op.code(10) and p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2)) or imp_bit_474 or imp_bit_497) & (imp_bit_17 or imp_bit_40 or imp_bit_59 or imp_bit_97 or imp_bit_114 or imp_bit_131 or imp_bit_176 or imp_bit_283 or imp_bit_300 or imp_bit_322 or imp_bit_363 or imp_bit_382 or imp_bit_424 or imp_bit_443 or imp_bit_457 or imp_bit_476 or imp_bit_503 or (op.code(9) and op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0)) or imp_bit_524);
    with cond8 select
        ex.imm_val <=
            x"ffffffff" when "100000000000000000",
            x"fffffff0" when "010000000000000000",
            x"fffffffe" when "001000000000000000",
            x"fffffff8" when "000100000000000000",
            x"00000010" when "000010000000000000",
            x"00000008" when "000001000000000000",
            imms_12_1 when "000000100000000000",
            x"0000000" & op.code(3 downto 0) when "000000010000000000",
            "000000000000000000000000000" & op.code(3 downto 0) & "0" when "000000001000000000",
            "00000000000000000000000000" & op.code(3 downto 0) & "00" when "000000000100000000",
            imms_8_1 when "000000000010000000",
            "00000000000000000000000" & op.code(7 downto 0) & "0" when "000000000001000000",
            imms_8_0 when "000000000000100000",
            x"000000" & op.code(7 downto 0) when "000000000000010000",
            x"00000001" when "000000000000001000",
            x"00000000" when "000000000000000100",
            x"00000002" when "000000000000000010",
            "0000000000000000000000" & op.code(7 downto 0) & "00" when "000000000000000001",
            x"00000004" when others;
    cond9 <= (imp_bit_250) & ((op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(8) and op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0)) or (op.code(8) and op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1))) & (imp_bit_185 or (not op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (not op.code(9) and not op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0)) or (not op.code(9) and op.code(10) and op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and op.addr(1)));
    with cond9 select
        ex.logic_func <=
            LOGIC_NOT when "100",
            LOGIC_OR when "010",
            LOGIC_AND when "001",
            LOGIC_XOR when others;
    ex.logic_sr_func <= BYTE_EQ when (imp_bit_28) = '1' else ZERO;
    ex.ma_wr <= (imp_bit_12 or imp_bit_14 or imp_bit_29 or imp_bit_35 or imp_bit_37 or imp_bit_48 or imp_bit_54 or imp_bit_56 or imp_bit_92 or imp_bit_94 or imp_bit_109 or imp_bit_111 or imp_bit_126 or imp_bit_128 or imp_bit_163 or imp_bit_165 or imp_bit_171 or imp_bit_173 or imp_bit_202 or imp_bit_210 or imp_bit_217 or imp_bit_236 or imp_bit_278 or imp_bit_280 or imp_bit_298 or imp_bit_317 or imp_bit_319 or imp_bit_346 or imp_bit_352 or imp_bit_358 or imp_bit_360 or imp_bit_377 or imp_bit_379 or imp_bit_408 or imp_bit_435 or imp_bit_450 or imp_bit_472 or imp_bit_487 or imp_bit_498 or imp_bit_500 or imp_bit_513 or imp_bit_520 or imp_bit_521);
    ex.mem_lock <= (imp_bit_200 or imp_bit_204 or imp_bit_234 or imp_bit_239);
    cond13 <= ((op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0)) or (op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_269 or imp_bit_299 or (op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and op.code(13) and op.code(14) and not op.code(15) and not p(0) and op.addr(0)) or (not op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and not op.code(12) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_234 or imp_bit_292 or (not op.code(8) and not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(15) and not p(0)) or imp_bit_434 or imp_bit_512);
    with cond13 select
        ex.mem_size <=
            WORD when "10",
            BYTE when "01",
            LONG when others;
    ex.mmu_reg_sel <= SEL_PTEH;
    cond15 <= (imp_bit_476) & (imp_bit_460 or imp_bit_487) & (imp_bit_200 or imp_bit_274 or imp_bit_413) & (imp_bit_7 or imp_bit_293 or imp_bit_459) & (imp_bit_292 or imp_bit_411 or imp_bit_437 or (not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0)) or imp_bit_515) & (imp_bit_160 or imp_bit_164 or imp_bit_267 or imp_bit_271 or (op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_343 or imp_bit_347 or (not op.code(9) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and op.code(15) and not p(0))) & (imp_bit_2 or imp_bit_81 or imp_bit_140 or imp_bit_152 or imp_bit_193 or imp_bit_199 or imp_bit_217 or imp_bit_234 or imp_bit_246 or imp_bit_257 or imp_bit_263 or imp_bit_265 or imp_bit_270 or imp_bit_298 or imp_bit_306 or imp_bit_311 or imp_bit_339 or imp_bit_340 or imp_bit_348 or imp_bit_353 or imp_bit_372 or imp_bit_397 or imp_bit_401 or imp_bit_403);
    with cond15 select
        ex.regnum_x <=
            "10001" when "1000000",
            "10011" when "0100000",
            "00000" when "0010000",
            "10100" when "0001000",
            "10000" when "0000100",
            '0' & op.code(7 downto 4) when "0000010",
            '0' & op.code(11 downto 8) when "0000001",
            "01111" when others;
    cond16 <= (imp_bit_30 or imp_bit_215) & (imp_bit_7 or imp_bit_459) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_221) & (imp_bit_202 or imp_bit_236 or imp_bit_435 or imp_bit_513) & (imp_bit_292 or imp_bit_408 or imp_bit_437 or imp_bit_472 or imp_bit_515) & (imp_bit_5 or imp_bit_73 or imp_bit_143 or imp_bit_144 or imp_bit_198 or imp_bit_207) & (imp_bit_2 or imp_bit_148 or imp_bit_195 or imp_bit_199 or imp_bit_298 or imp_bit_312 or imp_bit_350 or imp_bit_372 or imp_bit_401 or imp_bit_403 or imp_bit_407);
    with cond16 select
        ex.regnum_y <=
            "10000" when "1000000",
            "10100" when "0100000",
            "10010" when "0010000",
            "10011" when "0001000",
            "00000" when "0000100",
            '0' & op.code(11 downto 8) when "0000010",
            '0' & op.code(7 downto 4) when "0000001",
            "10001" when others;
    cond17 <= ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_459) & (imp_bit_430 or imp_bit_464 or imp_bit_511) & ((not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_205 or imp_bit_219 or imp_bit_305) & (imp_bit_161 or imp_bit_267 or imp_bit_271 or imp_bit_344) & (imp_bit_198 or imp_bit_436 or imp_bit_457 or (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(2) and not op.addr(3)) or imp_bit_487 or imp_bit_514) & (imp_bit_25 or imp_bit_26 or (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0)) or imp_bit_76 or imp_bit_78 or imp_bit_83 or imp_bit_140 or imp_bit_159 or imp_bit_166 or imp_bit_186 or imp_bit_187 or imp_bit_194 or imp_bit_195 or imp_bit_210 or imp_bit_217 or imp_bit_256 or imp_bit_262 or imp_bit_265 or imp_bit_270 or imp_bit_297 or imp_bit_306 or imp_bit_337 or imp_bit_339 or imp_bit_350 or imp_bit_353 or imp_bit_391 or imp_bit_396 or imp_bit_406);
    with cond17 select
        ex.regnum_z <=
            "10000" when "1000000",
            "10001" when "0100000",
            "00000" when "0010000",
            "10010" when "0001000",
            '0' & op.code(7 downto 4) when "0000100",
            "10011" when "0000010",
            '0' & op.code(11 downto 8) when "0000001",
            "01111" when others;
    cond23 <= (imp_bit_11 or imp_bit_34 or imp_bit_53 or imp_bit_91 or imp_bit_108 or imp_bit_125 or imp_bit_170 or imp_bit_207 or imp_bit_277 or imp_bit_303 or imp_bit_309 or imp_bit_316 or imp_bit_357 or imp_bit_376 or imp_bit_419 or imp_bit_426 or imp_bit_432 or imp_bit_464 or imp_bit_474 or imp_bit_497 or imp_bit_519) & (imp_bit_16 or imp_bit_24 or imp_bit_39 or imp_bit_47 or imp_bit_58 or imp_bit_66 or imp_bit_74 or imp_bit_76 or imp_bit_78 or imp_bit_96 or imp_bit_104 or imp_bit_113 or imp_bit_121 or imp_bit_130 or imp_bit_138 or imp_bit_143 or imp_bit_144 or imp_bit_175 or imp_bit_183 or imp_bit_185 or imp_bit_191 or imp_bit_195 or imp_bit_198 or imp_bit_214 or imp_bit_218 or imp_bit_220 or imp_bit_229 or imp_bit_237 or imp_bit_240 or imp_bit_244 or imp_bit_247 or imp_bit_255 or imp_bit_261 or imp_bit_266 or imp_bit_282 or imp_bit_289 or imp_bit_297 or imp_bit_310 or imp_bit_321 or imp_bit_329 or imp_bit_335 or imp_bit_338 or imp_bit_362 or imp_bit_370 or imp_bit_381 or imp_bit_389 or imp_bit_398 or imp_bit_406 or imp_bit_416 or imp_bit_418 or imp_bit_422 or imp_bit_427 or imp_bit_428 or imp_bit_433 or imp_bit_442 or imp_bit_451 or imp_bit_452 or imp_bit_455 or imp_bit_462 or imp_bit_475 or imp_bit_477 or imp_bit_502 or imp_bit_510 or imp_bit_523 or imp_bit_530);
    with cond23 select
        ex.xbus_sel <=
            SEL_PC when "10",
            SEL_IMM when "01",
            SEL_REG when others;
    cond24 <= ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & (imp_bit_12 or imp_bit_35 or imp_bit_54 or imp_bit_92 or imp_bit_109 or imp_bit_126 or imp_bit_171 or imp_bit_278 or imp_bit_317 or imp_bit_358 or imp_bit_377 or (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and op.addr(0) and not op.addr(1) and not op.addr(2)) or (not op.code(9) and not op.code(10) and p(0) and op.addr(0) and op.addr(1) and not op.addr(2) and not op.addr(3)) or imp_bit_498 or imp_bit_520) & (imp_bit_14 or (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_37 or imp_bit_56 or imp_bit_94 or imp_bit_111 or imp_bit_128 or imp_bit_173 or imp_bit_185 or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0)) or imp_bit_280 or imp_bit_319 or imp_bit_360 or imp_bit_379 or (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1) and not op.addr(2)) or (not op.code(9) and not op.code(10) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2) and not op.addr(3)) or imp_bit_500 or imp_bit_521) & (imp_bit_2 or imp_bit_5 or imp_bit_7 or imp_bit_17 or imp_bit_30 or imp_bit_40 or imp_bit_59 or imp_bit_73 or imp_bit_75 or imp_bit_97 or imp_bit_114 or imp_bit_131 or imp_bit_143 or imp_bit_144 or imp_bit_148 or imp_bit_176 or imp_bit_195 or imp_bit_197 or imp_bit_204 or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0) and not op.addr(0)) or imp_bit_207 or imp_bit_215 or imp_bit_221 or imp_bit_236 or imp_bit_283 or imp_bit_292 or imp_bit_298 or imp_bit_312 or imp_bit_322 or imp_bit_350 or imp_bit_363 or imp_bit_372 or imp_bit_382 or imp_bit_401 or imp_bit_403 or imp_bit_407 or imp_bit_408 or imp_bit_434 or imp_bit_437 or imp_bit_443 or imp_bit_459 or imp_bit_472 or imp_bit_503 or imp_bit_512 or imp_bit_515 or imp_bit_524);
    with cond24 select
        ex.ybus_sel <=
            SEL_MACH when "10000",
            SEL_MACL when "01000",
            SEL_PC when "00100",
            SEL_SR when "00010",
            SEL_REG when "00001",
            SEL_IMM when others;
    cond10 <= (imp_bit_202) & (imp_bit_19 or imp_bit_22 or imp_bit_29 or imp_bit_42 or imp_bit_45 or imp_bit_61 or imp_bit_64 or imp_bit_82 or imp_bit_99 or imp_bit_102 or imp_bit_116 or imp_bit_119 or imp_bit_133 or imp_bit_136 or imp_bit_140 or imp_bit_151 or imp_bit_157 or imp_bit_162 or imp_bit_163 or imp_bit_178 or imp_bit_181 or imp_bit_201 or imp_bit_210 or imp_bit_217 or imp_bit_228 or imp_bit_234 or imp_bit_254 or imp_bit_260 or imp_bit_268 or imp_bit_269 or imp_bit_285 or imp_bit_287 or imp_bit_292 or imp_bit_304 or imp_bit_324 or imp_bit_327 or imp_bit_332 or imp_bit_341 or imp_bit_345 or imp_bit_346 or imp_bit_365 or imp_bit_368 or imp_bit_384 or imp_bit_387 or imp_bit_411 or imp_bit_434 or imp_bit_445 or imp_bit_450 or imp_bit_470 or imp_bit_476 or imp_bit_487 or imp_bit_493 or imp_bit_505 or imp_bit_508 or imp_bit_512 or imp_bit_526 or imp_bit_528);
    with cond10 select
        ex_stall.ma_issue <=
            t_bcc when "10",
            '1' when "01",
            '0' when others;
    ex_stall.macsel1 <= SEL_ZBUS when (imp_bit_7 or imp_bit_68) = '1' else SEL_XBUS;
    ex_stall.macsel2 <= SEL_ZBUS when (imp_bit_7 or imp_bit_69) = '1' else SEL_YBUS;
    cond12 <= (imp_bit_435 or imp_bit_513) & (imp_bit_82 or imp_bit_85 or imp_bit_200 or imp_bit_228 or imp_bit_234 or imp_bit_254 or imp_bit_260 or imp_bit_268 or imp_bit_269);
    with cond12 select
        ex_stall.mem_addr_sel <=
            SEL_YBUS when "10",
            SEL_XBUS when "01",
            SEL_ZBUS when others;
    ex_stall.mem_wdata_sel <= SEL_ZBUS when (imp_bit_236 or imp_bit_435 or imp_bit_513) = '1' else SEL_YBUS;
    ex_stall.mmu_reg_sel <= SEL_PTEH;
    ex_stall.mulcom1 <= (imp_bit_188 or imp_bit_248 or imp_bit_394);
    cond6 <= ((op.code(0) and not op.code(1) and op.code(2) and op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((op.code(0) and not op.code(1) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & (imp_bit_248) & ((op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)));
    with cond6 select
        ex_stall.mulcom2 <=
            DMULSL when "10000",
            DMULUL when "01000",
            MULL when "00100",
            MULSW when "00010",
            MULUW when "00001",
            NOP when others;
    cond18 <= ((not op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0))) & ((not op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)));
    with cond18 select
        ex_stall.shiftfunc <=
            ROTATE when "100",
            ROTC when "010",
            ARITH when "001",
            LOGIC when others;
    cond19 <= ((op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & ((not op.code(8) and not op.code(9) and not op.code(10) and p(0) and op.addr(0) and not op.addr(1) and op.addr(2) and not op.addr(3))) & (imp_bit_86) & ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_67 or imp_bit_141 or imp_bit_353) & (imp_bit_4 or (not op.code(0) and not op.code(1) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_199 or imp_bit_413 or imp_bit_415) & ((not op.code(0) and op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_192 or (op.code(0) and op.code(1) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_236 or (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (not op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_395);
    with cond19 select
        ex_stall.sr_sel <=
            SEL_DIV0U when "100000",
            SEL_INT_MASK when "010000",
            SEL_ZBUS when "001000",
            SEL_SET_T when "000100",
            SEL_LOGIC when "000010",
            SEL_ARITH when "000001",
            SEL_PREV when others;
    cond20 <= ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0))) & (imp_bit_353) & (imp_bit_67 or imp_bit_141);
    with cond20 select
        ex_stall.t_sel <=
            SEL_SET when "100",
            SEL_SHIFT when "010",
            SEL_CARRY when "001",
            SEL_CLEAR when others;
    ex_stall.wrmach <= (imp_bit_7 or imp_bit_68);
    ex_stall.wrmacl <= (imp_bit_7 or imp_bit_69);
    cond22 <= (imp_bit_454 or imp_bit_465) & (imp_bit_438 or imp_bit_439) & (imp_bit_11 or imp_bit_15 or imp_bit_34 or imp_bit_38 or imp_bit_53 or imp_bit_57 or imp_bit_91 or imp_bit_95 or imp_bit_108 or imp_bit_112 or imp_bit_125 or imp_bit_129 or imp_bit_170 or imp_bit_174 or imp_bit_207 or imp_bit_221 or imp_bit_225 or imp_bit_231 or imp_bit_277 or imp_bit_281 or imp_bit_309 or imp_bit_316 or imp_bit_320 or imp_bit_357 or imp_bit_361 or imp_bit_376 or imp_bit_380 or imp_bit_419 or imp_bit_441 or imp_bit_456 or imp_bit_474 or imp_bit_477 or imp_bit_497 or imp_bit_501 or imp_bit_519 or imp_bit_522);
    with cond22 select
        ex_stall.wrpc_z <=
            not t_bcc when "100",
            t_bcc when "010",
            '1' when "001",
            '0' when others;
    ex_stall.wrpr_pc <= (imp_bit_205 or imp_bit_219 or imp_bit_305);
    ex_stall.wrreg_z <= (imp_bit_12 or imp_bit_14 or imp_bit_25 or imp_bit_26 or imp_bit_35 or imp_bit_37 or imp_bit_54 or imp_bit_56 or imp_bit_75 or imp_bit_78 or imp_bit_83 or imp_bit_92 or imp_bit_94 or imp_bit_109 or imp_bit_111 or imp_bit_126 or imp_bit_128 or (not op.code(0) and op.code(1) and op.code(2) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)) or imp_bit_140 or imp_bit_142 or imp_bit_155 or imp_bit_159 or imp_bit_161 or imp_bit_166 or imp_bit_171 or imp_bit_173 or imp_bit_186 or imp_bit_187 or imp_bit_194 or imp_bit_195 or imp_bit_198 or (op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0) and not op.addr(0)) or imp_bit_210 or imp_bit_217 or imp_bit_228 or (op.code(0) and op.code(1) and not op.code(2) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0)) or imp_bit_256 or imp_bit_262 or imp_bit_268 or imp_bit_269 or imp_bit_278 or imp_bit_280 or imp_bit_297 or imp_bit_305 or imp_bit_306 or imp_bit_317 or imp_bit_319 or imp_bit_337 or imp_bit_344 or imp_bit_350 or imp_bit_353 or imp_bit_358 or imp_bit_360 or imp_bit_377 or imp_bit_379 or imp_bit_391 or imp_bit_396 or imp_bit_406 or imp_bit_430 or imp_bit_436 or imp_bit_450 or imp_bit_459 or imp_bit_464 or (op.code(8) and op.code(9) and p(0) and not op.addr(0) and op.addr(1) and not op.addr(2)) or imp_bit_484 or imp_bit_487 or imp_bit_498 or imp_bit_500 or imp_bit_511 or imp_bit_514 or imp_bit_520 or imp_bit_521);
    ex_stall.wrsr_z <= (imp_bit_86);
    cond25 <= ((op.code(0) and not op.code(1) and op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(15) and not p(0)) or imp_bit_236 or imp_bit_371 or imp_bit_404) & (imp_bit_337 or imp_bit_339 or imp_bit_348 or imp_bit_353) & (imp_bit_7 or imp_bit_185 or imp_bit_250 or (op.code(0) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or (op.code(1) and not op.code(2) and op.code(3) and not op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and not p(0)) or imp_bit_430 or imp_bit_435 or imp_bit_459 or imp_bit_511 or imp_bit_513) & (imp_bit_5 or imp_bit_73 or imp_bit_76 or imp_bit_78 or imp_bit_143 or imp_bit_144 or imp_bit_198 or imp_bit_221 or imp_bit_297 or imp_bit_399 or imp_bit_457) & (imp_bit_15 or imp_bit_38 or imp_bit_57 or imp_bit_95 or imp_bit_112 or imp_bit_129 or imp_bit_174 or imp_bit_225 or imp_bit_281 or imp_bit_320 or imp_bit_361 or imp_bit_380 or imp_bit_441 or imp_bit_456 or imp_bit_477 or imp_bit_501 or imp_bit_522);
    with cond25 select
        ex_stall.zbus_sel <=
            SEL_MANIP when "10000",
            SEL_SHIFT when "01000",
            SEL_LOGIC when "00100",
            SEL_YBUS when "00010",
            SEL_WBUS when "00001",
            SEL_ARITH when others;
    cond7 <= (imp_bit_439) & (imp_bit_465) & (imp_bit_20 or imp_bit_23 or imp_bit_43 or imp_bit_46 or imp_bit_62 or imp_bit_65 or imp_bit_82 or imp_bit_100 or imp_bit_103 or imp_bit_117 or imp_bit_120 or imp_bit_134 or imp_bit_137 or imp_bit_161 or imp_bit_179 or imp_bit_182 or imp_bit_197 or imp_bit_203 or imp_bit_213 or imp_bit_217 or imp_bit_221 or imp_bit_224 or imp_bit_228 or imp_bit_234 or imp_bit_239 or imp_bit_241 or imp_bit_243 or imp_bit_246 or imp_bit_257 or imp_bit_263 or imp_bit_268 or imp_bit_270 or (not op.code(10) and op.code(11) and p(0) and not op.addr(1)) or imp_bit_288 or imp_bit_295 or imp_bit_309 or imp_bit_325 or imp_bit_328 or imp_bit_344 or imp_bit_366 or imp_bit_369 or imp_bit_385 or imp_bit_388 or imp_bit_421 or (op.code(8) and op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and op.code(14) and op.code(15) and not p(0) and not op.addr(0) and not op.addr(1)) or imp_bit_453 or (op.code(8) and op.code(9) and p(0) and not op.addr(0) and not op.addr(1)) or imp_bit_471 or imp_bit_479 or imp_bit_486 or imp_bit_489 or imp_bit_506 or imp_bit_509 or imp_bit_527 or imp_bit_529);
    with cond7 select
        id.if_issue <=
            not t_bcc when "100",
            t_bcc when "010",
            '0' when "001",
            '1' when others;
    id.ifadsel <= ((not op.code(0) and not op.code(1) and not op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (not op.code(0) and op.code(1) and not op.code(2) and not op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(4) and op.code(5) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (not op.code(0) and op.code(1) and op.code(2) and op.code(3) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (op.code(0) and not op.code(1) and not op.code(2) and not op.code(3) and op.code(12) and op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or imp_bit_208 or imp_bit_222 or imp_bit_227 or imp_bit_232 or (not op.code(10) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or imp_bit_310 or (not op.code(1) and not op.code(2) and not op.code(3) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (not op.code(1) and not op.code(3) and op.code(4) and op.code(5) and op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (op.code(1) and not op.code(2) and not op.code(3) and op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (not op.code(8) and op.code(9) and not op.code(10) and p(0) and not op.addr(0) and op.addr(1)) or imp_bit_428 or imp_bit_433 or imp_bit_447 or imp_bit_459 or imp_bit_482 or (not op.code(9) and op.code(11) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)) or (op.code(9) and op.code(10) and p(0) and not op.addr(0) and op.addr(1) and op.addr(2)));
    id.incpc <= (imp_bit_2 or imp_bit_8 or imp_bit_18 or imp_bit_41 or imp_bit_60 or imp_bit_74 or imp_bit_77 or imp_bit_79 or imp_bit_83 or imp_bit_98 or imp_bit_115 or imp_bit_132 or imp_bit_143 or imp_bit_147 or imp_bit_148 or imp_bit_156 or imp_bit_158 or imp_bit_162 or imp_bit_177 or imp_bit_186 or imp_bit_191 or imp_bit_193 or imp_bit_195 or imp_bit_202 or imp_bit_207 or imp_bit_211 or imp_bit_218 or (op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1)) or imp_bit_231 or imp_bit_238 or imp_bit_242 or imp_bit_244 or imp_bit_255 or imp_bit_261 or imp_bit_266 or imp_bit_271 or imp_bit_274 or imp_bit_284 or imp_bit_290 or imp_bit_293 or imp_bit_297 or imp_bit_304 or imp_bit_307 or imp_bit_309 or imp_bit_312 or imp_bit_323 or imp_bit_335 or imp_bit_338 or imp_bit_340 or imp_bit_345 or imp_bit_351 or imp_bit_353 or imp_bit_364 or imp_bit_372 or imp_bit_383 or imp_bit_401 or imp_bit_403 or imp_bit_407 or imp_bit_409 or imp_bit_414 or imp_bit_420 or imp_bit_425 or imp_bit_432 or imp_bit_444 or imp_bit_458 or imp_bit_475 or imp_bit_493 or imp_bit_504 or imp_bit_525);
    ilevel_cap <= (imp_bit_474);
    cond11 <= (imp_bit_85) & (imp_bit_267 or imp_bit_271) & (imp_bit_188 or imp_bit_248 or imp_bit_394);
    with cond11 select
        mac_busy <=
            WB_NOT_STALL when "100",
            WB_BUSY when "010",
            EX_NOT_STALL when "001",
            NOT_BUSY when others;
    mac_s_latch <= (imp_bit_267 or imp_bit_271);
    mac_stall_sense <= (imp_bit_7 or (not op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and not op.code(15) and not p(0)) or imp_bit_140 or imp_bit_188 or imp_bit_248 or imp_bit_394);
    maskint_next <= (imp_bit_73 or imp_bit_77 or imp_bit_79 or imp_bit_81 or imp_bit_143 or imp_bit_147 or imp_bit_190 or imp_bit_211 or imp_bit_218 or imp_bit_255 or imp_bit_261 or (not op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0)));
    slp <= ((op.code(0) and op.code(1) and not op.code(2) and op.code(3) and op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1)));
    cond14 <= (imp_bit_258) & (imp_bit_82) & (imp_bit_460) & (imp_bit_235) & (imp_bit_292) & (imp_bit_252) & (imp_bit_410 or imp_bit_492);
    with cond14 select
        wb.regnum_w <=
            "10000" when "1000000",
            "10010" when "0100000",
            "01111" when "0010000",
            "10011" when "0001000",
            "10100" when "0000100",
            "10001" when "0000010",
            "00000" when "0000001",
            '0' & op.code(11 downto 8) when others;
    wb_stall.cpu_data_mux <= COPROC when (imp_bit_6 or imp_bit_70) = '1' else DBUS;
    wb_stall.macsel1 <= SEL_WBUS when (imp_bit_80 or imp_bit_265 or imp_bit_270) = '1' else SEL_XBUS;
    wb_stall.macsel2 <= SEL_WBUS when (imp_bit_84 or imp_bit_267 or imp_bit_271) = '1' else SEL_YBUS;
    wb_stall.mulcom1 <= (imp_bit_265 or imp_bit_270);
    cond21 <= (imp_bit_267) & (imp_bit_271);
    with cond21 select
        wb_stall.mulcom2 <=
            MACL when "10",
            MACW when "01",
            NOP when others;
    wb_stall.wrmach <= (imp_bit_80);
    wb_stall.wrmacl <= (imp_bit_84);
    wb_stall.wrreg_w <= (imp_bit_6 or imp_bit_70 or imp_bit_82 or imp_bit_150 or imp_bit_162 or imp_bit_164 or imp_bit_201 or imp_bit_235 or imp_bit_252 or imp_bit_258 or imp_bit_292 or imp_bit_301 or imp_bit_303 or imp_bit_331 or imp_bit_345 or imp_bit_347 or imp_bit_410 or imp_bit_460 or imp_bit_492);
    wb_stall.wrsr_w <= ((op.code(0) and op.code(1) and not op.code(2) and op.code(3) and not op.code(4) and op.code(5) and not op.code(6) and not op.code(7) and not op.code(8) and not op.code(9) and not op.code(10) and not op.code(11) and not op.code(12) and not op.code(13) and not op.code(14) and not op.code(15) and not p(0) and op.addr(0) and not op.addr(1)) or (op.code(0) and op.code(1) and op.code(2) and not op.code(3) and not op.code(4) and not op.code(5) and not op.code(6) and not op.code(7) and not op.code(12) and not op.code(13) and op.code(14) and not op.code(15) and not p(0) and not op.addr(0) and not op.addr(1)));
end;
