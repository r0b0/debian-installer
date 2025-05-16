package main

import (
	"github.com/google/uuid"
	"golang.org/x/net/websocket"
	"log/slog"
)

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
