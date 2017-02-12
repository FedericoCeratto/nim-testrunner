#
## Nim test runner
#
# Copyright 2017 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see LICENSE file

import
  os,
  parsecfg,
  parseopt,
  streams,
  strutils,
  terminal

from osproc import execCmd
from times import epochTime

from globbing import match_filename

when defined(linux):
  from filemonitor import monitor_files

const
  default_conf_fname = ".testrunner.conf"
  default_test_fn_matchers = @["test_*.nim", "test/*.nim", "tests/*.nim"]
  default_monitor_fn_matcher = "**/*.nim"
  symbol = "●"
  success_color = fgGreen
  fail_color = fgRed
  nimtest_no_color_env_var = "NIMTEST_NO_COLOR"


type
  FnMatchers* = seq[string]
  Conf* = object
    basedir, conf_fname: string
    fn_matchers: seq[string]
    monitor_fn_matchers: seq[string]
    debug_mode: bool
    nocolor: bool
    compiler_args: string

proc print_help() =
  echo """Welcome to Nim test runner.
This command runs the Nim compiler against a set of test files.
It supports globbing and can run tests automatically when source files are changed.

Syntax:
  testurunner ['test filename globbing'...] [-m [:'monitored filename globbing']] [ -- compiler flags]
  testrunner 'tests/**/*.nim'
  testrunner -m
  testrunner mytest.nim 'tests/*.nim' -m:'**/*.nim' -d -- -d:ssl
  testrunner (-h | --help)

Options:
  -h --help       show help
  -d --debug      debug mode
  -m --monitor    without any argument, monitor **/*.nim
  -m:'<glob>'     monitor globbing. Remember the colon ":"
  --basedir <dir> basedir
  -c --conf       config file path

Protect globbings with single quotes.
Double asterisk "**" matches nested subdirectories.
Anything after "--" will be used as a compiler option for Nim.

If no test globs are passed, the following will be used:
  test_*.nim test/*.nim tests/*.nim

Testrunner will also parse .testrunner.conf if available, unless
a different config file is specified.
"""
  quit()

proc parse_cli_options(): Conf =
  result = Conf(
    basedir: get_current_dir(),
    fn_matchers: @[],
    monitor_fn_matchers: @[],
    compiler_args: "",
    nocolor: false,
  )

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break

    of cmdArgument:
      # Argument: test filename matcher
      result.fn_matchers.add p.key

    of cmdLongOption, cmdShortOption:
      if p.key == "":
        # "--" is handled as empty key and empty var
        # anything after this is to be passed to the compiler
        # as it is
        result.compiler_args = p.cmdLineRest()
        break

      case p.key
      of "help", "h":
        print_help()

      of "debug", "d":
        result.debug_mode = true

      of "nocolor", "b":
        result.nocolor = true

      of "basedir":
        result.basedir = p.val.expand_tilde()

      of "monitor", "m":
        if p.val == "":
          # no pattern is passed, add default value
          result.monitor_fn_matchers.add default_monitor_fn_matcher

        else:
          result.monitor_fn_matchers.add p.val

      of "conf", "c":
        if p.val.len == 0:
          echo "empty conf file"
          quit()
        result.conf_fname = p.val

proc load_config_file(conf: var Conf) =
  ## Load config file
  if conf.conf_fname.len == 0:
    if existsFile(default_conf_fname):
      conf.conf_fname = default_conf_fname
    else:
      return

  var f = newFileStream(conf.conf_fname, fmRead)
  if f == nil:
    echo("cannot open conf file '$#'" % conf.conf_fname)
    quit()

  var p: CfgParser
  p.open(f, conf.conf_fname)
  while true:
    var e = next(p)
    case e.kind
    of cfgKeyValuePair:
      case e.key:
        of "basedir":
          conf.basedir = e.value.expand_tilde()
        of "glob_include":
          conf.fn_matchers.add e.value

    of cfgOption:
      discard
    of cfgEof:
      break
    of cfgSectionStart:
      discard
    of cfgError:
      echo(e.msg)

  close p

proc parse_options_and_config_file(): Conf =
  var conf = parse_cli_options()
  conf.load_config_file()
  if conf.fn_matchers.len == 0:
    conf.fn_matchers = default_test_fn_matchers
  set_current_dir(conf.basedir)
  return conf

proc scan_test_files(conf: Conf): seq[string] =
  ## Scan for test files
  result = @[]
  for full_fname in conf.basedir.walkDirRec():
    let fname = full_fname[conf.basedir.len+1..^0]
    if match_filename(fname, conf.fn_matchers):
      result.add fname

proc run_tests(conf: Conf) =
  ## Run tests
  let t0 = epochTime()
  var success_cnt = 0
  var fail_cnt = 0
  for test_fn in conf.scan_test_files():
    let cmd = "nim c $# -r $#" % [conf.compiler_args, test_fn]
    echo cmd
    if conf.nocolor:
      putEnv(nimtest_no_color_env_var, "1")
    let exit_code = execCmd(cmd)
    if exit_code == 0:
      success_cnt.inc
    else:
      fail_cnt.inc

  let elapsed = formatFloat(epochTime() - t0, precision=2)
  let col = not conf.nocolor

  if col:
    let symbol_color = if fail_cnt == 0: success_color else: fail_color
    styledWriteLine(stdout,
      symbol_color, symbol & " ", resetStyle,
      "  Successful: ",
      success_color, $success_cnt, resetStyle,
      "  Failed: ",
      fail_color, $fail_cnt, resetStyle,
      "  Elapsed time: $#s" % elapsed,
    )
  else:
    echo "Successful: $#  Failed: $#  Elapsed time: $#s" % [
      $success_cnt, $fail_cnt, elapsed]



proc main() =
  let conf = parse_options_and_config_file()
  conf.run_tests()
  if conf.monitor_fn_matchers.len == 0:
    quit()

  when defined(linux):
    while monitor_files(conf.basedir, conf.monitor_fn_matchers, conf.debug_mode):
      conf.run_tests()

when isMainModule:
  main()
