package model

// DecodeEntity holds the emission-ready view of the decode entity declaration.
// The port list is taken verbatim from the "decode" component in Package.Components
// so the entity and the component declaration are always in sync.
type DecodeEntity struct {
	Ports []Port
}

// BuildEntity constructs a DecodeEntity by looking up the "decode" component
// in pkg.Components and reusing its Ports. Returns nil if the component is
// not found (which indicates a bug in newStaticPackage).
func BuildEntity(pkg *Package) *DecodeEntity {
	for _, c := range pkg.Components {
		if c.Name == "decode" {
			return &DecodeEntity{Ports: c.Ports}
		}
	}
	return nil
}
