import secrets
import socket
import string
import subprocess
import tempfile
import uuid

import flask
from flask import Flask, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)
backend_pin = ''.join(secrets.choice(string.digits) for i in range(5))
subprocesses = {}
print(f"BACKEND PIN: {backend_pin}")

context = {
    "top_disk_device": None,
    "efi_partition_uuid": None,
    "luks_partition_uuid": None,
    "luks_keyfile": None,
    "luks_crypt_uuid_file": None,
    "target": "/target",
    "luks_device": "luksroot",
    "root_device": "/dev/mapper/luksroot",
}


@app.route("/login", methods=["GET"])
def login():
    hostname = socket.gethostname()
    subprocess_key = _create_subprocess("10_install_required_packages_on_host.sh")
    return {"subprocess_key": subprocess_key, "hostname": hostname}


@app.route("/block_devices", methods=["GET"])
def get_block_devices():
    p = subprocess.run(["lsblk", "-OJ"], capture_output=True)
    return p.stdout


@app.route("/install", methods=["GET"])
def install_on_device():
    device_path = request.args.get("device_path", None)
    app.logger.info(f"Installing debian on device {device_path}")
    context["top_disk_device"] = device_path
    for partition in ("efi_partition_uuid", "luks_partition_uuid"):
        if context[partition] is None:
            context[partition] = uuid.UUID
    if context["luks_keyfile"] is None:
        context["luks_keyfile"] = tempfile.NamedTemporaryFile(prefix="luks", suffix=".key", delete=False).name
    if context["luks_crypt_uuid_file"] is None:
        context["luks_crypt_uuid_file"] = tempfile.NamedTemporaryFile(prefix="luks", suffix=".uuid", delete=False).name
    subprocess_key = _create_subprocess("20_partition_and_install.sh")
    return {"subprocess_key": subprocess_key}


@app.route("/process_status/<key>", methods=["GET"])
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
    status["output"] = sp.stdout.read()
    status["error"] = sp.stderr.read()
    status["return_code"] = sp.returncode
    return status


@app.before_request
def check_login():
    if request.method == "OPTIONS":
        return None
    if "password" not in request.authorization:
        flask.abort(401, "Not logged in")
    if request.authorization.password == backend_pin:
        return None
    flask.abort(401, "Not logged in")


def _create_subprocess(script):
    env = {}
    for k, v in context.items():
        if k is not None and v is not None:
            env[k] = str(v)
    sp = subprocess.Popen(f"scripts/{script}",  # TODO fixup the full path
                          env=env, text=True,
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
    key = secrets.token_urlsafe()
    subprocesses[key] = sp
    return key
