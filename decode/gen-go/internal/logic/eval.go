package logic

import "fmt"

// SigValue resolves one bit of a named bit-field for EvalBoolExpr.
// Given a sig name (e.g. "code", "p") and a bit index, it returns the
// 0/1 value of that bit. Implementations typically close over a uint16
// opcode or similar.
type SigValue func(sig string, bit int) int

// EvalBoolExpr evaluates a VHDL-text boolean expression like
//
//	"(code(3) = '0' or code(2) = '1' and p(0) = '0')"
//
// against a caller-supplied resolver for each named bit-field. Grammar
// (subset of VHDL boolean expressions):
//
//	expr   := or-expr
//	or     := and ('or' and)*
//	and    := unary ('and' unary)*
//	unary  := 'not' unary | '(' expr ')' | bit-literal | comparison
//	bit-literal := "'0'" | "'1'"
//	comparison := IDENT '(' INT ')' '=' "'" BIT "'"
//
// Whitespace is permitted between tokens. Operator precedence: AND
// binds tighter than OR (standard VHDL). The grammar matches the
// expressions emitted by model.BuildBody and is reused by the
// predecode functional-evaluation test.
//
// Returns an error if the expression is malformed (unbalanced parens,
// unknown sig, etc.).
func EvalBoolExpr(expr string, resolve SigValue) (bool, error) {
	p := exprParser{src: expr, resolve: resolve}
	v, err := p.parseOr()
	if err != nil {
		return false, err
	}
	p.skipSpaces()
	if p.pos != len(p.src) {
		return false, fmt.Errorf("trailing input at %d: %q", p.pos, p.src[p.pos:])
	}
	return v, nil
}

type exprParser struct {
	src     string
	pos     int
	resolve SigValue
}

func (p *exprParser) parseOr() (bool, error) {
	v, err := p.parseAnd()
	if err != nil {
		return false, err
	}
	for {
		p.skipSpaces()
		if !p.consumeWord("or") {
			break
		}
		w, err := p.parseAnd()
		if err != nil {
			return false, err
		}
		v = v || w
	}
	return v, nil
}

func (p *exprParser) parseAnd() (bool, error) {
	v, err := p.parseUnary()
	if err != nil {
		return false, err
	}
	for {
		p.skipSpaces()
		if !p.consumeWord("and") {
			break
		}
		w, err := p.parseUnary()
		if err != nil {
			return false, err
		}
		v = v && w
	}
	return v, nil
}

func (p *exprParser) parseUnary() (bool, error) {
	p.skipSpaces()
	if p.consumeWord("not") {
		v, err := p.parseUnary()
		return !v, err
	}
	if p.peek() == '(' {
		p.pos++
		v, err := p.parseOr()
		if err != nil {
			return false, err
		}
		p.skipSpaces()
		if p.peek() != ')' {
			return false, fmt.Errorf("expected ) at %d", p.pos)
		}
		p.pos++
		return v, nil
	}
	// Bare '0' or '1' literals.
	if p.peek() == '\'' {
		p.pos++
		if p.pos >= len(p.src) {
			return false, fmt.Errorf("unexpected end after '")
		}
		bit := p.src[p.pos]
		p.pos++
		if p.peek() != '\'' {
			return false, fmt.Errorf("expected closing ' at %d", p.pos)
		}
		p.pos++
		return bit == '1', nil
	}
	// sig(N) — bit reference. The grammar accepts:
	//   "sig(N)"            — bare bit, true iff bit=1 (std_logic form)
	//   "sig(N) = 'X'"      — legacy comparison (still accepted)
	sig := p.consumeIdent()
	if sig == "" {
		return false, fmt.Errorf("unexpected %q at %d", p.remaining(), p.pos)
	}
	p.skipSpaces()
	if p.peek() != '(' {
		return false, fmt.Errorf("expected ( after %q at %d", sig, p.pos)
	}
	p.pos++
	num := 0
	for p.pos < len(p.src) && p.src[p.pos] >= '0' && p.src[p.pos] <= '9' {
		num = num*10 + int(p.src[p.pos]-'0')
		p.pos++
	}
	if p.peek() != ')' {
		return false, fmt.Errorf("expected ) at %d", p.pos)
	}
	p.pos++
	p.skipSpaces()
	bitVal := p.resolve(sig, num)
	if p.peek() == '=' {
		p.pos++
		p.skipSpaces()
		if p.peek() != '\'' {
			return false, fmt.Errorf("expected ' at %d", p.pos)
		}
		p.pos++
		want := p.src[p.pos]
		p.pos++
		if p.peek() != '\'' {
			return false, fmt.Errorf("expected closing ' at %d", p.pos)
		}
		p.pos++
		return byte('0'+bitVal) == want, nil
	}
	return bitVal == 1, nil
}

func (p *exprParser) skipSpaces() {
	for p.pos < len(p.src) && p.src[p.pos] == ' ' {
		p.pos++
	}
}

func (p *exprParser) peek() byte {
	if p.pos >= len(p.src) {
		return 0
	}
	return p.src[p.pos]
}

func (p *exprParser) remaining() string {
	if p.pos >= len(p.src) {
		return ""
	}
	return p.src[p.pos:]
}

// consumeIdent reads a maximal run of [A-Za-z_] characters starting at
// the current position. Returns the identifier (and advances pos) or ""
// (and leaves pos unchanged) if no identifier starts here. The set of
// reserved words ("or", "and", "not") is the caller's concern; this
// helper only does lexical recognition.
func (p *exprParser) consumeIdent() string {
	start := p.pos
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
			p.pos++
		} else {
			break
		}
	}
	return p.src[start:p.pos]
}

func (p *exprParser) consumeWord(w string) bool {
	end := p.pos + len(w)
	if end > len(p.src) {
		return false
	}
	if p.src[p.pos:end] != w {
		return false
	}
	if end < len(p.src) {
		c := p.src[end]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
			return false
		}
	}
	p.pos = end
	return true
}
