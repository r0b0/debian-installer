package main

import (
	"os"
	"testing"
)

func TestParseLsblkJson(t *testing.T) {
	f, err := os.Open("test_data/lsblk.json")
	if err != nil {
		panic(err)
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
