package main

import (
	"fmt"
	"io"
	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
	"net/http"
	"golang.org/x/net/websocket"
	"net/url"
	"strconv"
)

type model struct {
	disk           string
	debian_version string
	username       string
	user_full_name string
	user_password  string
	root_password  string
	luks_password  string
	hostname       string
	timezone       string
	enable_swap    string
	swap_size      string
}

func (m *model) startInstallation(log io.Writer) error {
	post := url.Values{}
	post.Set("DISK", m.disk)
	post.Set("DEBIAN_VERSION", m.debian_version)
	post.Set("USERNAME", m.username)
	post.Set("USER_FULL_NAME", m.user_full_name)
	post.Set("USER_PASSWORD", m.user_password)
	post.Set("ROOT_PASSWORD", m.user_password)
	post.Set("LUKS_PASSWORD", m.luks_password)
	post.Set("HOSTNAME", m.hostname)
	post.Set("TIMEZONE", m.timezone)
	post.Set("ENABLE_SWAP", m.enable_swap)
	post.Set("SWAP_SIZE", m.swap_size)
	client := http.Client{}
	resp, err := client.PostForm("http://localhost:5000/install", post)
	if err != nil {
		log.Write([]byte("Error posting form\n"))
		return err
	}
	log.Write([]byte(resp.Status))
	// TODO
	return nil
}

func main() {
	devices := []string{"/dev/sda", "/dev/sdb"}
	m := model{debian_version: "bookworm"}
	green_colour := tcell.NewRGBColor(0x08, 0x69, 0x6b)

	app := tview.NewApplication()
	logView := tview.NewTextView().
		SetScrollable(true).
		ScrollToEnd().
		SetLabel("Log").
		SetChangedFunc(func() {
			app.Draw()
		})
	logView.SetBackgroundColor(tcell.ColorGray)

	origin := "http://localhost/"
	wsUrl := "ws://localhost:5000/process_output"
	ws, err := websocket.Dial(wsUrl, "", origin)
	if err != nil {
		panic(err)
	}
	go func() {
		for {
			_, err := io.Copy(logView, ws)
			if err != nil {
				logView.Write([]byte(fmt.Sprintf("Error reading websocket %v\n", err)))
				return
			}
		}
	}()

	form := tview.NewForm().
		AddDropDown("Installation Target Device", devices, 0, func(option string, _ int) {
			m.disk = option
		}).
		AddPasswordField("Disk Encryption Passphrase", "", 0, '*', func(text string) {
			m.luks_password = text
		}). // TODO second time
		AddPasswordField("Root Password", "", 0, '*', func(text string) {
			m.root_password = text
		}).
		AddInputField("Regular User Name", "", 0, nil, func(text string) {
			m.username = text
		}).
		AddInputField("Full Name", "", 0, nil, func(text string) {
			m.user_full_name = text
		}).
		AddPasswordField("Regular User Password", "", 0, '*', func(text string) {
			m.user_password = text
		}).
		AddInputField("Hostname", "debian", 0, nil, func(text string) {
			m.hostname = text
		}).
		AddInputField("Time Zone", "UTC", 0, nil, func(text string) {
			m.timezone = text // TODO dropdown
		}).
		AddDropDown("Enable Swap", []string{"None", "Partition", "File"}, 0, func(option string, optionIndex int) {
			m.enable_swap = option
		}).
		AddInputField("Swap Size", "1", 0, func(textToCheck string, lastChar rune) bool {
			_, err := strconv.Atoi(textToCheck)
			return err == nil
		}, func(text string) {
			m.swap_size = text
		}).
		AddButton("Install OVERWRITING THE WHOLE DRIVE", func() {
			m.startInstallation(logView)
		}).
		SetLabelColor(tcell.ColorWhite).
		SetFieldBackgroundColor(tcell.ColorGray).
		SetButtonBackgroundColor(green_colour).
		AddFormItem(logView)
	form.SetBorder(true).
		SetTitle("Opinionated Debian Installer").
		SetTitleColor(green_colour).
		SetTitleAlign(tview.AlignCenter)

	if err := app.SetRoot(form, true).EnableMouse(true).Run(); err != nil {
		panic(err)
	}
}
