#!/usr/bin/env python3
"""Проверка локализации Sguardo iOS (без Xcode).

  python3 tools/check-xcstrings.py            # проверка, код возврата 1 при ошибках
  python3 tools/check-xcstrings.py --interp   # плюс список строк с подстановками (для ревью типов)
  --catalog путь.xcstrings  --files A.swift,B.swift   # проверить свой кусок на отдельном каталоге

Проверяет:
  1. App/Localizable.xcstrings и App/InfoPlist.xcstrings — валидный JSON, sourceLanguage ru;
  2. у каждого ключа есть перевод на все 8 языков (state translated, не пустой);
     plural: ru/pl — one/few/many/other, остальные — one/other;
     набор подстановок (%@, %lld, %lf…) в переводе совпадает с ключом;
  3. каждая русская строка в App/*.swift в локализуемом месте (Text("…"), String(localized: "…"), …)
     есть в каталоге (ключ сравнивается без учёта типа подстановки);
  4. русские литералы вне локализуемых мест — ПРЕДУПРЕЖДЕНИЕ (если так и задумано — `// i18n: no` в строке);
  5. ключи каталога, которых нет в коде — предупреждение.
Fixture.swift (демо-данные снимков) не проверяется.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from swiftstrings import lex, localized  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["ru", "en", "de", "fr", "es", "pt", "it", "pl"]
PLURAL_NEED = {"ru": {"one", "few", "many", "other"}, "pl": {"one", "few", "many", "other"}}
SPEC = re.compile(r"%(?:(\d+)\$)?(#@\w+@|ll[dui]|l[fdu]|[@dDuUxXoOfeEgGcCsSpaAF])")
SKIP_FILES = {"Fixture.swift"}

errors, warns = [], []


def specs(s):
    """Подстановки строки без учёта порядка (позиционные %1$@ → %@), без %%."""
    s = s.replace("%%", "")
    out = []
    for m in SPEC.finditer(s):
        t = m.group(2)
        if t.startswith("#@"):
            out.append("#@")
        else:
            out.append(t)
    return sorted(out)


def norm_key(k):
    k = k.replace("%%", "\x00")
    k = SPEC.sub("%@", k)
    return k.replace("\x00", "%%")


def unit_ok(where, u, key_specs, plural_part=False):
    if not isinstance(u, dict) or "stringUnit" not in u:
        errors.append(f"{where}: нет stringUnit")
        return
    su = u["stringUnit"]
    if su.get("state") != "translated":
        errors.append(f"{where}: state={su.get('state')}")
    v = su.get("value")
    if not isinstance(v, str) or not v.strip():
        errors.append(f"{where}: пустое значение")
        return
    if key_specs is not None and specs(v) != key_specs:
        errors.append(f"{where}: подстановки {specs(v)} ≠ ключа {key_specs}: {v!r}")


def check_loc(where, loc, key, lang):
    ks = specs(key)
    if "stringUnit" in loc and "substitutions" not in loc:
        unit_ok(where, loc, ks)
        return
    if "variations" in loc:
        pl = loc["variations"].get("plural")
        if not pl:
            errors.append(f"{where}: variations без plural")
            return
        need = PLURAL_NEED.get(lang, {"one", "other"})
        miss = need - set(pl)
        if miss:
            errors.append(f"{where}: plural без {sorted(miss)}")
        for cat, u in pl.items():
            unit_ok(f"{where}[{cat}]", u, ks)
        return
    if "substitutions" in loc:
        unit_ok(where, loc, None)
        v = loc["stringUnit"].get("value", "")
        for name, sub in loc["substitutions"].items():
            if f"%#@{name}@" not in v:
                errors.append(f"{where}: подстановка {name} не используется в {v!r}")
            pl = sub.get("variations", {}).get("plural", {})
            need = PLURAL_NEED.get(lang, {"one", "other"})
            miss = need - set(pl)
            if miss:
                errors.append(f"{where}/{name}: plural без {sorted(miss)}")
            for cat, u in pl.items():
                if "%arg" not in u.get("stringUnit", {}).get("value", "") and cat != "zero":
                    warns.append(f"{where}/{name}[{cat}]: нет %arg (число не покажется)")
        return
    errors.append(f"{where}: неизвестная форма {list(loc)}")


def arg(name):
    if name in sys.argv:
        i = sys.argv.index(name)
        return sys.argv[i + 1] if i + 1 < len(sys.argv) else None
    return None


def load_catalog(name, required=True, path=None):
    p = path or os.path.join(ROOT, "App", name)
    if not os.path.exists(p):
        if required:
            errors.append(f"{name}: файла нет")
        return {}
    try:
        cat = json.load(open(p, encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        errors.append(f"{name}: невалидный JSON: {e}")
        return {}
    if cat.get("sourceLanguage") != "ru":
        errors.append(f"{name}: sourceLanguage должен быть ru")
    if "version" not in cat:
        errors.append(f"{name}: нет version")
    for key, ent in cat.get("strings", {}).items():
        if ent.get("shouldTranslate") is False:
            continue
        locs = ent.get("localizations", {})
        for lang in LANGS:
            if lang not in locs:
                if lang == "ru":
                    continue  # исходный язык: значение = ключ
                errors.append(f"{name}: {key!r}: нет {lang}")
                continue
            check_loc(f"{name}: {key!r} [{lang}]", locs[lang], key, lang)
        extra = set(locs) - set(LANGS)
        if extra:
            warns.append(f"{name}: {key!r}: лишние языки {sorted(extra)}")
    return cat.get("strings", {})


def main():
    show_interp = "--interp" in sys.argv
    only = set((arg("--files") or "").split(",")) - {""}
    strings = load_catalog("Localizable.xcstrings", path=arg("--catalog"))
    if not only:
        load_catalog("InfoPlist.xcstrings")
    by_norm = {}
    for k in strings:
        by_norm.setdefault(norm_key(k), []).append(k)
    used = set()
    interp_rows = []
    app = os.path.join(ROOT, "App")
    n_loc = 0
    for fn in sorted(os.listdir(app)):
        if not fn.endswith(".swift") or fn in SKIP_FILES or (only and fn not in only):
            continue
        src = open(os.path.join(app, fn), encoding="utf-8").read()
        lines = src.split("\n")
        for lit in lex(src):
            if not lit.has_cyr():
                continue
            line = lines[lit.line - 1]
            if "i18n: no" in line:
                continue
            if not localized(src, lit):
                warns.append(f"НЕ ЛОКАЛИЗОВАНО {fn}:{lit.line}: {lit.raw[:110]}")
                continue
            n_loc += 1
            nk = lit.text()
            hits = by_norm.get(nk)
            if not hits:
                errors.append(f"НЕТ В КАТАЛОГЕ {fn}:{lit.line}: {nk!r}")
                continue
            used.update(hits)
            exprs = [p[1] for p in lit.parts if not isinstance(p, str)]
            if exprs:
                interp_rows.append(f"{fn}:{lit.line}: {hits[0]!r}  ←  {exprs}")
    for k in ([] if only else strings):
        if k not in used and re.search(r"[А-Яа-яЁё]", k):
            warns.append(f"не найден в коде: {k!r}")
    if show_interp:
        print("== строки с подстановками ==")
        print("\n".join(interp_rows))
    for w in warns:
        print("WARN", w)
    for e in errors:
        print("ERR ", e)
    print(f"ключей в каталоге: {len(strings)}, локализуемых русских литералов в коде: {n_loc}, "
          f"ошибок: {len(errors)}, предупреждений: {len(warns)}")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
