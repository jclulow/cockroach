// Copyright 2018 The Cockroach Authors.
//
// Use of this software is governed by the Business Source License
// included in the file licenses/BSL.txt.
//
// As of the Change Date specified in that file, in accordance with
// the Business Source License, use of this software will be governed
// by the Apache License, Version 2.0, included in the file
// licenses/APL.txt.

// +build !windows

//lint:file-ignore Unconvert (redundant conversions are necessary for cross-platform compatibility)

package sysutil

import (
	"fmt"
	"os"
	"syscall"

	"golang.org/x/sys/unix"
)

// ProcessIdentity returns a string describing the user and group that this
// process is running as.
func ProcessIdentity() string {
	return fmt.Sprintf("uid %d euid %d gid %d egid %d",
		unix.Getuid(), unix.Geteuid(), unix.Getgid(), unix.Getegid())
}

// StatAndLinkCount wraps os.Stat, returning its result and, if the platform
// supports it, the link-count from the returned file info.
func StatAndLinkCount(path string) (os.FileInfo, int64, error) {
	stat, err := os.Stat(path)
	if err != nil {
		return stat, 0, err
	}
	if sys := stat.Sys(); sys != nil {
		if s, ok := sys.(*syscall.Stat_t); ok {
			return stat, int64(s.Nlink), nil
		}
	}
	return stat, 0, nil
}

// IsCrossDeviceLinkErrno checks whether the given error object (as
// extracted from an *os.LinkError) is a cross-device link/rename
// error.
func IsCrossDeviceLinkErrno(errno error) bool {
	return errno == syscall.EXDEV
}
