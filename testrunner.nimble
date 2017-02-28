# Package

version       = "0.1.0"
author        = "Federico Ceratto"
description   = "Test runner"
license       = "GPLv3"
bin           = @["testrunner"]

# Dependencies

when defined(Linux):
  requires "nim >= 0.16.0", "libnotify"
else:
  requires "nim >= 0.16.0"

