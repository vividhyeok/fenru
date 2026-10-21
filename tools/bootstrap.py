"""Generate stock platform runners using the pinned SDK, preserving app source."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as temporary:
    saved = Path(temporary)
    for name in ('lib', 'test', 'pubspec.yaml', 'analysis_options.yaml', '.gitignore', 'README.md'):
        source = root / name
        if source.is_dir():
            shutil.copytree(source, saved / name)
        elif source.exists():
            shutil.copy2(source, saved / name)
    subprocess.run(['flutter', 'create', '--platforms=windows,android', '--org', 'com.vividhyeok',
                    '--project-name', 'fenru', '--no-pub', str(root)], check=True, shell=(__import__('os').name == 'nt'))
    for source in saved.iterdir():
        destination = root / source.name
        if source.is_dir():
            shutil.copytree(source, destination, dirs_exist_ok=True)
        else:
            shutil.copy2(source, destination)

manifest = root / 'android/app/src/main/AndroidManifest.xml'
text = manifest.read_text()
text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
text = text.replace('android:label="fenru"', 'android:label="Fenru"')
manifest.write_text(text)
runner = root / 'windows/runner/main.cpp'
runner.write_text(runner.read_text().replace('L"fenru"', 'L"Fenru"'))
print('Platform runners generated; source preserved.')
