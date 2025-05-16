package main

import (
	"bytes"
	"log/slog"
	"net/http"
	"os"
	"strings"
)

func (c *BackendContext) Login(w http.ResponseWriter, _ *http.Request) {
	type login struct {
		Hostname  string            `json:"hostname"`
		HasEfi    bool              `json:"has_efi"`
		HasNvidia bool              `json:"has_nvidia"`
		Running   bool              `json:"running"`
		Environ   map[string]string `json:"environ"`
	}
	data := login{}
	var err error
	data.Hostname, err = os.Hostname()
	if err != nil {
		slog.Error("failed to detect hostname", "error", err)
		http.Error(w, "failed to detect hostname", 500)
		return
	}
	_, err = os.Stat("/sys/firmware/efi")
	if err == nil {
		data.HasEfi = true
	} else if os.IsNotExist(err) {
		data.HasEfi = false
	} else {
		slog.Error("failed to detect efi", "error", err)
		http.Error(w, "failed to detect efi", 500)
		return
	}
	data.HasNvidia = detectNvidia()
	data.Running = c.runningCmd != nil && c.runningCmd.Process != nil
	data.Environ = c.runningParameters
	err = writeJson(w, data)
	if err != nil {
		slog.Error("failed to write data", "error", err)
		http.Error(w, "failed to write data", 500)
		return
	}
}

func detectNvidia() bool {
	out, err := runAndGiveStdout("nvidia-detect")
	if err != nil {
		slog.Warn("failed to run nvidia-detect, assuming no nvidia", "error", err)
		return false
	}
	outString := string(out)
	if strings.Contains(outString, "No NVIDIA GPU detected") {
		return false
	}
	if strings.Contains(outString, "nvidia-driver") {
		return true
	}
	return false
}

func (c *BackendContext) GetBlockDevices(w http.ResponseWriter, _ *http.Request) {
	out, err := runAndGiveStdout("lsblk", "-OJ")
	if err != nil {
		slog.Error("failed to execute lsblk", "error", err)
		http.Error(w, "failed to execute lsblk", 500)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_, err = w.Write(out)
	if err != nil {
		slog.Error("failed to send output", "error", err)
		return
	}
}

func (c *BackendContext) Install(w http.ResponseWriter, r *http.Request) {
	if c.runningCmd != nil {
		slog.Error("already running")
		http.Error(w, "already running", 409)
		return
	}
	err := r.ParseMultipartForm(1024 * 1024)
	if err != nil {
		slog.Error("failed to parse form", "error", err)
		http.Error(w, "failed to parse form", 400)
		return
	}
	slog.Debug("Install button pressed")
	for k, v := range r.Form {
		slog.Debug(" form value", "key", k, "value", v[0])
		c.runningParameters[k] = v[0]
	}
	c.doRunInstall()
}

func (c *BackendContext) ProcessStatus(w http.ResponseWriter, _ *http.Request) {
	type status struct {
		Status     string `json:"status"`
		Output     string `json:"output"`
		ReturnCode int    `json:"return_code"`
		Command    string `json:"command"`
	}
	s := status{
		Status:     "RUNNING",
		Output:     c.cmdOutput.String(),
		ReturnCode: -1,
		Command:    "",
	}
	if c.runningCmd == nil || c.runningCmd.Process == nil {
		http.Error(w, "no running process", 404)
		return
	}
	if c.runningCmd.ProcessState != nil {
		s.Status = "FINISHED"
		s.ReturnCode = c.runningCmd.ProcessState.ExitCode()
		s.Command = strings.Join(c.runningCmd.Args, " ")
	}

	err := writeJson(w, s)
	if err != nil {
		slog.Error("failed to write data", "error", err)
		http.Error(w, "failed to write data", 500)
		return
	}
}

func (c *BackendContext) DownloadLog(w http.ResponseWriter, _ *http.Request) {
	w.Header().Add("Content-Type", "text/plain;charset=UTF-8")
	w.Header().Add("Content-Disposition", "attachment;filename=installer.log")
	_, err := w.Write(c.cmdOutput.Bytes())
	if err != nil {
		slog.Error("failed to write data", "error", err)
		return
	}
}

func (c *BackendContext) Clear(w http.ResponseWriter, _ *http.Request) {
	if c.runningCmd == nil || c.runningCmd.Process == nil {
		return
	}
	if c.runningCmd.ProcessState != nil {
		// already finished, clear
		c.runningCmd = nil
		c.cmdOutput = bytes.Buffer{}
		return
	}
	err := c.runningCmd.Cancel()
	if err != nil {
		slog.Error("failed to stop the process", "error", err)
		http.Error(w, "failed to stop the process", 500)
	}
}
