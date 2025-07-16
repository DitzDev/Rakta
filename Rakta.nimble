# Package

version       = "0.1.0"
author        = "DitzDev"
description   = "Powerfull, Fast, and Minimalist web Framework for Nim. Focus on your Backend."
license       = "MIT"
srcDir        = "src"

skipFiles = @["todo.markdown"]
skipDirs = @["tests", "public"]

# Dependencies

requires "nim >= 2.2.4"

when not defined(windows):
  requires "httpbeast >= 0.4.0"
  
task docs, "generate documentation":
  exec("mkdir -p htmldocs/Rakta")
  --project
  --git.url: "https://github.com/DitzDev/Rakta"
  --git.commit: main
  setCommand "doc", "src/Rakta.nim"
