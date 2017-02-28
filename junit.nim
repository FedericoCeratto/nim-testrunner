#
## Nim test runner - JUnit support
#
# Copyright 2017 Federico Ceratto <federico.ceratto@gmail.com>
# Released under GPLv3 License, see LICENSE file

type
  JUnitTestCase* = ref object of RootObj
    # Name of the test method, required.
    name*: string
    # Number of assertions in the test case. optional
    assertions*: int
    # Class name for the class the test method is in. required
    classname*: string
    # Time taken (in seconds) to execute the test. optional
    time*: float
    # Outcome
    status*: string
    # Test was skipped
    skipped*: bool
    # Error message.
    error_message*: string
    # Failure message.
    failure_message*: string
    # Data that was written to standard out while the test was executed. optional
    system_out*: string
    # Data that was written to standard error while the test was executed. optional
    system_err*: string

  JUnitTestSuite* = ref object of RootObj
    # Suite name
    name*: string
    # The total number of tests in the suite, required.
    tests*: int
    # the total number of disabled tests in the suite. optional
    disabled*: int
    # The total number of tests in the suite that errored. An errored test is one that had an unanticipated problem
    errors*: int
    # The total number of tests in the suite that failed. A failure is a test which the code has explicitly failed
    failures*: int
    # Host on which the tests were executed. 'localhost' should be used if the hostname cannot be determined. optional
    hostname*: string
    # Starts at 0 for the first testsuite and is incremented by 1 for each following testsuite
    id*: int
    # Derived from testsuite/@name in the non-aggregated documents. optional
    package*: string
    # The total number of skipped tests. optional
    skipped*: int
    # Time taken (in seconds) to execute the tests in the suite. optional
    time*: float
    # when the test was executed in ISO 8601 format (2014-01-21T16:17:18). Timezone may not be specified. optional
    timestamp*: int
    # Data that was written to standard out while the test was executed. optional
    system_out*: string
    # Data that was written to standard error while the test was executed. optional
    system_err*: string

    testcases*: seq[JUnitTestCase]

  JUnitTestSuites* = ref object of RootObj
    # total number of disabled tests from all testsuites
    disabled*: int
    # name
    name*: string
    # total number of tests with error result from all testsuites.
    errors*: int
    # total number of failed tests from all testsuites.
    failures*: int
    # total number of successful tests from all testsuites.
    tests*: int
    # time in seconds to execute all test suites.
    time*: float

    suites*: seq[JUnitTestSuite]
