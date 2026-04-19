#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$SCRIPT_DIR"
DEMO_PATH="$REPO_ROOT/testdata/font-embolden-demo.png"
MIXED_DEMO_PATH="$REPO_ROOT/testdata/font-embolden-mixed-demo.png"
FREETYPE_TEXT_EXPECTED_PATH="$OUT_DIR/freetype-regular-vs-embolden-text-12px.png"
FREETYPE_TEXT_LARGE_EXPECTED_PATH="$OUT_DIR/freetype-regular-vs-embolden-text-24px.png"

if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists freetype2; then
  echo "error: freetype2 development files are required (pkg-config freetype2)" >&2
  exit 1
fi
if ! command -v cc >/dev/null 2>&1; then
  echo "error: C compiler (cc) is required" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/write_goregular.go" <<'EOGO'
package main

import (
	"os"

"golang.org/x/image/font/gofont/goregular"
)

func main() {
	if len(os.Args) != 2 {
		panic("usage: write_goregular <ttf-path>")
	}
	if err := os.WriteFile(os.Args[1], goregular.TTF, 0o644); err != nil {
		panic(err)
	}
}
EOGO
( cd "$REPO_ROOT" && go run "$TMP_DIR/write_goregular.go" "$TMP_DIR/goregular.ttf" )

