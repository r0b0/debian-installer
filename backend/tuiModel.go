package main

import (
	_ "embed"
	"encoding/json"
	"io"
	"strings"
)

// when adding fields here, you need to add them to startInstallation() in tuiRest.go too
type Model struct {
	Disk          string `json:"DISK"`
	DebianVersion string `json:"DEBIAN_VERSION"`
	Username      string `json:"USERNAME"`
	UserFullName  string `json:"USER_FULL_NAME"`
	UserPassword  string `json:"USER_PASSWORD"`
	RootPassword  string `json:"ROOT_PASSWORD"`
	DisableLuks   string `json:"DISABLE_LUKS"`
	LuksPassword  string `json:"LUKS_PASSWORD"`
	EnableMokUki  string `json:"ENABLE_MOK_SIGNED_UKI"`
	MokPassword   string `json:"MOK_ENROLL_PASSWORD"`
	EnableTpm     string `json:"ENABLE_TPM"`
	Hostname      string `json:"HOSTNAME"`
	Timezone      string `json:"TIMEZONE"`
	SwapSize      string `json:"SWAP_SIZE"`
	NvidiaPackage string `json:"NVIDIA_PACKAGE"`
	EnablePopcon  string `json:"ENABLE_POPCON"`
	EnableFlathub string `json:"ENABLE_FLATHUB"`
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

//go:embed timezones.txt
var timezonesStr string
var timezones = strings.Split(timezonesStr, "\n")

func getTimeZoneOffset(tz string) int {
	return getSliceIndex(tz, timezones)
}

func getSliceIndex(what string, where []string) int {
	for i, t := range where {
		if what == t {
			return i
		}
	}
	return 0
}
