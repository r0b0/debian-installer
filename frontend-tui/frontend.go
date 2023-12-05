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

type model struct {
	disk          string
	debianVersion string
	username      string
	userFullName  string
	userPassword  string
	rootPassword  string
	luksPassword  string
	hostname      string
	timezone      string
	enableSwap    string
	swapSize      string
}

func LOG(l io.Writer, format string, args ...any) {
	_, _ = l.Write([]byte(fmt.Sprintf(format+"\n", args...)))
}

func (m *model) startInstallation(log io.Writer) error {
	post := url.Values{}
	post.Set("DISK", m.disk)
	post.Set("DEBIAN_VERSION", m.debianVersion)
	post.Set("USERNAME", m.username)
	post.Set("USER_FULL_NAME", m.userFullName)
	post.Set("USER_PASSWORD", m.userPassword)
	post.Set("ROOT_PASSWORD", m.userPassword)
	post.Set("LUKS_PASSWORD", m.luksPassword)
	post.Set("HOSTNAME", m.hostname)
	post.Set("TIMEZONE", m.timezone)
	post.Set("ENABLE_SWAP", m.enableSwap)
	post.Set("SWAP_SIZE", m.swapSize)
	client := http.Client{}
	resp, err := client.PostForm("http://localhost:5000/install", post)
	if err != nil {
		LOG(log, "Error posting form: %v", err)
		return err
	}
	LOG(log, "Post status: %s", resp.Status)
	return nil
}

type BlockDevice struct {
	Path  string `json:"path"`
	Model string `json:"model"`
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

func getAvailableDrives(drives *[]string, dropDown *tview.DropDown, log io.Writer) error {
	client := http.Client{}
	res, err := client.Get("http://localhost:5000/block_devices")
	if err != nil {
		LOG(log, "Error geting available drives: %v", err)
		return err
	}
	defer res.Body.Close()
	devices, err := parseLsblkJson(res.Body)
	if err != nil {
		LOG(log, "Failed to parse JSON data: %v", err)
		return err
	}
	LOG(log, "Available devices: %v", devices)
	clear(*drives)
	var driveDescriptions []string
	for _, device := range devices.Blockdevices {
		*drives = append(*drives, device.Path)
		driveDescription := fmt.Sprintf("%s %s (%s)", device.Path, device.Model, device.Size)
		driveDescriptions = append(driveDescriptions, driveDescription)
	}
	LOG(log, "Drives: %v", drives)
	LOG(log, "Drive descriptions: %v", driveDescriptions)
	dropDown.SetOptions(driveDescriptions, nil)
	return nil
}

func processOutput(wsUrl string, log io.Writer) error {
	origin := "http://localhost/"
	ws, err := websocket.Dial(wsUrl, "", origin)
	if err != nil {
		LOG(log, "Failed to connect to web socket: %v", err)
		return err
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

	return nil
}

func main() {
	var devices []string

	m := model{debianVersion: "bookworm"}  // TODO fetch this from GET /login response.environ
	greenColour := tcell.NewRGBColor(0x08, 0x69, 0x6b)

	app := tview.NewApplication()
	logView := tview.NewTextView().
		SetScrollable(true).
		ScrollToEnd().
		SetLabel("Log").
		SetChangedFunc(func() {
			app.Draw()
		})
	// logView.SetBackgroundColor(tcell.ColorGray)

	form := tview.NewForm().
		AddDropDown("Installation Target Device", nil, 0, nil).
		AddPasswordField("Disk Encryption Passphrase", "", 0, '*', func(text string) {
			m.luksPassword = text
		}). // TODO second time
		AddPasswordField("Root Password", "", 0, '*', func(text string) {
			m.rootPassword = text
		}).
		AddInputField("Regular User Name", "", 0, nil, func(text string) {
			m.username = text
		}).
		AddInputField("Full Name", "", 0, nil, func(text string) {
			m.userFullName = text
		}).
		AddPasswordField("Regular User Password", "", 0, '*', func(text string) {
			m.userPassword = text
		}).
		AddInputField("Hostname", "debian", 0, nil, func(text string) {
			m.hostname = text
		}).
		AddInputField("Time Zone", "UTC", 0, nil, func(text string) {
			m.timezone = text // TODO dropdown
		}).
		AddDropDown("Enable Swap", []string{"None", "Partition", "File"}, 0, func(option string, optionIndex int) {
			m.enableSwap = option
		}).
		AddInputField("Swap Size", "1", 0, func(textToCheck string, lastChar rune) bool {
			_, err := strconv.Atoi(textToCheck)
			return err == nil
		}, func(text string) {
			m.swapSize = text
		}).
		AddButton("Install OVERWRITING THE WHOLE DRIVE", func() {
			err := m.startInstallation(logView)
			if err != nil {
				LOG(logView, "Failed to start installation: %v", err)
			}
		}).
		// SetLabelColor(tcell.ColorWhite).
		// SetFieldBackgroundColor(tcell.ColorGray).
		// SetFieldTextColor(tcell.ColorBlack).
		// SetButtonBackgroundColor(green_colour).
		AddFormItem(logView)
	form.SetBorder(true).
		SetTitle("Opinionated Debian Installer").
		SetTitleColor(greenColour).
		SetTitleAlign(tview.AlignCenter)

	// TODO fetch everything from the back-end first and create the form after - it will be much easier
	_ = processOutput("ws://localhost:5000/process_output", logView)
	devicesDropdown := form.GetFormItemByLabel("Installation Target Device").(*tview.DropDown)
	go func() {
		_ = getAvailableDrives(&devices, devicesDropdown, logView)
		devicesDropdown.SetSelectedFunc(func(_ string, index int) {
			if index < 0 {
				return
			}
			m.disk = devices[index]
			LOG(logView, "Selected device path '%s'", devices[index])
		})
	}()

	if err := app.SetRoot(form, true).EnableMouse(true).Run(); err != nil {
		panic(err)
	}
}