cat >"$TMP_DIR/freetype_embolden_az.c" <<'EOC'
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s <font.ttf> <outdir> <dotY>\n", argv[0]);
    return 2;
  }

  const char *font_path = argv[1];
  const char *outdir = argv[2];
  int baseline = atoi(argv[3]);

  FT_Library lib;
  FT_Face face;
  if (FT_Init_FreeType(&lib)) return 1;
  if (FT_New_Face(lib, font_path, 0, &face)) return 1;
  FT_Set_Pixel_Sizes(face, 0, 12);

  for (int ch = 'A'; ch <= 'Z'; ch++) {
    const int W = 80;
    const int H = 80;
    unsigned char *img = (unsigned char *)calloc(W * H, 1);
    if (!img) return 1;

    if (!FT_Load_Char(face, ch, FT_LOAD_NO_HINTING)) {
      FT_Outline_EmboldenXY(&face->glyph->outline, 64, 64);
      if (!FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL)) {
        FT_GlyphSlot g = face->glyph;
        int x0 = 20 + g->bitmap_left;
        int y0 = baseline - g->bitmap_top;
        for (int y = 0; y < g->bitmap.rows; y++) {
          int yy = y0 + y;
          if (yy < 0 || yy >= H) continue;
          for (int x = 0; x < g->bitmap.width; x++) {
            int xx = x0 + x;
            if (xx < 0 || xx >= W) continue;
            unsigned char v = g->bitmap.buffer[y * g->bitmap.pitch + x];
            unsigned char *dst = &img[yy * W + xx];
            if (v > *dst) *dst = v;
          }
        }
      }
    }

    char outpath[1024];
    snprintf(outpath, sizeof(outpath), "%s/freetype-embolden-%c-12px.pgm", outdir, ch);
    FILE *fp = fopen(outpath, "wb");
    if (!fp) return 1;
    fprintf(fp, "P5\n%d %d\n255\n", W, H);
    fwrite(img, 1, W * H, fp);
    fclose(fp);
    free(img);
  }

  {
    const int W = 1100;
    const int H = 220;
    const int left_x = 30;
    const int right_x = 570;
    const int line_y[] = {50, 95, 140, 185};
    const char *lines[] = {
      "Sphinx of black quartz, judge my vow while vectors and rasters align.",
      "Pack my box with five dozen liquor jugs; embolden makes stems visibly thicker.",
      "Quick wafting zephyrs vex bold Jim as regular and embolden are compared.",
      "How razorback-jumping frogs can level six piqued gymnasts! 1234567890",
    };
    const int n_lines = (int)(sizeof(lines) / sizeof(lines[0]));
    unsigned char *img = (unsigned char *)calloc(W * H, 1);
    if (!img) return 1;

    for (int i = 0; i < n_lines; i++) {
      const char *s = lines[i];

      {
        int pen_x = left_x;
        int baseline = line_y[i];
        for (const char *p = s; *p; p++) {
          unsigned char ch = (unsigned char)*p;
          if (FT_Load_Char(face, ch, FT_LOAD_NO_HINTING)) continue;
          if (FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL)) continue;
          FT_GlyphSlot g = face->glyph;
          int x0 = pen_x + g->bitmap_left;
          int y0 = baseline - g->bitmap_top;
          for (int y = 0; y < g->bitmap.rows; y++) {
            int yy = y0 + y;
            if (yy < 0 || yy >= H) continue;
            for (int x = 0; x < g->bitmap.width; x++) {
              int xx = x0 + x;
              if (xx < 0 || xx >= W) continue;
              unsigned char v = g->bitmap.buffer[y * g->bitmap.pitch + x];
              unsigned char *dst = &img[yy * W + xx];
              if (v > *dst) *dst = v;
            }
          }
          pen_x += g->advance.x >> 6;
        }
      }

      {
        int pen_x = right_x;
        int baseline = line_y[i];
        for (const char *p = s; *p; p++) {
          unsigned char ch = (unsigned char)*p;
          if (FT_Load_Char(face, ch, FT_LOAD_NO_HINTING)) continue;
          FT_Outline_EmboldenXY(&face->glyph->outline, 64, 64);
          if (FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL)) continue;
          FT_GlyphSlot g = face->glyph;
          int x0 = pen_x + g->bitmap_left;
          int y0 = baseline - g->bitmap_top;
          for (int y = 0; y < g->bitmap.rows; y++) {
            int yy = y0 + y;
            if (yy < 0 || yy >= H) continue;
            for (int x = 0; x < g->bitmap.width; x++) {
              int xx = x0 + x;
              if (xx < 0 || xx >= W) continue;
              unsigned char v = g->bitmap.buffer[y * g->bitmap.pitch + x];
              unsigned char *dst = &img[yy * W + xx];
              if (v > *dst) *dst = v;
            }
          }
          pen_x += g->advance.x >> 6;
        }
      }
    }

    {
      char outpath[1024];
      snprintf(outpath, sizeof(outpath), "%s/freetype-regular-vs-embolden-text-12px.pgm", outdir);
      FILE *fp = fopen(outpath, "wb");
      if (!fp) return 1;
      fprintf(fp, "P5\n%d %d\n255\n", W, H);
      fwrite(img, 1, W * H, fp);
      fclose(fp);
    }
    free(img);
  }

  FT_Set_Pixel_Sizes(face, 0, 24);
  {
    const int W = 2300;
    const int H = 440;
    const int left_x = 60;
    const int right_x = 1180;
    const int line_y[] = {100, 190, 280, 370};
    const char *lines[] = {
      "Sphinx of black quartz, judge my vow while vectors and rasters align.",
      "Pack my box with five dozen liquor jugs; embolden makes stems visibly thicker.",
      "Quick wafting zephyrs vex bold Jim as regular and embolden are compared.",
      "How razorback-jumping frogs can level six piqued gymnasts! 1234567890",
    };
    const int n_lines = (int)(sizeof(lines) / sizeof(lines[0]));
    unsigned char *img = (unsigned char *)calloc(W * H, 1);
    if (!img) return 1;

    for (int i = 0; i < n_lines; i++) {
      const char *s = lines[i];

      {
        int pen_x = left_x;
        int baseline = line_y[i];
        for (const char *p = s; *p; p++) {
          unsigned char ch = (unsigned char)*p;
          if (FT_Load_Char(face, ch, FT_LOAD_NO_HINTING)) continue;
          if (FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL)) continue;
          FT_GlyphSlot g = face->glyph;
          int x0 = pen_x + g->bitmap_left;
          int y0 = baseline - g->bitmap_top;
          for (int y = 0; y < g->bitmap.rows; y++) {
            int yy = y0 + y;
            if (yy < 0 || yy >= H) continue;
            for (int x = 0; x < g->bitmap.width; x++) {
              int xx = x0 + x;
              if (xx < 0 || xx >= W) continue;
              unsigned char v = g->bitmap.buffer[y * g->bitmap.pitch + x];
              unsigned char *dst = &img[yy * W + xx];
              if (v > *dst) *dst = v;
            }
          }
          pen_x += g->advance.x >> 6;
        }
      }

      {
        int pen_x = right_x;
        int baseline = line_y[i];
        for (const char *p = s; *p; p++) {
          unsigned char ch = (unsigned char)*p;
          if (FT_Load_Char(face, ch, FT_LOAD_NO_HINTING)) continue;
          FT_Outline_EmboldenXY(&face->glyph->outline, 64, 64);
          if (FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL)) continue;
          FT_GlyphSlot g = face->glyph;
          int x0 = pen_x + g->bitmap_left;
          int y0 = baseline - g->bitmap_top;
          for (int y = 0; y < g->bitmap.rows; y++) {
            int yy = y0 + y;
            if (yy < 0 || yy >= H) continue;
            for (int x = 0; x < g->bitmap.width; x++) {
              int xx = x0 + x;
              if (xx < 0 || xx >= W) continue;
              unsigned char v = g->bitmap.buffer[y * g->bitmap.pitch + x];
              unsigned char *dst = &img[yy * W + xx];
              if (v > *dst) *dst = v;
            }
          }
          pen_x += g->advance.x >> 6;
        }
      }
    }

    {
      char outpath[1024];
      snprintf(outpath, sizeof(outpath), "%s/freetype-regular-vs-embolden-text-24px.pgm", outdir);
      FILE *fp = fopen(outpath, "wb");
      if (!fp) return 1;
      fprintf(fp, "P5\n%d %d\n255\n", W, H);
      fwrite(img, 1, W * H, fp);
      fclose(fp);
    }
    free(img);
  }

  FT_Done_Face(face);
  FT_Done_FreeType(lib);
  return 0;
}
EOC

