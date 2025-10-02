package main

import (
	"encoding/json"
	"net/http"
	"os/exec"
)

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
