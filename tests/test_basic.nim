#
## Nim test runner - unit tests
#
# 2017 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3, see LICENSE file

import unittest

import filemonitor

suite "glob":
  test "extract_monitoring_root":
    assert extract_monitoring_root("a/**/*.nim") == ("a", true)
    assert extract_monitoring_root("a/b/*.nim") == ("a/b", false)
    assert extract_monitoring_root("a/b/*") == ("a/b", false)
    assert extract_monitoring_root("a/b/*/tests/*.nim") == ("a/b", false)
    assert extract_monitoring_root("*.nim") == ("", false)

  test "extract_monitoring_root abs":
    assert extract_monitoring_root("/foo/a/**/*.nim") == ("/foo/a", true)
    assert extract_monitoring_root("/foo/a/b/*.nim") == ("/foo/a/b", false)
    assert extract_monitoring_root("/foo/a/b/*") == ("/foo/a/b", false)
    assert extract_monitoring_root("/foo/a/b/*/tests/*.nim") == ("/foo/a/b", false)
    assert extract_monitoring_root("/foo/*.nim") == ("/foo", false)
