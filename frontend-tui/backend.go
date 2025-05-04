package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"

	"golang.org/x/net/websocket"
)

type BackendContext struct {
	runningCmd        *exec.Cmd
	runningParameters []string
	cmdOutput         string
	outputReaders     []io.Reader
}

func HandleCors(pattern string, next func(w http.ResponseWriter, r *http.Request)) {
	http.HandleFunc(pattern, func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Access-Control-Allow-Origin", "*")
		writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
		writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With")
		next(writer, request)
	})
}

func writeJson(w http.ResponseWriter, data any) error {
	jData, err := json.Marshal(data)
	if err != nil {
		return err
	}
	w.Header().Set("Content-Type", "application/json")
	_, err = w.Write(jData)
	return err
}

func httpError(w http.ResponseWriter, code int, message string, args ...any) {
	slog.Error(message, args)
	http.Error(w, message, code)
}

func (c *BackendContext) Login(w http.ResponseWriter, r *http.Request) {
	type login struct {
		Hostname  string   `json:"hostname"`
		HasEfi    bool     `json:"has_efi"`
		HasNvidia bool     `json:"has_nvidia"`
		Running   bool     `json:"running"`
		Environ   []string `json:"environ"`
	}
	data := login{}
	var err error
	data.Hostname, err = os.Hostname()
	if err != nil {
		httpError(w, 500, "failed to detect hostname", "error", err)
		return
	}
	_, err = os.Stat("/sys/firmware/efi")
	if err == nil {
		data.HasEfi = true
	} else if os.IsNotExist(err) {
		data.HasEfi = false
	} else {
		httpError(w, 500, "failed to detect efi", "error", err)
		return
	}
	data.HasNvidia = false // TODO
	data.Running = c.runningCmd.Process != nil
	data.Environ = c.runningParameters
	err = writeJson(w, data)
	if err != nil {
		httpError(w, 500, "failed to write data", "error", err)
		return
	}
}

func (c *BackendContext) GetBlockDevices(w http.ResponseWriter, r *http.Request) {
	// TODO
	http.Error(w, "not implemented", 501)
}

func (c *BackendContext) Install(w http.ResponseWriter, r *http.Request) {
	// TODO
	http.Error(w, "not implemented", 501)
}

func (c *BackendContext) Clear(w http.ResponseWriter, r *http.Request) {
	// TODO
	http.Error(w, "not implemented", 501)
}

func (c *BackendContext) ProcessStatus(w http.ResponseWriter, r *http.Request) {
	// TODO
	http.Error(w, "not implemented", 501)
}

func (c *BackendContext) DownloadLog(w http.ResponseWriter, r *http.Request) {
	// TODO
	http.Error(w, "not implemented", 501)
}

func (c *BackendContext) GetProcessOutput(ws *websocket.Conn) {
	fmt.Fprintf(ws, "not implemented")
}

func Backend(listenAddr *string) {
	app := BackendContext{
		runningCmd:        exec.Command(os.Getenv("INSTALLER_SCRIPT")),
		runningParameters: os.Environ(),
		cmdOutput:         "",
		outputReaders:     make([]io.Reader, 0),
	}
	HandleCors("/login", app.Login)
	HandleCors("/block_devices", app.GetBlockDevices)
	HandleCors("/install", app.Install)
	HandleCors("/clear", app.Clear)
	HandleCors("/process_status", app.ProcessStatus)
	HandleCors("/download_log", app.DownloadLog)
	http.Handle("/process_output", websocket.Handler(app.GetProcessOutput))
	slog.Info("Starting backend http server", "listenAddr", *listenAddr)
	err := http.ListenAndServe(*listenAddr, nil)
	if errors.Is(err, http.ErrServerClosed) {
		slog.Info("Server closed")
	} else {
		slog.Error("Failed to start server", "error", err)
		os.Exit(1)
	}
}
