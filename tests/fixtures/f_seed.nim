## Fixture: standalone properties whose seed comes from the environment.
import proptest

let passing = forAllResult(initSettings(name = "passing"), x in int):
  discard
echo "cases=", passing.casesRun

let failing = forAllResult(initSettings(name = "failing"), xs in seq[int]):
  doAssert xs.len < 3
echo "runSeed=", failing.runSeed
echo "casesBeforeFailure=", failing.casesRun
echo "counterexample=", failing.failures[0].inputs[0].value
echo "shrinkExecutions=", failing.failures[0].shrinkExecutions
