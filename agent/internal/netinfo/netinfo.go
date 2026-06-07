// Package netinfo detects the host's reachable network addresses so the agent
// can tell the phone how to find it — both on the LAN and over Tailscale —
// without the user having to type IPs by hand.
package netinfo

import "net"

// tailscaleRange is the CGNAT block Tailscale assigns tailnet IPs from
// (100.64.0.0/10). Identifying addresses by range works the same on every
// platform, unlike matching interface names such as "tailscale0"/"Tailscale".
var tailscaleRange = mustCIDR("100.64.0.0/10")

func mustCIDR(s string) *net.IPNet {
	_, n, err := net.ParseCIDR(s)
	if err != nil {
		panic(err)
	}
	return n
}

// LocalAddresses inspects the machine's network interfaces and returns the
// best-guess LAN IPv4 address and Tailscale IPv4 address. Either may be empty
// if no matching interface is up. When multiple candidates exist the first one
// found wins — good enough for display/pairing purposes.
func LocalAddresses() (lan string, tailscale string) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", ""
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ipNet, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip4 := ipNet.IP.To4()
			if ip4 == nil {
				continue
			}
			switch {
			case tailscaleRange.Contains(ip4):
				if tailscale == "" {
					tailscale = ip4.String()
				}
			case ip4.IsPrivate():
				if lan == "" {
					lan = ip4.String()
				}
			}
		}
	}
	return lan, tailscale
}
