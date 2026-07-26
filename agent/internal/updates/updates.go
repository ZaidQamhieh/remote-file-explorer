// Package updates discovers the newest Android APK the agent should serve to
// the app. APKs are dropped in the updates dir named rfe-<versionName>-<versionCode>.apk
// (e.g. rfe-1.2.0-12.apk); versionCode is the monotonic comparison key.
package updates

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
)

// Release describes one available APK.
type Release struct {
	VersionName string `json:"versionName"`
	VersionCode int    `json:"versionCode"`
	Filename    string `json:"-"`
	Size        int64  `json:"size"`
	SHA256      string `json:"sha256"`
}

// rfe-<versionName>-<versionCode>.apk
var apkPattern = regexp.MustCompile(`^rfe-(.+)-(\d+)\.apk$`)

// Latest returns the highest-versionCode APK in dir, or nil if the dir is
// empty or missing.
func Latest(dir string) (*Release, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var best *Release
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		m := apkPattern.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		code, err := strconv.Atoi(m[2])
		if err != nil {
			continue
		}
		if best != nil && code <= best.VersionCode {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return nil, err
		}
		best = &Release{
			VersionName: m[1],
			VersionCode: code,
			Filename:    e.Name(),
			Size:        info.Size(),
		}
	}
	if best != nil {
		file, err := os.Open(Path(dir, best))
		if err != nil {
			return nil, err
		}
		hash := sha256.New()
		if _, err := io.Copy(hash, file); err != nil {
			file.Close()
			return nil, err
		}
		if err := file.Close(); err != nil {
			return nil, err
		}
		best.SHA256 = hex.EncodeToString(hash.Sum(nil))
	}
	return best, nil
}

// Path returns the absolute path to a release's APK within dir.
func Path(dir string, rel *Release) string {
	return filepath.Join(dir, rel.Filename)
}
