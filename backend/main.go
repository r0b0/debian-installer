package main

import (
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
)

func main() {
	tuiCmd := flag.NewFlagSet("tui", flag.ExitOnError)
	tuiBaseUrlString := tuiCmd.String("baseUrl", "http://localhost:5000", "base URL of the web service")

	backendCmd := flag.NewFlagSet("backend", flag.ExitOnError)
	backendPort := backendCmd.Int("listenPort", 5000, "listen tcp port for the web server")
	backendStatic := backendCmd.String("staticHtmlFolder", "/var/www/html/opinionated-debian-installer/", "folder with static html content")

	if len(os.Args) < 2 {
		fmt.Println("expected 'tui' or 'backend' subcommands")
		os.Exit(1)
	}

	switch os.Args[1] {
	case "tui":
		err := tuiCmd.Parse(os.Args[2:])
		if errors.Is(err, flag.ErrHelp) {
			flag.Usage()
			os.Exit(0)
		}
		Tui(tuiBaseUrlString)
		return

	case "backend":
		err := backendCmd.Parse(os.Args[2:])
		if errors.Is(err, flag.ErrHelp) {
			flag.Usage()
			os.Exit(0)
		}
		Backend(backendPort, backendStatic)
		return

	default:
		flag.Usage()
		os.Exit(3)
	}
}

func SystemdNotifyReady() error {
	socketName := os.Getenv("NOTIFY_SOCKET")
	if socketName == "" {
		return nil
	}
	systemdSocket := &net.UnixAddr{
		Name: socketName,
		Net:  "unixgram",
	}
	message := "READY=1"
	conn, err := net.DialUnix(systemdSocket.Net, nil, systemdSocket)
	if err != nil {
		return err
	}
	defer conn.Close()
	if _, err = conn.Write([]byte(message)); err != nil {
		return err
	}
	return nil
}
