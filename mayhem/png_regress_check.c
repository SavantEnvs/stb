/* Known-answer check for stb_image's PNG decoder: replays upstream's own regression table
   tests/pngsuite/ref_results.csv (width, height, components, error string, FNV-1a pixel hash). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_IMPLEMENTATION
#include "../stb_image.h"

static unsigned int fnv1a_hash32(const stbi_uc *bytes, size_t len)
{
   unsigned int hash = 0x811c9dc5;
   size_t i;
   for (i = 0; i < len; ++i)
      hash = (hash ^ bytes[i]) * 0x01000193;
   return hash;
}

int main(void)
{
   char line[1024];
   int total = 0, passed = 0, failed = 0;
   FILE *csv = fopen("pngsuite/ref_results.csv", "r");
   if (!csv) { fprintf(stderr, "cannot open pngsuite/ref_results.csv (run from tests/)\n"); return 2; }
   if (!fgets(line, sizeof line, csv)) return 2;  /* header */
   while (fgets(line, sizeof line, csv)) {
      char name[512], err[256];
      int w, h, n, gw, gh, gn;
      unsigned int hash, ghash = 0;
      const char *gerr = "";
      stbi_uc *pix;
      char *p = line, *f[6];
      int i;
      line[strcspn(line, "\r\n")] = 0;
      for (i = 0; i < 6; ++i) {
         f[i] = p;
         p = strchr(p, ',');
         if (i < 5) { if (!p) break; *p++ = 0; }
      }
      if (i < 6) { ++total; ++failed; printf("bad csv row\n"); continue; }
      snprintf(name, sizeof name, "%s", f[0]);
      w = atoi(f[1]); h = atoi(f[2]); n = atoi(f[3]);
      snprintf(err, sizeof err, "%s", f[4]);
      hash = (unsigned int) strtoul(f[5], NULL, 16);
      ++total;
      pix = stbi_load(name, &gw, &gh, &gn, 0);
      if (!pix) gerr = stbi_failure_reason();
      else { ghash = fnv1a_hash32(pix, (size_t) gw * gh * gn); stbi_image_free(pix); }
      if (gw == w && gh == h && gn == n && strcmp(gerr, err) == 0 && ghash == hash) ++passed;
      else { ++failed; printf("MISMATCH %s: got %dx%dx%d '%s' 0x%08x, want %dx%dx%d '%s' 0x%08x\n", name, gw, gh, gn, gerr, ghash, w, h, n, err, hash); }
   }
   fclose(csv);
   printf("PNGREGRESS total=%d passed=%d failed=%d\n", total, passed, failed);
   return failed != 0;
}
