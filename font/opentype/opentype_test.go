// Copyright 2017 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package opentype

import (
	"image"
	"testing"

	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/sfnt"
	"golang.org/x/image/math/fixed"
)

var (
	regular   font.Face
	emboldened font.Face
	clamped    font.Face
)

func init() {
	font, err := sfnt.Parse(goregular.TTF)
	if err != nil {
		panic(err)
	}

	regular, err = NewFace(font, defaultFaceOptions())
	if err != nil {
		panic(err)
	}
	emboldenOpts := defaultFaceOptions()
	emboldenOpts.Embolden = fixed.I(1)
	emboldened, err = NewFace(font, emboldenOpts)
	if err != nil {
		panic(err)
	}
	clampOpts := defaultFaceOptions()
	clampOpts.Embolden = -fixed.I(1)
	clamped, err = NewFace(font, clampOpts)
	if err != nil {
		panic(err)
	}
}

var runeTests = []struct {
	r       rune
	advance fixed.Int26_6
	dr      image.Rectangle
}{
	{' ', 213, image.Rect(0, 0, 0, 0)},
	{'A', 512, image.Rect(0, -9, 8, 0)},
	{'Á', 512, image.Rect(0, -12, 8, 0)},
	{'Æ', 768, image.Rect(0, -9, 12, 0)},
	{'i', 189, image.Rect(0, -9, 3, 0)},
	{'x', 384, image.Rect(0, -7, 6, 0)},
}

func TestFaceGlyphAdvance(t *testing.T) {
	for _, test := range runeTests {
		got, ok := regular.GlyphAdvance(test.r)
		if !ok {
			t.Errorf("could not get glyph advance width for %q", test.r)
			continue
		}

		if got != test.advance {
			t.Errorf("%q: glyph advance width=%d. want=%d", test.r, got, test.advance)
			continue
		}
	}
}

func TestFaceGlyphBounds(t *testing.T) {
	for _, test := range runeTests {
		bounds, advance, ok := regular.GlyphBounds(test.r)
		if !ok {
			t.Errorf("could not get glyph bounds for %q", test.r)
			continue
		}

		// bounds must fit inside the draw rect.
		testFixedBounds := fixed.R(test.dr.Min.X, test.dr.Min.Y,
			test.dr.Max.X, test.dr.Max.Y)
		if !bounds.In(testFixedBounds) {
			t.Errorf("%q: glyph bounds %v must be inside %v", test.r, bounds, testFixedBounds)
			continue
		}
		if advance != test.advance {
			t.Errorf("%q: glyph advance width=%d. want=%d", test.r, advance, test.advance)
			continue
		}
	}
}

func TestFaceGlyph(t *testing.T) {
	dot := image.Pt(200, 500)
	fixedDot := fixed.P(dot.X, dot.Y)

	for _, test := range runeTests {
		dr, mask, maskp, advance, ok := regular.Glyph(fixedDot, test.r)
		if !ok {
			t.Errorf("could not get glyph for %q", test.r)
			continue
		}
		if got, want := dr, test.dr.Add(dot); got != want {
			t.Errorf("%q: glyph draw rectangle=%d. want=%d", test.r, got, want)
			continue
		}
		if got, want := mask.Bounds(), image.Rect(0, 0, dr.Dx(), dr.Dy()); got != want {
			t.Errorf("%q: glyph mask rectangle=%d. want=%d", test.r, got, want)
			continue
		}
		if maskp != (image.Point{}) {
			t.Errorf("%q: glyph maskp=%d. want=%d", test.r, maskp, image.Point{})
			continue
		}
		if advance != test.advance {
			t.Errorf("%q: glyph advance width=%d. want=%d", test.r, advance, test.advance)
			continue
		}
	}
}

func BenchmarkFaceGlyph(b *testing.B) {
	fixedDot := fixed.P(200, 500)
	r := 'A'

	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _, _, ok := regular.Glyph(fixedDot, r)
		if !ok {
			b.Fatalf("could not get glyph for %q", r)
		}
	}
}

