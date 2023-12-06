package main

import (
	"os"
	"testing"
)

func TestParseLsblkJson(t *testing.T) {
	f, err := os.Open("test_data/lsblk.json")
	if err != nil {
		t.Fatalf("Failed to open json file: %v", err)
	}
	devices, err := parseLsblkJson(f)
	if err != nil {
		t.Fatalf("Failed to parse json: %v", err)
	}
	if len(devices.Blockdevices) == 0 {
		t.Fatalf("No devices parsed: %v", devices.Blockdevices)
	}

	device := devices.Blockdevices[0]
	t.Logf("First device: %v", device)
	if "/dev/sda" != device.Path {
		t.Errorf("First device path = %s; want /dev/sda", device.Path)
	}
}

func TestParseLoginJson(t *testing.T) {
	f, err := os.Open("test_data/login.json")
	if err != nil {
		t.Fatalf("Failed to open json file: %v", err)
	}
	login, err := parseLoginJson(f)
	if err != nil {
		t.Fatalf("Failed to parse json: %v", err)
	}

	if "/dev/sda" != login.Disk {
		t.Errorf("Disk for installation = %s; want /dev/sda", login.Disk)
	}
}
