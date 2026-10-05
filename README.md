# embed-roc-in-zig-example

Reproduces the features of [roc-platform-template-zig](https://github.com/lukewilliamboswell/roc-platform-template-zig) but instead of producing a compiled platform, we make the zig compiler link everything together directly into an executable.

build.zig uses the Roc compiler to compile the Roc code to an object file that exports `roc_main`. Then compiles the host and links the two into the executable.

## Requirements

- Zig 0.16.0
- A nightly Roc compiler

## Building

```
zig build
```