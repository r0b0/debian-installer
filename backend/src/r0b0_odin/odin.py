import secrets
import socket
import string
import subprocess

import flask
from flask import Flask, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)
backend_pin = ''.join(secrets.choice(string.digits) for i in range(5))
print(f"BACKEND PIN: {backend_pin}")


@app.route("/login")
def login():
    _check_login()
    hostname = socket.gethostname()
    return {"address": hostname}


@app.route("/block_devices")
def get_block_devices():
    _check_login()
    p = subprocess.run(["lsblk", "-OJ"], capture_output=True)
    return p.stdout


def _check_login():
    if request.args.get("pin", None) == backend_pin:
        return True
    flask.abort(403, "Not logged in")

tasks = {
    "efi-part-uuid": {
        "command": {
            "args": ["uuidgen > efi-part.uuid"],
            "shell": True
        }
    },
    "luks-part-uuid": {
        "command": {
            "args": ["uuidgen > luks-part.uuid"],
            "shell": True
        }
    },

}

