package logic

import (
	"fmt"
	"sort"
	"strings"
	"testing"
)

// TestPrimeImplicantsSingleton — single minterm in is itself prime.
func TestPrimeImplicantsSingleton(t *testing.T) {
	m := LogicMap{SigBit{"i", 0}: 1, SigBit{"i", 1}: 0}
	got := PrimeImplicants([]LogicMap{m})
	if len(got) != 1 {
		t.Fatalf("want 1 prime, got %d: %v", len(got), got)
	}
	if !mapEqual(got[0], m) {
		t.Errorf("prime not equal to input: got %v want %v", got[0], m)
	}
}

// TestPrimeImplicantsMerge — two minterms differing in one bit merge into one.
func TestPrimeImplicantsMerge(t *testing.T) {
	a := LogicMap{SigBit{"i", 0}: 0, SigBit{"i", 1}: 1}
	b := LogicMap{SigBit{"i", 0}: 1, SigBit{"i", 1}: 1}
	got := PrimeImplicants([]LogicMap{a, b})
	if len(got) != 1 {
		t.Fatalf("want 1 prime (merged), got %d: %v", len(got), got)
	}
	// Merged implicant has only bit 1 = 1.
	want := LogicMap{SigBit{"i", 1}: 1}
	if !mapEqual(got[0], want) {
		t.Errorf("merged prime: got %v want %v", got[0], want)
	}
}

// TestPrimeImplicantsThreeWayMerge — four minterms collapse to one don't-care implicant.
func TestPrimeImplicantsThreeWayMerge(t *testing.T) {
	// bit0,bit1 vary; bit2 fixed at 1
	mts := []LogicMap{
		{SigBit{"i", 0}: 0, SigBit{"i", 1}: 0, SigBit{"i", 2}: 1},
		{SigBit{"i", 0}: 1, SigBit{"i", 1}: 0, SigBit{"i", 2}: 1},
		{SigBit{"i", 0}: 0, SigBit{"i", 1}: 1, SigBit{"i", 2}: 1},
		{SigBit{"i", 0}: 1, SigBit{"i", 1}: 1, SigBit{"i", 2}: 1},
	}
	got := PrimeImplicants(mts)
	if len(got) != 1 {
		t.Fatalf("want 1 prime, got %d: %v", len(got), got)
	}
	want := LogicMap{SigBit{"i", 2}: 1}
	if !mapEqual(got[0], want) {
		t.Errorf("got %v want %v", got[0], want)
	}
}

// TestPrimeImplicantsTwoNonMergeable — minterms differing in two bits stay separate.
func TestPrimeImplicantsTwoNonMergeable(t *testing.T) {
	a := LogicMap{SigBit{"i", 0}: 0, SigBit{"i", 1}: 0}
	b := LogicMap{SigBit{"i", 0}: 1, SigBit{"i", 1}: 1}
	got := PrimeImplicants([]LogicMap{a, b})
	if len(got) != 2 {
		t.Fatalf("want 2 primes, got %d", len(got))
	}
}

func mapEqual(a, b LogicMap) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if w, ok := b[k]; !ok || w != v {
			return false
		}
	}
	return true
}

// sortedLogicMapStr stringifies a LogicMap deterministically for test diffs.
func sortedLogicMapStr(m LogicMap) string {
	var keys []SigBit
	for k := range m {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].Sig != keys[j].Sig {
			return keys[i].Sig < keys[j].Sig
		}
		return keys[i].Bit < keys[j].Bit
	})
	var parts []string
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s%d=%d", k.Sig, k.Bit, m[k]))
	}
	return "{" + strings.Join(parts, ",") + "}"
}

// TestReduceImplicantsCoversAllMinterms — sanity: every input minterm is
// covered by at least one output implicant.
func TestReduceImplicantsCoversAllMinterms(t *testing.T) {
	mts := []LogicMap{
		{SigBit{"i", 0}: 0, SigBit{"i", 1}: 0, SigBit{"i", 2}: 0},
		{SigBit{"i", 0}: 0, SigBit{"i", 1}: 0, SigBit{"i", 2}: 1},
		{SigBit{"i", 0}: 1, SigBit{"i", 1}: 1, SigBit{"i", 2}: 0},
	}
	primes := ReduceImplicants(mts)
	if len(primes) == 0 {
		t.Fatalf("ReduceImplicants returned empty for non-empty input")
	}
	for i, m := range mts {
		covered := false
		for _, p := range primes {
			if mapCovers(p, m) {
				covered = true
				break
			}
		}
		if !covered {
			t.Errorf("minterm %d %v not covered by any prime: %v",
				i, sortedLogicMapStr(m), primes)
		}
	}
}

