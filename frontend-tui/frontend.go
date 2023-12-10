package main

import (
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
	"golang.org/x/net/websocket"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

func LOG(l io.Writer, format string, args ...any) {
	_, _ = l.Write([]byte(fmt.Sprintf(format+"\n", args...)))
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
	Running  bool   `json:"running"`
}

func parseLoginJson(data io.Reader) (Model, error) {
	var login LoginResp
	err := json.NewDecoder(data).Decode(&login)
	if err != nil {
		return Model{}, err
	}
	return login.Environ, nil
}
func loginToBackend(hostname string) (Model, error) {
	client := http.Client{}
	resp, err := client.Get("http://" + hostname + ":5000/login")
	if err != nil {
		return Model{}, err
	}
	defer resp.Body.Close()
	return parseLoginJson(resp.Body)
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
func getAvailableDrives(hostname string) ([]string, []string, error) {
	client := http.Client{}
	resp, err := client.Get("http://" + hostname + ":5000/block_devices")
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

func (m *Model) startInstallation(hostname string, log io.Writer) error {
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
	resp, err := client.PostForm("http://"+hostname+":5000/install", post)
	if err != nil {
		LOG(log, "Error posting form: %v", err)
		return err
	}
	defer resp.Body.Close()
	LOG(log, "Post status: %s", resp.Status)
	return nil
}

func stop(hostname string) error {
	client := http.Client{}
	resp, err := client.Get("http://" + hostname + ":5000/clear")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}

//go:embed timezones.txt
var timezonesStr string

func main() {
	hostname := flag.String("hostname", "localhost", "backend host")
	flag.Parse()

	devices, deviceNames, err := getAvailableDrives(*hostname)
	if err != nil {
		panic(fmt.Sprintf("Failed to get available drives from back-end: %v", err))
	}

	m, err := loginToBackend(*hostname)
	if err != nil {
		panic(fmt.Sprintf("Failed to get configuration from back-end: %v", err))
	}

	greenColour := tcell.NewRGBColor(0x08, 0x69, 0x6b)

	app := tview.NewApplication()
	logView := tview.NewTextView().
		SetScrollable(true).
		ScrollToEnd().
		SetLabelWidth(10).
		SetLabel(" Log").
		SetChangedFunc(func() {
			app.Draw()
		})

	SwapOptionKeys := []string{"none", "partition", "file"}
	var swapIndex int
	switch m.EnableSwap {
	case "partition":
		swapIndex = 1
	case "file":
		swapIndex = 2
	default:
		swapIndex = 0
	}

	timezones := strings.Split(timezonesStr, "\n")
	utcIndex := 589

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
		AddDropDown("Time Zone", timezones, utcIndex, func(option string, _ int) {
			m.Timezone = option
		}).
		AddDropDown("Enable Swap", SwapOptionKeys, swapIndex, func(option string, _ int) {
			m.EnableSwap = option
		}).
		AddInputField("Swap Size", m.SwapSize, 0, func(textToCheck string, lastChar rune) bool {
			_, err := strconv.Atoi(textToCheck)
			return err == nil
		}, func(text string) {
			m.SwapSize = text
		}).
		AddButton("Install OVERWRITING THE WHOLE DRIVE", func() {
			err := m.startInstallation(*hostname, logView)
			if err != nil {
				LOG(logView, "Failed to start installation: %v", err)
			}
		}).
		AddButton("Stop", func() {
			err := stop(*hostname)
			if err != nil {
				LOG(logView, "Failed to stop installation: %v", err)
			}
		})

	processOutput("ws://"+*hostname+":5000/process_output", logView)

	grid := tview.NewGrid().
		SetRows(23, 0).
		AddItem(form, 0, 0, 1, 1, 0, 0, true).
		AddItem(logView, 1, 0, 1, 1, 0, 0, false)
	grid.SetBorder(true).
		SetTitle("Opinionated Debian Installer").
		SetTitleColor(greenColour).
		SetTitleAlign(tview.AlignCenter)

	if err := app.SetRoot(grid, true).EnableMouse(true).SetFocus(grid).Run(); err != nil {
		panic(err)
	}
}
