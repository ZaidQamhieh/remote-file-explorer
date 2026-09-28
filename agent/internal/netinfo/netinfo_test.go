package netinfo

import (
	"net"
	"testing"
)

func TestTailscaleCIDRAndNetworkDetection(t *testing.T) {
	if !tailscaleRange.Contains(net.ParseIP("100.64.0.1")) || !tailscaleRange.Contains(net.ParseIP("100.127.255.254")) || tailscaleRange.Contains(net.ParseIP("100.128.0.1")) {
		t.Fatal("Tailscale range does not match 100.64.0.0/10")
	}

	info := Detect()
	if info.LAN != "" {
		ip := net.ParseIP(info.LAN)
		if ip == nil || ip.To4() == nil || !ip.IsPrivate() {
			t.Errorf("detected LAN address is not private IPv4: %q", info.LAN)
		}
	}
	if info.Tailscale != "" {
		ip := net.ParseIP(info.Tailscale)
		if ip == nil || ip.To4() == nil || !tailscaleRange.Contains(ip) {
			t.Errorf("detected Tailscale address is outside its IPv4 range: %q", info.Tailscale)
		}
	}
	if info.LAN == "" && info.MAC != "" {
		t.Errorf("MAC address %q was returned without a LAN IPv4 address", info.MAC)
	}
	lan, tailscale := LocalAddresses()
	if lan != "" {
		ip := net.ParseIP(lan)
		if ip == nil || ip.To4() == nil {
			t.Errorf("LocalAddresses returned invalid LAN IPv4: %q", lan)
		}
	}
	if tailscale != "" {
		ip := net.ParseIP(tailscale)
		if ip == nil || !tailscaleRange.Contains(ip) {
			t.Errorf("LocalAddresses returned invalid Tailscale IPv4: %q", tailscale)
		}
	}
}

func TestMustCIDRPanicsForInvalidConfiguration(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Fatal("mustCIDR did not panic for invalid CIDR")
		}
	}()
	mustCIDR("not-a-network")
}
