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
	"fmt"
	"golang.org/x/net/websocket"
	"io"
	"net/http"
	"net/url"
)

func loginToBackend(baseUrl *url.URL) (Model, error) {
	client := http.Client{}
	resp, err := client.Get(baseUrl.JoinPath("login").String())
	if err != nil {
		return Model{}, err
	}
	defer resp.Body.Close()
	return parseLoginJson(resp.Body)
}

func getAvailableDrives(baseUrl *url.URL) ([]string, []string, error) {
	client := http.Client{}
	resp, err := client.Get(baseUrl.JoinPath("block_devices").String())
	if err != nil {
		return []string{}, []string{}, err
	}
	defer resp.Body.Close()
	devices, err := parseLsblkJson(resp.Body)
	if err != nil {
		return []string{}, []string{}, err
	}
	var drives []string
	var driveDescriptions []string
	for _, device := range devices.Blockdevices {
		drives = append(drives, device.Path)
		driveDescription := fmt.Sprintf("%s %s (%s)", device.Path, device.Model, device.Size)
		driveDescriptions = append(driveDescriptions, driveDescription)
	}
	return drives, driveDescriptions, nil
}

func processOutput(baseUrl *url.URL, log io.Writer) {
	origin := "http://localhost/"
	wsUrl := baseUrl.JoinPath("process_output")
	wsUrl.Scheme = "ws"
	ws, err := websocket.Dial(wsUrl.String(), "", origin)
	if err != nil {
		LOG(log, "Failed to connect to web socket: %v", err)
		return
	}
	go func() {
		_, err := io.Copy(log, ws)
		if err != nil {
			LOG(log, "Error reading websocket: %v", err)
		}
		LOG(log, "Finished")
	}()
}

func (m *Model) startInstallation(baseUrl *url.URL, log io.Writer) error {
	post := url.Values{}

	post.Set("DISK", m.Disk)
	post.Set("DEBIAN_VERSION", m.DebianVersion)
	post.Set("USERNAME", m.Username)
	post.Set("USER_FULL_NAME", m.UserFullName)
	post.Set("USER_PASSWORD", m.UserPassword)
	post.Set("ROOT_PASSWORD", m.UserPassword)
	post.Set("DISABLE_LUKS", m.DisableLuks)
	post.Set("LUKS_PASSWORD", m.LuksPassword)
	post.Set("ENABLE_MOK_SIGNED_UKI", m.EnableMokUki)
	post.Set("MOK_ENROLL_PASSWORD", m.MokPassword)
	post.Set("ENABLE_TPM", m.EnableTpm)
	post.Set("HOSTNAME", m.Hostname)
	post.Set("TIMEZONE", m.Timezone)
	post.Set("SWAP_SIZE", m.SwapSize)
	post.Set("NVIDIA_PACKAGE", m.NvidiaPackage)
	post.Set("ENABLE_FLATHUB", m.EnableFlathub)
	post.Set("ENABLE_POPCON", m.EnablePopcon)
	client := http.Client{}
	resp, err := client.PostForm(baseUrl.JoinPath("install").String(), post)
	if err != nil {
		LOG(log, "Error posting form: %v", err)
		return err
	}
	defer resp.Body.Close()
	LOG(log, "Post status: %s", resp.Status)
	return nil
}

func stop(baseUrl *url.URL) error {
	client := http.Client{}
	resp, err := client.Get(baseUrl.JoinPath("clear").String())
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}
