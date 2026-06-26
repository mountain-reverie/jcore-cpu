package insns

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
)

type Row struct {
	keys []string
	vals map[string]any
}

func (r *Row) ensure() {
	if r.vals == nil {
		r.vals = map[string]any{}
	}
}
func (r *Row) Get(key string) (any, bool) { v, ok := r.vals[key]; return v, ok }
func (r *Row) Set(key string, v any) {
	r.ensure()
	if _, ok := r.vals[key]; !ok {
		r.keys = append(r.keys, key)
	}
	r.vals[key] = v
}

type Doc struct {
	Rows []*Row
}

func Load(path string) (*Doc, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	doc := &Doc{}
	if err := decodeTop(dec, doc); err != nil {
		return nil, err
	}
	return doc, nil
}

// decodeTop reads the top-level object and populates doc.Rows from the
// "instructions" array. Other top-level keys are ignored (none exist today).
func decodeTop(dec *json.Decoder, doc *Doc) error {
	// Consume opening '{'
	tok, err := dec.Token()
	if err != nil {
		return fmt.Errorf("expected '{': %w", err)
	}
	if d, ok := tok.(json.Delim); !ok || d != '{' {
		return fmt.Errorf("expected '{', got %v", tok)
	}

	for dec.More() {
		// Read key
		keyTok, err := dec.Token()
		if err != nil {
			return err
		}
		key, ok := keyTok.(string)
		if !ok {
			return fmt.Errorf("expected string key, got %v", keyTok)
		}

		if key == "instructions" {
			// Consume '['
			arrTok, err := dec.Token()
			if err != nil {
				return err
			}
			if d, ok := arrTok.(json.Delim); !ok || d != '[' {
				return fmt.Errorf("expected '[', got %v", arrTok)
			}
			for dec.More() {
				row, err := decodeObject(dec)
				if err != nil {
					return err
				}
				doc.Rows = append(doc.Rows, row)
			}
			// Consume ']'
			if _, err := dec.Token(); err != nil {
				return err
			}
		} else {
			// Skip unknown top-level values
			var discard any
			if err := dec.Decode(&discard); err != nil {
				return err
			}
		}
	}

	// Consume closing '}'
	_, err = dec.Token()
	return err
}

// decodeObject reads a JSON object from dec and returns an order-preserving Row.
func decodeObject(dec *json.Decoder) (*Row, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	if d, ok := tok.(json.Delim); !ok || d != '{' {
		return nil, fmt.Errorf("expected '{', got %v", tok)
	}

	row := &Row{}
	for dec.More() {
		keyTok, err := dec.Token()
		if err != nil {
			return nil, err
		}
		key, ok := keyTok.(string)
		if !ok {
			return nil, fmt.Errorf("expected string key, got %v", keyTok)
		}

		var val any
		if err := dec.Decode(&val); err != nil {
			return nil, err
		}
		row.Set(key, val)
	}

	// Consume '}'
	if _, err := dec.Token(); err != nil {
		return nil, err
	}
	return row, nil
}

func (d *Doc) Bytes() ([]byte, error) {
	var b bytes.Buffer
	b.WriteString("{\n  \"instructions\": [\n")
	for i, r := range d.Rows {
		if err := writeRow(&b, r, "    "); err != nil {
			return nil, err
		}
		if i < len(d.Rows)-1 {
			b.WriteString(",\n")
		} else {
			b.WriteString("\n")
		}
	}
	b.WriteString("  ]\n}\n")
	return b.Bytes(), nil
}

func writeRow(b *bytes.Buffer, r *Row, indent string) error {
	b.WriteString(indent + "{\n")
	for i, k := range r.keys {
		vb, err := json.Marshal(r.vals[k])
		if err != nil {
			return fmt.Errorf("marshal %s: %w", k, err)
		}
		kb, _ := json.Marshal(k)
		b.WriteString(indent + "  " + string(kb) + ": " + string(vb))
		if i < len(r.keys)-1 {
			b.WriteString(",\n")
		} else {
			b.WriteString("\n")
		}
	}
	b.WriteString(indent + "}")
	return nil
}
