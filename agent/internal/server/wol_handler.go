package server

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
)

func wolRelayHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			MAC string `json:"mac"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, http.StatusBadRequest, "INVALID_BODY", "expected {\"mac\": \"aa:bb:cc:dd:ee:ff\"}")
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
			// Log the real dial error; the client gets the stable code only,
			// not the host's socket/permission details (PR-53).
			log.Printf("wol: dial: %v", err)
			writeError(w, http.StatusInternalServerError, "WOL_FAILED", "failed to send wake packet")
			return
		}
		defer conn.Close()
		if _, err := conn.Write(packet[:]); err != nil {
			log.Printf("wol: write: %v", err)
			writeError(w, http.StatusInternalServerError, "WOL_FAILED", "failed to send wake packet")
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "sent"})
	}
}