// TestReduceImplicantsMinimizesCount — fully-mergeable group becomes 1.
func TestReduceImplicantsMinimizesCount(t *testing.T) {
	mts := []LogicMap{
		{SigBit{"i", 0}: 0, SigBit{"i", 1}: 0},
		{SigBit{"i", 0}: 0, SigBit{"i", 1}: 1},
		{SigBit{"i", 0}: 1, SigBit{"i", 1}: 0},
		{SigBit{"i", 0}: 1, SigBit{"i", 1}: 1},
	}
	primes := ReduceImplicants(mts)
	if len(primes) != 1 {
		t.Errorf("4-minterm full cover should reduce to 1, got %d: %v",
			len(primes), primes)
	}
	if len(primes[0]) != 0 {
		t.Errorf("merged implicant should be all-don't-care (empty map), got %v",
			primes[0])
	}
}

// ---------------------------------------------------------------------------
// pickMinCover / subsetCovers direct unit tests
// ---------------------------------------------------------------------------

// buildCoverage constructs the coverage table needed by pickMinCover.
// primes[i] covers the minterm indices listed in coveredBy[i].
func buildCoverage(numPrimes int, coveredBy [][]int) []map[int]bool {
	cov := make([]map[int]bool, numPrimes)
	for i := range cov {
		cov[i] = map[int]bool{}
	}
	for i, minttermIdxs := range coveredBy {
		for _, mi := range minttermIdxs {
			cov[i][mi] = true
		}
	}
	return cov
}

