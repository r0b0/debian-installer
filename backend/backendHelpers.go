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
