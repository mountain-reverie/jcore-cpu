package freespace

import (
	"math/bits"
	"sort"
)

// Rank orders candidates best-first, in place:
//
//  1. Virgin encodings — claimed by no variant recorded in insns.json, not
//     merely free of the --avoid list. These are the ones with no future
//     compatibility cost.
//  2. Proximity to the requested family, by Hamming distance over the
//     candidate's fixed bits. Encodings near their relatives keep the
//     QMC-reduced direct decoder small.
//  3. Numeric order, so output is deterministic.
func Rank(cands []Candidate, family string, claims []Claim) {
	dist := make(map[string]int, len(cands))
	for _, c := range cands {
		d := 1 << 16 // sorts after any real distance
		if near, ok := Nearest(c, family, claims); ok {
			d = bits.OnesCount16(c.Match ^ near.Match)
		}
		dist[c.Code] = d
	}
	sort.SliceStable(cands, func(i, j int) bool {
		a, b := cands[i], cands[j]
		if a.Virgin != b.Virgin {
			return a.Virgin
		}
		if da, db := dist[a.Code], dist[b.Code]; da != db {
			return da < db
		}
		return a.Match < b.Match
	})
}

// Nearest returns the claim in the named family closest to the candidate by
// Hamming distance, breaking ties on the lower match value. It reports false
// when no family was requested or the family has no members.
func Nearest(c Candidate, family string, claims []Claim) (Claim, bool) {
	if family == "" {
		return Claim{}, false
	}
	var best Claim
	bestDist := -1
	for _, cl := range claims {
		if cl.Group != family {
			continue
		}
		d := bits.OnesCount16(c.Match ^ cl.Match)
		if bestDist == -1 || d < bestDist || (d == bestDist && cl.Match < best.Match) {
			best, bestDist = cl, d
		}
	}
	return best, bestDist != -1
}
