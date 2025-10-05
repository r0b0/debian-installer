package main

import (
	"fmt"
	"github.com/Wifx/gonetworkmanager"
)

type Wifi struct {
	nm gonetworkmanager.NetworkManager
}

type Ap struct {
	ssid        string
	device      gonetworkmanager.Device
	accessPoint gonetworkmanager.AccessPoint
	security    bool
}

func (a *Ap) String() string {
	var security string
	if a.security {
		security = "password protected"
	} else {
		security = "open"
	}
	return fmt.Sprintf("%s (%s)", a.ssid, security)
}

func NewWifi() (*Wifi, error) {
	nm, err := gonetworkmanager.NewNetworkManager()
	if err != nil {
		return nil, err
	}
	wifi := Wifi{nm: nm}
	return &wifi, nil
}

func (w *Wifi) GetAccessPoints() ([]Ap, error) {
	allAccessPoints := make([]Ap, 0)

	devices, err := w.nm.GetAllDevices()
	if err != nil {
		return nil, err
	}

	for _, device := range devices {
		deviceType, err := device.GetPropertyDeviceType()
		if err != nil {
			return nil, err
		}
		if deviceType != gonetworkmanager.NmDeviceTypeWifi {
			continue
		}

		deviceWifi, err := gonetworkmanager.NewDeviceWireless(device.GetPath())
		if err != nil {
			return nil, err
		}

		accessPoints, err := deviceWifi.GetAccessPoints()
		if err != nil {
			return nil, err
		}
		for _, ap := range accessPoints {
			ssid, err := ap.GetPropertySSID()
			if err != nil {
				continue
			}
			wpa, err := ap.GetPropertyFlags()
			if err != nil {
				return nil, err
			}
			allAccessPoints = append(allAccessPoints, Ap{
				ssid:        ssid,
				device:      device,
				accessPoint: ap,
				security:    wpa&1 == 1,
			})
		}
	}

	return allAccessPoints, nil
}

func (w *Wifi) Connect(ap Ap, password string) (gonetworkmanager.ActiveConnection, error) {
	connection := make(map[string]map[string]interface{})
	connection["802-11-wireless"] = make(map[string]interface{})
	if ap.security {
		connection["802-11-wireless"]["security"] = "802-11-wireless-security"
		connection["802-11-wireless-security"] = make(map[string]interface{})
		connection["802-11-wireless-security"]["key-mgmt"] = "wpa-psk"
		connection["802-11-wireless-security"]["psk"] = password
	}

	activeConn, err := w.nm.AddAndActivateWirelessConnection(connection, ap.device, ap.accessPoint)
	if err != nil {
		return nil, err
	}
	return activeConn, nil
}
