import json
import os


def receivers():
    for entry in json.loads(os.environ.get("FAKE_SOLAAR", "[]")):
        yield entry
