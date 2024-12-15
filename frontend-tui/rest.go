package main

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
	}
	go func() {
		for {
			_, err := io.Copy(log, ws)
			if err != nil {
				LOG(log, "Error reading websocket: %v", err)
				return
			}
		}
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
	post.Set("LUKS_PASSWORD", m.LuksPassword)
	post.Set("ENABLE_TPM", boolString(m.EnableTpm))
	post.Set("HOSTNAME", m.Hostname)
	post.Set("TIMEZONE", m.Timezone)
	post.Set("ENABLE_SWAP", m.EnableSwap)
	post.Set("SWAP_SIZE", m.SwapSize)
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

func boolString(i bool) string {
	if i {
		return "true"
	} else {
		return "false"
	}
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
