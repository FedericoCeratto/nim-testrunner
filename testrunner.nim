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
  import libnotify

import junit

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
    debug_mode, nocolor, norun, notify: bool
    compiler_args: string
    junit_output_filename: string

  Summary = ref object of RootObj
    success_cnt, fail_cnt, fail_to_compile_cnt: int

  Notifier = object
    enabled: bool
    when defined(linux):
      client: NotifyClient

proc print_help() =
  echo """Welcome to Nim test runner.
This command runs the Nim compiler against a set of test files.
It supports globbing and can run tests automatically when source files are changed.

Syntax:
  testrunner ['test filename globbing'...] [-m [:'monitored filename globbing']] [ -- compiler flags]
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
  -o --norun      do not run test files, run "nim c" only
  -q --nonotify   do not send desktop notifications (enabled only with -m on Linux)
  --junit:<fname> write out JUnit summary (default: junit.xml)

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
    norun: false,
    notify: true,
    junit_output_filename: "",
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

      of "norun", "o":
        result.norun = true

      of "nonotify", "q":
        result.notify = false

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

      of "junit":
        result.junit_output_filename =
          if p.val == "": "junit.xml"
          else: p.val


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

proc newNotifier(): Notifier =
  ## Init desktop notifier
  result.enabled = false
  when defined(linux):
    result.client = newNotifyClient("testrunner")
    result.client.set_app_name("testrunner")

proc send(notifier: Notifier, msg: string) =
  ## Send notification
  when defined(linux):
    notifier.client.send_new_notification("normal", msg, "STOCK_YES",
      urgency=NotificationUrgency.Normal, timeout=2)

proc safe_write(path, contents: string) =
  ## Create dirs, write file atomically
  path.splitPath.head.createDir
  let tmp_fname = path & ".tmp"
  try:
    tmp_fname.writeFile(contents)
    moveFile(tmp_fname, path)
  except Exception:
    raise newException(Exception,
      "Unable to save file $#: $#" % [path, getCurrentExceptionMsg()])

proc generate_junit_summary(fname: string, testsuites: JUnitTestSuites) =
  ## Generate and write out a test summary in JUnit format
  ## One Nim unittest file maps into one JUnitTestSuite
  include "junitxml.tmpl"
  let contents = testsuites.generate_junit()
  safe_write(fname, contents)

proc run_tests(conf: Conf, old_summary: var Summary, notifier: Notifier) =
  ## Run tests
  let t0 = epochTime()
  var summary = Summary()
  var testsuites = JUnitTestSuites()
  testsuites.suites = @[]

  let test_fnames = conf.scan_test_files()
  echo "Compiling $# test files..." % $test_fnames.len
  var compiled_test_fnames: seq[string] = @[]
  for test_fn in test_fnames:
    let cmd = "nim c $# $#" % [conf.compiler_args, test_fn]
    echo "Running: $#" % cmd
    let exit_code = execCmd(cmd)
    if exit_code == 0:
      assert test_fn.endswith(".nim")
      compiled_test_fnames.add test_fn[0..^5]
    else:
      summary.fail_to_compile_cnt.inc
      testsuites.errors.inc
      echo "Failed to compile $#" % test_fn

  if conf.norun == false:
    echo "Running $# test files..." % $compiled_test_fnames.len
    for fn in compiled_test_fnames:
      let cmd = "./" & fn
      echo "Running: $#" % cmd
      if conf.nocolor:
        putEnv(nimtest_no_color_env_var, "1")
      let t1 = epochTime()
      let exit_code = execCmd(cmd)
      let elapsed = epochTime() - t1
      var ts = JUnitTestSuite(name:fn)
      if exit_code == 0:
        summary.success_cnt.inc
        testsuites.tests.inc
        ts.tests.inc
        let tc = JUnitTestCase(name:fn, status:"PASSED",
          assertions:1, time:elapsed)
        ts.time = elapsed
        ts.testcases = @[tc]

      else:
        summary.fail_cnt.inc exit_code
        testsuites.failures.inc exit_code
        ts.failures.inc exit_code
        testsuites.tests.inc  # TODO: correct?
        ts.tests.inc          # TODO: correct?
        let tc = JUnitTestCase(name:fn, status:"FAILED",
          assertions:1, time:elapsed)
        ts.time = elapsed
        ts.testcases = @[tc]

      # TODO: more detailed report
      testsuites.suites.add ts


  let elapsed = formatFloat(epochTime() - t0, precision=2)
  testsuites.time = epochTime() - t0
  let col = not conf.nocolor

  if col:
    let symbol_color =
      if summary.fail_cnt == 0: success_color
      else: fail_color

    styledWriteLine(stdout,
      symbol_color, symbol & " ", resetStyle,
      "  Successful: ",
      success_color, $summary.success_cnt, resetStyle,
      "  Failed: ",
      fail_color, $summary.fail_cnt, resetStyle,
      "  Failed to compile: ",
      fail_color, $summary.fail_to_compile_cnt, resetStyle,
      "  Elapsed time: $#s" % elapsed,
    )
  else:
    echo "Successful: $#  Failed: $#  Elapsed time: $#s" % [
      $summary.success_cnt, $summary.fail_cnt, elapsed]

  if notifier.enabled:
    let fixed = old_summary.fail_cnt - summary.fail_cnt
    if fixed > 0:
      notifier.send("$# test fixed" % $fixed)
    elif fixed < 0:
      notifier.send("$# test broken" % $(fixed * -1))

  old_summary = summary

  if conf.junit_output_filename != "":
    generate_junit_summary(conf.junit_output_filename, testsuites)

proc main() =
  let conf = parse_options_and_config_file()
  var notifier = newNotifier()
  var summary = Summary()
  run_tests(conf, summary, notifier)
  if conf.monitor_fn_matchers.len == 0:
    quit()

  notifier.enabled = conf.notify

  when defined(linux):
    while monitor_files(conf.basedir, conf.monitor_fn_matchers, conf.debug_mode):
      run_tests(conf, summary, notifier)

when isMainModule:
  main()
