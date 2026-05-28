package logic

// PrimeImplicants returns all prime implicants covering the input
// minterms via the Quine-McCluskey tabular method:
//
//  1. Treat each input minterm as an implicant of "size" = number of
//     fixed bits.
//  2. In each iteration, try to merge every pair of implicants that
//     differ in exactly one bit (same Sig, same Bit position; values
//     differ). The merged implicant drops that bit (becomes don't-care).
//  3. Implicants that participated in at least one merge are dropped;
//     unmerged implicants are "prime" for this iteration.
//  4. Repeat with the merged set until no merges happen.
//  5. Return the union of all primes from every iteration.
//
// Duplicate implicants are de-duplicated by their LogicMap content.
// The result order is sorted for deterministic output.
func PrimeImplicants(minterms []LogicMap) []LogicMap {
	if len(minterms) == 0 {
		return nil
	}
	current := make([]LogicMap, len(minterms))
	copy(current, minterms)

	primeSet := map[string]LogicMap{}

	for {
		merged := map[int]bool{}
		var next []LogicMap
		nextKeys := map[string]bool{}

		for i := 0; i < len(current); i++ {
			for j := i + 1; j < len(current); j++ {
				m, ok := tryMerge(current[i], current[j])
				if !ok {
					continue
				}
				merged[i] = true
				merged[j] = true
				key := CanonicalKey(m)
				if !nextKeys[key] {
					nextKeys[key] = true
					next = append(next, m)
				}
			}
		}
		// Implicants that did not merge in this round are prime.
		for i, lm := range current {
			if !merged[i] {
				key := CanonicalKey(lm)
				if _, seen := primeSet[key]; !seen {
					primeSet[key] = lm.Clone()
				}
			}
		}
		if len(next) == 0 {
			break
		}
		current = next
	}

	// Sort primes by canonical key for deterministic output.
	out := make([]LogicMap, 0, len(primeSet))
	keys := make([]string, 0, len(primeSet))
	for k := range primeSet {
		keys = append(keys, k)
	}
	sortStrings(keys)
	for _, k := range keys {
		out = append(out, primeSet[k])
	}
	return out
}

// tryMerge attempts to combine two implicants that differ in exactly one
// bit. Returns the merged implicant (with that bit dropped) and ok=true,
// or zero-value and ok=false if they cannot be merged. Two implicants can
// merge only if (a) they have the same keys, and (b) values agree on
// every key except exactly one.
func tryMerge(a, b LogicMap) (LogicMap, bool) {
	if len(a) != len(b) {
		return nil, false
	}
	var diffKey SigBit
	diffCount := 0
	for k, va := range a {
		vb, ok := b[k]
		if !ok {
			return nil, false
		}
		if va != vb {
			diffCount++
			if diffCount > 1 {
				return nil, false
			}
			diffKey = k
		}
	}
	if diffCount != 1 {
		return nil, false
	}
	out := make(LogicMap, len(a)-1)
	for k, v := range a {
		if k == diffKey {
			continue
		}
		out[k] = v
	}
	return out, true
}

// CanonicalKey serializes a LogicMap into a stable string for
// deduplication or use as a map key. Keys are sorted by Sig then Bit,
// and the format is "sig:bit=val,sig:bit=val,...". Exported so callers
// (e.g. model.BuildDirect's imp_bit frequency counting) can use the
// same canonicalization as the QMC internals.
func CanonicalKey(m LogicMap) string {
	keys := make([]SigBit, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sortSigBits(keys)
	var b []byte
	for _, k := range keys {
		b = append(b, k.Sig...)
		b = append(b, ':')
		b = appendInt(b, k.Bit)
		b = append(b, '=')
		b = append(b, byte('0'+m[k]))
		b = append(b, ',')
	}
	return string(b)
}

func sortSigBits(s []SigBit) {
	// stdlib import-free insertion sort to keep qmc.go self-contained;
	// inputs are small (typically <20 entries).
	for i := 1; i < len(s); i++ {
		for j := i; j > 0; j-- {
			a, b := s[j-1], s[j]
			less := a.Sig < b.Sig || (a.Sig == b.Sig && a.Bit < b.Bit)
			if less {
				break
			}
			s[j-1], s[j] = b, a
		}
	}
}

func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0; j-- {
			if s[j-1] <= s[j] {
				break
			}
			s[j-1], s[j] = s[j], s[j-1]
		}
	}
}

