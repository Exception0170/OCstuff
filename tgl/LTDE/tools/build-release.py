#!/usr/bin/env python3
"""Build the LTDE release from the current sources."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import hashlib

base=Path(__file__).resolve().parents[1]
repo=base.parent
name="ltde-v1.0.2010"
output=base/(name+".zip")
files={}

def add_tree(source,target,exclude=()):
    for path in sorted(source.rglob("*")):
        relative=path.relative_to(source)
        if path.is_file() and not any(part in exclude for part in relative.parts):
            files[target/relative]=path.read_bytes()

add_tree(base/"ltde",Path("ltde"),{"dbgev.app","logs","__pycache__"})
add_tree(base/"usr",Path("usr"))
add_tree(repo/"usr/lib/tgl",Path("usr/lib/tgl"))
for lib in ("tgl-ui.lua","tgl-img.lua"):
    files[Path("usr/lib")/lib]=(repo/"usr/lib"/lib).read_bytes()
add_tree(base/"docs",Path("docs"))
for target,source in (("README.md","ABOUT.md"),("ABOUT.md","ABOUT.md"),("CHANGELOG.md","CHANGELOG.md")):
    files[Path(target)]=(base/source).read_bytes()

with ZipFile(output,"w",compression=ZIP_DEFLATED) as archive:
    for path,data in sorted(files.items()):
        info=ZipInfo(name+"/"+path.as_posix(),date_time=(2026,10,20,0,0,0))
        info.compress_type=ZIP_DEFLATED
        info.external_attr=0o100644<<16
        archive.writestr(info,data)
digest=hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix(".zip.sha256").write_text(digest+"  "+output.name+"\n")
print(str(output))
print(str(len(files))+" files; SHA-256 "+digest)
