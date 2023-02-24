import json
import pathlib
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
subprocesses = {}

context = {
    "top_disk_device": None,
    "efi_partition_uuid": uuid.UUID,
    "luks_partition_uuid": uuid.UUID,
    "luks_keyfile": tempfile.NamedTemporaryFile(prefix="luks", suffix=".key", delete=False).name,
    "luks_crypt_uuid_file": tempfile.NamedTemporaryFile(prefix="luks", suffix=".uuid", delete=False).name,
    "target": "/target",
    "luks_device": "luksroot",
    "root_device": "/dev/mapper/luksroot",
    "debian_version": "bullseye",
}


@app.route("/login", methods=["GET"])
def login():
    hostname = socket.gethostname()
    return {"hostname": hostname}


@app.route("/block_devices", methods=["GET"])
def get_block_devices():
    p = subprocess.run(["lsblk", "-OJ"], capture_output=True, text=True)
    return p.stdout


@app.route("/install", methods=["GET"])
def install_on_device():
    device_path = request.args.get("device_path", None)
    return do_install_on_device(device_path)


def do_install_on_device(device_path):
    app.logger.info(f"Installing debian on device {device_path}")
    context["top_disk_device"] = device_path
    subprocess_key = _create_subprocess("20_partitions.sh")
    return {"subprocess_key": subprocess_key}


@app.route("/available-tasksel-tasks", methods=["GET"])
def available_tasksel_tasks():
    command = ["tasksel", "--list-tasks"]
    tasks = []
    txt_output = subprocess.run(command, capture_output=True, text=True)
    for line in txt_output.stdout.splitlines():
        print(f"tasksel line: {line}")
        # merge spaces
        line = ' '.join(line.split())
        _, name, description = line.split(" ", 2)
        tasks.append({"name": name, "desc": description})
    return {"available_tasksel_tasks": tasks}


@app.route("/process_status/<key>", methods=["GET"])
def get_process_status(key):
    status = {"status": "RUNNING",
              "key": key,
              "output": "",
              "error": "",
              "return_code": -1}
    sp = subprocesses.get(key, None)
    app.logger.info(f"Subprocess {sp}")
    if sp is None:
        app.logger.error(f"No subprocess with {key=}")
        flask.abort(404, "No such process")
    return_code = sp.poll()
    if return_code is None:
        return status
    status["command"] = sp.args
    status["status"] = "FINISHED"
    status["output"] = sp.stdout.read()
    status["error"] = sp.stderr.read()
    status["return_code"] = sp.returncode
    return status


def _create_subprocess(script):
    scripts_dir = pathlib.Path(__file__).parent / "scripts"
    script_path = f"{scripts_dir}/{script}"
    app.logger.info(f"Starting script {script_path}")
    env = {}
    for k, v in context.items():
        if k is not None and v is not None:
            env[k] = str(v)
            app.logger.info(f"  env: {k} = {v}")
    sp = subprocess.Popen(script_path,
                          env=env, text=True,
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
    key = secrets.token_urlsafe()
    subprocesses[key] = sp
    return key
