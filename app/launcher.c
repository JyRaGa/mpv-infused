// mpv.app launcher: runs Homebrew's mpv (kept current by `brew upgrade`) in GUI mode.
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    char **args = calloc(argc + 2, sizeof(char *));
    args[0] = "/opt/homebrew/bin/mpv";
    args[1] = "--player-operation-mode=pseudo-gui";
    for (int i = 1; i < argc; i++) args[i + 1] = argv[i];
    execv(args[0], args);
    return 127;
}
