package main

/*
Opinionated Debian Installer
Copyright (C) 2022-2025 Robert T.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

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
	_, err = parseLoginJson(f)
	if err != nil {
		t.Fatalf("Failed to parse json: %v", err)
	}
}

func TestGetTimeZoneOffset(t *testing.T) {
	const UTC_OFFSET = 589
	o := getTimeZoneOffset("UTC")
	if UTC_OFFSET != o {
		t.Errorf("Offset of UTC timezone = %d; want %d", o, UTC_OFFSET)
	}
}

func TestGetSliceIndex(t *testing.T) {
	var WHERE = []string{"a", "b", "c"}
	const WHAT = "b"
	o := getSliceIndex(WHAT, WHERE)
	if 1 != o {
		t.Errorf("Slice index = %d; want %d", o, 2)
	}
}
