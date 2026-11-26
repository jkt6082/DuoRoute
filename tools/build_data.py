"""Rebuild addons/DuoRoute/Data.lua from QuestieDB + Questie (run after updating vendor/)."""
import os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
for script in ('extract.py', 'tags.py', 'gendata.py'):
    print('==', script)
    subprocess.run([sys.executable, '-I', os.path.join(here, script)], check=True)
