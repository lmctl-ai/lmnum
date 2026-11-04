"""Run gallery calculations and file handoffs without renderers or downloads."""
import re, subprocess, tempfile
from pathlib import Path
from invocation import compiler_cmd

root = Path.cwd()
sources = sorted((root / 'examples/gallery').glob('*.lms'))
assert len(sources) == 25, len(sources)
handoffs = 0
with tempfile.TemporaryDirectory(prefix='gallery-', dir=root / 'build') as scratch:
    scratch = Path(scratch)
    for source in sources:
        text = source.read_text()
        assert 'r.stdout' not in text, source
        end = text.index('assert(r.ok);', text.index('end _lmcode_')) + len('assert(r.ok);')
        read = re.search(r'^output = read_file\("([^"]+)"\);$', text, re.M)
        if read:
            end = read.end()
        text = text[:end] + '\n'
        text = text.replace(' install="github:lmctl-ai/lmnum@latest"', '')
        if read:
            text += 'require(output != "", "empty numerical data");\n'
        program = scratch / source.name
        program.write_text(text)
        result = subprocess.run(compiler_cmd() + [str(program)], cwd=scratch,
                                capture_output=True, text=True, timeout=300)
        assert result.returncode == 0, (source.name, result.stdout, result.stderr)
        if read:
            assert (scratch / read[1]).stat().st_size > 0, source
            handoffs += 1
assert handoffs == 4, handoffs
print(f'PASS {len(sources)} offline gallery calculations and {handoffs} file handoffs')
