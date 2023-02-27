import json
import pathlib
import os
import secrets
import socket
import string
import subprocess
import tempfile
import threading
import uuid

import flask
from flask import Flask, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)
subprocesses = {}
threads = {}
FIFO_PATH = "/tmp/installer_pipe"
if not os.path.exists(FIFO_PATH):
    subprocess_fifo = os.mkfifo(FIFO_PATH)
fifo_fd = open(FIFO_PATH, "w")


@app.route("/login", methods=["GET"])
def login():
    hostname = socket.gethostname()
    return {"hostname": hostname}


@app.route("/block_devices", methods=["GET"])
def get_block_devices():
    p = subprocess.run(["lsblk", "-OJ"], capture_output=True, text=True)
    return p.stdout


@app.route("/timezones", methods=["GET"])
def get_timezones():
    timezones = []
    with open("timezones.txt") as fd:
        while True:
            l = fd.readline()
            if l.startswith("#"):
                continue
            if not l:
                break
            timezones.append(l.strip())
    return {"timezones": timezones}


@app.route("/install", methods=["POST"])
def install():
    subprocess_env = {}
    for k, v in request.form.items():
        subprocess_env[k] = v
        app.logger.info(f"  env: {k} = {v}")
    # TODO separate thread for subprocess
    # TODO already running?
    sp = subprocess.Popen("./installer.sh", env=subprocess_env, text=True, stdout=fifo_fd, stderr=fifo_fd)
    key = secrets.token_urlsafe()
    subprocesses[key] = sp
    return {"subprocess_key": key}


#def do_install_on_device(device_path):
    #app.logger.info(f"Installing debian on device {device_path}")
    #context["top_disk_device"] = device_path
    #subprocess_key = _create_subprocess("20_partitions.sh")
    #return {"subprocess_key": subprocess_key}


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
