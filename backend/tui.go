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
		AddCheckbox("Enable NVIDIA", m.NvidiaPackage == "nvidia-driver", func(checked bool) {
			if checked {
				m.NvidiaPackage = "nvidia-driver"
			} else {
				m.NvidiaPackage = ""
			}
		}).
		AddCheckbox("Enable Flathub", m.EnableFlathub == "true", func(checked bool) {
			if checked {
				m.EnableFlathub = "true"
			} else {
				m.EnableFlathub = "false"
			}
		}).
		AddCheckbox("Enable Popcon", m.EnablePopcon == "true", func(checked bool) {
			if checked {
				m.EnablePopcon = "true"
			} else {
				m.EnablePopcon = "false"
			}
		})

	secureBootForm := tview.NewForm().
		AddCheckbox("MOK-Signed UKI", m.EnableMokUki == "true", func(checked bool) {
			if checked {
				m.EnableMokUki = "true"
			} else {
				m.EnableMokUki = "false"
			}
		}).
		AddPasswordField("MOK Password", m.MokPassword, 0, '*', func(text string) {
			m.MokPassword = text
		})

	processingForm := tview.NewForm().
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

	wizard := NewWizard()
	wizard.AddForm("Device", diskForm).
		AddForm("Users", usersForm).
		AddForm("Configuration", configForm).
		AddForm("Secure Boot", secureBootForm).
		AddPage("Processing", processingForm, tview.NewFlex().
			SetDirection(tview.FlexRow).
			AddItem(tview.NewTextView().
				SetText(" Processing"), 3, 0, false).
			AddItem(processingForm, 3, 0, true).
			AddItem(logView, 0, 100, false))

	mainFlex := tview.NewFlex().
		SetDirection(tview.FlexRow).
		AddItem(wizard.MakePages(), 0, 100, true).
		AddItem(wizard.Footer, 1, 0, false)
	mainFlex.SetBorder(true).
		SetTitle("Opinionated Debian Installer").
		SetTitleColor(greenColour).
		SetTitleAlign(tview.AlignCenter)

	app.SetInputCapture(wizard.InputCapture)

	_ = SystemdNotifyReady()

	if err := app.SetRoot(mainFlex, true).EnableMouse(true).SetFocus(mainFlex).Run(); err != nil {
		panic(err)
	}
}
