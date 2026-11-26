"""Run every DuoRoute test against the mock WoW API. Needs: pip install lupa"""
import glob, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
failed = []
for t in sorted(glob.glob(os.path.join(here, 'test_*.py'))):
    r = subprocess.run([sys.executable, '-I', t], cwd=here, capture_output=True, text=True)
    out = r.stdout + r.stderr
    bad = r.returncode != 0 or 'Traceback' in out or 'Error' in out
    print(('FAIL ' if bad else 'ok   ') + os.path.basename(t))
    if bad:
        failed.append(t)
        print(out[-1500:])
sys.exit(1 if failed else 0)
