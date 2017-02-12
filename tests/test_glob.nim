#
# 2017 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3, see LICENSE file
#
# Globbing
#

import unittest

import globbing

suite "glob":
  test "ident":
    check glob("a.nim", "a.nim")
    check glob("x/a.nim", "x/a.nim")
    check glob("x/y/a.nim", "x/y/a.nim")
    check glob("./x/y/a.nim", "./x/y/a.nim")

  test "one glob":
    check glob("a.nim", "*.nim")
    check glob("a.nim", "a*")
    check glob("a.nim", "a*m")
    check glob("test_x.nim", "test_*.nim")
    check glob("testfoo.nim", "test_*.nim") == false

  test "one glob with dir":
    check glob("foo/a.nim", "foo/*.nim")
    check glob("foo/a.nim", "*/a.nim")

  test "more globs":
    check glob("foo/a.nim", "*/*.nim")
    check glob("foo/a.nim", "*/a.*")
    check glob("foo/a.nim", "*/foo/a.*") == false
    check glob("ii/foo/a.nim", "*/foo/a.*")
    check glob("ii/foo/a.nim", "*/*/a.*")
    check glob("42/ii/foo/a.nim", "*/*/a.*") == false
    check glob("string/strong", "st*ing/st*ong")
    #check glob("and_a_double_string", "and*double*string")
    #check glob("string/strong/and_a_double_string", "st*ing/st*ong/and*double*string")

  test "doublestar":
    check glob("foo/bar/baz/a.nim", "foo/**/a.*")
    check glob("foo/bar/baz/a.nim", "**/a.*")
    check glob("foo/bar/baz/a.nim", "**")
    check glob("foo/bar/baz/a.nim", "foo/**")

  test "slash doublestar":
    check glob("/foo/bar/baz/a.nim", "/**/a.*")
    check glob("/foo/bar/baz/a.nim", "**/a.*")
    check glob("foo/bar/baz/a.nim", "/**/a.*") == false
    check glob("foo/bar/baz/a.nim", "**/a.*")

  test "more doublestar":
    expect ValueError:
      discard glob("foo/bar/baz/a.nim", "**/baz/**")

  test "hidden dirs":
    check glob(".config/i3/hi.nim", ".config/*/*.nim")
    check glob(".config/z/hi.nim", ".config/*/*.nim")
    check glob(".vim/doc/hi.txt", ".*/doc/*.txt")
    check glob("vim/doc/hi.txt", ".*/doc/*.txt") == false

  test "broken":
    #check glob("foo/bar/baz/a.nim", "") == false
    #check glob("foo/bar/baz/a.nim", "***") == false
    check glob("foo/bar/baz/a.nim", "*/**")
    check glob("foo/bar/baz/a.nim", "**/*")
    check glob("foo/bar/baz/a.nim", "/") == false

  let fn_matchers = @[
    "**/*.nim",
    "tests/**/*.nim",
    "all_files/**",
    "*.cfg",
  ]

  test "matchers":
    check match_filename("x.nim", fn_matchers)
    check match_filename("x/y.nim", fn_matchers)
    check match_filename("tests/y.nim", fn_matchers)
    check match_filename("tests/y.txt", fn_matchers) == false
    check match_filename("tests/a/b/c/y.nim", fn_matchers)
    check match_filename("all_files", fn_matchers)
    check match_filename("all_files/a/b/", fn_matchers)
    check match_filename("all_files/a/b/c/y.nim", fn_matchers)
    check match_filename("cfg", fn_matchers) == false

  test "matchers with caching":
    check cached_match_filename("x.nim", fn_matchers)
    check cached_match_filename("x/y.nim", fn_matchers)
    check cached_match_filename("x/y.nim", fn_matchers)
    check cached_match_filename("tests/y.nim", fn_matchers)
    check cached_match_filename("tests/y.txt", fn_matchers) == false
    check cached_match_filename("tests/y.txt", fn_matchers) == false
    check cached_match_filename("tests/a/b/c/y.nim", fn_matchers)
    check cached_match_filename("all_files", fn_matchers)
    check cached_match_filename("all_files/a/b/", fn_matchers)
    check cached_match_filename("all_files/a/b/c/y.nim", fn_matchers)
    check cached_match_filename("cfg", fn_matchers) == false