cc "$TMP_DIR/freetype_embolden_az.c" $(pkg-config --cflags --libs freetype2) -o "$TMP_DIR/freetype_embolden_az"
"$TMP_DIR/freetype_embolden_az" "$TMP_DIR/goregular.ttf" "$TMP_DIR" 55

cat >"$TMP_DIR/convert_and_generate_demo.go" <<'EOGO'
package main

import (
"bufio"
"bytes"
"fmt"
"image"
"image/color"
"image/draw"
"image/png"
"io"
"os"
"path/filepath"

"golang.org/x/image/font"
"golang.org/x/image/font/basicfont"
"golang.org/x/image/font/gofont/goregular"
"golang.org/x/image/font/opentype"
"golang.org/x/image/font/sfnt"
"golang.org/x/image/math/fixed"
)

func decodePGM(path string) (*image.Gray, error) {
b, err := os.ReadFile(path)
if err != nil {
return nil, err
}
r := bufio.NewReader(bytes.NewReader(b))
var magic string
if _, err := fmt.Fscanln(r, &magic); err != nil {
return nil, err
}
if magic != "P5" {
return nil, fmt.Errorf("unexpected magic %q", magic)
}
var w, h, max int
if _, err := fmt.Fscan(r, &w, &h, &max); err != nil {
return nil, err
}
if max != 255 {
return nil, fmt.Errorf("unexpected max value %d", max)
}
if _, err := r.ReadByte(); err != nil {
return nil, err
}
pix := make([]byte, w*h)
if _, err := io.ReadFull(r, pix); err != nil {
return nil, err
}
img := image.NewGray(image.Rect(0, 0, w, h))
copy(img.Pix, pix)
return img, nil
}

func writePNG(path string, img image.Image) error {
f, err := os.Create(path)
if err != nil {
return err
}
defer f.Close()
return png.Encode(f, img)
}

func generateDemo(path string) error {
parsed, err := sfnt.Parse(goregular.TTF)
if err != nil {
return err
}
regular, err := opentype.NewFace(parsed, &opentype.FaceOptions{Size: 64, DPI: 72, Hinting: font.HintingNone})
if err != nil {
return err
}
defer regular.Close()
bold, err := opentype.NewFace(parsed, &opentype.FaceOptions{Size: 64, DPI: 72, Hinting: font.HintingNone, Embolden: 64})
if err != nil {
return err
}
defer bold.Close()

dst := image.NewRGBA(image.Rect(0, 0, 1000, 360))
draw.Draw(dst, dst.Bounds(), image.NewUniform(color.RGBA{0xFF, 0xFF, 0xFF, 0xFF}), image.Point{}, draw.Src)

label := font.Drawer{Dst: dst, Src: image.NewUniform(color.RGBA{0x30, 0x30, 0x30, 0xFF}), Face: basicfont.Face7x13}
label.Dot = fixed.P(40, 40)
label.DrawString("Regular")
label.Dot = fixed.P(40, 190)
label.DrawString("Embolden(64)")

text := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
rd := font.Drawer{Dst: dst, Src: image.NewUniform(color.RGBA{0x20, 0x20, 0x20, 0xFF}), Face: regular, Dot: fixed.P(40, 130)}
rd.DrawString(text)
bd := font.Drawer{Dst: dst, Src: image.NewUniform(color.RGBA{0x20, 0x20, 0x20, 0xFF}), Face: bold, Dot: fixed.P(40, 280)}
bd.DrawString(text)

return writePNG(path, dst)
}

