#!/usr/bin/env python3
"""把 Rime 格式的 .dict.yaml 转成 libime_pinyindict 可读的文本格式。

libime 的文本词库格式是 `词条 带单引号的拼音 词频`，
而 Rime 词库是 `词条<TAB>空格分隔的拼音`，两者不通用。
另外不同版本的 libime 支持的音节表略有差异，遇到不认识的音节
libime_pinyindict 会直接 abort，这里通过重试自动剔除。
"""

import os
import re
import resource
import subprocess
import sys
import tempfile

try:
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
except (ValueError, OSError):
    pass

PINYIN_RE = re.compile(r"^[a-z\u00fc\u00ea]+( [a-z\u00fc\u00ea]+)*$")
BAD_RE = re.compile(r"invalid full pinyin: (.+)")


def probe_bad_syllables(entries):
    """libime 报错时会把整串拼音打出来，无法直接定位坏音节，
    这里对每个出现过的音节单独编译一次，得到真实的不支持列表。"""
    syllables = sorted({s for _, pinyin in entries for s in pinyin.split("'")})
    bad = set()
    with tempfile.TemporaryDirectory() as tmpdir:
        src = os.path.join(tmpdir, "probe.txt")
        dst = os.path.join(tmpdir, "probe.bin")
        for syl in syllables:
            with open(src, "w", encoding="utf-8") as fh:
                fh.write(f"中 {syl} 0\n")
            if os.path.exists(dst):
                os.unlink(dst)
            proc = subprocess.run(
                ["libime_pinyindict", src, dst], capture_output=True, text=True
            )
            if proc.returncode != 0:
                bad.add(syl)
    return bad, len(syllables)


def parse_yaml(path):
    started = False
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not started:
                if line.strip() == "...":
                    started = True
                continue
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                continue
            word, pinyin = parts[0].strip(), parts[1].strip()
            if not word or any(c.isspace() for c in word):
                continue
            if not PINYIN_RE.match(pinyin):
                continue
            yield word, pinyin.replace(" ", "'")


def write_text(entries, path):
    with open(path, "w", encoding="utf-8") as fh:
        for word, pinyin in entries:
            fh.write(f"{word} {pinyin} 0\n")


def build(entries, tmpdir):
    src = os.path.join(tmpdir, "dict.txt")
    dst = os.path.join(tmpdir, "dict.bin")
    write_text(entries, src)
    proc = subprocess.run(
        ["libime_pinyindict", src, dst], capture_output=True, text=True
    )
    return proc, dst


def main():
    if len(sys.argv) != 3:
        sys.exit(f"用法: {sys.argv[0]} <input.dict.yaml> <output.txt>")

    src_yaml, out_txt = sys.argv[1], sys.argv[2]
    entries = list(parse_yaml(src_yaml))
    print(f"解析 {len(entries)} 条词条", file=sys.stderr)

    bad, total_syllables = probe_bad_syllables(entries)
    if bad:
        print(
            f"探测 {total_syllables} 个音节，libime 不支持: {' '.join(sorted(bad))}",
            file=sys.stderr,
        )
        before = len(entries)
        entries = [
            (w, p) for (w, p) in entries if not (bad & set(p.split("'")))
        ]
        dropped = before - len(entries)
        print(f"剔除 {dropped} 条含不支持音节的词条", file=sys.stderr)
    else:
        dropped = 0

    with tempfile.TemporaryDirectory() as tmpdir:
        proc, _ = build(entries, tmpdir)
        if proc.returncode != 0:
            sys.exit(f"libime_pinyindict 失败: {(proc.stderr or '').strip()}")

    write_text(entries, out_txt)
    print(
        f"完成: {len(entries)} 条，剔除 {dropped} 条 -> {out_txt}", file=sys.stderr
    )


if __name__ == "__main__":
    main()
