"""Мини-лексер Swift: находит строковые литералы (с интерполяцией) вне комментариев.

Используется tools/check-xcstrings.py. Без зависимостей.
"""
import re

LOCALIZED_BEFORE = re.compile(
    r"(?:String\(\s*localized:\s*|LocalizedStringKey\(\s*|LocalizedStringResource\(\s*"
    r"|\bText\(\s*|\bButton\(\s*|\bLabel\(\s*|\bTextField\(\s*|\bSecureField\(\s*|\bToggle\(\s*"
    r"|\bSection\(\s*|\bPicker\(\s*|\bMenu\(\s*|\bLink\(\s*|\bStepper\(\s*|\bDatePicker\(\s*"
    r"|\bContentUnavailableView\(\s*|\bNavigationLink\(\s*"
    r"|\.navigationTitle\(\s*|\.alert\(\s*|\.confirmationDialog\(\s*|\.help\(\s*"
    r"|\.accessibilityLabel\(\s*|\.accessibilityHint\(\s*|\.accessibilityValue\(\s*"
    r"|\bitem\(\s*|\bselAction\(\s*|\b(?:item|selAction)\(\s*\"[^\"]*\"\s*,\s*"
    r"|Button\(\s*role:\s*\.\w+\s*,?\s*|Button\(\s*role:\s*nil\s*,?\s*)$"
)
CYR = re.compile(r"[А-Яа-яЁё]")


class Lit:
    def __init__(self, start, end, parts, raw, line):
        self.start, self.end, self.parts, self.raw, self.line = start, end, parts, raw, line

    def has_cyr(self):
        return any(isinstance(p, str) and CYR.search(p) for p in self.parts)

    def text(self, spec=lambda e: "%@"):
        out = []
        if all(isinstance(p, str) for p in self.parts):
            return "".join(self.parts)  # без подстановок Xcode берёт ключ как есть (% не удваивается)
        for p in self.parts:
            if isinstance(p, str):
                out.append(p.replace("%", "%%"))
            else:
                out.append(spec(p[1]))
        return "".join(out)


ESC = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0", "r": "\r"}


def lex(src):
    """Возвращает список Lit верхнего уровня (вложенные в интерполяцию тоже, отдельно)."""
    lits = []
    i, n = 0, len(src)

    def line_of(pos):
        return src.count("\n", 0, pos) + 1

    def read_string(i, out):
        # src[i] == '"' (возможно '"""'); raw-строки #"…"# — тоже
        hashes = 0
        j = i
        while j > 0 and src[j - 1] == "#":
            hashes += 1
            j -= 1
        start = j
        multi = src.startswith('"""', i)
        q = '"""' if multi else '"'
        k = i + len(q)
        parts, buf = [], []
        close = q + "#" * hashes
        esc = "\\" + "#" * hashes
        while k < n:
            if src.startswith(close, k):
                k += len(close)
                break
            if src.startswith(esc, k):
                k2 = k + len(esc)
                c = src[k2] if k2 < n else ""
                if c == "(":
                    if buf:
                        parts.append("".join(buf)); buf = []
                    depth, m = 1, k2 + 1
                    expr_start = m
                    while m < n and depth:
                        ch = src[m]
                        if ch == '"':
                            m = read_string(m, out)
                            continue
                        if ch == "(":
                            depth += 1
                        elif ch == ")":
                            depth -= 1
                        m += 1
                    parts.append(("interp", src[expr_start:m - 1].strip()))
                    k = m
                    continue
                if c == "u" and k2 + 1 < n and src[k2 + 1] == "{":
                    e = src.index("}", k2)
                    buf.append(chr(int(src[k2 + 2:e], 16)))
                    k = e + 1
                    continue
                if multi and c == "\n":
                    k = k2 + 1
                    continue
                buf.append(ESC.get(c, c))
                k = k2 + 1
                continue
            buf.append(src[k])
            k += 1
        if buf:
            parts.append("".join(buf))
        out.append(Lit(start, k, parts, src[start:k], line_of(start)))
        return k

    while i < n:
        c = src[i]
        if src.startswith("//", i):
            e = src.find("\n", i)
            i = n if e < 0 else e
            continue
        if src.startswith("/*", i):
            e = src.find("*/", i)
            i = n if e < 0 else e + 2
            continue
        if c == '"':
            i = read_string(i, lits)
            continue
        i += 1
    return lits


def localized(src, lit):
    before = src[max(0, lit.start - 80):lit.start]
    return bool(LOCALIZED_BEFORE.search(before))
