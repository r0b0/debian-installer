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

	form := tview.NewForm().
		SetHorizontal(true).
		AddDropDown("Installation Target Device", deviceNames, getSliceIndex(m.Disk, devices), func(_ string, optionIndex int) {
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

	grid := tview.NewGrid().
		SetRows(17, -1).
		AddItem(form, 0, 0, 1, 1, 0, 0, true).
		AddItem(logView, 1, 0, 1, 1, 0, 0, false)
	grid.SetBorder(true).
		SetTitle("Opinionated Debian Installer").
		SetTitleColor(greenColour).
		SetTitleAlign(tview.AlignCenter)

	_ = SystemdNotifyReady()

	if err := app.SetRoot(grid, true).EnableMouse(true).SetFocus(grid).Run(); err != nil {
		panic(err)
	}
}
