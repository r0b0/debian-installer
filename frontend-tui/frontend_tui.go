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

	form := tview.NewForm().
		AddDropDown("Installation Target Device", deviceNames, getSliceIndex(m.Disk, devices), func(_ string, optionIndex int) {
			m.Disk = devices[optionIndex]
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
		SetRows(25, 0).
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
