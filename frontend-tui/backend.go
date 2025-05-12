package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"golang.org/x/net/context"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"strings"

	"golang.org/x/net/websocket"
)

type BackendContext struct {
	runningCmd        *exec.Cmd
	runningParameters map[string]string
	cmdOutput         bytes.Buffer
	websockets        map[string]*websocket.Conn
	wsHandlers        map[string]chan string
	ctx               context.Context
}

func HandleCors(pattern string, next func(w http.ResponseWriter, r *http.Request)) {
	// TODO no need for CORS now
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

func runAndGiveStdout(command ...string) ([]byte, error) {
	path, err := exec.LookPath(command[0])
	if err != nil {
		return nil, err
	}
	out, err := exec.Command(path, command[1:]...).Output()
	if err != nil {
		return nil, err
	}
	return out, nil
}

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
	// slog.Debug("install", "form", r.Form, "postform", r.PostForm)
	for k, v := range r.Form {
		// slog.Debug("form value", "key", k, "value", v)
		c.runningParameters[k] = v[0]
	}
	c.doRunInstall()
}

func (c *BackendContext) Write(p []byte) (int, error) {
	c.cmdOutput.Write(p)

	slog.Debug("writing a message to all web sockets", "data", p)
	for name, ws := range c.websockets {
		_, err := ws.Write(p)
		if err != nil {
			slog.Warn("failed to write to websocket, closing", "socket_addr", name, "error", err)
			c.closeWebSocket(name)
		}
	}
	return len(p), nil
}

func (c *BackendContext) closeWebSocket(name string) {
	done := c.wsHandlers[name]
	done <- name
	delete(c.websockets, name)
	delete(c.wsHandlers, name)
}

func (c *BackendContext) doRunInstall() {
	c.runningCmd = exec.CommandContext(c.ctx, os.Getenv("INSTALLER_SCRIPT"))
	c.runningCmd.Stderr = c
	c.runningCmd.Stdout = c
	for k, v := range c.runningParameters {
		c.runningCmd.Env = append(c.runningCmd.Env, fmt.Sprintf("%s=%s", k, v))
	}
	err := c.runningCmd.Start()
	if err != nil {
		slog.Error("failed to start the installer script", "error", err)
	}
	go c.waitForInstallerFinished()
}

func (c *BackendContext) waitForInstallerFinished() {
	slog.Debug("waiting for the installer to finish")
	err := c.runningCmd.Wait()
	if err != nil {
		slog.Error("command failed", "error", err)
	} else {
		slog.Info("command finished successfully")
	}
	for name := range c.websockets {
		// slog.Debug("closing websocket", "name", name)
		c.closeWebSocket(name)
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

func (c *BackendContext) GetProcessOutput(ws *websocket.Conn) {
	slog.Debug("new websocket connected", "addr", ws.RemoteAddr().String())
	_, err := ws.Write(c.cmdOutput.Bytes())
	if err != nil {
		slog.Warn("failed to write existing buffer to the new socket", "error", err)
		return
	}
	done := c.addWebsocket(ws)
	name := <-done
	slog.Debug("closing websocket connection", "name", name)
}

func (c *BackendContext) addWebsocket(ws *websocket.Conn) chan string {
	name := uuid.New().String()
	c.websockets[name] = ws
	n := make(chan string)
	c.wsHandlers[name] = n
	return n
}

func Backend(listenPort *int, staticPath *string) {
	slog.SetLogLoggerLevel(slog.LevelDebug)

	backendIp, found := os.LookupEnv("BACK_END_IP_ADDRESS")
	if !found {
		slog.Warn("environment variable BACK_END_IP_ADDRESS not found, using localhost")
		backendIp = "localhost"
	}

	app := BackendContext{
		runningCmd:        nil,
		runningParameters: map[string]string{"NON_INTERACTIVE": "yes"},
		cmdOutput:         bytes.Buffer{},
		websockets:        make(map[string]*websocket.Conn),
		wsHandlers:        make(map[string]chan string),
		ctx:               context.Background(),
	}

	for _, s := range os.Environ() {
		keyValue := strings.Split(s, "=")
		app.runningParameters[keyValue[0]] = keyValue[1]
	}

	HandleCors("/login", app.Login)
	HandleCors("/block_devices", app.GetBlockDevices)
	HandleCors("/install", app.Install)
	HandleCors("/clear", app.Clear)
	HandleCors("/process_status", app.ProcessStatus)
	HandleCors("/download_log", app.DownloadLog)
	http.Handle("/process_output", websocket.Handler(app.GetProcessOutput))
	http.Handle("/", http.FileServer(http.Dir(*staticPath)))

	autoInstall, found := os.LookupEnv("AUTO_INSTALL")
	if found && autoInstall == "true" {
		slog.Info("automatically starting the installation")
		app.doRunInstall()
	}

	err := SystemdNotifyReady()
	if err != nil {
		slog.Error("failed to notify systemd", "error", err)
	}

	slog.Info("Starting backend http server", "backendIp", backendIp, "port", *listenPort)
	err = http.ListenAndServe(fmt.Sprintf("%s:%d", backendIp, *listenPort), nil)
	if errors.Is(err, http.ErrServerClosed) {
		slog.Info("Server closed")
	} else {
		slog.Error("Failed to start server", "error", err)
		os.Exit(1)
	}
}
