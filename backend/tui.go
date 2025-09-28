package main

import (
	"fmt"
	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
	"io"
	"net/url"
	"strconv"
)

func LOG(l io.Writer, format string, args ...any) {
	_, _ = l.Write([]byte(fmt.Sprintf(format+"\n", args...)))
}

func Tui(baseUrlString *string) {
	baseUrl, err := url.Parse(*baseUrlString)
	if err != nil {
		panic(fmt.Sprintf("Invalid base url: %s", *baseUrlString))
	}

	devices, deviceNames, err := getAvailableDrives(baseUrl)
	if err != nil {
		panic(fmt.Sprintf("Failed to get available drives from back-end: %v", err))
	}

	m, err := loginToBackend(baseUrl)
	if err != nil {
		panic(fmt.Sprintf("Failed to get configuration from back-end: %v", err))
	}

	greenColour := tcell.NewRGBColor(0x51, 0xa1, 0xd0)

	app := tview.NewApplication()
	logView := tview.NewTextView().
		SetScrollable(true).
		ScrollToEnd().
		SetLabelWidth(10).
		SetLabel(" Log").
		SetChangedFunc(func() {
			app.Draw()
		})

	dataOk := true
	pages := tview.NewPages()

	diskForm := tview.NewForm().
		AddDropDown("Device", deviceNames, getSliceIndex(m.Disk, devices), func(_ string, optionIndex int) {
			m.Disk = devices[optionIndex]
		}).
		AddCheckbox("Disable Encryption", m.DisableLuks == "true", func(checked bool) {
			if checked {
				m.DisableLuks = "true"
			} else {
				m.DisableLuks = "false"
			}
		}).
		AddPasswordField("Disk Encryption Passphrase", m.LuksPassword, 0, '*', func(text string) {
			m.LuksPassword = text
		}). // TODO second time
		AddCheckbox("Unlock with TPM", m.EnableTpm == "true", func(checked bool) {
			if checked {
				m.EnableTpm = "true"
			} else {
				m.EnableTpm = "false"
			}
		}).
		AddButton("Next", func() {
			pages.SwitchToPage("Users")
		})

	usersForm := tview.NewForm().
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
		AddButton("Back", func() {
			pages.SwitchToPage("Device")
		}).
		AddButton("Next", func() {
			pages.SwitchToPage("Configuration")
		})

	configForm := tview.NewForm().
		AddInputField("Hostname", m.Hostname, 0, nil, func(text string) {
			m.Hostname = text
		}).
		AddDropDown("Time Zone", timezones, getTimeZoneOffset(m.Timezone), func(option string, _ int) {
			m.Timezone = option
		}).
		AddInputField("Swap Size", m.SwapSize, 0, func(textToCheck string, lastChar rune) bool {
			_, err := strconv.Atoi(textToCheck)
			return err == nil
		}, func(text string) {
			m.SwapSize = text
		}).
		AddCheckbox("Enable NVIDIA", false, func(checked bool) {
			if checked {
				m.NvidiaPackage = "nvidia-driver"
			} else {
				m.NvidiaPackage = ""
			}
		}).
		AddCheckbox("Enable Flathub", false, func(checked bool) {
			if checked {
				m.EnableFlathub = "true"
			} else {
				m.EnableFlathub = "false"
			}
		}).
		AddCheckbox("Enable Popcon", false, func(checked bool) {
			if checked {
				m.EnablePopcon = "true"
			} else {
				m.EnablePopcon = "false"
			}
		}).
		AddButton("Back", func() {
			pages.SwitchToPage("Users")
		}).
		AddButton("Next", func() {
			pages.SwitchToPage("Secure Boot")
		})

	secureBootForm := tview.NewForm().
		AddCheckbox("MOK-Signed UKI", false, func(checked bool) {
			if checked {
				m.EnableMokUki = "true"
			} else {
				m.EnableMokUki = "false"
			}
		}).
		AddPasswordField("MOK Password", m.MokPassword, 0, '*', func(text string) {
			m.MokPassword = text
		}).
		AddButton("Back", func() {
			pages.SwitchToPage("Configuration")
		}).
		AddButton("Next", func() {
			pages.SwitchToPage("Processing")
		})

	processingForm := tview.NewForm().
		AddButton("Back", func() {
			pages.SwitchToPage("Secure Boot")
		}).
		AddButton("Install OVERWRITING THE WHOLE DRIVE", func() {
			if !dataOk {
				LOG(logView, "Data not consistent") // TODO
				return
			}
			err := m.startInstallation(baseUrl, logView)
			if err != nil {
				LOG(logView, "Failed to start installation: %v", err)
			}
		}).
		AddButton("Stop", func() {
			err := stop(baseUrl)
			if err != nil {
				LOG(logView, "Failed to stop installation: %v", err)
			}
		})

	processOutput(baseUrl, logView)

	footer := tview.NewTextView().
		SetText(" [:blue]F1[-:-] Device  [:blue]F2[-:-] Users  [:blue]F3[-:-] Configuration  [:blue]F4[-:-] SecureBoot  [:blue]F5[-:-] Log").
		SetDynamicColors(true)

	pages.
		AddPage("Device", diskForm, true, true).
		AddPage("Users", usersForm, true, false).
		AddPage("Configuration", configForm, true, false).
		AddPage("Secure Boot", secureBootForm, true, false).
		AddPage("Processing", tview.NewFlex().
			SetDirection(tview.FlexRow).
			AddItem(tview.NewTextView().
				SetText(" Processing"), 3, 0, false).
			AddItem(processingForm, 3, 0, true).
			AddItem(logView, 0, 100, false),
			true, false)

	mainFlex := tview.NewFlex().
		SetDirection(tview.FlexRow).
		AddItem(pages, 0, 100, true).
		AddItem(footer, 1, 0, false)
	mainFlex.SetBorder(true).
		SetTitle("Opinionated Debian Installer").
		SetTitleColor(greenColour).
		SetTitleAlign(tview.AlignCenter)
	
	app.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyF1:
			pages.SwitchToPage("Device")
			return nil
		case tcell.KeyF2:
			pages.SwitchToPage("Users")
			return nil
		case tcell.KeyF3:
			pages.SwitchToPage("Configuration")
			return nil
		case tcell.KeyF4:
			pages.SwitchToPage("Secure Boot")
			return nil
		case tcell.KeyF5:
			pages.SwitchToPage("Processing")
			return nil
		default:
			return event
		}
	})

	_ = SystemdNotifyReady()

	if err := app.SetRoot(mainFlex, true).EnableMouse(true).SetFocus(mainFlex).Run(); err != nil {
		panic(err)
	}
}