func generateMixedDemo(path string) error {
parsed, err := sfnt.Parse(goregular.TTF)
if err != nil {
return err
}
regular, err := opentype.NewFace(parsed, &opentype.FaceOptions{Size: 64, DPI: 72, Hinting: font.HintingNone})
if err != nil {
return err
}
defer regular.Close()
bold, err := opentype.NewFace(parsed, &opentype.FaceOptions{Size: 64, DPI: 72, Hinting: font.HintingNone, Embolden: 64})
if err != nil {
return err
}
defer bold.Close()

dst := image.NewRGBA(image.Rect(0, 0, 1200, 440))
draw.Draw(dst, dst.Bounds(), image.NewUniform(color.RGBA{0xFF, 0xFF, 0xFF, 0xFF}), image.Point{}, draw.Src)

label := font.Drawer{Dst: dst, Src: image.NewUniform(color.RGBA{0x30, 0x30, 0x30, 0xFF}), Face: basicfont.Face7x13}
label.Dot = fixed.P(40, 40)
label.DrawString("Regular (HintingNone)")
label.Dot = fixed.P(620, 40)
label.DrawString("Embolden(64)")

texts := []string{
"AbCdEfGhIjKlMnOpQrStUvWxYz",
"Go embolden: QuickBrownFox",
"MixCase 123: VectorRaster",
}
for i, s := range texts {
y := 130 + i*120
rd := font.Drawer{Dst: dst, Src: image.NewUniform(color.RGBA{0x20, 0x20, 0x20, 0xFF}), Face: regular, Dot: fixed.P(40, y)}
rd.DrawString(s)
bd := font.Drawer{Dst: dst, Src: image.NewUniform(color.RGBA{0x20, 0x20, 0x20, 0xFF}), Face: bold, Dot: fixed.P(620, y)}
bd.DrawString(s)
}

return writePNG(path, dst)
}

func main() {
if len(os.Args) != 7 {
panic("usage: convert_and_generate_demo <tmp-dir> <font-testdata-out-dir> <demo-png-path> <mixed-demo-png-path> <freetype-text-expected-path> <freetype-text-large-expected-path>")
}
tmpDir := os.Args[1]
outDir := os.Args[2]
demoPath := os.Args[3]
mixedDemoPath := os.Args[4]
freetypeTextExpectedPath := os.Args[5]
freetypeTextLargeExpectedPath := os.Args[6]

for ch := 'A'; ch <= 'Z'; ch++ {
pgmPath := filepath.Join(tmpDir, fmt.Sprintf("freetype-embolden-%c-12px.pgm", ch))
img, err := decodePGM(pgmPath)
if err != nil {
panic(err)
}
pngPath := filepath.Join(outDir, fmt.Sprintf("freetype-embolden-%c-12px.png", ch))
if err := writePNG(pngPath, img); err != nil {
panic(err)
}
}

if err := generateDemo(demoPath); err != nil {
panic(err)
}
if err := generateMixedDemo(mixedDemoPath); err != nil {
panic(err)
}
textPGMPath := filepath.Join(tmpDir, "freetype-regular-vs-embolden-text-12px.pgm")
textImg, err := decodePGM(textPGMPath)
if err != nil {
panic(err)
}
if err := writePNG(freetypeTextExpectedPath, textImg); err != nil {
panic(err)
}
largeTextPGMPath := filepath.Join(tmpDir, "freetype-regular-vs-embolden-text-24px.pgm")
largeTextImg, err := decodePGM(largeTextPGMPath)
if err != nil {
panic(err)
}
if err := writePNG(freetypeTextLargeExpectedPath, largeTextImg); err != nil {
panic(err)
}
}
EOGO

( cd "$REPO_ROOT" && go run "$TMP_DIR/convert_and_generate_demo.go" "$TMP_DIR" "$OUT_DIR" "$DEMO_PATH" "$MIXED_DEMO_PATH" "$FREETYPE_TEXT_EXPECTED_PATH" "$FREETYPE_TEXT_LARGE_EXPECTED_PATH" )

echo "Generated: $OUT_DIR/freetype-embolden-{A..Z}-12px.png"
echo "Generated: $DEMO_PATH"
echo "Generated: $MIXED_DEMO_PATH"
echo "Generated: $FREETYPE_TEXT_EXPECTED_PATH"
echo "Generated: $FREETYPE_TEXT_LARGE_EXPECTED_PATH"
