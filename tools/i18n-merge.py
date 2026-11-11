#!/usr/bin/env python3
"""Добавить/обновить строки в String Catalog из простого JSON (без Xcode).

  python3 tools/i18n-merge.py new-strings.json [App/Localizable.xcstrings]

new-strings.json — список объектов:
  {"key": "Удалить", "ru": "Удалить", "en": "Delete", "de": "Löschen", ..., "comment": "необязательно"}
Значение языка:
  - строка — обычный перевод;
  - {"one": "...", "few": "...", "many": "...", "other": "..."} — plural (ru/pl: one/few/many/other, остальные one/other);
    ключ должен содержать ровно ОДНУ подстановку (%lld);
  - {"value": "В «%1$@»: %#@n@", "subs": {"n": {"argNum": 2, "spec": "lld", "one": "%arg клиент", ...}}}
    — plural для строки с несколькими подстановками.
Ключ = текст литерала из кода, где \\(x) заменён на %@ (String), %lld (Int), %lf (Double); «%» → «%%».
"ru" можно не указывать, если перевод = ключ и plural не нужен.
После слияния — python3 tools/check-xcstrings.py.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["ru", "en", "de", "fr", "es", "pt", "it", "pl"]
CATS = ["zero", "one", "two", "few", "many", "other"]


def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}


def loc(v):
    if isinstance(v, str):
        return unit(v)
    if "subs" in v:
        subs = {}
        for name, s in v["subs"].items():
            subs[name] = {
                "argNum": s["argNum"],
                "formatSpecifier": s.get("spec", "lld"),
                "variations": {"plural": {c: unit(s[c]) for c in CATS if c in s}},
            }
        return {"stringUnit": {"state": "translated", "value": v["value"]}, "substitutions": subs}
    return {"variations": {"plural": {c: unit(v[c]) for c in CATS if c in v}}}


def main():
    src = sys.argv[1]
    cat_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "App", "Localizable.xcstrings")
    if os.path.exists(cat_path):
        cat = json.load(open(cat_path, encoding="utf-8"))
    else:
        cat = {"sourceLanguage": "ru", "strings": {}, "version": "1.0"}
    items = json.load(open(src, encoding="utf-8"))
    added = updated = 0
    for it in items:
        key = it["key"]
        ent = cat["strings"].get(key)
        if ent is None:
            ent = {}
            added += 1
        else:
            updated += 1
        if it.get("comment"):
            ent["comment"] = it["comment"]
        locs = ent.setdefault("localizations", {})
        for lang in LANGS:
            if lang in it:
                locs[lang] = loc(it[lang])
            elif lang == "ru" and "ru" not in locs:
                locs["ru"] = unit(key)
        ent["localizations"] = {k: locs[k] for k in sorted(locs)}
        cat["strings"][key] = ent
    cat["strings"] = {k: cat["strings"][k] for k in sorted(cat["strings"])}
    with open(cat_path, "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, indent=2, separators=(",", " : "))
        f.write("\n")
    print(f"{cat_path}: добавлено {added}, обновлено {updated}, всего {len(cat['strings'])}")


if __name__ == "__main__":
    main()
