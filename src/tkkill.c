// tkkill — setuid-root Helfer der App „Sweep“: beendet App-Prozesse per SIGKILL.
// Aufruf: tkkill <pid> [pid ...]
//
// Sicherheit (wie fmpkg in FileTransfer):
//  * nimmt Befehle nur von der echten App an: Aufrufer = /Applications/Tasks.app/Tasks, läuft als mobile,
//    wird nicht debuggt und hat keine DYLD_-Variablen. Eine Shell oder fremde App kann ihn nicht benutzen.
//  * beendet nur Apps (Programm liegt in einem .app-Bundle), nie System-Prozesse, nie SpringBoard,
//    nie die Sweep-App selbst.
#include <stdio.h>
#include <sys/stat.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/sysctl.h>

#define APP_BIN "/Applications/Tasks.app/Tasks"
#define MOBILE  501
int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

/* Einzige erlaubte DYLD_-Variable: DYLD_INSERT_LIBRARIES, wenn darin nur Cydia Substrate steht (so lädt
 * Substrate sich unter iOS 5/6 in jede App). Jede Bibliothek muss aufgelöst unter
 * /Library/Frameworks/CydiaSubstrate.framework/ oder /Library/MobileSubstrate/ liegen, root gehören und
 * für niemand anderen beschreibbar sein. Alles andere (eigene Bibliotheken, DYLD_LIBRARY_PATH …) bleibt verboten. */
static int hasPrefixStr(const char *s, const char *p) { return strncmp(s, p, strlen(p)) == 0; }
static int trustedDyld(const char *kv) {
    const char *key = "DYLD_INSERT_LIBRARIES=";
    if (!hasPrefixStr(kv, key)) return 0;
    const char *val = kv + strlen(key);
    char list[1024];
    size_t n = strlen(val);
    if (n == 0 || n >= sizeof list) return 0;
    memcpy(list, val, n + 1);
    char *save = NULL;
    for (char *p = strtok_r(list, ":", &save); p; p = strtok_r(NULL, ":", &save)) {
        char real[PATH_MAX]; struct stat st;
        if (!realpath(p, real)) return 0;
        if (!hasPrefixStr(real, "/Library/Frameworks/CydiaSubstrate.framework/") && !hasPrefixStr(real, "/Library/MobileSubstrate/")) return 0;
        if (lstat(real, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 || (st.st_mode & 022)) return 0;
    }
    return 1;
}

static int callerOK(void) {
    if (getuid() != MOBILE || geteuid() != 0) return 0;
    pid_t pp = getppid();
    char path[1024] = { 0 };
    if (proc_pidpath(pp, path, sizeof path) <= 0 || strcmp(path, APP_BIN) != 0) return 0;
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pp };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len == 0) return 0;
    if (kp.kp_eproc.e_ucred.cr_uid != MOBILE || (kp.kp_proc.p_flag & P_TRACED)) return 0;
    int argmax = 0; size_t sz = sizeof argmax;
    int mma[2] = { CTL_KERN, KERN_ARGMAX };
    if (sysctl(mma, 2, &argmax, &sz, NULL, 0) != 0 || argmax <= 0) return 0;
    char *buf = malloc((size_t)argmax);
    int mpa[3] = { CTL_KERN, KERN_PROCARGS2, pp };
    sz = (size_t)argmax;
    if (!buf || sysctl(mpa, 3, buf, &sz, NULL, 0) != 0) { free(buf); return 0; }
    int ok = 1;
    for (size_t i = sizeof(int); i < sz; ) {
        size_t n = strnlen(buf + i, sz - i);
        if (n >= 5 && strncmp(buf + i, "DYLD_", 5) == 0 && !trustedDyld(buf + i)) { ok = 0; break; }
        i += n + 1;
    }
    free(buf);
    return ok;
}

// Nur Apps: Programmpfad enthält ".app/", ist nicht SpringBoard und nicht Sweep selbst
static int isApp(pid_t pid) {
    char path[1024] = { 0 };
    if (pid <= 1 || proc_pidpath(pid, path, sizeof path) <= 0) return 0;
    if (!strstr(path, ".app/")) return 0;
    if (strstr(path, "/SpringBoard.app/") || strcmp(path, APP_BIN) == 0) return 0;
    return 1;
}

int main(int argc, char **argv) {
    if (!callerOK()) { fprintf(stderr, "tkkill: caller refused\n"); return 2; }
    if (setgid(0) != 0 || setuid(0) != 0) return 3;
    int killed = 0;
    for (int i = 1; i < argc; i++) {
        pid_t pid = (pid_t)atoi(argv[i]);
        if (isApp(pid) && kill(pid, SIGKILL) == 0) killed++;
    }
    return killed > 0 ? 0 : 1;
}
