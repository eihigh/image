#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$SCRIPT_DIR"
DEMO_PATH="$REPO_ROOT/testdata/font-embolden-demo.png"

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
if _, err := r.ReadByte(); err != nil {
return nil, err
}
pix := make([]byte, w*h)
if _, err := r.Read(pix); err != nil {
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

func main() {
if len(os.Args) != 4 {
panic("usage: convert_and_generate_demo <tmp-dir> <font-testdata-out-dir> <demo-png-path>")
}
tmpDir := os.Args[1]
outDir := os.Args[2]
demoPath := os.Args[3]

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
}
EOGO

( cd "$REPO_ROOT" && go run "$TMP_DIR/convert_and_generate_demo.go" "$TMP_DIR" "$OUT_DIR" "$DEMO_PATH" )

echo "Generated: $OUT_DIR/freetype-embolden-{A..Z}-12px.png"
echo "Generated: $DEMO_PATH"
