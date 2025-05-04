package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
)

func main() {
	tuiCmd := flag.NewFlagSet("tui", flag.ExitOnError)
	tuiBaseUrlString := tuiCmd.String("baseUrl", "http://localhost:5000", "base URL of the web service")

	backendCmd := flag.NewFlagSet("backend", flag.ExitOnError)
	backendAddr := backendCmd.String("addr", "localhost:5000", "listen address for the web server")

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
		Backend(backendAddr)
		return

	default:
		flag.Usage()
		os.Exit(3)
	}
}
