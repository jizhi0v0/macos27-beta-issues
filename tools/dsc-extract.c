#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
typedef int (*extract_fn)(const char*, const char*, void (^)(unsigned, unsigned));
int main(int argc, char** argv){
  if(argc<3){ fprintf(stderr,"usage: extract <cache> <root>\n"); return 2; }
  void* h = dlopen("/Applications/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/usr/lib/dsc_extractor.bundle", RTLD_LAZY);
  if(!h){ fprintf(stderr,"dlopen: %s\n", dlerror()); return 1; }
  extract_fn f = (extract_fn)dlsym(h, "dyld_shared_cache_extract_dylibs_progress");
  if(!f){ fprintf(stderr,"dlsym failed\n"); return 1; }
  int r = f(argv[1], argv[2], ^(unsigned c, unsigned t){
      if(c % 200 == 0 || c==t) { printf("%u/%u\n", c, t); fflush(stdout); }
  });
  printf("result=%d\n", r);
  return r;
}
