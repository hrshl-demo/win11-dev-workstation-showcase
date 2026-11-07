"""Quick flow: the quick pages never carry their own copy of a command.

A code block of a quick step is either written inline (label, lang, actor, text) or named by {"ref": "<block id>"}; sources.resolve_page() has
already replaced every ref by the one definition before the page is rendered or checked.
"""


def step_codes(step):
    """The code blocks of a quick step, in order (already resolved)."""
    refs = list(step.get("codes") or [])
    if step.get("code"):
        refs.insert(0, step["code"])
    return refs


def texts(d):
    """The text of every code block of a quick page (for the check that the generated page equals its sources)."""
    out = []
    for s in d.get("steps", []) or []:
        out.extend(c["text"] for c in step_codes(s))
    return out
