#pragma once

namespace shade::config {

  // Entry point for `Shade config <command> [options]`. Returns a process
  // exit code. Pure CLI helper; does not start Application or mutate live config.
  int runCli(int argc, char* argv[]);

} // namespace shade::config
