package server

import (
	"net"
	"net/http"
)

func wolRelayHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			MAC string `json:"mac"`
		}
		if !decodeJSONBody(w, r, &body) {
			return
		}
		mac, err := net.ParseMAC(body.MAC)
		if err != nil || len(mac) != 6 {
			writeError(w, http.StatusBadRequest, "INVALID_MAC", "MAC must be 6-byte colon-separated")
			return
		}

		// Build magic packet: 6×0xFF + 16×MAC.
		var packet [102]byte
		for i := 0; i < 6; i++ {
			packet[i] = 0xFF
		}
		for i := 0; i < 16; i++ {
			copy(packet[6+i*6:], mac)
		}

		conn, err := net.Dial("udp4", "255.255.255.255:9")
		if err != nil {
			writeServerError(w, r, "WOL_FAILED", err)
			return
		}
		defer conn.Close()
		if _, err := conn.Write(packet[:]); err != nil {
			writeServerError(w, r, "WOL_FAILED", err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "sent"})
	}
}
