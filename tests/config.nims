switch("path", "$projectDir/../src")

# Repeatable runs: no failure database unless a test sets PROPTEST_DB.
switch("define", "proptestDb=off")

# The suite also runs in release; its own failures use `check` (located in
# every build), so the trace warning (A8) would only add noise.
switch("define", "proptestTraceWarning=false")
