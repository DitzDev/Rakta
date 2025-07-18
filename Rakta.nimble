# Package

version       = "0.2.0"
author        = "DitzDev"
description   = "Express.js like, Powerful, Fast, and Minimalist Web Framework for Nim. Focus on your Backend."
license       = "MIT"
srcDir        = "src"

skipFiles = @["todo.markdown"]
skipDirs = @["tests", "public"]

# Dependencies

requires "nim >= 2.2.4"

task docs, "generate documentation":
  exec("mkdir -p htmldocs/Rakta")
  --project
  --git.url: "https://github.com/DitzDev/Rakta"
  --git.commit: main
  setCommand "doc", "src/Rakta.nim"
