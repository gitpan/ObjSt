/* standard perlmain */

extern "C" {
#define __attribute__(attr)
#include "EXTERN.h"
#include "perl.h"
}

extern "C" void xs_init();
static PerlInterpreter *osperl;

int main (int argc, char **argv, char **env)
{
  int exitstatus;
 
  PERL_SYS_INIT(&argc,&argv);
 
  perl_init_i18nl10n(1);
 
  osperl = perl_alloc();
  if (!osperl) exit(1);

  perl_construct(osperl);
  exitstatus = perl_parse(osperl, xs_init, argc, argv, (char **)NULL);
  if (!exitstatus) exitstatus = perl_run(osperl);

  perl_destruct(osperl);
  perl_free(osperl);

  PERL_SYS_TERM();

  exit(exitstatus);
}
