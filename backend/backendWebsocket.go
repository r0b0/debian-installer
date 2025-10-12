package main

/*
Opinionated Debian Installer
Copyright (C) 2022-2025 Robert T.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

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