func TestFaceKern(t *testing.T) {
	// FIXME(sbinet) there is no kerning with gofont/goregular
	for _, test := range []struct {
		r1, r2 rune
		want   fixed.Int26_6
	}{
		{'A', 'A', 0},
		{'A', 'V', 0},
		{'V', 'A', 0},
		{'A', 'v', 0},
		{'W', 'a', 0},
		{'W', 'i', 0},
		{'Y', 'i', 0},
		{'f', '(', 0},
		{'f', 'f', 0},
		{'f', 'i', 0},
		{'T', 'a', 0},
		{'T', 'e', 0},
	} {
		got := regular.Kern(test.r1, test.r2)
		if got != test.want {
			t.Errorf("(%q, %q): glyph kerning=%d. want=%d", test.r1, test.r2, got, test.want)
			continue
		}
	}
}

func TestFaceMetrics(t *testing.T) {
	want := font.Metrics{Height: 888, Ascent: 726, Descent: 162, XHeight: 407, CapHeight: 555,
		CaretSlope: image.Point{X: 0, Y: 1}}
	got := regular.Metrics()
	if got != want {
		t.Fatalf("metrics failed. got=%#v. want=%#v", got, want)
	}
}

func TestFaceEmboldenGlyphConsistency(t *testing.T) {
	fixedDot := fixed.P(200, 500)
	dr0, mask0, _, advance0, ok := regular.Glyph(fixedDot, 'A')
	if !ok {
		t.Fatal("regular face: could not get glyph for 'A'")
	}
	dr1, mask1, _, advance1, ok := emboldened.Glyph(fixedDot, 'A')
	if !ok {
		t.Fatal("emboldened face: could not get glyph for 'A'")
	}
	if got, want := dr1.Min, dr0.Min; got != want {
		t.Fatalf("glyph draw min=%v, want=%v", got, want)
	}
	if got, want := dr1.Max.Y, dr0.Max.Y; got != want {
		t.Fatalf("glyph draw maxY=%d, want=%d", got, want)
	}
	if got, want := dr1.Max.X, dr0.Max.X+1; got != want {
		t.Fatalf("glyph draw maxX=%d, want=%d", got, want)
	}
	if got, want := advance1, advance0+fixed.I(1); got != want {
		t.Fatalf("glyph advance=%d, want=%d", got, want)
	}
	if got, want := countNonZeroAlphaPixels(mask1), countNonZeroAlphaPixels(mask0); got <= want {
		t.Fatalf("glyph mask area=%d, want > %d", got, want)
	}
}

func TestFaceEmboldenBoundsAndAdvance(t *testing.T) {
	bounds0, advance0, ok := regular.GlyphBounds('x')
	if !ok {
		t.Fatal("regular face: could not get glyph bounds for 'x'")
	}
	bounds1, advance1, ok := emboldened.GlyphBounds('x')
	if !ok {
		t.Fatal("emboldened face: could not get glyph bounds for 'x'")
	}
	if got, want := bounds1.Min, bounds0.Min; got != want {
		t.Fatalf("glyph bounds min=%v, want=%v", got, want)
	}
	if got, want := bounds1.Max.Y, bounds0.Max.Y; got != want {
		t.Fatalf("glyph bounds maxY=%d, want=%d", got, want)
	}
	if got, want := bounds1.Max.X, bounds0.Max.X+fixed.I(1); got != want {
		t.Fatalf("glyph bounds maxX=%d, want=%d", got, want)
	}
	if got, want := advance1, advance0+fixed.I(1); got != want {
		t.Fatalf("glyph bounds advance=%d, want=%d", got, want)
	}

	a0, ok := regular.GlyphAdvance('x')
	if !ok {
		t.Fatal("regular face: could not get glyph advance for 'x'")
	}
	a1, ok := emboldened.GlyphAdvance('x')
	if !ok {
		t.Fatal("emboldened face: could not get glyph advance for 'x'")
	}
	if got, want := a1, a0+fixed.I(1); got != want {
		t.Fatalf("glyph advance=%d, want=%d", got, want)
	}
}

func TestFaceEmboldenNegativeClampedToZero(t *testing.T) {
	got, ok := clamped.GlyphAdvance('A')
	if !ok {
		t.Fatal("clamped face: could not get glyph advance for 'A'")
	}
	want, ok := regular.GlyphAdvance('A')
	if !ok {
		t.Fatal("regular face: could not get glyph advance for 'A'")
	}
	if got != want {
		t.Fatalf("negative embolden should clamp to zero: got=%d want=%d", got, want)
	}
}

func countNonZeroAlphaPixels(mask image.Image) int {
	a, ok := mask.(*image.Alpha)
	if !ok {
		return 0
	}
	n := 0
	for _, p := range a.Pix {
		if p != 0 {
			n++
		}
	}
	return n
}
