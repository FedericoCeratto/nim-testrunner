#
## Nim test runner - globbing
#
# Copyright 2017 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see LICENSE file

import os
import tables
import strutils


proc match_star(s, pattern: string): bool =
  ## Match a path component against a pattern
  if pattern.contains '*':
    if s.len < pattern.len - 1:
      return false
    var
      pl = ""
      pr = ""
    (pl, pr) = pattern.split('*')
    #echo s.startswith(pl) and s.endswith(pr), " > ", s, " > ", pattern
    return s.startswith(pl) and s.endswith(pr)

  return s == pattern

proc glob*(path, pattern: string): bool =
  ## Apply globbing pattern to a filename
  let
    components = path.split('/')
    pattern_tokens = pattern.split('/')
  var
    c_pos = 0
    found_doublestar = false

  for pat_pos in 0..pattern_tokens.len-1:
    let pat = pattern_tokens[pat_pos]
    if pat == "**":
      if found_doublestar:
        raise newException(ValueError, "Multiple double-stars are not supported")
      found_doublestar = true
      c_pos = components.len - (pattern_tokens.len - pat_pos)
    else:
      if not match_star(components[c_pos], pat):
        return false

    c_pos.inc
  return true


var matches_cache = initTable[string, bool]()

proc match_filename*(path: string, fn_matchers: seq[string]): bool =
  for matcher in fn_matchers:
    if glob(path, matcher):
      return true

  return false

proc cached_match_filename*(path: string, fn_matchers: seq[string]): bool =
  try:
    return matches_cache[path]
  except:
    result = match_filename(path, fn_matchers)
    matches_cache[path] = result