// allCovered checks that every minterm index in uncovered is covered by at
// least one prime in the returned subset, using the given coverage table.
func allCovered(subset []int, coverage []map[int]bool, uncovered []int) bool {
	for _, u := range uncovered {
		found := false
		for _, c := range subset {
			if coverage[c][u] {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}

// TestPickMinCoverSinglePrime — two minterms both covered by one prime; the
// function must return exactly that one prime index.
func TestPickMinCoverSinglePrime(t *testing.T) {
	// Prime 0 covers minterms 0 and 1; prime 1 covers only minterm 0.
	coverage := buildCoverage(2, [][]int{
		{0, 1}, // prime 0
		{0},    // prime 1
	})
	uncovered := []int{0, 1}
	candidates := []int{0, 1}

	got := pickMinCover(candidates, coverage, uncovered)
	if len(got) != 1 {
		t.Fatalf("want 1 prime in cover, got %d: %v", len(got), got)
	}
	// The only prime that covers both minterms is prime 0.
	if got[0] != 0 {
		t.Errorf("expected prime index 0, got %d", got[0])
	}
}

// TestPickMinCoverOptimalSubset — 5 minterms, 4 useful primes, but 2 are
// sufficient. Verifies the algorithm picks the minimum-cardinality cover.
//
// Layout:
//
//	prime 0 → minterms {0,1}
//	prime 1 → minterms {2,3}
//	prime 2 → minterms {0,4}   (overlapping but redundant with prime 0+1+3)
//	prime 3 → minterms {1,2}   (overlapping but redundant with prime 0+1)
//
// Minimum cover: primes {0,1} cover all 5? No — they cover {0,1,2,3} but
// not minterm 4. So minimum is {0,1,2} or {2,1} etc. Let's redesign:
//
//	prime 0 → minterms {0,1,4}
//	prime 1 → minterms {2,3}
//	prime 2 → minterms {0,2}
//	prime 3 → minterms {1,3,4}
//
// Optimal 2-prime cover: {0,1} covers {0,1,2,3,4}. Confirm primes 2 and 3
// alone don't work for size-2 ({2,3} misses minterm 4 via prime 2+3 → wait).
// Actually {0,1}: prime0={0,1,4}, prime1={2,3} → covers all 5 minterms. Yes.
func TestPickMinCoverOptimalSubset(t *testing.T) {
	coverage := buildCoverage(4, [][]int{
		{0, 1, 4}, // prime 0
		{2, 3},    // prime 1
		{0, 2},    // prime 2 — redundant given primes 0+1
		{1, 3, 4}, // prime 3 — redundant given primes 0+1
	})
	uncovered := []int{0, 1, 2, 3, 4}
	candidates := []int{0, 1, 2, 3}

	got := pickMinCover(candidates, coverage, uncovered)
	if len(got) > 2 {
		t.Errorf("optimal cover needs at most 2 primes, got %d: %v", len(got), got)
	}
	if !allCovered(got, coverage, uncovered) {
		t.Errorf("returned cover %v does not cover all minterms", got)
	}
}

// TestPickMinCoverBothEssential — both primes are essential (each is the
// only one covering some minterm), so the cover is unique. Repeated calls
// must be stable: no randomness from map iteration or goroutine scheduling.
//
// Note: this is a stability/regression guard, not a true tie-breaking test —
// there is no tie to break because only one valid cover exists. A genuine
// tie-breaking test would require multiple equally-minimal covers, which
// the current SH-2 spec does not exercise in a way that's easy to isolate.
func TestPickMinCoverBothEssential(t *testing.T) {
	// prime 0 covers minterms {0,2}, prime 1 covers minterms {1,2}.
	// Both are needed (prime 0 is the only one for minterm 0; prime 1 is
	// the only one for minterm 1), so the cover is unique.
	coverage := buildCoverage(2, [][]int{
		{0, 2}, // prime 0
		{1, 2}, // prime 1
	})
	uncovered := []int{0, 1, 2}
	candidates := []int{0, 1}

	firstLen := -1
	for run := range 100 {
		got := pickMinCover(candidates, coverage, uncovered)
		if firstLen == -1 {
			firstLen = len(got)
		}
		if len(got) != firstLen {
			t.Fatalf("run %d: non-deterministic result: first length %d, this run %d",
				run, firstLen, len(got))
		}
		if !allCovered(got, coverage, uncovered) {
			t.Fatalf("run %d: cover %v does not cover all minterms", run, got)
		}
	}
	if firstLen != 2 {
		t.Errorf("expected cover of length 2, got %d", firstLen)
	}
}

// TestPickMinCoverBruteForceLimit — when len(useful) > petrickBruteForceLimit
// the function must skip the DFS and return the full useful set directly.
// This is documented as: "valid cover, sub-optimal cardinality".
//
// Limitation: because the 31 base primes are disjoint (each is the only
// prime covering its unique minterm), every prime is essential and would
// be returned by either the brute-force DFS or the fallback. The redundant
// 32nd prime is what distinguishes the two paths: the DFS would drop it,
// the fallback returns it. The test asserts the fallback contract:
//
//  1. The returned set is a valid cover (all minterms covered).
//  2. Its length equals len(useful), i.e., no minimization was performed.
//
// This test is primarily a panic-safety and contract-freezing test — a
// future change that removed the fallback path entirely would still pass
// the "valid cover" check, so the length equality is the load-bearing
// assertion here.
func TestPickMinCoverBruteForceLimit(t *testing.T) {
	const numPrimes = 32 // 32 > petrickBruteForceLimit (30)
	// Each of the first 31 primes covers exactly one unique minterm.
	// Prime 31 is a duplicate of prime 0 (covers minterm 0 again).
	coveredBy := make([][]int, numPrimes)
	for i := range 31 {
		coveredBy[i] = []int{i}
	}
	coveredBy[31] = []int{0} // redundant: also covers minterm 0

	coverage := buildCoverage(numPrimes, coveredBy)

	uncovered := make([]int, 31)
	for i := range uncovered {
		uncovered[i] = i
	}
	candidates := make([]int, numPrimes)
	for i := range candidates {
		candidates[i] = i
	}

	got := pickMinCover(candidates, coverage, uncovered)

	// Contract 1: must be a valid cover despite being non-minimal.
	if !allCovered(got, coverage, uncovered) {
		t.Errorf("fallback cover %v does not cover all %d minterms", got, len(uncovered))
	}

	// Contract 2: fallback returns the full useful set without minimization.
	// All 32 primes are useful (each covers at least one uncovered minterm),
	// so the returned slice must have length 32.
	if len(got) != numPrimes {
		t.Errorf("fallback path: want len(useful)=%d returned, got %d; "+
			"the fallback contract is to return all useful primes unfiltered",
			numPrimes, len(got))
	}
}
