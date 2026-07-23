package measure

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type Marker struct {
	Val uint8
	NS  float64
}

func ParseMarkers(traceText string) []Marker {
	var out []Marker
	markerRe := regexp.MustCompile(`LED: WRITE 0x([0-9A-Fa-f]{1,2}) at ([0-9.]+) ns`)
	for _, line := range strings.Split(traceText, "\n") {
		mm := markerRe.FindStringSubmatch(line)
		if mm == nil {
			continue
		}
		v, _ := strconv.ParseUint(mm[1], 16, 8)
		ns, _ := strconv.ParseFloat(mm[2], 64)
		out = append(out, Marker{Val: uint8(v), NS: ns})
	}
	return out
}

func CyclesBetween(m []Marker, from uint8, to uint8, nsPerCycle float64) (float64, error) {
	i := -1
	for k, mk := range m {
		if mk.Val == from {
			i = k
			break
		}
	}
	if i < 0 {
		return 0, fmt.Errorf("marker 0x%02X not found", from)
	}
	for k := i + 1; k < len(m); k++ {
		if m[k].Val == to {
			return (m[k].NS - m[i].NS) / nsPerCycle, nil
		}
	}
	return 0, fmt.Errorf("marker 0x%02X after 0x%02X not found", to, from)
}
