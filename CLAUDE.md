# EIN (Emacs IPython Notebook) Development Guide

## Build & Test Commands
- `make test-compile` - Compile and check for warnings
- `make test-unit` - Run unit tests
- `make test-int` - Run integration tests
- `make test` - Run all tests
- `make quick` - Run compilation checks and unit tests

Run single test: `cask exec ert-runner -L ./lisp -L ./test -l test/testein.el test/test-ein-specific-file.el`

## Code Style Guidelines
- Prefix all functions/variables with `ein:` namespace
- Use `ein:deflocal` for buffer-local permanent variables
- Private helpers use `--` suffix: `ein:function--helper`
- Predicate functions end with `-p`: `ein:kernel-live-p`
- Data structs use `ein:$` prefix: `ein:$notebook`, `ein:$kernel`
- Use lexical binding: `;;; filename.el --- Description -*- lexical-binding:t -*-`
- Error handling: `condition-case` and `ein:log` at appropriate levels
- Use `cl-loop` and `ein:and-let*` for concise coding patterns
- Prefer using existing patterns from neighboring files
- Test files follow `test-ein-*.el` naming pattern

## Dependencies
- Requires Emacs 25+
- Uses `Cask` for package management
- Core deps: websocket, request, deferred, polymode, dash