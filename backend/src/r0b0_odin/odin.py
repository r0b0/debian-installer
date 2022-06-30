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
subprocesses = {}
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


@app.route("/install")
def install_on_device():
    _check_login()
    device_path = request.args.get("device_path", None)
    app.logger.info(f"Installing debian on device {device_path}")
    subprocess_key = _create_subprocess("partition_and_install", device_path=device_path)
    return {"subprocess_key": subprocess_key}


@app.route("/process_status/<key>")
def get_process_status(key):
    status = {"status": "RUNNING",
              "key": key,
              "output": "",
              "error": "",
              "return_code": -1}
    sp = subprocesses.get(key, None)
    if sp is None:
        app.logger.error(f"No subprocess with {key=}")
        flask.abort(404, "No such process")
    return_code = sp.poll()
    if return_code is None:
        return status
    status["status"] = "FINISHED"
    status["output"] = sp.stdout
    status["error"] = sp.stderr
    status["return_code"] = sp.returncode
    return status


def _check_login():
    if request.args.get("pin", None) == backend_pin:
        app.logger.warn("Deprecated pin request argument received")
        return True
    if request.authorization.password == backend_pin:
        return True
    flask.abort(403, "Not logged in")


def _create_subprocess(script, **kwargs):
    args = ["sleep", "30"]  # TODO
    sp = subprocess.Popen(args)
    key = secrets.token_urlsafe()
    subprocesses[key] = sp
    return key