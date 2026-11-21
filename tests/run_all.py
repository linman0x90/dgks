"""Runs every tests/test_*.py and prints a summary. Exits with 1 if any test fails.

    python tests/run_all.py            all tests
    python tests/run_all.py -v         also print each test's output
    python tests/run_all.py sync pvp   only tests whose file name contains one of the words
"""
import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
verbose = "-v" in sys.argv[1:]
words = [a for a in sys.argv[1:] if a != "-v"]

failed = []
for path in sorted(glob.glob(os.path.join(HERE, "test_*.py"))):
    name = os.path.basename(path)[:-3]
    if words and not any(w in name for w in words):
        continue
    run = subprocess.run([sys.executable, path], cwd=HERE, capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = run.stdout + run.stderr
    ok = run.returncode == 0
    checks = sum(1 for line in out.splitlines() if line.startswith(("PASS", "FAIL")))
    print(f"{'ok  ' if ok else 'FAIL'} {name} ({checks} checks)")
    if verbose or not ok:
        print("    " + out.strip().replace("\n", "\n    "))
    if not ok:
        failed.append(name)

print(f"\n{len(failed)} failed" + (": " + ", ".join(failed) if failed else ""))
sys.exit(1 if failed else 0)
