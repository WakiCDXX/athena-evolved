#!/usr/bin/env python3
"""Compile gate — static analysis before loading any self-modified script.

Mirrors the compiler-in-the-loop RL reward-shaping ladder:
  syntax → type-check → smoke test → full regression

Usage:
    python3 compile_gate.py <script_path> [--strict]
    python3 compile_gate.py --batch file1.sh file2.py ...

Exit codes:
    0  — all checks passed
    1  — syntax error (blocks load)
    2  — style/shellcheck warning (does not block, logged)
    3  — file not found
"""
import sys, os, subprocess, json

def check_bash(path):
    """Run bash -n on a script. Returns (ok, errors[])."""
    errors = []
    r = subprocess.run(["bash", "-n", path], capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        errors.append(r.stderr.strip())
        return False, errors
    # shellcheck if available
    sc = subprocess.run(["shellcheck", path], capture_output=True, text=True, timeout=30)
    if sc.returncode != 0:
        for line in sc.stdout.strip().splitlines():
            errors.append(f"shellcheck: {line}")
        return len(errors) == 0, errors  # warnings don't fail
    return True, []

def check_python(path):
    """Run py_compile on a Python file. Returns (ok, errors[])."""
    errors = []
    try:
        import py_compile
        py_compile.compile(path, doraise=True)
    except py_compile.PyCompileError as e:
        errors.append(str(e))
        return False, errors
    return True, []

def grade(errors, strict=False):
    """Return 0-1 score: 1 = clean, 0.5 = warnings only, 0 = errors."""
    if not errors:
        return 1.0
    if strict:
        return 0.0
    # non-blocking warnings
    warn_only = all("shellcheck" in e for e in errors)
    return 0.5 if warn_only else 0.0

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("Usage: compile_gate.py <script> [--strict]")
        sys.exit(3)

    path = sys.argv[1]
    strict = "--strict" in sys.argv

    if not os.path.exists(path):
        print(json.dumps({"file": path, "status": "missing", "score": 0, "errors": ["file not found"]}))
        sys.exit(3)

    ok = True
    all_errors = []
    if path.endswith(".py"):
        ok, all_errors = check_python(path)
    elif path.endswith(".sh"):
        ok, all_errors = check_bash(path)
    else:
        # Try both
        p_ok, p_err = check_python(path)
        b_ok, b_err = check_bash(path)
        all_errors = p_err + b_err
        ok = p_ok and b_ok

    g = grade(all_errors, strict)
    result = {"file": path, "status": "pass" if ok and g == 1.0 else "warn" if g == 0.5 else "fail", "score": g, "errors": all_errors}
    print(json.dumps(result))
    sys.exit(0 if g > 0 else 1)

if __name__ == "__main__":
    main()
