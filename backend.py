import secrets
import socket
import subprocess
import threading
import time

import flask
from flask import Flask, request
from flask_cors import CORS
from flask_sock import Sock
from simple_websocket import ConnectionClosed

app = Flask(__name__)
sock = Sock(app)
CORS(app)
running_subprocess = None
subprocess_output = ""
output_readers = []
INSTALLER_SCRIPT = "./installer.sh"


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
            line = fd.readline()
            if line.startswith("#"):
                continue
            if not line:
                break
            timezones.append(line.strip())
    return {"timezones": timezones}


@app.route("/install", methods=["POST"])
def install():
    global running_subprocess
    if running_subprocess is not None:
        app.logger.error("Process already running")
        flask.abort(409, "Already running")

    subprocess_env = {"NON_INTERACTIVE": "yes"}
    for k, v in request.form.items():
        subprocess_env[k] = v
        app.logger.info(f"  env: {k} = {v}")

    running_subprocess = subprocess.Popen(INSTALLER_SCRIPT,
                                          env=subprocess_env,
                                          text=True,
                                          stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE)
    def output_reader(fd, main):
        app.logger.info("Starting output reader thread")
        global subprocess_output
        for line in fd:
            print(line, end="")
            to_remove = []
            for websocket in output_readers:
                try:
                    websocket.send(line)
                except ConnectionClosed as e:
                    to_remove.append(websocket)
            for websocket in to_remove:
                app.logger.info(f"Removing websocket output reader {websocket}")
                output_readers.remove(websocket)
            subprocess_output += line
        app.logger.info("Output reader thread finished")
        if main:
            for websocket in output_readers:
                websocket.close()

    threading.Thread(target=output_reader,
                     args=(running_subprocess.stdout, True),
                     name="Stdout reader")\
        .start()
    threading.Thread(target=output_reader,
                     args=(running_subprocess.stderr, False),
                     name="Stderr reader")\
        .start()
    return {}


@app.route("/clear", methods=["GET"])
def clear():
    global running_subprocess
    if running_subprocess is None:
        return {}
    if running_subprocess.poll() is None:
        # still running
        running_subprocess.terminate()
        return {}
    running_subprocess = None
    return {}


@app.route("/process_status", methods=["GET"])
def get_process_status():
    status = {"status": "RUNNING",
              "output": subprocess_output,
              "return_code": -1}
    if running_subprocess is None:
        app.logger.error(f"No subprocess")
        flask.abort(404, "No such process")
    return_code = running_subprocess.poll()
    if return_code is None:
        return status
    status["command"] = running_subprocess.args
    status["status"] = "FINISHED"
    status["return_code"] = running_subprocess.returncode
    return status


@sock.route("/process_output")
def get_process_output(ws):
    global output_readers
    app.logger.info("Websocket connected")
    ws.send(subprocess_output)
    output_readers.append(ws)
    while ws in output_readers:
        time.sleep(60)
    app.logger.info("Websocket closing")
