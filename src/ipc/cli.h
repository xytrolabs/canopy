#pragma once

namespace shade::ipc {

  // Entry point for `Shade msg <command> [args...]`. Returns a process exit
  // code. Forwards the command to the running instance over the IPC socket.
  int runCli(int argc, char* argv[]);

} // namespace shade::ipc
