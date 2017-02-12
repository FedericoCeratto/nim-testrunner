#
## Nim test runner - file monitor
#
# Copyright 2017 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see LICENSE file

import asyncio
import fsmonitor
import os,
  sets,
  strutils,
  tables

from globbing import match_filename

# Global vars needed by monitorEvent callback
var
  change_detected = false
  verbose_mode = false
  monitored_dirs = initTable[string, seq[string]]()

proc monitorEvent(m: FSMonitor; ev: MonitorEvent) =
  ## Event callback
  for mdir, fn_matchers in monitored_dirs.pairs():
    if not ev.fullname.startswith(mdir):
      continue

    if match_filename(ev.fullname, fn_matchers):
      change_detected = true
      if verbose_mode:
        echo "$# - $#" % [ev.fullname, $ev.kind]
      break

proc extract_monitoring_root*(fn_matcher: string): (string, bool) =
  ## Extract directory to monitor, see unit tests for examples
  ## Works with absolute and relative paths
  let (mdir, mname, mext) = splitFile(fn_matcher)
  var
    cnt = 0
    rdir = ""
    recurse = false
  for item in split(mdir, DirSep):
    if item == "**":
      recurse = true
      break
    if item.contains("*"):
      break
    if cnt > 0:
      # use cnt instead of rdir.len to support abs paths
      rdir.add $DirSep

    rdir.add item
    cnt.inc
  return (rdir, recurse)

proc rec_walk(rootdir: string, seen_dirs: var HashSet[string]) =
  ## Walk directory recursively. Modify `seen_dirs`
  seen_dirs.incl rootdir
  for d in walkDirs(joinPath(rootdir, "*")):
    if not seen_dirs.contains(d):
      seen_dirs.incl d
      rec_walk(d, seen_dirs)

iterator recurse_dirs(rootdir: string): string =
  ## Walk directory recursively. Return dirs only.
  var dirs = initSet[string]()
  rec_walk(rootdir, dirs)
  for d in dirs:
    yield d

proc monitor_files*(basedir: string, fn_matchers: seq[string], verbose: bool,
    filter = {MonitorCloseWrite}): bool =
  ## Monitor files for change. Do not monitor existing files, rather
  ## monitor directories where files might appear or be modified
  ## Return false to exit the monitoring loop
  verbose_mode = verbose
  change_detected = false
  monitored_dirs = initTable[string, seq[string]]()
  let m = newMonitor()

  for rel_matcher in fn_matchers:
    let matcher = joinPath(basedir, rel_matcher)
    let (mdir, recurse) = extract_monitoring_root(matcher)
    if not existsDir(mdir):
      continue
    if monitored_dirs.hasKey(mdir):
      monitored_dirs[mdir].add matcher
    else:
      monitored_dirs[mdir] = @[matcher]
    if recurse:
      for subdir in recurse_dirs(mdir):
        if monitored_dirs.hasKey(subdir):
          monitored_dirs[subdir].add matcher
        else:
          monitored_dirs[subdir] = @[matcher]

  if monitored_dirs.len == 0:
    return false

  for mdir in monitored_dirs.keys():
    m.add(mdir, filter)

  var dispatcher = newDispatcher()
  dispatcher.register(m, monitorEvent)

  if verbose:
    let n = monitored_dirs.len
    if n == 1: echo "$# dir monitored..." % $n
    else: echo "$# dirs monitored..." % $n

  while change_detected == false:
    # block here, polling for changes
    if not dispatcher.poll():
      echo "Unable to monitor files"
      return false

  return true
