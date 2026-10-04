#!/usr/bin/env python3
"""Reuse the established isolated native runner, adding actual R9 visual tests.

No GUI or app process is launched. Temporary package cleanup belongs to the
existing runner; all production sources/resources and tests are copied unchanged.
"""
from pathlib import Path
runner = Path(__file__).with_name('test-onboarding-isolated.py')
source = runner.read_text()
needle = '    shutil.copy2(root / "Tests/OpenIslandAppTests/OnboardingRuntimeTests.swift", package / "Tests/OpenIslandAppTests")'
assert source.count(needle) == 1
source = source.replace(needle, needle + '\n    shutil.copy2(root / "Tests/OpenIslandAppTests/OnboardingR9VisualTests.swift", package / "Tests/OpenIslandAppTests")')
exec(compile(source, str(runner), 'exec'), {'__file__': str(runner), '__name__': '__main__'})
