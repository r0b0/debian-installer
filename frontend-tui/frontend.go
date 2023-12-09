package main

import (
	"encoding/json"
	"fmt"
	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
	"golang.org/x/net/websocket"
	"io"
	"net/http"
	"net/url"
	"strconv"
)

func LOG(l io.Writer, format string, args ...any) {
	_, _ = l.Write([]byte(fmt.Sprintf(format+"\n", args...)))
}

var SwapOptions = map[string]int{
	"None":      0,
	"File":      1,
	"Partition": 2,
}

type Model struct {
	Disk          string `json:"DISK"`
	DebianVersion string `json:"DEBIAN_VERSION"`
	Username      string `json:"USERNAME"`
	UserFullName  string `json:"USER_FULL_NAME"`
	UserPassword  string `json:"USER_PASSWORD"`
	RootPassword  string `json:"ROOT_PASSWORD"`
	LuksPassword  string `json:"LUKS_PASSWORD"`
	Hostname      string `json:"HOSTNAME"`
	Timezone      string `json:"TIMEZONE"`
	EnableSwap    string `json:"ENABLE_SWAP"`
	SwapSize      string `json:"SWAP_SIZE"`
}
type LoginResp struct {
	Environ  Model  `json:"environ"`
	HasEfi   bool   `json:"has_efi"`
	Hostname string `json:"hostname"`
}

func parseLoginJson(data io.Reader) (Model, error) {
	var login LoginResp
	err := json.NewDecoder(data).Decode(&login)
	if err != nil {
		return Model{}, err
	}
	return login.Environ, nil
}
func loginToBackend() (Model, error) {
	client := http.Client{}
	res, err := client.Get("http://localhost:5000/login")
	if err != nil {
		return Model{}, err
	}
	defer res.Body.Close()
	return parseLoginJson(res.Body)
}

type BlockDevice struct {
	Path  string `json:"path"`
	Model string `json:"Model"`
	Size  string `json:"size"`
}
type LsblkResp struct {
	Blockdevices []BlockDevice `json:"blockdevices"`
}

func parseLsblkJson(data io.Reader) (LsblkResp, error) {
	var devices LsblkResp
	err := json.NewDecoder(data).Decode(&devices)
	if err != nil {
		return LsblkResp{}, err
	}
	return devices, nil
}
func getAvailableDrives() ([]string, []string, error) {
	client := http.Client{}
	res, err := client.Get("http://localhost:5000/block_devices")
	if err != nil {
		return []string{}, []string{}, err
	}
	defer res.Body.Close()
	devices, err := parseLsblkJson(res.Body)
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

func processOutput(wsUrl string, log io.Writer) {
	origin := "http://localhost/"
	ws, err := websocket.Dial(wsUrl, "", origin)
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

func (m *Model) startInstallation(log io.Writer) error {
	post := url.Values{}

	post.Set("DISK", m.Disk)
	post.Set("DEBIAN_VERSION", m.DebianVersion)
	post.Set("USERNAME", m.Username)
	post.Set("USER_FULL_NAME", m.UserFullName)
	post.Set("USER_PASSWORD", m.UserPassword)
	post.Set("ROOT_PASSWORD", m.UserPassword)
	post.Set("LUKS_PASSWORD", m.LuksPassword)
	post.Set("HOSTNAME", m.Hostname)
	post.Set("TIMEZONE", m.Timezone)
	post.Set("ENABLE_SWAP", m.EnableSwap)
	post.Set("SWAP_SIZE", m.SwapSize)
	client := http.Client{}
	resp, err := client.PostForm("http://localhost:5000/install", post)
	if err != nil {
		LOG(log, "Error posting form: %v", err)
		return err
	}
	LOG(log, "Post status: %s", resp.Status)
	return nil
}

func main() {
	devices, deviceNames, err := getAvailableDrives()
	if err != nil {
		panic(fmt.Sprintf("Failed to get available drives from back-end: %v", err))
	}

	m, err := loginToBackend()
	if err != nil {
		panic(fmt.Sprintf("Failed to get configuration from back-end: %v", err))
	}

	greenColour := tcell.NewRGBColor(0x08, 0x69, 0x6b)

	app := tview.NewApplication()
	logView := tview.NewTextView().
		SetScrollable(true).
		ScrollToEnd().
		SetLabel("Log").
		SetChangedFunc(func() {
			app.Draw()
		})

	var SwapOptionKeys []string
	for k := range SwapOptions {
		SwapOptionKeys = append(SwapOptionKeys, k)
	}
	form := tview.NewForm().
		AddDropDown("Installation Target Device", deviceNames, 0, func(_ string, optionIndex int) {
			m.Disk = devices[optionIndex]
		}).
		AddPasswordField("Disk Encryption Passphrase", m.LuksPassword, 0, '*', func(text string) {
			m.LuksPassword = text
		}). // TODO second time
		AddPasswordField("Root Password", m.RootPassword, 0, '*', func(text string) {
			m.RootPassword = text
		}).
		AddInputField("Regular User Name", m.Username, 0, nil, func(text string) {
			m.Username = text
		}).
		AddInputField("Full Name", m.UserFullName, 0, nil, func(text string) {
			m.UserFullName = text
		}).
		AddPasswordField("Regular User Password", m.UserPassword, 0, '*', func(text string) {
			m.UserPassword = text
		}).
		AddInputField("Hostname", m.Hostname, 0, nil, func(text string) {
			m.Hostname = text
		}).
		AddInputField("Time Zone", m.Timezone, 0, nil, func(text string) {
			m.Timezone = text // TODO dropdown
		}).
		AddDropDown("Enable Swap", SwapOptionKeys, SwapOptions[m.EnableSwap], func(option string, optionIndex int) {
			m.EnableSwap = option  // XXX this is broken, debug this
		}).
		AddInputField("Swap Size", m.SwapSize, 0, func(textToCheck string, lastChar rune) bool {
			_, err := strconv.Atoi(textToCheck)
			return err == nil
		}, func(text string) {
			m.SwapSize = text
		}).
		AddButton("Install OVERWRITING THE WHOLE DRIVE", func() {
			err := m.startInstallation(logView)
			if err != nil {
				LOG(logView, "Failed to start installation: %v", err)
			}
		}).
		AddFormItem(logView)
	form.SetBorder(true).
		SetTitle("Opinionated Debian Installer").
		SetTitleColor(greenColour).
		SetTitleAlign(tview.AlignCenter)

	processOutput("ws://localhost:5000/process_output", logView)

	if err := app.SetRoot(form, true).EnableMouse(true).Run(); err != nil {
		panic(err)
	}
}
