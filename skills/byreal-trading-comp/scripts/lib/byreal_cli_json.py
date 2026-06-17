import json


def iter_json_objects(raw):
    depth = 0
    buf = []
    in_string = False
    escaped = False

    for ch in raw:
        if depth > 0:
            buf.append(ch)

        if depth == 0:
            if ch == "{":
                buf = ["{"]
                depth = 1
            continue

        if escaped:
            escaped = False
            continue

        if ch == "\\" and in_string:
            escaped = True
            continue

        if ch == '"':
            in_string = not in_string
            continue

        if in_string:
            continue

        if ch == "{":
            depth += 1
            continue

        if ch == "}" and depth > 0:
            depth -= 1
            if depth == 0 and buf:
                yield "".join(buf)
                buf = []


def extract_success_object(raw):
    for candidate in iter_json_objects(raw):
        try:
            obj = json.loads(candidate)
        except Exception:
            continue
        if isinstance(obj, dict) and "success" in obj:
            return obj
    return None


def extract_success_object_from_file(path):
    with open(path) as f:
        return extract_success_object(f.read())
