-- Configuration that runs the existing mult_tap testbench against the
-- sequential shift-and-add multiplier architecture mult(seq).
--
-- It binds the 'mult_i' instance (the mult component inside mult_tap, see
-- tests/mult_tap.vhd line ~65) to entity work.mult architecture seq.  The
-- original mult_tap configuration (default binding to mult(stru)) is left
-- untouched and must still pass.

configuration mult_seq_tap of mult_tap is
  for tb
    for mult_i : mult
      use entity work.mult(seq);
    end for;
  end for;
end configuration mult_seq_tap;
