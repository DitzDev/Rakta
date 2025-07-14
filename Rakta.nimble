# Package

version       = "0.1.0"
author        = "DitzDev"
description   = "Powerfull, Fast, and Minimalist web Framework for Nim. Focus on your Backend."
license       = "MIT"
srcDir        = "src"

skipFiles = @["todo.markdown"]
skipDirs = @["tests"]

# Dependencies

requires "nim >= 2.2.4"

when not defined(windows):
  requires "httpbeast >= 0.4.0"