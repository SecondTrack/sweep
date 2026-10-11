// setuid-root Helfer für die Tasks-App: beendet Prozesse per SIGKILL.
// Aufruf: tkkill <pid> [pid ...]   -> jeder gültige pid>1 wird gekillt.
// Wird beim Deploy mit chown root:wheel + chmod 4755 ins Bundle gelegt.
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>

int main(int argc, char **argv){
    setgid(0); setuid(0);   // Root-Rechte übernehmen (setuid-Bit)
    int killed = 0;
    for(int i=1;i<argc;i++){
        int pid = atoi(argv[i]);
        if(pid > 1){ if(kill(pid, SIGKILL) == 0) killed++; }
    }
    return killed>0 ? 0 : 1;
}