func appendInt(b []byte, n int) []byte {
	if n == 0 {
		return append(b, '0')
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return append(b, buf[i:]...)
}

// ReduceImplicants returns a minimum-cardinality set of prime implicants
// that covers every minterm. Combines PrimeImplicants with a Petrick-style
// minimum-cover search. The result is the public entry point that other
// packages should use; the underlying primes generator is exported for
// tests and ad-hoc inspection.
func ReduceImplicants(minterms []LogicMap) []LogicMap {
	if len(minterms) == 0 {
		return nil
	}
	primes := PrimeImplicants(minterms)
	if len(primes) <= 1 {
		return primes
	}

	// Build the prime → set-of-covered-minterm-indices table.
	coverage := make([]map[int]bool, len(primes))
	for i, p := range primes {
		set := map[int]bool{}
		for j, m := range minterms {
			if mapCovers(p, m) {
				set[j] = true
			}
		}
		coverage[i] = set
	}

	// 1. Find essential primes (primes that are the only one covering
	//    some minterm).
	essential := map[int]bool{}
	covered := map[int]bool{}
	for j := range minterms {
		var only int
		count := 0
		for i := range primes {
			if coverage[i][j] {
				only = i
				count++
			}
		}
		if count == 1 {
			essential[only] = true
		}
	}
	for i := range essential {
		for j := range coverage[i] {
			covered[j] = true
		}
	}
	// 2. Find a minimum cover of the still-uncovered minterms using a
	//    breadth-first search over subsets of non-essential primes.
	uncovered := []int{}
	for j := range minterms {
		if !covered[j] {
			uncovered = append(uncovered, j)
		}
	}
	chosen := map[int]bool{}
	for i := range essential {
		chosen[i] = true
	}
	if len(uncovered) > 0 {
		var nonEssential []int
		for i := range primes {
			if !essential[i] {
				nonEssential = append(nonEssential, i)
			}
		}
		best := pickMinCover(nonEssential, coverage, uncovered)
		for _, i := range best {
			chosen[i] = true
		}
	}
	// Emit in primes order for determinism.
	var out []LogicMap
	for i, p := range primes {
		if chosen[i] {
			out = append(out, p)
		}
	}
	return out
}

// mapCovers reports whether implicant p covers minterm m. A prime covers
// a minterm iff every fixed bit in the prime equals the corresponding bit
// in the minterm; bits absent from the prime are don't-cares.
func mapCovers(p, m LogicMap) bool {
	for k, v := range p {
		if w, ok := m[k]; !ok || w != v {
			return false
		}
	}
	return true
}

// petrickBruteForceLimit caps the number of useful non-essential primes
// before pickMinCover falls back to returning all of them rather than
// enumerating subsets. The DFS over subsets is O(C(N,k)) which becomes
// prohibitive past ~30 candidates. The SH-2 decoder fits comfortably
// under this limit (largest production case is ~12 non-essential primes
// observed), so the cap exists only as a safety net for future or
// pathological reuse of the logic package.
const petrickBruteForceLimit = 30

// pickMinCover returns the minimum-cardinality subset of candidates that
// covers every minterm index in uncovered. Brute-force breadth-first
// over subset size. Past petrickBruteForceLimit useful candidates, falls
// back to returning all useful primes — a valid cover, just not
// guaranteed minimum.
func pickMinCover(candidates []int, coverage []map[int]bool, uncovered []int) []int {
	// Filter candidates to only those that contribute to uncovered.
	useful := []int{}
	for _, c := range candidates {
		for _, u := range uncovered {
			if coverage[c][u] {
				useful = append(useful, c)
				break
			}
		}
	}
	if len(useful) == 0 {
		return nil
	}
	if len(useful) > petrickBruteForceLimit {
		// Too many candidates to brute-force optimally; return all
		// useful primes. Valid cover, sub-optimal cardinality.
		return useful
	}
	// Try sizes 1..N.
	for size := 1; size <= len(useful); size++ {
		var found []int
		if subsetCovers(useful, size, 0, nil, coverage, uncovered, &found) {
			return found
		}
	}
	return useful // shouldn't reach here if primes generated correctly
}

// subsetCovers DFS-enumerates subsets of `cands` of given size; sets
// *out and returns true if any covers all uncovered minterm indices.
func subsetCovers(cands []int, size, start int, current []int,
	coverage []map[int]bool, uncovered []int, out *[]int) bool {
	if len(current) == size {
		for _, u := range uncovered {
			any := false
			for _, c := range current {
				if coverage[c][u] {
					any = true
					break
				}
			}
			if !any {
				return false
			}
		}
		// Copy current into *out.
		*out = make([]int, len(current))
		copy(*out, current)
		return true
	}
	remaining := size - len(current)
	for i := start; i <= len(cands)-remaining; i++ {
		if subsetCovers(cands, size, i+1, append(current, cands[i]),
			coverage, uncovered, out) {
			return true
		}
	}
	return false
}
