#!/bin/bash

awk '
    /^\| \[/ && match($0, /\]\(/) {
        prefix = substr($0, 1, RSTART-1)
        suffix = substr($0, RSTART)
        gsub(/\\_/, "\x01", prefix)    # protect already-escaped underscores
        gsub(/_/, "\\_", prefix)       # escape remaining underscores
        gsub(/\x01/, "\\_", prefix)    # restore protected ones
        $0 = prefix suffix
    }
    {print}
' README.new > README.md

rm README.new
