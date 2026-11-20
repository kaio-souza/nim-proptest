switch("path", "$projectDir/../src")

# Repeatable runs: no failure database unless a test sets PROPTEST_DB.
switch("define", "proptestDb=off")
