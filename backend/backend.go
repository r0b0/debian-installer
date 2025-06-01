package main

import (
	"bytes"
	"errors"
	"fmt"
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

	http.HandleFunc("/login", app.Login)
	http.HandleFunc("/block_devices", app.GetBlockDevices)
	http.HandleFunc("/install", app.Install)
	http.HandleFunc("/clear", app.Clear)
	http.HandleFunc("/process_status", app.ProcessStatus)
	http.HandleFunc("/download_log", app.DownloadLog)
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
