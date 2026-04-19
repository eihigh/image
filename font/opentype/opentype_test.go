// Copyright 2017 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package opentype

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/sfnt"
	"golang.org/x/image/math/fixed"
)

var (
	regular     font.Face
	regularBold font.Face
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

	boldOpts := defaultFaceOptions()
	boldOpts.Embolden = 64
	regularBold, err = NewFace(font, boldOpts)
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

func TestFaceGlyphEmbolden(t *testing.T) {
	dot := fixed.P(200, 500)
	dr0, _, _, adv0, ok0 := regular.Glyph(dot, 'A')
	dr1, _, _, adv1, ok1 := regularBold.Glyph(dot, 'A')
	if !ok0 || !ok1 {
		t.Fatalf("could not load glyphs: regular=%v bold=%v", ok0, ok1)
	}
	if adv1 != adv0 {
		t.Fatalf("embolden changed advance: got %d, want %d", adv1, adv0)
	}
	if dr1 == dr0 {
		t.Fatalf("emboldened draw rect unchanged: %v", dr1)
	}
}

func TestFaceGlyphEmboldenFreeTypeExpected(t *testing.T) {
	f, err := sfnt.Parse(goregular.TTF)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	face, err := NewFace(f, &FaceOptions{
		Size:     12,
		DPI:      72,
		Hinting:  font.HintingNone,
		Embolden: 64,
	})
	if err != nil {
		t.Fatalf("NewFace: %v", err)
	}
	defer face.Close()

	// RGBA() returns 16-bit channel values (0..65535), so 8-bit 128 maps to 128*257.
	const threshold = uint32(128 * 257)
	// Allow small rasterizer differences while keeping comparison strict.
	const maxMismatchedPixels = 80
	for ch := 'A'; ch <= 'Z'; ch++ {
		got := image.NewAlpha(image.Rect(0, 0, 80, 80))
		d := font.Drawer{
			Dst:  got,
			Src:  image.NewUniform(color.Alpha{A: 255}),
			Face: face,
			Dot:  fixed.P(20, 55),
		}
		d.DrawString(string(ch))

		path := filepath.FromSlash("../testdata/freetype-embolden-" + string(ch) + "-12px.png")
		fp, err := os.Open(path)
		if err != nil {
			t.Fatalf("%c: Open expected image %q: %v", ch, path, err)
		}
		wantImg, err := png.Decode(fp)
		fp.Close()
		if err != nil {
			t.Fatalf("%c: Decode expected image: %v", ch, err)
		}
		if got.Bounds() != wantImg.Bounds() {
			t.Fatalf("%c: image bounds mismatch: got %v, want %v", ch, got.Bounds(), wantImg.Bounds())
		}

		mismatched := 0
		for y := got.Bounds().Min.Y; y < got.Bounds().Max.Y; y++ {
			for x := got.Bounds().Min.X; x < got.Bounds().Max.X; x++ {
				gr, _, _, _ := got.At(x, y).RGBA()
				wr, _, _, _ := wantImg.At(x, y).RGBA()
				if (gr >= threshold) != (wr >= threshold) {
					mismatched++
				}
			}
		}
		if mismatched > maxMismatchedPixels {
			t.Fatalf("%c: embolden mask differs from FreeType expected: mismatched=%d, max=%d", ch, mismatched, maxMismatchedPixels)
		}
	}
}

func TestFaceGlyphEmboldenFreeTypeTextExpected12px(t *testing.T) {
	parsed, err := sfnt.Parse(goregular.TTF)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	regular, err := NewFace(parsed, &FaceOptions{Size: 12, DPI: 72, Hinting: font.HintingNone})
	if err != nil {
		t.Fatalf("NewFace regular: %v", err)
	}
	defer regular.Close()
	bold, err := NewFace(parsed, &FaceOptions{Size: 12, DPI: 72, Hinting: font.HintingNone, Embolden: 64})
	if err != nil {
		t.Fatalf("NewFace bold: %v", err)
	}
	defer bold.Close()

	got := image.NewAlpha(image.Rect(0, 0, 1100, 220))
	lines := []string{
		"Sphinx of black quartz, judge my vow while vectors and rasters align.",
		"Pack my box with five dozen liquor jugs; embolden makes stems visibly thicker.",
		"Quick wafting zephyrs vex bold Jim as regular and embolden are compared.",
		"How razorback-jumping frogs can level six piqued gymnasts! 1234567890",
	}
	lineY := []int{50, 95, 140, 185}
	for i, s := range lines {
		rd := font.Drawer{Dst: got, Src: image.NewUniform(color.Alpha{A: 255}), Face: regular, Dot: fixed.P(30, lineY[i])}
		rd.DrawString(s)
		bd := font.Drawer{Dst: got, Src: image.NewUniform(color.Alpha{A: 255}), Face: bold, Dot: fixed.P(570, lineY[i])}
		bd.DrawString(s)
	}

	fp, err := os.Open(filepath.FromSlash("../testdata/freetype-regular-vs-embolden-text-12px.png"))
	if err != nil {
		t.Fatalf("Open expected image: %v", err)
	}
	wantImg, err := png.Decode(fp)
	fp.Close()
	if err != nil {
		t.Fatalf("Decode expected image: %v", err)
	}
	if got.Bounds() != wantImg.Bounds() {
		t.Fatalf("image bounds mismatch: got %v, want %v", got.Bounds(), wantImg.Bounds())
	}

	const threshold = uint32(128 * 257)
	const maxMismatchedPixels = 13000
	mismatched := 0
	for y := got.Bounds().Min.Y; y < got.Bounds().Max.Y; y++ {
		for x := got.Bounds().Min.X; x < got.Bounds().Max.X; x++ {
			gr, _, _, _ := got.At(x, y).RGBA()
			wr, _, _, _ := wantImg.At(x, y).RGBA()
			if (gr >= threshold) != (wr >= threshold) {
				mismatched++
			}
		}
	}
	if mismatched > maxMismatchedPixels {
		t.Fatalf("regular-vs-embolden text differs from FreeType expected: mismatched=%d, max=%d", mismatched, maxMismatchedPixels)
	}
}

func TestFaceGlyphEmboldenFreeTypeExpectedLarge120px(t *testing.T) {
	parsed, err := sfnt.Parse(goregular.TTF)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	const threshold = uint32(128 * 257)
	testCases := []struct {
		ch          rune
		embolden    fixed.Int26_6
		maxMismatch int
	}{
		{'A', 128, 2000},
		{'M', 256, 3000},
		{'W', 384, 4000},
		{'Q', 512, 5000},
	}
	for _, tc := range testCases {
		face, err := NewFace(parsed, &FaceOptions{
			Size:     120,
			DPI:      72,
			Hinting:  font.HintingNone,
			Embolden: tc.embolden,
		})
		if err != nil {
			t.Fatalf("%c: NewFace: %v", tc.ch, err)
		}
		got := image.NewAlpha(image.Rect(0, 0, 280, 280))
		d := font.Drawer{
			Dst:  got,
			Src:  image.NewUniform(color.Alpha{A: 255}),
			Face: face,
			Dot:  fixed.P(40, 220),
		}
		d.DrawString(string(tc.ch))
		face.Close()

		path := filepath.FromSlash(fmt.Sprintf("../testdata/freetype-embolden-120px-%c-w%d.png", tc.ch, tc.embolden))
		fp, err := os.Open(path)
		if err != nil {
			t.Fatalf("%c: Open expected image %q: %v", tc.ch, path, err)
		}
		wantImg, err := png.Decode(fp)
		fp.Close()
		if err != nil {
			t.Fatalf("%c: Decode expected image: %v", tc.ch, err)
		}
		if got.Bounds() != wantImg.Bounds() {
			t.Fatalf("%c: image bounds mismatch: got %v, want %v", tc.ch, got.Bounds(), wantImg.Bounds())
		}

		mismatched := 0
		for y := got.Bounds().Min.Y; y < got.Bounds().Max.Y; y++ {
			for x := got.Bounds().Min.X; x < got.Bounds().Max.X; x++ {
				gr, _, _, _ := got.At(x, y).RGBA()
				wr, _, _, _ := wantImg.At(x, y).RGBA()
				if (gr >= threshold) != (wr >= threshold) {
					mismatched++
				}
			}
		}
		if mismatched > tc.maxMismatch {
			t.Fatalf("%c: embolden mask differs from large FreeType expected: mismatched=%d, max=%d", tc.ch, mismatched, tc.maxMismatch)
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
